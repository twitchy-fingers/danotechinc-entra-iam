#!/usr/bin/env python3
"""
build_access_model.py - simulate DanotechInc's RBAC model before it's built.

Reads the role model (model/*.csv) and the HR feed, then answers, for all 200
people: which roles would they get, which entitlements would that give them,
and does the result break any access policy or separation-of-duties rule?

Why simulate: in Phase 05 these roles become dynamic groups that act on 200
real accounts the moment they're created. Finding a contractor with payment
rights, or a person who can approve and pay the same expense, is far cheaper
in a CSV than in production.

Outputs (generated/):
  access-model-report.md     policy checks, SoD results, coverage, sample personas
  permission-matrix.md       role x entitlement, one table per application
  role-membership.csv        each person and the roles they receive
  employee-entitlements.csv  each person, each entitlement, and which roles grant it
  dynamic-group-rules.json   Entra ID dynamic membership rules for Phase 05

Exit code 1 if any ERROR (policy violation or un-excepted SoD conflict).

Usage
  python build_access_model.py
  python build_access_model.py --as-of 2026-11-05 --feed ../../../data/hr/employees.csv
"""
import argparse
import csv
import json
import sys
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
PHASE = HERE.parent.parent
REPO = PHASE.parent
MODEL = PHASE / "model"
OUT = PHASE / "generated"
DYNAMIC_LAYERS = ("Birthright", "Department", "Job")
HIGH = ("High", "Privileged")


