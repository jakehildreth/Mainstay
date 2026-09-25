# Runbook: Create and install the Mainstay GitHub App

One-time setup. You do this once, by hand, in the GitHub UI — no agent can do these authenticated steps for you. When it is done, the scheduled sweep authenticates as the App and no token ever needs rotating.

The code side is already merged: the workflow mints a one-hour installation token per account and sweeps that account. This runbook creates the credential that makes it live.

## 1. Create the App

1. Open https://github.com/settings/apps/new (your avatar → **Settings → Developer settings → GitHub Apps → New GitHub App**).
2. **GitHub App name:** `Mainstay branch protection`. The name must be unique across GitHub — the bare name `Mainstay` is taken by the account `@mainstay`, so use this. The workflow keys off the Client ID and private key, not the name, so the exact wording does not matter.
3. **Homepage URL:** `https://github.com/jakehildreth/Mainstay`.
4. **Webhook:** untick **Active**. The App reacts to nothing; it is only a credential.
5. **Repository permissions:**
   - **Administration:** Read and write
   - **Contents:** Read-only
6. Leave every other permission at **No access**.
7. **Where can this GitHub App be installed?** choose **Any account** — the App must install on the two orgs, not just your account.
8. Click **Create GitHub App**.

## 2. Collect the client ID and generate the private key

On the App's settings page after creation:

1. Copy the **Client ID** (a short alphanumeric string near the top, not the App ID). Store it as a repository *variable*:

   ```bash
   gh variable set MAINSTAY_APP_CLIENT_ID --repo jakehildreth/Mainstay --body '<client-id>'
   ```

2. Scroll to **Private keys → Generate a private key**. A `.pem` file downloads. Store it as a repository *secret*:

   ```bash
   gh secret set MAINSTAY_APP_PRIVATE_KEY --repo jakehildreth/Mainstay < ~/Downloads/<the-file>.pem
   ```

3. Delete the downloaded `.pem` after the secret is set.

## 3. Install the App on all three accounts

The App must be **public** before the organizations are selectable. A private App installs only on the account that owns it, so the orgs will not appear in the install list. If you left the App private at creation, make it public first: App settings → **Advanced** → **Danger zone** → **Make public**. (Setting it to **Any account** at creation is the same thing; the step only bites if the App is still private.)

From the App's settings page, **Install App** in the left rail. Install it three times, once per account, choosing **All repositories** each time:

| Account | Type |
| --- | --- |
| `jakehildreth` | personal account |
| `gilmourltd` | organization |
| `cliux-org` | organization |

For each org you may be redirected to that org's install page; as the org owner you approve it yourself. Verify all three appear under the App's **Installations**.

## 4. Confirm, then remove the old token

1. Trigger a dry run and watch every matrix job go green:

   ```bash
   gh workflow run sweep.yml --repo jakehildreth/Mainstay -f whatIf=true
   gh run watch --repo jakehildreth/Mainstay
   ```

   All three jobs (`jakehildreth`, `gilmourltd`, `cliux-org`) should pass. A job failing at the **Mint installation token** step means the App is not installed on that account or the key/client ID is wrong.

2. Once green, delete the old `MAINSTAY_TOKEN` secret — nothing reads it now:

   ```bash
   gh secret delete MAINSTAY_TOKEN --repo jakehildreth/Mainstay
   ```

## If something is wrong

A job that goes red after a previously green run means the key was revoked or the App uninstalled. See `docs/runbooks/app-key-compromise.md`.
