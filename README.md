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
- A fine grained personal access token with **Administration: write** on the repositories you want swept

The workflow `GITHUB_TOKEN` cannot do this. It is scoped to the repository containing the workflow, so it cannot administer any other repository.

## Quick start

```powershell
Import-Module ./Mainstay.psd1

# See what would change, without changing anything
Invoke-MainstaySweep -Token $token -Owner 'yourname' -WhatIf

# Apply
Invoke-MainstaySweep -Token $token -Owner 'yourname'
```

## Examples

Sweep an account and two organizations, leaving one repository alone:

```powershell
Invoke-MainstaySweep -Token $token -Owner 'yourname' `
    -IncludeOrganization 'org-one', 'org-two' `
    -ExcludeRepository 'LegacyThing'
```

Keep private repository names out of a public log:

```powershell
Invoke-MainstaySweep -Token $token -Owner 'yourname' -RedactPrivateName
```

Private names become a stable marker such as `<private:9f2a41c8>`. The same repository produces the same marker every run, so a repeatedly failing repository can be tracked across runs without disclosing which one it is.

## Running it on a schedule

`.github/workflows/sweep.yml` runs the sweep daily at 06:00 UTC, and on demand through **Actions > Sweep > Run workflow**. The manual run takes a `whatIf` input for a dry run.

Configure it with the `env` block at the top of the job, and store the token as a repository secret named `MAINSTAY_TOKEN`.

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
