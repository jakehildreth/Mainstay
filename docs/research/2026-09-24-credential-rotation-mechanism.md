# Research: Which credential mechanism should Mainstay use so rotation never depends on a human?

**Date:** 2026-09-24 · **Status:** Complete · **Recommendation:** Candidate 1 — GitHub App + `actions/create-github-app-token`

**Context.** Mainstay (jakehildreth/Mainstay, public repo) runs `.github/workflows/sweep.yml` daily at 06:00 UTC. The sweep applies a branch-protection ruleset to every repo owned by personal account `jakehildreth` plus orgs `gilmourltd` and `cliux-org` (Jake owns/admins all three). It authenticates with `secrets.MAINSTAY_TOKEN`, currently a fine-grained PAT with `Administration: write` and `Contents: read`. The workflow's own `GITHUB_TOKEN` is unusable (scoped to the containing repo). Logs are world-readable.

---

## Candidate 1: GitHub App + actions/create-github-app-token

### (a) Can a GitHub App hold the "Administration" repository permission and create repo rulesets via REST?

**Yes.** `POST /repos/{owner}/{repo}/rulesets` ("Create a repository ruleset") is listed under **Repository permissions for "Administration"** (access: `write`) in *Permissions required for GitHub Apps*, and the **Tokens** column is `UAT, IAT` — i.e. a GitHub App **installation access token** works. The same table lists `PUT`/`DELETE` ruleset endpoints under Administration:write. `GET /repos/{owner}/{repo}/branches` and `GET /repos/{owner}/{repo}/branches/{branch}` sit under **Repository permissions for "Contents"** (read), also `UAT, IAT`. So an App granted repository permissions `Administration: write` + `Contents: read` covers the sweep's whole API surface.

- Source: https://docs.github.com/en/rest/authentication/permissions-required-for-github-apps#repository-permissions-for-administration (rulesets rows) and `#repository-permissions-for-contents` (branches rows)
- Ruleset endpoint itself: https://docs.github.com/en/rest/repos/rules#create-a-repository-ruleset

### (b) One App, three installations — and how create-github-app-token picks the installation

**Yes, one App installed in three places is the documented model.** GitHub Docs: "You can install the same GitHub App on multiple accounts. For example, if you install the app on your personal account and on a few organizations that you own, you'll be able to use the app on your personal repositories, on the organizations where you installed the app, and on repositories owned by those organizations."

- Source: https://docs.github.com/en/apps/using-github-apps/installing-a-github-app-from-a-third-party#about-installing-github-apps

Installation tokens are **per-installation**: an installation access token is scoped to the account where that installation lives ("API requests made by an app installation … access resources owned by that installation"). There is no single token spanning all three accounts; the workflow mints one installation token per target account.

- Source: https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation

`actions/create-github-app-token` selects the installation via the **`owner` input** ("Create a token for all repositories in another owner's installation": `owner: another-owner`). For multiple accounts, the README's own pattern is a **matrix strategy** ("Create tokens for multiple user or organization accounts"), one step invocation per owner. Without `owner`, it defaults to the current repository's owner — which would be wrong here since Mainstay must act on `gilmourltd` and `cliux-org` too. Optional `repositories` narrows scope further; optional `permission-*` inputs can only *reduce* what the installation was granted.

- Source: https://github.com/actions/create-github-app-token/blob/main/README.md (sections: "Create a token for all repositories in another owner's installation", "Create tokens for multiple user or organization accounts", "Create a token with specific permissions")

### (c) Installation token lifetime

**1 hour.** "The installation access token will expire after 1 hour." (docs.github.com); the action README repeats it: "An installation access token expires after 1 hour."

- Sources: https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation#using-an-installation-access-token-to-authenticate-as-an-app-installation ; https://github.com/actions/create-github-app-token/blob/main/README.md

A daily sweep that finishes in minutes is unaffected — a fresh token is minted per run, per owner.

### (d) What is stored long-term; does the private key expire?

Stored as Actions secrets/variables in jakehildreth/Mainstay: the App's **Client ID** (README recommends a repository *variable*) and the App's **private key** (repository *secret*). Rotation: **none required by GitHub policy.** "Private keys do not expire and instead need to be manually revoked." Up to 25 keys per App may exist so a key can be rotated without downtime if desired — purely an operator choice.

