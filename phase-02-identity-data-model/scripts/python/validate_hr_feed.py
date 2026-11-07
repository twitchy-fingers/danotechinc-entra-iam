#!/usr/bin/env python3
"""
validate_hr_feed.py - the quality gate between the HR system and Entra ID.

Every HR file must pass this script before Phase 04 provisions anything.
Bad HR data doesn't stay in HR: a wrong job code becomes wrong access in every
connected application, and a missing end date becomes an account that never
expires. Catching it here is cheaper than cleaning it up in six systems.

Checks the file against:
  - contract/hr-attribute-contract.json   (fields, formats, allowed values)
  - reference/job-codes.csv               (job code catalogue)
  - reference/offices.csv                 (office, country, usage location)
  - ../data/hr/departments.csv            (department, cost centre)

Severity
  ERROR    blocks the feed. Provisioning must not run.
  WARNING  feed may run, but HR must fix the record (tracked as an issue).

Exit code: 0 = no errors, 1 = errors found (so CI and Phase 04 can stop on it).

Usage
  python validate_hr_feed.py ../../../data/hr/employees.csv
  python validate_hr_feed.py feed.csv --as-of 2026-11-05 --report out.md --profile
  python validate_hr_feed.py today.csv --previous yesterday.csv     # mass-change guard
"""
import argparse
import csv
import json
import re
import sys
import unicodedata
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
PHASE = HERE.parent.parent
REPO = PHASE.parent


