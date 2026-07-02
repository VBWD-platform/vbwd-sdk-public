# GHRM — GitHub App private key

This directory holds the **GitHub App private key** the GHRM (GitHub Repo
Manager) plugin uses to authenticate as your GitHub App and manage repository
collaborators (add/remove buyers on purchase/cancellation).

```
var/ghrm/auth/github-app.pem   ← the private key (NEVER commit it)
```

- The host `var/` dir is bind-mounted into the backend container at `/app/var`,
  so the plugin reads the key at **`/app/var/ghrm/auth/github-app.pem`**
  (the default `github_app_private_key_path`).
- `*.pem` here is **git-ignored** (`var/ghrm/auth/*.pem` in the repo root
  `.gitignore`). Keep it that way — it is a secret.
- Permissions should be tight: `chmod 600 github-app.pem`.

---

## How to obtain the key

You create a **GitHub App**, then generate and download its private key.

### 1. Create the GitHub App

1. Go to **GitHub → Settings → Developer settings → GitHub Apps → New GitHub App**
   (for an organisation: **Org Settings → Developer settings → GitHub Apps**).
2. Fill in:
   - **GitHub App name** — any unique name, e.g. `MyPlatform Packages`
   - **Homepage URL** — your platform URL
   - **Webhook** — uncheck *Active* (not needed)
3. Under **Permissions → Repository permissions**, grant:
   - **Administration → Read & Write** (required to add/remove collaborators)
4. Under **Where can this GitHub App be installed?** choose **Only on this account**.
5. Click **Create GitHub App**.
6. Note the **App ID** on the next page → this is the `github_app_id` config value.

### 2. Generate and download the private key

1. On the App settings page, scroll to **Private keys**.
2. Click **Generate a private key** — GitHub downloads a `.pem` file.
3. Move/rename it into this directory as `github-app.pem`:
   ```bash
   mv ~/Downloads/your-app.*.private-key.pem var/ghrm/auth/github-app.pem
   chmod 600 var/ghrm/auth/github-app.pem
   ```
4. Restart (or it's picked up on next request) — the backend reads it at
   `/app/var/ghrm/auth/github-app.pem`.

> Lost the key or it leaked? Generate a new one in the same **Private keys**
> section and delete the old one. GitHub lets you hold multiple keys during
> rotation.

### 3. Install the App + get the Installation ID

1. On the App settings page click **Install App** → install it on your
   org/account → choose repositories.
2. After installing, the URL ends in the **Installation ID**:
   `https://github.com/settings/installations/XXXXXXXX` → `github_installation_id`.

---

## Related config keys (set in the GHRM plugin config)

| Key | Value |
|-----|-------|
| `github_app_id` | The App ID from step 1.6 |
| `github_app_private_key_path` | `/app/var/ghrm/auth/github-app.pem` (default) |
| `github_installation_id` | The Installation ID from step 3 |

Full setup (incl. the OAuth App for user login) lives in the plugin docs:
`vbwd-backend/plugins/ghrm/docs/github-integration.md` and
`vbwd-backend/plugins/ghrm/README.md`.