- Sources: https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/managing-private-keys-for-github-apps ("Private keys do not expire…") ; https://github.com/actions/create-github-app-token/blob/main/README.md (setup steps 2–3)

### (e) Exact workflow diff shape

Replace the PAT-secret env wiring with a token-minting step per owner. Because the PowerShell module currently takes one `MAINSTAY_TOKEN` and iterates owners internally, the smallest-diff shape that matches the action's documented multi-account pattern is a **matrix job over owners**, passing each minted token as `MAINSTAY_TOKEN`:

```yaml
jobs:
  sweep:
    strategy:
      fail-fast: false
      matrix:
        owner: [jakehildreth, gilmourltd, cliux-org]
    steps:
      - uses: actions/create-github-app-token@v3
        id: app-token
        with:
          client-id: ${{ vars.MAINSTAY_APP_CLIENT_ID }}
          private-key: ${{ secrets.MAINSTAY_APP_PRIVATE_KEY }}
          owner: ${{ matrix.owner }}
      - name: Run sweep
        shell: pwsh
        env:
          MAINSTAY_TOKEN: ${{ steps.app-token.outputs.token }}
        run: # ... unchanged, scoped to ${{ matrix.owner }} ...
```

(Alternatively one job calling the step three times into three env vars; the matrix is the README's documented pattern.)

- Source: https://github.com/actions/create-github-app-token/blob/main/README.md

### Org installation specifics (cross-cutting)

**Organization owners can install GitHub Apps on their organization** — no other approver involved. Jake is owner of both orgs, so installation on `gilmourltd` and `cliux-org` is a unilateral settings action (Install App → choose account → choose All repositories). Non-owners would only trigger an install *request* to the owner; irrelevant here.

- Source: https://docs.github.com/en/apps/using-github-apps/installing-a-github-app-from-a-third-party#requirements-to-install-a-github-app ("Organization owners can install GitHub Apps on their organization.")
- Own-app install flow: https://docs.github.com/en/apps/using-github-apps/installing-your-own-github-app (app must be "Any account" visibility to install beyond the owning account)

---

## Candidate 2: Fine-grained PAT at maximum lifetime

### Current documented expiration limit

The historical "fine-grained PATs must expire" rule (2022 beta: tokens "must expire") was **relaxed in October 2024**: "developers can now create fine-grained tokens with no expiration for personal projects." Current docs' creation step: "Infinite lifetimes are allowed but may be blocked by a maximum lifetime policy set by your organization or enterprise owner." The URL-prefill parameter accepts `expires_in=none`.

- Sources: https://github.blog/changelog/2024-10-18-new-pat-rotation-policies-preview-and-optional-expiration-for-fine-grained-pats/ ; https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token (step 7 and `expires_in` row: "Integer between 1 and 366, or `none`")

**Catch that matters for Mainstay:** "Enterprises and organizations have a **366 day expiration policy for fine-grained tokens by default**, so developers still can't create infinite lifetime fine-grained PATs for use against an organization they're a member of, unless the administrator relaxes the policy." A fine-grained PAT has exactly **one resource owner**; Mainstay needs to write to repos in `gilmourltd` and `cliux-org`, so the PAT(s) targeting those orgs are capped at 366 days unless Jake changes each org's policy. Only the `jakehildreth`-owned-repos PAT could be infinite. (Also note: the sweep today uses *one* PAT — a single fine-grained PAT cannot span multiple owners, so the current setup must already be either multiple secrets or a personal-account PAT leaning on public-repo read; an org-owned PAT is per-org.)

- Sources: changelog above; policy docs: https://docs.github.com/en/organizations/managing-programmatic-access-to-your-organization/setting-a-personal-access-token-policy-for-your-organization#enforcing-a-maximum-lifetime-policy-for-personal-access-tokens ("the default the maximum lifetime policy for organizations is set to expire within 366 days")
- One-owner-per-token: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens ("Each token is limited to access resources owned by a single user or organization.")

### What renewal requires

Purely manual: UI → regenerate/create token → paste new value into the repo secret. GitHub offers pre-filled creation URLs (`.../personal-access-tokens/new?name=...&administration=write&contents=read&target_name=...&expires_in=366`) which trims the click-path but not the human dependency.

- Source: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#pre-filling-fine-grained-personal-access-token-details-using-url-parameters

### What GitHub does proactively

- At expiry the token is **automatically revoked** and cannot be restored: "Upon reaching your token's expiration date, the token is automatically revoked… It is not possible to restore an expired or revoked token."
- An unused PAT is auto-revoked after **one year** regardless of expiry.
- **No advance-warning email timing is documented.** GitHub's docs for PATs document revocation reasons and the org non-compliant-token behavior ("Users will learn that their existing token is non-compliant when API calls for your organization are rejected"), but no documented pre-expiry email schedule for PATs. Treat reminder emails as best-effort, not a control. (GitHub's own docs point users at failing API calls as the discovery mechanism.)

