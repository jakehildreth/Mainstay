# Mainstay

Keeps branch protection consistent across every repository you own.

GitHub has no account level setting that applies branch protection to new repositories. Organization rulesets can do it, but they need a paid plan and they do not cover a personal account at all. Mainstay closes that gap: it runs on a schedule, finds repositories missing the canonical ruleset, and creates it.

The sweep is idempotent. It creates what is missing and never edits or removes an existing ruleset, so a deliberate per repository exception survives.

## What it applies

A branch ruleset targeting the repository default branch:

| Rule | Effect |
| --- | --- |
| `pull_request` @ 0 approvals | All merges go through a PR. No reviewer required. |
| `non_fast_forward` | No force pushes. |
| `deletion` | The branch cannot be deleted. |

`bypass_actors` is empty, so the rule applies to administrators too.

Targeting uses `~DEFAULT_BRANCH` rather than a literal branch name, so repositories that use something other than `main` are handled correctly.

`require_extra_approval_for_unattributed_changes` is set to `false` on purpose. Left at its default it can demand an approval despite the approval count being zero, which contradicts the point of the rule.

## Requirements

- PowerShell 7.4+ (this runs in GitHub Actions, where `pwsh` is preinstalled)
- A GitHub App installed on every account you want swept, granted **Administration: write** and **Contents: read** on those repositories. The workflow mints a short lived installation token from the App for each run.

The workflow `GITHUB_TOKEN` cannot do this. It is scoped to the repository containing the workflow, so it cannot administer any other repository. The App's private key is stored once as a repository secret and never expires, so there is no token to rotate by hand.

## Quick start

Locally, authenticate with the `gh` CLI token. It already carries `repo` scope, which covers everything a sweep needs, and it saves minting a second credential:

```powershell
cd /path/to/Mainstay
Import-Module ./Mainstay.psd1 -Force

$env:MAINSTAY_TOKEN = gh auth token

# See what would change, without changing anything
Invoke-MainstaySweep -Owner 'yourname' -OwnerType User -WhatIf

# Apply
Invoke-MainstaySweep -Owner 'yourname' -OwnerType User
```

`-Token` defaults to the `MAINSTAY_TOKEN` environment variable, so setting it once per session means the parameter can be omitted. Pass `-Token` explicitly if you would rather not set the variable.

Leave `-WhatIf` on unless you actually intend to create rulesets.

## Credentials

Three credentials are in play. They do the same job in different places, and mixing them up is the easiest way to confuse yourself later.

| | Used by | Scope | Notes |
| --- | --- | --- | --- |
| `gh auth token` | You, locally | Broad. Whatever your `gh` login holds | Convenient for local runs. Rotates when you re-authenticate |
| App private key secret | The workflow, to mint tokens | Grants only what the App holds: Administration write, Contents read | Stored once as `MAINSTAY_APP_PRIVATE_KEY`. Never expires. See the compromise runbook in `docs/runbooks/` |
| Installation token | The sweep itself, per run | One owner, one hour | Minted fresh by `create-github-app-token` each run. Never stored |

`Contents: read` is not optional. Mainstay checks whether a repository has any commits before protecting it, and listing branches needs that permission. Without it, every repository that still needs a ruleset fails with `403`, and the sweep silently never creates anything.

## Examples
Sweep your personal account, leaving one repository alone:

```powershell
Invoke-MainstaySweep -Owner 'yourname' -OwnerType User -ExcludeRepository 'LegacyThing'
```

Sweep one organization:

```powershell
Invoke-MainstaySweep -Owner 'org-one' -OwnerType Org
```

The sweep covers a single account per call, because an installation token is scoped to one account. The scheduled workflow calls it once per account through a matrix.

Keep private repository names out of a public log:

```powershell
Invoke-MainstaySweep -Owner 'yourname' -OwnerType User -RedactPrivateName -RedactionSalt $salt
```

