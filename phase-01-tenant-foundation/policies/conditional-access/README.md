# Baseline Conditional Access policies

Policy definitions as JSON, deployed by `05-Deploy-BaselineConditionalAccess.ps1`. Keeping policies as code means every change is reviewed in a pull request and the history of the tenant's access rules lives in Git.

`{{BREAKGLASS_GROUP_ID}}` is replaced at deploy time with the object ID of `GRP-CA-Exclude-BreakGlass`, so no tenant-specific IDs are hard-coded.

## Roles targeted by CA100

| Role | Template ID |
|---|---|
| Global Administrator | `62e90394-69f5-4237-9190-012177145e10` |
| Privileged Role Administrator | `e8611ab8-c189-46e8-94e1-60213ab1f814` |
| Privileged Authentication Administrator | `7be44c8a-adaf-4e2a-84d6-ab2649e08a13` |
| Security Administrator | `194ae4cb-b126-40b2-bd5b-6091b380977d` |
| Conditional Access Administrator | `b1be1c3e-b65d-4f19-8427-f6fa0d97feb9` |
| Application Administrator | `9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3` |
| Cloud Application Administrator | `158c047a-c907-4556-b7ef-446551a6b5f7` |
| Authentication Administrator | `c4e39bd9-1100-46d3-8c65-fb160da0071f` |
| User Administrator | `fe930be7-5e62-47db-91af-98c3a49a38b1` |
| Helpdesk Administrator | `729827e3-9c14-49f7-bb1b-9608f156bbb8` |
| Groups Administrator | `fdd7a751-b60b-444a-984c-02652fe8fa1c` |
| Exchange Administrator | `29232cdf-9323-42fd-ade2-1d097af3e4de` |
| SharePoint Administrator | `f28a1f50-f6e7-4571-818b-6a12f2af6b6c` |
| Billing Administrator | `b0f54661-2d74-4c50-afa3-1ec803f12efe` |

Role-based targeting applies to **active** role holders. Phase 06 introduces PIM; eligible admins are covered once they activate, because activation makes the assignment active.