- Sources: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/token-expiration-and-revocation ; https://docs.github.com/en/organizations/managing-programmatic-access-to-your-organization/setting-a-personal-access-token-policy-for-your-organization#enforcing-a-maximum-lifetime-policy-for-personal-access-tokens

### Failure mode if forgotten

Daily sweep starts failing with `401 {"message":"Bad credentials"}` (verified empirically today against `api.github.com/user` with an invalid token) on every target repo until a human rotates. Rotation does not "never depend on human memory" — it depends on it once per 366 days per org at best.

---

## Candidate 3: Self-renewing PAT

### (a) Can a PAT be minted programmatically?

**No.** There is no REST endpoint to create personal access tokens. The only PAT-management APIs that exist are **org-level, GitHub-App-only** endpoints to *list/approve/deny/revoke* fine-grained PAT requests and tokens (`organization_personal_access_tokens`, `organization_personal_access_token_requests` permissions) — introduced March 2023. Creation itself happens only through the web UI flow (docs document UI steps and pre-filled URLs; nothing else).

- Sources: https://github.blog/changelog/2023-03-24-organization-apis-for-fine-grained-pats-management/ ("Only a GitHub app is able to call these APIs… manage the active tokens" — approve/revoke only) ; https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens (creation is UI-only; note "If you require more tokens or are building automations, consider using a GitHub App")

### (b) Can a PAT update the Actions secret it will become?

Yes in isolation — `PUT /repos/{owner}/{repo}/actions/secrets/{secret_name}` is available to fine-grained PATs with repository **Secrets: write** — but it is **moot**: there is no API to produce the new PAT *value* to write (per (a)).

- Source: https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens#repository-permissions-for-secrets

### (c) Conclusion

**Candidate 3 collapses.** The renewal pipeline has an unbridgeable gap at step one (minting the replacement token). Any "self-renewing PAT" scheme would require browser/UI automation, which is out of scope and fragile by design.

---

## Cross-cutting comparison

| | **1. GitHub App** | **2. Fine-grained PAT max lifetime** | **3. Self-renewing PAT** |
|---|---|---|---|
| Stored long-term | App Client ID (variable) + private key (secret) in Mainstay repo | 1–3 PAT values as secrets (one per owner — a PAT has a single resource owner) | PAT + Secrets:write PAT (hypothetical) |
| What rotates, how often | Installation tokens, minted fresh **per run**, 1-hour TTL. Private key **never expires** (manual revoke only) | PAT expires ≤366 days for org-owned resources (default org policy); personal-account PAT can be infinite | — |
| Annual human burden | **Zero** after setup (setup: create App, 3 installs, store key) | ≥1 rotation per org-scoped PAT per year, manual, or relax org lifetime policy (weakens org posture) | Impossible |
| Failure mode if forgotten | None — nothing to remember | Silent daily 401 `Bad credentials` sweep failures until rotated | — |
| Blast radius if stored secret leaks | Private key ⇒ attacker can mint installation tokens for **only** the 3 installations, with **only** Administration:write + Contents:read, each token dying in ≤1h; revoke key + uninstall to kill. Attributable to the App in audit logs | Leaked PAT is usable until expiry (up to 366 days) with its full permissions, acting **as Jake the user**; GitHub auto-revokes tokens pushed to public repos/gists, but a value skimmed from logs isn't "pushed" | — |
| Public-repo log exposure | Mitigated by design: the only value ever in a run env is a 1-hour token; secret masking applies. Push-protection auto-revocation covers GitHub App tokens if printed | A PAT leaked in logs stays live for months; auto-revocation only triggers on push to a repo/gist | — |

