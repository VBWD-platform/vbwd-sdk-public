# VBWD SDK — Free Plugin Set (CE install)

`recipes/dev-install-ce.sh` installs this curated Community-Edition plugin set.
The **`PLUGIN_REGISTRY`** array in that recipe is the single source of truth: each
row is `id | backend_dir | fe_user_plugin | fe_admin_plugin | deps`, and the
`plugins.json` enable-manifests (backend + both frontends, build-time and runtime)
are generated from it, so the cloned set and the enabled set always match.

This set is kept in sync with the `vbwd-platform` free set (`docs/free-plugins.md`
there). `invoice` is **core** (not a plugin). `bot_base` and `referral` are pulled
in automatically as dependencies of the bot plugins.

## Installed plugins (21 logical + core)

| Feature | backend dir | fe-user | fe-admin | Seeds demo data |
|---|---|---|---|---|
| cms | `cms` | `cms` | `cms-admin` | ✓ (pages, layouts, widgets, styles) |
| email | `email` | — | `email-admin` | ✓ (templates) |
| subscription | `subscription` | `subscription` | `subscription-admin` | ✓ (plans, add-ons) |
| discount | `discount` | — | `discount-admin` | ✓ (coupons, rules) |
| token-payments | `token_payment` | `token-payment` | `token-payment-admin` | ✓ (token bundles) |
| shop | `shop` | `shop` | `shop-admin` | ✓ (products, stock) |
| booking | `booking` | `booking` | `booking` | ✓ (resources) |
| ghrm | `ghrm` | `ghrm` | `ghrm-admin` | ✓ (software packages) |
| dataset | `dataset` | `dataset` | `dataset` | ✓ |
| tarot | `tarot` | `tarot` | `tarot-admin` | ✓ (78 arcana) |
| checkout | `checkout` | `checkout` | — | ✓ |
| wp-import | `wp_import` | — | `wp-import` | — |
| cms-ai | `cms_ai` | — | `cms-ai` | — |
| paypal | `paypal` | `paypal-payment` | — | — (payment method) |
| stripe | `stripe` | `stripe-payment` | — | — (payment method) |
| meinchat-bot | `bot_meinchat` | — | — | ✓ |
| meinchat | `meinchat` | `meinchat` | `meinchat-admin` | ✓ |
| telegram | `bot_telegram` | — | `bot-telegram-admin` | — |
| meinchat-bot-llm | `bot_meinchat_llm` | — | — | ✓ |
| landing1 | — | `landing1` | — | — |
| _(dep)_ bot-base | `bot_base` | — | — | — |
| _(dep)_ referral | `referral` | — | — | — |
| **invoice** | _core_ | — | — | ✓ (core demo data) |

Backend dirs are the importable snake_case Python package names; the GitHub repo is
`vbwd-plugin-<dir with _→->`. fe-user/fe-admin dirs are the manifest keys the Vue
apps match; the fe-admin repo drops the trailing `-admin`.

## Dependency notes

- email → booking, shop, subscription
- subscription → ghrm, meinchat, tarot, dataset
- cms → cms-ai, wp-import, dataset (fe-user dataset/ghrm/checkout also import the
  fe-user `cms` plugin at build time)
- bot_base → bot-telegram, bot-meinchat, bot-meinchat-llm
- meinchat → bot-meinchat, bot-meinchat-llm, referral; referral → discount, meinchat
- Only `cms`, `cms_ai`, `bot_meinchat_llm` ship `requirements.txt` (installed by the
  api entrypoint at container start).

To change the set, edit one `PLUGIN_REGISTRY` row in `recipes/dev-install-ce.sh`
and update this file.
