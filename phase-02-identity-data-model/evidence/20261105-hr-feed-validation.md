# HR feed validation report

- File: `employees.csv`
- Evaluated as of: 2026-11-05
- Contract version: 1.0
- Records: 200
- Errors: **0**  ·  Warnings: **6**
- Result: **PASSED: feed may be provisioned**

## Summary by rule

| Rule | Severity | Count |
|---|---|---|
| DQ-15 | WARNING | 1 |
| DQ-20 | WARNING | 5 |

## Findings

| Severity | Rule | EmployeeId | Detail |
|---|---|---|---|
| WARNING | DQ-15 | DT01101 | Still PreHire on or after start date 2026-11-02: HR hasn't confirmed the start |
| WARNING | DQ-20 | DT01082 | Contract runs 392 days; policy maximum is 12 months before renewal |
| WARNING | DQ-20 | DT01089 | Contract runs 451 days; policy maximum is 12 months before renewal |
| WARNING | DQ-20 | DT01154 | Contract runs 392 days; policy maximum is 12 months before renewal |
| WARNING | DQ-20 | DT01192 | Contract runs 481 days; policy maximum is 12 months before renewal |
| WARNING | DQ-20 | DT01196 | Contract runs 422 days; policy maximum is 12 months before renewal |

## Feed profile

- Records: **200**
- By employee type: Employee 184, Contractor 12, Intern 4
- By status: Active 194, PreHire 6
- People managers (derived `IsPeopleManager`): **29**
- Records with a future end date (leavers, contractors, interns): **20**

**Largest spans of control** (affects approval and review workload):

- Brandon Collins (DT01024): 16 direct reports
- Lucía Herrera (DT01010): 15 direct reports
- Ngozi Balogun (DT01027): 13 direct reports
- Rachel Okafor (DT01022): 13 direct reports
- Oluwaseun Ogunleye (DT01031): 12 direct reports

| Department | Records |
|---|---|
| Customer Success | 16 |
| Engineering | 54 |
| Executive Office | 3 |
| Finance | 18 |
| Human Resources | 12 |
| Information Security | 10 |
| Information Technology | 16 |
| Legal & Compliance | 7 |
| Marketing | 22 |
| Operations | 10 |
| Sales | 32 |
