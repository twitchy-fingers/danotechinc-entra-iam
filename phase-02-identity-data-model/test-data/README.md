# Test data

These files are **deliberately broken** copies of the HR feed. They prove the validator catches each class of defect before it can reach Entra ID. Never provision from them.

## `employees-with-errors.csv`

| Injected defect | Rule | EmployeeId | Person |
|---|---|---|---|
| Contractor with EndDate removed | DQ-13 | DT01082 | Ashley King |
| JobCode typo FIN-ACT | DQ-06 | DT01039 | Taylor Coleman |
| Manager DT09999 does not exist | DQ-08 | DT01099 | Neha Menon |
| Engineering job code but Department set to Sales | DQ-07 | DT01139 | Kwame Osei |
| UsageLocation GB for a Lagos employee | DQ-16 | DT01124 | Femi Okonkwo |
| Active with EndDate 2026-10-15 already passed | DQ-15 | DT01092 | Yaa Addo |
| EndDate before HireDate | DQ-14 | DT01067 | Ananya Khan |
| UPN with uppercase and accent-free mismatch | DQ-05 | DT01125 | Olumide Ojo |
| Manager set to DT01175 (who reports to DT01173): loop | DQ-09 | DT01173 | Kofi Addo |
| Manager set to DT01173: loop | DQ-09 | DT01175 | Aisha Ojo |
| Trailing space in FirstName | DQ-19 | DT01055 | Ama Boateng |
| Manager removed: second record without a manager | DQ-10 | DT01072 | Akosua Mensah |
| Second record re-uses an existing EmployeeId | DQ-03 | DT01112 | Test Duplicate |

Expected result: **BLOCKED**, with at least one ERROR for every rule above except DQ-19 (WARNING). Some defects trigger more than one finding: the duplicate ID is reported on both rows, the reversed dates also make the record an unprocessed leaver (DQ-15), and the trailing space breaks both name hygiene checks.

## `employees-truncated.csv`

The first 150 rows of the real feed, simulating an HR export that stopped part-way. On its own it passes validation, because every remaining record is internally consistent. Run it with the real file as `--previous`:

Run from this folder in PowerShell:

```powershell
python ..\scripts\python\validate_hr_feed.py employees-truncated.csv --previous ..\..\data\hr\employees.csv
```

Expected result: **BLOCKED by DQ-21**. 50 of 200 records (25%) disappeared, above the 10% threshold. Without this guard, a truncated file would look like 50 people left the company, and Phase 04 would disable 50 accounts.
