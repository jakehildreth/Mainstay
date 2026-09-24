# Runbook: Mainstay App private key compromise

Use this if you suspect the Mainstay GitHub App's private key has leaked. The key lives in the `MAINSTAY_APP_PRIVATE_KEY` Actions secret on `jakehildreth/Mainstay`. A leaked key lets an attacker mint installation tokens scoped to `Administration: write` + `Contents: read` on the three installations; each token dies in one hour. Act promptly, but the one-hour token lifetime bounds the damage.

The Mainstay App never rotates its key on a schedule — GitHub keys do not expire. This runbook is the only rotation path.

## 1. Revoke the leaked key

Revoking kills every token the key could mint. Existing installation tokens already issued stay valid for the rest of their one-hour life, but no new ones can be made.

1. Open the App's settings: **GitHub → your avatar → Settings → Developer settings → GitHub Apps → Mainstay** (or https://github.com/settings/apps).
2. Scroll to **Private keys**.
3. Find the key by its fingerprint and click **Delete** (this is the revoke).

The next scheduled sweep will fail at the token-minting step and go red — that is expected until step 3 lands.

## 2. If the leak reached the installations

If you think the attacker actually used the key, not just saw it, cut access at the installation too:

1. Open https://github.com/settings/installations (personal account) and each org's **Settings → GitHub Apps** (`gilmourltd`, `cliux-org`).
2. For Mainstay, choose **Configure → Uninstall**, then reinstall with **All repositories**.

Uninstalling revokes all outstanding installation tokens for that installation immediately.

## 3. Generate a fresh key and update the secret

1. Back in the App settings → **Private keys → Generate a private key**. A `.pem` file downloads.
2. Update the Actions secret on the repo:

   ```bash
   gh secret set MAINSTAY_APP_PRIVATE_KEY --repo jakehildreth/Mainstay < path/to/downloaded.pem
   ```

   (Paste the file contents if your shell can't redirect: open the `.pem`, copy all of it including the `BEGIN/END` lines, and run `gh secret set MAINSTAY_APP_PRIVATE_KEY` then paste.)

3. Delete the downloaded `.pem` from your machine.

## 4. Confirm recovery

Trigger a dry run and watch it go green:

```bash
gh workflow run sweep.yml --repo jakehildreth/Mainstay -f whatIf=true
gh run watch --repo jakehildreth/Mainstay
```

A green run means the new key mints tokens and the sweep reaches every account. If it fails at the token step, the key wasn't stored correctly; if it fails per-repository, that is an ordinary cause, not the key.

## Blast radius, for reference

A leaked key is not a leaked password. It can only mint tokens for the App's three existing installations, with only the App's two permissions, and every token expires in one hour. Revoking the key (step 1) stops all future minting. This is deliberately narrower than a leaked PAT, which acts as you with full scope until expiry.
