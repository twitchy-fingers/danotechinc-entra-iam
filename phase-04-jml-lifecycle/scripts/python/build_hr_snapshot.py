#!/usr/bin/env python3
"""
build_hr_snapshot.py - produce the HR export for a given day.

DanotechInc's "HR system" is the master file (data/hr/employees.csv, as of
27 Oct 2026) plus the dated changes HR has made since (hr-changes/hr-changes.csv).
This script applies every change effective on or before --as-of and writes the
result: exactly what a real HR system would export that morning.

Why separate changes from the master file: it keeps the 200-person baseline
stable for Phases 02 and 03, and makes every joiner, mover and leaver an
explicit, dated, reviewable line, which is how HR change requests work.

Usage
  python build_hr_snapshot.py --as-of 2026-11-09
  python build_hr_snapshot.py --as-of 2026-11-09 --out ..\\..\\output\\hr-snapshot-20261109.csv
"""
import argparse
import csv
import sys
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
PHASE = HERE.parent.parent
REPO = PHASE.parent


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--as-of", default=date.today().isoformat())
    ap.add_argument("--master", default=str(REPO / "data" / "hr" / "employees.csv"))
    ap.add_argument("--changes", default=str(PHASE / "hr-changes" / "hr-changes.csv"))
    ap.add_argument("--out")
    args = ap.parse_args()
    as_of = date.fromisoformat(args.as_of)

    with open(args.master, encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        fields = reader.fieldnames
        rows = list(reader)
    by_id = {r["EmployeeId"]: r for r in rows}

    with open(args.changes, encoding="utf-8-sig", newline="") as f:
        changes = sorted(csv.DictReader(f), key=lambda c: (c["EffectiveDate"], c["ChangeId"]))

    applied, pending = [], []
    for c in changes:
        if date.fromisoformat(c["EffectiveDate"]) > as_of:
            pending.append(c)
            continue
        r = by_id.get(c["EmployeeId"])
        if r is None:
            sys.exit(f"{c['ChangeId']}: unknown EmployeeId {c['EmployeeId']}")
        if c["Field"] not in fields:
            sys.exit(f"{c['ChangeId']}: unknown field {c['Field']}")
        r[c["Field"]] = c["NewValue"]
        applied.append(c)

    out = Path(args.out) if args.out else PHASE / "output" / f"hr-snapshot-{as_of:%Y%m%d}.csv"
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

    ids = sorted({c["ChangeId"] for c in applied})
    print(f"HR snapshot as of {as_of}: {len(rows)} records, {len(ids)} change(s) applied ({', '.join(ids) or 'none'})")
    nxt = sorted({(c['EffectiveDate'], c['ChangeId'], c['Person']) for c in pending})[:3]
    if nxt:
        print("Next pending: " + "; ".join(f"{d} {i} {p}" for d, i, p in nxt))
    print(f"Written to {out}")


if __name__ == "__main__":
    main()