def ascii_slug(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return "".join(ch for ch in s.lower() if ch.isalnum())


def read_csv(path: Path) -> list[dict]:
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def parse_date(s: str):
    try:
        return date.fromisoformat(s)
    except (TypeError, ValueError):
        return None


class Findings:
    def __init__(self):
        self.items = []

    def add(self, rule, severity, eid, message):
        self.items.append({"rule": rule, "severity": severity, "employeeId": eid or "-", "message": message})

    def count(self, sev):
        return sum(1 for i in self.items if i["severity"] == sev)


def validate(rows, contract, jobcodes, offices, depts, as_of, previous=None):
    f = Findings()
    fields = {fd["name"]: fd for fd in contract["fields"]}
    by_id = {}

    # DQ-01 required columns exist at all (a missing column fails every row, so check once)
    missing_cols = [n for n in fields if rows and n not in rows[0]]
    if missing_cols:
        f.add("DQ-01", "ERROR", None, f"Missing columns: {', '.join(missing_cols)}")
        return f

    ids = Counter(r["EmployeeId"] for r in rows)
    upns = Counter(r["UserPrincipalName"].lower() for r in rows)
    for r in rows:
        by_id.setdefault(r["EmployeeId"], r)

    reports_to = defaultdict(list)
    for r in rows:
        if r["ManagerEmployeeId"]:
            reports_to[r["ManagerEmployeeId"]].append(r["EmployeeId"])

    no_manager = [r for r in rows if not r["ManagerEmployeeId"]]

    for r in rows:
        eid = r["EmployeeId"]

        # DQ-01 required values
        for name, fd in fields.items():
            if fd.get("required") and not r.get(name, "").strip():
                f.add("DQ-01", "ERROR", eid, f"{name} is empty")

        # DQ-02 EmployeeId format / DQ-03 uniqueness
        if not re.fullmatch(fields["EmployeeId"]["pattern"], eid):
            f.add("DQ-02", "ERROR", eid, f"EmployeeId '{eid}' doesn't match DT + 5 digits")
        if ids[eid] > 1:
            f.add("DQ-03", "ERROR", eid, f"EmployeeId appears {ids[eid]} times")

        # DQ-04 UPN unique / DQ-05 UPN naming rule
        upn = r["UserPrincipalName"]
        if upns[upn.lower()] > 1:
            f.add("DQ-04", "ERROR", eid, f"UPN {upn} is not unique")
        if not re.fullmatch(fields["UserPrincipalName"]["pattern"], upn):
            f.add("DQ-05", "ERROR", eid, f"UPN '{upn}' breaks the naming rule (first.last[n]@{contract['tenantDomain']})")
        else:
            expected = f"{ascii_slug(r['FirstName'])}.{ascii_slug(r['LastName'])}"
            prefix = upn.split("@")[0]
            if re.sub(r"\d+$", "", prefix) != expected:
                f.add("DQ-05", "WARNING", eid, f"UPN prefix '{prefix}' doesn't match name (expected '{expected}'); name change or typo?")
            if r["MailNickname"] != prefix:
                f.add("DQ-05", "ERROR", eid, f"MailNickname '{r['MailNickname']}' must equal UPN prefix '{prefix}'")

        # DQ-06 job code exists; DQ-07 department / cost centre / family consistent
        jc = jobcodes.get(r["JobCode"])
        if not jc:
            f.add("DQ-06", "ERROR", eid, f"JobCode '{r['JobCode']}' not in job code catalogue")
        else:
            if jc["Status"] != "Active":
                f.add("DQ-06", "ERROR", eid, f"JobCode '{r['JobCode']}' is retired")
            if jc["DepartmentCode"] != r["DepartmentCode"]:
                f.add("DQ-07", "ERROR", eid, f"JobCode {r['JobCode']} belongs to {jc['DepartmentCode']}, record says {r['DepartmentCode']}")
            if jc["JobFamily"] != r["JobFamily"]:
                f.add("DQ-07", "ERROR", eid, f"JobFamily '{r['JobFamily']}' doesn't match catalogue '{jc['JobFamily']}'")
            if r["EmployeeType"] not in jc["AllowedEmployeeTypes"].split("|"):
                f.add("DQ-07", "ERROR", eid, f"EmployeeType {r['EmployeeType']} not allowed for job code {r['JobCode']}")
            # DQ-18 level within range (interns are always L1)
            lvl = r["JobLevel"]
            if re.fullmatch(fields["JobLevel"]["pattern"], lvl):
                n, lo, hi = int(lvl[1:]), int(jc["MinLevel"][1:]), int(jc["MaxLevel"][1:])
                if r["EmployeeType"] == "Intern":
                    if n != 1:
                        f.add("DQ-18", "WARNING", eid, f"Intern at level {lvl}; interns should be L1")
                elif not lo <= n <= hi:
                    f.add("DQ-18", "WARNING", eid, f"Level {lvl} outside {r['JobCode']} range {jc['MinLevel']}-{jc['MaxLevel']}")
            else:
                f.add("DQ-18", "ERROR", eid, f"JobLevel '{lvl}' invalid")

        d = depts.get(r["DepartmentCode"])
        if not d:
            f.add("DQ-07", "ERROR", eid, f"DepartmentCode '{r['DepartmentCode']}' unknown")
        else:
            if d["Department"] != r["Department"]:
                f.add("DQ-07", "ERROR", eid, f"Department '{r['Department']}' doesn't match code {r['DepartmentCode']} ('{d['Department']}')")
            if d["CostCenter"] != r["CostCenter"]:
                f.add("DQ-07", "ERROR", eid, f"CostCenter {r['CostCenter']} doesn't match department ({d['CostCenter']})")
            if d["Division"] != r["Division"]:
                f.add("DQ-07", "ERROR", eid, f"Division '{r['Division']}' doesn't match department ('{d['Division']}')")

        # DQ-08 manager exists, DQ-09 not self, DQ-11 manager status
        mid = r["ManagerEmployeeId"]
        if mid:
            m = by_id.get(mid)
            if not m:
                f.add("DQ-08", "ERROR", eid, f"Manager {mid} not found in file")
            elif mid == eid:
                f.add("DQ-09", "ERROR", eid, "Employee is their own manager")
            else:
                if m["EmploymentStatus"] != "Active":
                    f.add("DQ-11", "WARNING", eid, f"Manager {mid} is {m['EmploymentStatus']}")
                m_end = parse_date(m["EndDate"])
                if m_end and m_end >= as_of and m["EmployeeType"] == "Employee":
                    f.add("DQ-11", "WARNING", eid, f"Manager {m['DisplayName']} leaves on {m_end}; HR must reassign this report")

        # DQ-12 employee type, status
        if r["EmployeeType"] not in fields["EmployeeType"]["allowed"]:
            f.add("DQ-12", "ERROR", eid, f"EmployeeType '{r['EmployeeType']}' not allowed")
        if r["EmploymentStatus"] not in fields["EmploymentStatus"]["allowed"]:
            f.add("DQ-12", "ERROR", eid, f"EmploymentStatus '{r['EmploymentStatus']}' not allowed")

        hire, end = parse_date(r["HireDate"]), parse_date(r["EndDate"])
        if not hire:
            f.add("DQ-14", "ERROR", eid, f"HireDate '{r['HireDate']}' is not a valid YYYY-MM-DD date")
        if r["EndDate"] and not end:
            f.add("DQ-14", "ERROR", eid, f"EndDate '{r['EndDate']}' is not a valid YYYY-MM-DD date")

        # DQ-13 fixed-term workers must have an end date
        if r["EmployeeType"] in ("Contractor", "Intern") and not r["EndDate"]:
            f.add("DQ-13", "ERROR", eid, f"{r['EmployeeType']} without EndDate: account would never expire")

        # DQ-14 end after hire
        if hire and end and end <= hire:
            f.add("DQ-14", "ERROR", eid, f"EndDate {end} is not after HireDate {hire}")

        # DQ-15 status vs dates (time-dependent: uses --as-of)
        st = r["EmploymentStatus"]
        if hire:
            if st == "PreHire" and hire <= as_of:
                f.add("DQ-15", "WARNING", eid, f"Still PreHire on or after start date {hire}: HR hasn't confirmed the start")
            if st == "Active" and hire > as_of:
                f.add("DQ-15", "ERROR", eid, f"Active but start date {hire} is in the future: would enable the account early")
        if end and st == "Active" and end < as_of:
            f.add("DQ-15", "ERROR", eid, f"Active but EndDate {end} has passed: leaver not processed")

        # DQ-16 usage location matches country, DQ-17 office consistency
        o = offices.get(r["Office"])
        if not o:
            f.add("DQ-17", "ERROR", eid, f"Office '{r['Office']}' not in reference list")
        else:
            if (o["City"], o["Country"]) != (r["City"], r["Country"]):
                f.add("DQ-17", "ERROR", eid, f"City/Country '{r['City']}, {r['Country']}' don't match office {r['Office']}")
            if o["UsageLocation"] != r["UsageLocation"]:
                f.add("DQ-16", "ERROR", eid, f"UsageLocation {r['UsageLocation']} doesn't match {r['Country']} ({o['UsageLocation']})")

        # DQ-19 name hygiene
        for name in ("FirstName", "LastName"):
            if r[name] != r[name].strip() or "  " in r[name]:
                f.add("DQ-19", "WARNING", eid, f"{name} has extra spaces")
        if r["DisplayName"] != f"{r['FirstName']} {r['LastName']}":
            f.add("DQ-19", "WARNING", eid, f"DisplayName '{r['DisplayName']}' differs from 'FirstName LastName'")

        # DQ-20 contract length policy (max 12 months without renewal)
        if r["EmployeeType"] == "Contractor" and hire and end and (end - hire).days > 366:
            f.add("DQ-20", "WARNING", eid, f"Contract runs {(end - hire).days} days; policy maximum is 12 months before renewal")

    # DQ-10 exactly one person without a manager (the CEO)
    if len(no_manager) != 1 or no_manager[0]["JobCode"] != "EXE-CEO":
        names = ", ".join(f"{r['EmployeeId']} {r['DisplayName']}" for r in no_manager) or "none"
        f.add("DQ-10", "ERROR", None, f"Expected exactly one record without a manager (the CEO); found: {names}")

    # DQ-09 reporting loops (A -> B -> A)
    for r in rows:
        seen, cur = set(), r["EmployeeId"]
        while cur and cur in by_id:
            if cur in seen:
                f.add("DQ-09", "ERROR", r["EmployeeId"], "Reporting line loops back on itself")
                break
            seen.add(cur)
            cur = by_id[cur]["ManagerEmployeeId"]

    # DQ-21 mass-change guard (circuit breaker against a truncated or wrong file)
    if previous is not None:
        prev_ids = {p["EmployeeId"] for p in previous}
        cur_ids = set(ids)
        gone = prev_ids - cur_ids
        threshold = contract.get("massChangeThresholdPercent", 10)
        pct = 100 * len(gone) / max(len(prev_ids), 1)
        if pct > threshold:
            f.add("DQ-21", "ERROR", None,
                  f"{len(gone)} of {len(prev_ids)} records ({pct:.0f}%) disappeared since the previous file; "
                  f"threshold is {threshold}%. Possible truncated export: provisioning blocked.")
        elif gone:
            f.add("DQ-21", "WARNING", None, f"{len(gone)} records removed since previous file: {', '.join(sorted(gone))}")

    return f, reports_to


def profile(rows, reports_to, as_of):
    out = ["## Feed profile", ""]
    out += [f"- Records: **{len(rows)}**",
            f"- By employee type: " + ", ".join(f"{k} {v}" for k, v in Counter(r['EmployeeType'] for r in rows).most_common()),
            f"- By status: " + ", ".join(f"{k} {v}" for k, v in Counter(r['EmploymentStatus'] for r in rows).most_common()),
            f"- People managers (derived `IsPeopleManager`): **{len(reports_to)}**",
            f"- Records with a future end date (leavers, contractors, interns): "
            f"**{sum(1 for r in rows if r['EndDate'] and parse_date(r['EndDate']) and parse_date(r['EndDate']) >= as_of)}**", ""]
    spans = sorted(((len(v), k) for k, v in reports_to.items()), reverse=True)[:5]
    names = {r["EmployeeId"]: r["DisplayName"] for r in rows}
    out += ["**Largest spans of control** (affects approval and review workload):", ""]
    out += [f"- {names.get(k, k)} ({k}): {n} direct reports" for n, k in spans]
    out += ["", "| Department | Records |", "|---|---|"]
    out += [f"| {k} | {v} |" for k, v in sorted(Counter(r['Department'] for r in rows).items())]
    return out


def main():
    # Windows consoles default to a legacy code page; when output is piped in
    # PowerShell, characters like ✅ or · would crash print(). Force UTF-8.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("feed")
    ap.add_argument("--as-of", default=date.today().isoformat(), help="Date to evaluate time-based rules (YYYY-MM-DD)")
    ap.add_argument("--previous", help="Previous HR file, for the mass-change guard (DQ-21)")
    ap.add_argument("--report", help="Write a Markdown report to this path")
    ap.add_argument("--json", help="Write findings as JSON to this path")
    ap.add_argument("--profile", action="store_true", help="Include a statistical profile of the feed")
    args = ap.parse_args()

    as_of = date.fromisoformat(args.as_of)
    contract = json.loads((PHASE / "contract" / "hr-attribute-contract.json").read_text(encoding="utf-8"))
    jobcodes = {r["JobCode"]: r for r in read_csv(PHASE / "reference" / "job-codes.csv")}
    offices = {r["Office"]: r for r in read_csv(PHASE / "reference" / "offices.csv")}
    depts = {r["DepartmentCode"]: r for r in read_csv(REPO / "data" / "hr" / "departments.csv")}
    rows = read_csv(Path(args.feed))
    previous = read_csv(Path(args.previous)) if args.previous else None

    result = validate(rows, contract, jobcodes, offices, depts, as_of, previous)
    findings, reports_to = result if isinstance(result, tuple) else (result, {})

    errors, warnings = findings.count("ERROR"), findings.count("WARNING")
    verdict = "BLOCKED: fix errors before provisioning" if errors else "PASSED: feed may be provisioned"
    lines = [f"# HR feed validation report", "",
             f"- File: `{Path(args.feed).name}`",
             f"- Evaluated as of: {as_of}",
             f"- Contract version: {contract['version']}",
             f"- Records: {len(rows)}",
             f"- Errors: **{errors}**  ·  Warnings: **{warnings}**",
             f"- Result: **{verdict}**", ""]
    if findings.items:
        by_rule = Counter((i["rule"], i["severity"]) for i in findings.items)
        lines += ["## Summary by rule", "", "| Rule | Severity | Count |", "|---|---|---|"]
        lines += [f"| {r} | {s} | {n} |" for (r, s), n in sorted(by_rule.items())]
        lines += ["", "## Findings", "", "| Severity | Rule | EmployeeId | Detail |", "|---|---|---|---|"]
        order = {"ERROR": 0, "WARNING": 1}
        for i in sorted(findings.items, key=lambda x: (order[x["severity"]], x["rule"], x["employeeId"])):
            lines.append(f"| {i['severity']} | {i['rule']} | {i['employeeId']} | {i['message']} |")
    if args.profile:
        lines += [""] + profile(rows, reports_to, as_of)

    text = "\n".join(lines)
    print(text)
    if args.report:
        Path(args.report).write_text(text + "\n", encoding="utf-8")
    if args.json:
        Path(args.json).write_text(json.dumps({"asOf": str(as_of), "errors": errors, "warnings": warnings,
                                               "findings": findings.items}, indent=2), encoding="utf-8")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