def read_csv(p):
    with open(p, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def split(v, sep="|"):
    return [x.strip() for x in v.split(sep) if x.strip()] if v else []


def matches(role, person):
    """AND across criteria, OR within a criterion. Empty criterion = any."""
    if split(role["Departments"]) and person["DepartmentCode"] not in split(role["Departments"]):
        return False
    if split(role["JobCodes"]) and person["JobCode"] not in split(role["JobCodes"]):
        return False
    if split(role["JobLevels"]) and person["JobLevel"] not in split(role["JobLevels"]):
        return False
    if split(role["EmployeeTypes"]) and person["EmployeeType"] not in split(role["EmployeeTypes"]):
        return False
    if role["PeopleManager"] == "Yes" and person["IsPeopleManager"] != "PeopleManager":
        return False
    return True


def dynamic_rule(role, dept_names):
    """Translate the role's criteria into Entra ID dynamic membership rule syntax."""
    q = lambda vals: "[" + ",".join(f'"{v}"' for v in vals) + "]"
    parts = ['(user.accountEnabled -eq true)', '(user.companyName -eq "DanotechInc")']
    if split(role["Departments"]):
        parts.append(f"(user.department -in {q([dept_names[d] for d in split(role['Departments'])])})")
    if split(role["JobCodes"]):
        parts.append(f"(user.extensionAttribute1 -in {q(split(role['JobCodes']))})")
    if split(role["JobLevels"]):
        parts.append(f"(user.extensionAttribute2 -in {q(split(role['JobLevels']))})")
    if split(role["EmployeeTypes"]):
        parts.append(f"(user.employeeType -in {q(split(role['EmployeeTypes']))})")
    if role["PeopleManager"] == "Yes":
        parts.append('(user.extensionAttribute4 -eq "PeopleManager")')
    return " -and ".join(parts)


class Checks:
    def __init__(self):
        self.items = []

    def add(self, cid, sev, msg):
        self.items.append((cid, sev, msg))

    def n(self, sev):
        return sum(1 for i in self.items if i[1] == sev)


def main():
    # Windows consoles default to a legacy code page; when output is piped in
    # PowerShell, characters like ✅ or · would crash print(). Force UTF-8.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--feed", default=str(REPO / "data" / "hr" / "employees.csv"))
    ap.add_argument("--as-of", default=date.today().isoformat())
    ap.add_argument("--out", default=str(OUT))
    args = ap.parse_args()
    as_of = date.fromisoformat(args.as_of)
    out = Path(args.out)
    out.mkdir(exist_ok=True)

    people = read_csv(args.feed)
    roles = read_csv(MODEL / "roles.csv")
    ents = {e["EntitlementId"]: e for e in read_csv(MODEL / "entitlements.csv")}
    sod = read_csv(MODEL / "sod-rules.csv")
    exceptions = read_csv(MODEL / "sod-exceptions.csv")
    jobcodes = read_csv(REPO / "phase-02-identity-data-model" / "reference" / "job-codes.csv")
    dept_names = {d["DepartmentCode"]: d["Department"] for d in read_csv(REPO / "data" / "hr" / "departments.csv")}
    by_id = {p["EmployeeId"]: p for p in people}

    # Derived attribute from Phase 02: IsPeopleManager
    managers = {p["ManagerEmployeeId"] for p in people if p["ManagerEmployeeId"]}
    for p in people:
        p["IsPeopleManager"] = "PeopleManager" if p["EmployeeId"] in managers else ""

    chk = Checks()
    role_ents = {r["RoleId"]: split(r["Entitlements"], ";") for r in roles}

    # ---- Structural checks -------------------------------------------------
    for r in roles:
        for e in role_ents[r["RoleId"]]:
            if e not in ents:
                chk.add("PC-03", "ERROR", f"{r['RoleId']} references unknown entitlement {e}")
        if not r["Owner"]:
            chk.add("PC-03", "ERROR", f"{r['RoleId']} has no owner")
        if r["Layer"] != "Privileged" and any(ents.get(e, {}).get("Sensitivity") == "Privileged" for e in role_ents[r["RoleId"]]):
            chk.add("PC-04", "ERROR", f"{r['RoleId']} ({r['Layer']}) grants a Privileged entitlement; only PIM roles may")
        if r["Layer"] == "Requestable" and any(r[k] for k in ("Departments", "JobCodes", "JobLevels", "PeopleManager", "Members")):
            chk.add("PC-07", "ERROR", f"{r['RoleId']} is requestable but has automatic membership criteria")
    for e in ents.values():
        if not e["Owner"]:
            chk.add("PC-03", "ERROR", f"Entitlement {e['EntitlementId']} has no owner")

    # PC-01 every job code is covered by at least one job role
    covered = {c for r in roles if r["Layer"] == "Job" for c in split(r["JobCodes"])}
    for jc in jobcodes:
        if jc["JobCode"] not in covered:
            chk.add("PC-01", "ERROR", f"Job code {jc['JobCode']} ({jc['StandardTitle']}) has no job role")

    # ---- Assign roles to people ---------------------------------------------
    assigned = defaultdict(list)  # EmployeeId -> [RoleId]
    for r in roles:
        if r["Layer"] in DYNAMIC_LAYERS:
            for p in people:
                if matches(r, p):
                    assigned[p["EmployeeId"]].append(r["RoleId"])
        elif r["Layer"] == "Privileged":
            for mid in split(r["Members"]):
                p = by_id.get(mid)
                if not p:
                    chk.add("PC-06", "ERROR", f"{r['RoleId']} member {mid} not in HR feed")
                    continue
                if p["EmployeeType"] != "Employee":
                    chk.add("PC-06", "ERROR", f"{r['RoleId']} member {p['DisplayName']} is a {p['EmployeeType']}; privileged roles are employee-only")
                if p["EmploymentStatus"] != "Active":
                    chk.add("PC-06", "ERROR", f"{r['RoleId']} member {p['DisplayName']} is {p['EmploymentStatus']}")
                assigned[mid].append(r["RoleId"])

    role_by_id = {r["RoleId"]: r for r in roles}
    person_ents = {}
    for p in people:
        grants = defaultdict(list)
        for rid in assigned[p["EmployeeId"]]:
            for e in role_ents[rid]:
                grants[e].append(rid)
        person_ents[p["EmployeeId"]] = grants

    # PC-02 everyone gets birthright
    for p in people:
        if "BR-WORKFORCE" not in assigned[p["EmployeeId"]]:
            chk.add("PC-02", "ERROR", f"{p['DisplayName']} ({p['EmployeeId']}) gets no birthright access")

    # PC-05 contractors and interns never hold High or Privileged
    for p in people:
        if p["EmployeeType"] in ("Contractor", "Intern"):
            for e, via in person_ents[p["EmployeeId"]].items():
                if ents[e]["Sensitivity"] in HIGH:
                    chk.add("PC-05", "ERROR", f"{p['EmployeeType']} {p['DisplayName']} gets {ents[e]['Sensitivity']} {e} via {', '.join(via)}")

    # PC-08 entitlements no role grants; PC-09 dynamic roles with no members
    granted_anywhere = {e for r in roles for e in role_ents[r["RoleId"]]}
    for e in ents:
        if e not in granted_anywhere:
            chk.add("PC-08", "WARNING", f"Entitlement {e} is not granted by any role")
    # Member counts reflect ENABLED accounts only: pre-hires are disabled, and every
    # dynamic rule requires accountEnabled = true, so they join groups on day one.
    counts = Counter(rid for eid, rids in assigned.items() if by_id[eid]["EmploymentStatus"] == "Active" for rid in rids)
    for r in roles:
        if r["Layer"] in DYNAMIC_LAYERS + ("Privileged",) and counts[r["RoleId"]] == 0:
            chk.add("PC-09", "WARNING", f"{r['RoleId']} has no members")

    # ---- Separation of duties -------------------------------------------------
    exc = {(x["RuleId"], x["EmployeeId"]): x for x in exceptions}
    sod_rows, potential = [], []
    for rule in sod:
        a, b = set(split(rule["SideA"])), set(split(rule["SideB"]))
        # Role-level: one role containing both sides is always a design error
        for r in roles:
            re_ = set(role_ents[r["RoleId"]])
            if re_ & a and re_ & b:
                chk.add("SOD", "ERROR", f"{rule['RuleId']}: role {r['RoleId']} grants both sides by itself")
        for p in people:
            pe = set(person_ents[p["EmployeeId"]])
            if pe & a and pe & b:
                x = exc.get((rule["RuleId"], p["EmployeeId"]))
                if x and date.fromisoformat(x["Expires"]) >= as_of:
                    status = f"Excepted ({x['ExceptionId']}, expires {x['Expires']})"
                    chk.add("SOD", "INFO", f"{rule['RuleId']}: {p['DisplayName']} holds both sides under {x['ExceptionId']}")
                elif x:
                    status = f"EXPIRED exception {x['ExceptionId']}"
                    chk.add("SOD", "ERROR", f"{rule['RuleId']}: {p['DisplayName']}'s exception {x['ExceptionId']} expired {x['Expires']}")
                else:
                    status = "VIOLATION"
                    chk.add("SOD", "ERROR", f"{rule['RuleId']}: {p['DisplayName']} ({p['EmployeeId']}) holds {sorted(pe & a)} and {sorted(pe & b)}")
                sod_rows.append((rule["RuleId"], p["EmployeeId"], p["DisplayName"], ", ".join(sorted(pe & a)), ", ".join(sorted(pe & b)), status))
        # Potential: side A holders who could REQUEST side B (Phase 12 must block)
        for r in roles:
            if r["Layer"] != "Requestable":
                continue
            for side_have, side_req in ((a, b), (b, a)):
                if set(role_ents[r["RoleId"]]) & side_req:
                    holders = [p for p in people if set(person_ents[p["EmployeeId"]]) & side_have]
                    if holders:
                        potential.append((rule["RuleId"], r["RoleId"], len(holders)))

    # ---- Outputs --------------------------------------------------------------
    with open(out / "role-membership.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["EmployeeId", "DisplayName", "JobCode", "EmployeeType", "EmploymentStatus", "IsPeopleManager", "Roles"])
        for p in people:
            w.writerow([p["EmployeeId"], p["DisplayName"], p["JobCode"], p["EmployeeType"], p["EmploymentStatus"],
                        p["IsPeopleManager"], ";".join(assigned[p["EmployeeId"]])])

    with open(out / "employee-entitlements.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["EmployeeId", "DisplayName", "Application", "EntitlementId", "Sensitivity", "GrantedByRoles"])
        for p in people:
            for e, via in sorted(person_ents[p["EmployeeId"]].items()):
                w.writerow([p["EmployeeId"], p["DisplayName"], ents[e]["Application"], e, ents[e]["Sensitivity"], ";".join(via)])

    rules_json = []
    for r in roles:
        entry = {"roleId": r["RoleId"], "groupName": r["GroupName"], "layer": r["Layer"], "owner": r["Owner"],
                 "description": r["Description"] or r["RoleName"], "entitlements": role_ents[r["RoleId"]],
                 "expectedMembers": counts[r["RoleId"]]}
        if r["Layer"] in DYNAMIC_LAYERS:
            entry["membershipType"] = "Dynamic"
            entry["membershipRule"] = dynamic_rule(r, dept_names)
        elif r["Layer"] == "Privileged":
            entry["membershipType"] = "Assigned (role-assignable, PIM-eligible)"
            entry["members"] = split(r["Members"])
        else:
            entry["membershipType"] = "Access package"
        rules_json.append(entry)
    (out / "dynamic-group-rules.json").write_text(json.dumps(rules_json, indent=2, ensure_ascii=False), encoding="utf-8")

    # Permission matrix: one table per application
    apps = []
    for e in ents.values():
        if e["Application"] not in apps:
            apps.append(e["Application"])
    pm = ["# Permission matrix", "",
          "Generated by `build_access_model.py` from `model/roles.csv` and `model/entitlements.csv`. Do not edit by hand.", "",
          "**Layers:** BR = birthright, DR = department, JR = job, PR = privileged (PIM), RQ = requestable (access package).",
          "**Sensitivity:** L = Low, M = Medium, H = High, P = Privileged.", ""]
    for app in apps:
        app_ents = sorted([e for e in ents.values() if e["Application"] == app], key=lambda e: e["EntitlementId"])
        rows = [r for r in roles if set(role_ents[r["RoleId"]]) & {e["EntitlementId"] for e in app_ents}]
        if not rows:
            continue
        pm += [f"## {app}", "", "Owner: " + app_ents[0]["Owner"] + " · Granted by: " + app_ents[0]["GrantedBy"], ""]
        pm.append("| Role | Members | " + " | ".join(f"{e['EntitlementId']} ({e['Sensitivity'][0]})" for e in app_ents) + " |")
        pm.append("|---|---|" + "---|" * len(app_ents))
        for r in rows:
            cells = ["✓" if e["EntitlementId"] in role_ents[r["RoleId"]] else "" for e in app_ents]
            m = counts[r["RoleId"]] if r["Layer"] != "Requestable" else "on request"
            pm.append(f"| `{r['RoleId']}` | {m} | " + " | ".join(cells) + " |")
        pm.append("")
    (out / "permission-matrix.md").write_text("\n".join(pm), encoding="utf-8")

    # Report
    errs, warns = chk.n("ERROR"), chk.n("WARNING")
    layer_counts = Counter(r["Layer"] for r in roles)
    sens = Counter(ents[e]["Sensitivity"] for pe in person_ents.values() for e in pe)
    per_person = [len(pe) for pe in person_ents.values()]
    rep = ["# Access model simulation report", "",
           f"- Evaluated as of: {as_of}",
           f"- People: {len(people)} · Roles: {len(roles)} ({', '.join(f'{k} {v}' for k, v in layer_counts.items())}) · Entitlements: {len(ents)}",
           f"- Active people (counted in role sizes): {sum(1 for p in people if p['EmploymentStatus'] == 'Active')} · Pre-hires (roles apply from day one): {sum(1 for p in people if p['EmploymentStatus'] == 'PreHire')}",
           f"- Entitlement grants: {sum(per_person)} (average {sum(per_person)/len(per_person):.1f} per person, max {max(per_person)})",
           f"- Grants by sensitivity: " + ", ".join(f"{k} {sens[k]}" for k in ("Low", "Medium", "High", "Privileged")),
           f"- Errors: **{errs}** · Warnings: **{warns}**",
           f"- Result: **{'FAIL: fix the model before Phase 05' if errs else 'PASS: model is ready to implement'}**", "",
           "## Policy checks", "",
           "| Check | Description | Result |", "|---|---|---|"]
    desc = {"PC-01": "Every job code maps to a job role", "PC-02": "Everyone receives birthright access",
            "PC-03": "Roles reference real entitlements; everything has an owner",
            "PC-04": "Privileged entitlements only through PIM roles",
            "PC-05": "Contractors and interns never receive High or Privileged access",
            "PC-06": "Privileged role members are active employees",
            "PC-07": "Requestable roles have no automatic membership",
            "PC-08": "Every entitlement is granted by some role", "PC-09": "Every role has members",
            "SOD": "No one holds both sides of a SoD rule without an approved exception"}
    for cid, d in desc.items():
        hits = [i for i in chk.items if i[0] == cid and i[1] in ("ERROR", "WARNING")]
        rep.append(f"| {cid} | {d} | {'✅ Pass' if not hits else f'❌ {len(hits)} finding(s)'} |")
    if errs or warns:
        rep += ["", "### Findings", ""] + [f"- **{s}** {c}: {m}" for c, s, m in chk.items if s in ("ERROR", "WARNING")]

    rep += ["", "## Separation of duties", "", "| Rule | Person | Side A held | Side B held | Status |", "|---|---|---|---|---|"]
    rep += [f"| {r} | {n} ({e}) | {a} | {b} | {s} |" for r, e, n, a, b, s in sod_rows] or ["| - | none | | | |"]
    rep += ["", "### Conflicts that Phase 12 must block at request time", "",
            "These people don't hold a conflict today, but could **request** the other side through an access package. "
            "Phase 12 configures these packages as incompatible.", "",
            "| Rule | Requestable role | People who must be blocked |", "|---|---|---|"]
    rep += [f"| {r} | `{q}` | {n} |" for r, q, n in potential] or ["| - | none | - |"]

    rep += ["", "## Role sizes", "", "| Role | Layer | Group | Members |", "|---|---|---|---|"]
    rep += [f"| `{r['RoleId']}` | {r['Layer']} | `{r['GroupName']}` | {counts[r['RoleId']] if r['Layer'] != 'Requestable' else 'on request'} |" for r in roles]

    def persona(eid, why):
        p = by_id[eid]
        lines = [f"### {p['DisplayName']} ({eid}): {p['JobTitle']}, {p['Department']}", "", f"*{why}*", "",
                 f"Roles: {', '.join(f'`{r}`' for r in assigned[eid])}", "", "| Entitlement | Application | Sensitivity | Via |", "|---|---|---|---|"]
        lines += [f"| {e} | {ents[e]['Application']} | {ents[e]['Sensitivity']} | {', '.join(v)} |" for e, v in sorted(person_ents[eid].items())]
        return lines + [""]

    first = lambda pred: next(p["EmployeeId"] for p in people if pred(p))
    samples = [
        ("DT01022", "Financial Controller: the only approved SoD exception (EXC-001)."),
        (first(lambda p: p["JobCode"] == "ENG-DEVOPS"), "DevOps engineer: production deploy rights, so must never get repository admin (SOD-02)."),
        ("DT01196", "SOC contractor: gets the limited SOC role, not Security Reader, because contractors can't hold High access."),
        (first(lambda p: p["EmployeeType"] == "Intern" and p["JobCode"] == "ENG-SWE"), "Software engineering intern: same job role as engineers, nothing High."),
        ("DT01015", "Senior IAM engineer: standing Global Reader, plus PIM-eligible admin roles."),
        ("DT01101", "Pre-hire: roles are calculated now but only take effect when HR activates the account (groups require accountEnabled = true)."),
    ]
    rep += ["", "## Sample personas", ""]
    for eid, why in samples:
        rep += persona(eid, why)
    (out / "access-model-report.md").write_text("\n".join(rep), encoding="utf-8")

    print("\n".join(rep[:12]))
    for c, s, m in chk.items:
        if s in ("ERROR", "WARNING"):
            print(f"  {s} {c}: {m}")
    print(f"\nOutputs written to {out}")
    sys.exit(1 if errs else 0)


if __name__ == "__main__":
    main()