Notes on exposure: GitHub automatically revokes PATs and GitHub App tokens "pushed to a public repository or public gist" — but that scanner does not cover values exfiltrated via Actions logs, so the structural difference (1-hour token vs months-long PAT) is what matters for the public Mainstay repo.

- Source: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/token-expiration-and-revocation#token-revoked-when-pushed-to-a-public-repository-or-public-gist

## Recommendation for THIS setup

**Use Candidate 1: a GitHub App owned by `jakehildreth`, granted repository permissions `Administration: write` and `Contents: read`, installed on all three accounts (`jakehildreth`, `gilmourltd`, `cliux-org`), with `actions/create-github-app-token@v3` minting a per-owner installation token in a matrix job (or three sequential steps), each exposed to the sweep as `MAINSTAY_TOKEN`.**

Why it wins here, concretely:

1. **Rotation never depends on a human** — the question asked. The long-lived secret (private key) never expires under GitHub policy; short-lived tokens are derived at runtime.
2. **Three installations are explicitly supported** ("install the same GitHub App on multiple accounts"), and Jake owns all three, so installation is a unilateral owner action with no approval flow.
3. **The exact permissions needed exist for Apps**: Administration:write covers `POST /repos/{owner}/{repo}/rulesets` for installation tokens; Contents:read covers branch listing.
4. **Public-repo blast radius is minimal**: a log leak yields at most a 1-hour, two-permission, per-owner token; the private key never enters the runner unless the step is misconfigured to echo it.
5. Candidate 2 fails the premise (366-day org policy default forces an annual human ritual per org, and expiry discovery is a failing API call, not a documented advance warning). Candidate 3 is impossible (no PAT-creation API).

### Auth-failure error shapes for the "fail loudly" ticket (recommended path)

Grounded in docs and verified empirically 2026-09-24:

- **Expired/revoked/invalid installation token or PAT** → `401 Unauthorized`, body `{"message":"Bad credentials","documentation_url":"https://docs.github.com/rest","status":"401"}`. (Verified against `GET /user` with an invalid token; documented: "Authenticating with invalid credentials will initially return a `401 Unauthorized` response.") Source: https://docs.github.com/en/rest/authentication/authenticating-to-the-rest-api#failed-login-limit
- **Valid token, insufficient permission or wrong installation/owner** → `403 Forbidden` with `"Resource not accessible by integration"` (App token) or `"Resource not accessible by personal access token"`, plus the `X-Accepted-GitHub-Permissions` header naming the required permission set. Source: https://docs.github.com/en/rest/using-the-rest-api/troubleshooting-the-rest-api#resource-not-accessible
- **Resource hidden from the installation** (repo outside the installation's granted repos, or private repo the token can't see) → `404 Not Found` (GitHub deliberately 404s rather than confirms existence). Source: https://docs.github.com/en/rest/using-the-rest-api/troubleshooting-the-rest-api#404-not-found-for-an-existing-resource
- **create-github-app-token step itself fails** (bad key, App not installed on `owner`, or `permission-*` exceeding the installation's grant) → the *step* fails before the sweep runs ("Setting a permission that the installation does not have will result in an error."). Source: https://github.com/actions/create-github-app-token/blob/main/README.md
- Repeated 401s in a short window → GitHub temporarily rejects **all** auth attempts from that actor with `403` (failed-login limiting) — the loud-failure logic should treat 403-after-401s as auth-class failure, not permission drift. Source: https://docs.github.com/en/rest/authentication/authenticating-to-the-rest-api#failed-login-limit
- Not auth but relevant to the sweep: branch protection on a private repo in a **free** org is refused with `403` regardless of mechanism (already encoded in `MAINSTAY_EXCLUDE` for `gilmour.ltd`).

Setup checklist for the implementation ticket: create App (Any account visibility) → grant repo perms Administration:write + Contents:read, no webhook needed → generate private key → install on all three accounts (All repositories) → store `MAINSTAY_APP_CLIENT_ID` (variable) and `MAINSTAY_APP_PRIVATE_KEY` (secret) on jakehildreth/Mainstay → matrix the sweep over owners with `owner: ${{ matrix.owner }}` → delete the old `MAINSTAY_TOKEN` PAT(s) after cutover.
