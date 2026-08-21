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

Locally, authenticate with the `gh` CLI token. It already carries `repo` scope, which covers everything a sweep needs, and it saves minting a second credential:

```powershell
cd /path/to/Mainstay
Import-Module ./Mainstay.psd1 -Force

$env:MAINSTAY_TOKEN = gh auth token

# See what would change, without changing anything
Invoke-MainstaySweep -Owner 'yourname' -WhatIf

# Apply
Invoke-MainstaySweep -Owner 'yourname'
```

`-Token` defaults to the `MAINSTAY_TOKEN` environment variable, so setting it once per session means the parameter can be omitted. Pass `-Token` explicitly if you would rather not set the variable.

Leave `-WhatIf` on unless you actually intend to create rulesets.

## Credentials

Two separate tokens are in play. They do the same job in different places, and mixing them up is the easiest way to confuse yourself later.

| | Used by | Scope | Notes |
| --- | --- | --- | --- |
| `gh auth token` | You, locally | Broad. Whatever your `gh` login holds | Convenient for local runs. Rotates when you re-authenticate |
| `MAINSTAY_TOKEN` secret | The workflow only | Fine grained: Administration write, Contents read | GitHub will not read it back. If you lose the value, mint a new one |

`Contents: read` is not optional. Mainstay checks whether a repository has any commits before protecting it, and listing branches needs that permission. Without it, every repository that still needs a ruleset fails with `403`, and the sweep silently never creates anything.

## Examples

Sweep an account and two organizations, leaving one repository alone:

```powershell
Invoke-MainstaySweep -Owner 'yourname' `
    -IncludeOrganization 'org-one', 'org-two' `
    -ExcludeRepository 'LegacyThing'
```

Keep private repository names out of a public log:

```powershell
Invoke-MainstaySweep -Owner 'yourname' -RedactPrivateName -RedactionSalt $salt
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
Invoke-MainstaySweep -Owner 'yourname' -WhatIf
```

Redaction exists to protect the public Actions log. It was never meant to hide anything from you.

Setting `MAINSTAY_SALT` also invalidates every marker published before it. Older logs cannot be correlated with newer ones, which is the intended effect.

## Running it on a schedule

`.github/workflows/sweep.yml` runs the sweep daily at 06:00 UTC, and on demand through **Actions > Sweep > Run workflow**. The manual run takes a `whatIf` input for a dry run.

Configure it with the `env` block at the top of the job. Store the token as a repository secret named `MAINSTAY_TOKEN`, and optionally a salt named `MAINSTAY_SALT`.

Setting the secrets:

```bash
gh secret set MAINSTAY_TOKEN --repo owner/Mainstay
gh secret set MAINSTAY_SALT  --repo owner/Mainstay
```

Triggering a dry run and reading the result:

```bash
gh workflow run sweep.yml --repo owner/Mainstay -f whatIf=true
gh run watch --repo owner/Mainstay
gh run view --repo owner/Mainstay --web
```

A run that reports every repository as `Failed` with `403` usually means the PAT is missing a permission. A run that fails immediately with `MAINSTAY_TOKEN secret is not set.` means the secret name does not match, which is case sensitive.

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