Private names become a stable marker such as `<private:9f2a41c8>`. The same repository produces the same marker every run, so a repeatedly failing repository can be tracked across runs without disclosing which one it is.

### Why the salt matters

Without a salt the marker is a plain hash of the repository name. Repository names are short and predictable, so anyone reading a public log can hash a list of likely names and match them against the markers. The redaction stops casual reading, not a motivated guesser.

A salt that is not published removes that shortcut. Markers stay stable run to run, so correlation still works, but they cannot be reproduced from a name alone.

`-RedactionSalt` defaults to the `MAINSTAY_SALT` environment variable. Redacting without one is allowed and produces a warning.

Generate one with:

```powershell
[Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
```

### Identifying a redacted repository

The salt lives only in the `MAINSTAY_SALT` secret, and GitHub will not read a secret back. Nobody can map a marker to a name from the logs alone, including you.

That is not a problem, because you never need the salt for it. To find out which repository a marker refers to, run locally without redaction and read the real names:

```powershell
$env:MAINSTAY_TOKEN = gh auth token
Invoke-MainstaySweep -Owner 'yourname' -OwnerType User -WhatIf
```

Redaction exists to protect the public Actions log. It was never meant to hide anything from you.

Setting `MAINSTAY_SALT` also invalidates every marker published before it. Older logs cannot be correlated with newer ones, which is the intended effect.

## Running it on a schedule

`.github/workflows/sweep.yml` runs the sweep daily at 06:00 UTC, and on demand through **Actions > Sweep > Run workflow**. The manual run takes a `whatIf` input for a dry run.

The workflow runs one job per account through a matrix. Each job mints a one hour installation token for that account with `create-github-app-token`, then sweeps only that account. The accounts, their type (`User` or `Org`), and any per-account exclusions are the matrix `include` rows at the top of the job.

Two secrets and one variable configure the App:

| Name | Kind | Holds |
| --- | --- | --- |
| `MAINSTAY_APP_CLIENT_ID` | variable | The App's client ID |
| `MAINSTAY_APP_PRIVATE_KEY` | secret | The App's private key. Never expires |
| `MAINSTAY_SALT` | secret | Optional redaction salt |

Setting them:

```bash
gh variable set MAINSTAY_APP_CLIENT_ID --repo owner/Mainstay --body '<client-id>'
gh secret set MAINSTAY_APP_PRIVATE_KEY --repo owner/Mainstay < path/to/private-key.pem
gh secret set MAINSTAY_SALT          --repo owner/Mainstay
```

Triggering a dry run and reading the result:

```bash
gh workflow run sweep.yml --repo owner/Mainstay -f whatIf=true
gh run watch --repo owner/Mainstay
gh run view --repo owner/Mainstay --web
```

A job that reports every repository for its account as `Failed` usually means the App was uninstalled or its key revoked: the workflow treats all-repositories-failed as an authentication problem, exits non-zero, and GitHub emails you. A partial failure — some repositories succeed, a few report `Failed` — stays green, because that is a per-repository cause such as a free private plan. A job that fails at the token minting step means the App is not installed on that account or the key is wrong.

> This repository is public, which means its Actions logs are readable by anyone. The workflow passes `-RedactPrivateName` for that reason. Remove it only if the repository is private.

## What gets skipped

A repository is left alone when it is a fork, is archived, has no commits yet, is named in `-ExcludeRepository`, or you do not hold admin permission on it.

The empty repository case matters more than it looks. A ruleset requiring a pull request on the default branch would stand in the way of the very first push, so Mainstay waits until a repository has at least one branch before protecting it.

Branch protection on a private repository requires a paid plan. Private repositories on a free account or free organization are reported as `Failed` with the upgrade message returned by GitHub.

## Tests

```powershell
Invoke-Pester -Path ./Tests
```

## License

MIT License w/Commons Clause - see [LICENSE](LICENSE) file for details.

---

Made with 💜 by [Jake Hildreth](https://jakehildreth.com)
