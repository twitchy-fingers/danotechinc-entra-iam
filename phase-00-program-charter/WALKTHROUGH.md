# Phase 00 Walkthrough: Setting Up the Program

**Goal:** Create the GitHub repository that will hold the entire program, protect it properly, and record the facts about the tenant that later phases depend on.

**Time:** About 1 hour.
**Performed by:** Adaeze Nwosu (IAM Manager), with Kofi Owusu as reviewer.

## Prerequisites

- A GitHub account.
- [Git](https://git-scm.com/downloads) and the [GitHub CLI](https://cli.github.com/) (`gh`) installed.
- This repository's files on your machine.

---

## Step 1: Record what the tenant actually has

**Why:** Every later decision depends on licences. PIM, ID Protection, access reviews and Lifecycle Workflows only exist while P2 or Suite licences are active, and trials expire. Writing the facts down on day one prevents a nasty surprise in Phase 12 when a feature you planned around silently disappears.

1. Sign in to the [Microsoft Entra admin center](https://entra.microsoft.com) as `daniel.opara@danotechinc.onmicrosoft.com`.
2. Go to **Billing → Licenses → All products**.
3. For each product (Microsoft Entra ID P2, Microsoft Entra Suite), note the **total licences**, **assigned** and **expiry / next lifecycle date**.
4. Go to **Identity → Overview** and note the **Tenant ID**. You'll need it in every script.
5. Fill in [`docs/licensing.md`](../docs/licensing.md).

Phase 01 automates this check with a Graph script, so you can re-verify it at any time.

> **What to do with the expiry date:** Count the phases between now and expiry. If PIM (Phase 06), Conditional Access risk policies (Phase 07), entitlement management (Phase 12) or access reviews (Phase 13) fall after it, decide now whether to purchase licences or re-sequence. Record the decision as an ADR.

---

## Step 2: Create the repository

**Why public:** Branch rulesets and secret scanning are free on public repositories. On private repositories they need a paid GitHub plan. A public repo also doubles as a portfolio. Because this repo will never contain secrets (Step 4 enforces that), public is safe.

```bash
cd danotechinc-entra-iam
git init -b main
git add .
git commit -m "Phase 00: program charter, HR dataset, conventions"

gh auth login                    # choose GitHub.com, HTTPS, browser login
gh repo create danotechinc-entra-iam --public --source=. --push \
  --description "Enterprise IAM program on Microsoft Entra ID for fictional DanotechInc"
```

---

## Step 3: Protect the `main` branch

**Why:** The repository is the record of how identity is configured. If anyone can push directly to `main`, a change can reach the tenant without a second pair of eyes, which is exactly the "single engineer change" risk in the charter. Requiring a pull request with one approval is the Git equivalent of separation of duties.

Create a ruleset that blocks direct pushes and force-pushes, and requires a reviewed pull request:

```bash
OWNER=$(gh api user --jq .login)

gh api -X POST "repos/$OWNER/danotechinc-entra-iam/rulesets" --input - <<'JSON'
{
  "name": "protect-main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true
      }
    }
  ]
}
JSON
```

> **Working solo?** GitHub won't let you approve your own pull request. If you're the only contributor, set `required_approving_review_count` to `0`. You still get the PR record and checks; document that compensating control in an ADR.

---

## Step 4: Stop secrets from ever reaching the repo

**Why:** Phase 01 creates an automation app with a certificate, and later phases handle SAML signing certificates and client IDs. A leaked credential in a public repo is found by scanners within minutes. Push protection blocks the commit *before* it reaches GitHub, which is much better than detecting it afterwards.

```bash
gh api -X PATCH "repos/$OWNER/danotechinc-entra-iam" --input - <<'JSON'
{
  "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" }
  }
}
JSON
```

The [`.gitignore`](../.gitignore) at the root also excludes certificate files (`*.pfx`, `*.pem`, `*.key`), `.env` files and local output folders. Defence in depth: `.gitignore` prevents accidental staging, push protection catches anything that slips through.

---

## Step 5: Create a milestone for each phase

**Why:** Milestones let you track progress per phase and give GRC a clean view of what was done when. Closed issues under a milestone become part of the audit trail.

```bash
phases=(
 "00 Program charter" "01 Tenant foundation" "02 Identity data model" "03 RBAC design"
 "04 JML lifecycle" "05 Groups and app roles" "06 Privileged access"
 "07 Zero Trust Conditional Access" "08 SSO and federation" "09 Cloud IAM"
 "10 Non-human identities" "11 Agent authorization" "12 Entitlement management"
 "13 Access reviews" "14 Logging and monitoring" "15 Identity operations"
 "16 Identity vulnerability management" "17 Compliance" "18 Capstone"
)
for p in "${phases[@]}"; do
  gh api -X POST "repos/$OWNER/danotechinc-entra-iam/milestones" -f title="Phase $p" >/dev/null
  echo "Created milestone: Phase $p"
done
```

---

## Step 6: Create labels

**Why:** Labels let you filter work by type and risk. The `risk:high` label is a signal to the reviewer that a change could lock users or admins out, so it deserves a slower, more careful review.

```bash
gh label create "type:config"   --color 1f6feb --description "Tenant configuration change"
gh label create "type:docs"     --color 8250df --description "Documentation"
gh label create "type:script"   --color 2da44e --description "Automation script"
gh label create "type:evidence" --color bf8700 --description "Audit evidence"
gh label create "risk:high"     --color d1242f --description "Could cause lockout or broad access change"
gh label create "decision"      --color 0e8a16 --description "Needs or records an ADR"
```

---

## Step 7: Create a project board

**Why:** A board gives a single view of every phase's work: what's planned, in progress and done.

```bash
gh auth refresh -s project
gh project create --owner "$OWNER" --title "DanotechInc IAM Program"
```

Then, in the GitHub web UI, link the project to the repository (**Projects → Link a project**) and add a **Milestone** field to the board view.

---

## Step 8: Open the first issues

Create one issue per Phase 01 task so the next phase starts with a clear checklist:

```bash
gh issue create --title "Phase 01: Create and test break-glass accounts" \
  --milestone "Phase 01 Tenant foundation" --label "type:config,risk:high"
gh issue create --title "Phase 01: Baseline Conditional Access and disable security defaults" \
  --milestone "Phase 01 Tenant foundation" --label "type:config,risk:high"
gh issue create --title "Phase 01: Create Azure subscription and log pipeline" \
  --milestone "Phase 01 Tenant foundation" --label "type:config"
```

---

## Validation checklist

- [ ] `docs/licensing.md` completed with seat counts, expiry dates and Tenant ID
- [ ] Repository created and pushed
- [ ] Direct push to `main` is rejected (`git push origin main` from a local change should fail)
- [ ] Secret scanning and push protection show **Enabled** under **Settings → Code security**
- [ ] 19 milestones exist
- [ ] Project board linked to the repository
- [ ] Phase 01 issues created

Commit a screenshot of the Code security settings page to `phase-00-program-charter/evidence/` as audit evidence that secret protection was active from day one.

**Next:** [Phase 01 walkthrough](../phase-01-tenant-foundation/WALKTHROUGH.md)
