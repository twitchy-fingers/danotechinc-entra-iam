# HR feed validation report

- File: `employees-with-errors.csv`
- Evaluated as of: 2026-11-05
- Contract version: 1.0
- Records: 201
- Errors: **14**  ·  Warnings: **7**
- Result: **BLOCKED: fix errors before provisioning**

## Summary by rule

| Rule | Severity | Count |
|---|---|---|
| DQ-03 | ERROR | 2 |
| DQ-05 | ERROR | 1 |
| DQ-06 | ERROR | 1 |
| DQ-07 | ERROR | 1 |
| DQ-08 | ERROR | 1 |
| DQ-09 | ERROR | 2 |
| DQ-10 | ERROR | 1 |
| DQ-13 | ERROR | 1 |
| DQ-14 | ERROR | 1 |
| DQ-15 | ERROR | 2 |
| DQ-15 | WARNING | 1 |
| DQ-16 | ERROR | 1 |
| DQ-19 | WARNING | 2 |
| DQ-20 | WARNING | 4 |

## Findings

| Severity | Rule | EmployeeId | Detail |
|---|---|---|---|
| ERROR | DQ-03 | DT01112 | EmployeeId appears 2 times |
| ERROR | DQ-03 | DT01112 | EmployeeId appears 2 times |
| ERROR | DQ-05 | DT01125 | UPN 'Olumide.ojo@danotechinc.onmicrosoft.com' breaks the naming rule (first.last[n]@danotechinc.onmicrosoft.com) |
| ERROR | DQ-06 | DT01039 | JobCode 'FIN-ACT' not in job code catalogue |
| ERROR | DQ-07 | DT01139 | JobCode ENG-SWE-SR belongs to ENG, record says SAL |
| ERROR | DQ-08 | DT01099 | Manager DT09999 not found in file |
| ERROR | DQ-09 | DT01173 | Reporting line loops back on itself |
| ERROR | DQ-09 | DT01175 | Reporting line loops back on itself |
| ERROR | DQ-10 | - | Expected exactly one record without a manager (the CEO); found: DT01001 Daniel Opara, DT01072 Akosua Mensah |
| ERROR | DQ-13 | DT01082 | Contractor without EndDate: account would never expire |
| ERROR | DQ-14 | DT01067 | EndDate 2018-01-01 is not after HireDate 2020-03-02 |
| ERROR | DQ-15 | DT01067 | Active but EndDate 2018-01-01 has passed: leaver not processed |
| ERROR | DQ-15 | DT01092 | Active but EndDate 2026-10-15 has passed: leaver not processed |
| ERROR | DQ-16 | DT01124 | UsageLocation GB doesn't match Nigeria (NG) |
| WARNING | DQ-15 | DT01101 | Still PreHire on or after start date 2026-11-02: HR hasn't confirmed the start |
| WARNING | DQ-19 | DT01055 | FirstName has extra spaces |
| WARNING | DQ-19 | DT01055 | DisplayName 'Ama Boateng' differs from 'FirstName LastName' |
| WARNING | DQ-20 | DT01089 | Contract runs 451 days; policy maximum is 12 months before renewal |
| WARNING | DQ-20 | DT01154 | Contract runs 392 days; policy maximum is 12 months before renewal |
| WARNING | DQ-20 | DT01192 | Contract runs 481 days; policy maximum is 12 months before renewal |
| WARNING | DQ-20 | DT01196 | Contract runs 422 days; policy maximum is 12 months before renewal |
