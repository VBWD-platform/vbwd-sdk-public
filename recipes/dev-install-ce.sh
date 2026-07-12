#!/bin/bash
set -e

# VBWD Community Edition - Development Installation Script
# Works for both local development and GitHub Actions
# Usage: ./recipes/dev-install-ce.sh [--domain <hostname>] [--ssl]
#                                    [--admin-email <addr>] [--admin-password <pw>]
#                                    [--all-plugins | --plugins-list <id> [<id> ...]]
# Or set VBWD_DOMAIN / VBWD_SSL / VBWD_ADMIN_EMAIL / VBWD_ADMIN_PASSWORD env
# vars before running.
#
# Plugin selection:
#   --all-plugins                 Install the full curated demo set (DEFAULT).
#   --plugins-list cms shop tarot Install only the named plugins (+ their
#                                 declared dependencies, resolved automatically).
#
# Every installed plugin is ENABLED, has its demo settings applied (the
# plugin's config.json / admin-config.json), gets its demo data populated
# (plugins that ship a populate script), and has any bundled assets
# (prompts / templates under the plugin's var/ subtree) seeded into the
# shared var/ directory. Re-running is idempotent.
#
# Examples:
#   ./recipes/dev-install-ce.sh                              # http://localhost, admin@vbwd.local / admin123, all plugins
#   ./recipes/dev-install-ce.sh --domain myapp.com          # http://myapp.com
#   ./recipes/dev-install-ce.sh --domain myapp.com --ssl    # https://myapp.com
#   VBWD_DOMAIN=myapp.com VBWD_SSL=1 ./recipes/dev-install-ce.sh
#   ./recipes/dev-install-ce.sh --admin-email me@x.io --admin-password 'S3cret!'
#   ./recipes/dev-install-ce.sh --plugins-list cms shop tarot # CMS + Shop + Tarot (+ deps)
#
# The default admin (admin@vbwd.local / admin123) is for LOCAL DEVELOPMENT
# ONLY. The Step 3.6 routine rotates an existing admin's password to whatever
# the caller passed, so you can re-run this script with new credentials.

# Parse arguments
DOMAIN="${VBWD_DOMAIN:-localhost}"
SSL="${VBWD_SSL:-0}"
ADMIN_EMAIL="${VBWD_ADMIN_EMAIL:-admin@vbwd.local}"
ADMIN_PASSWORD="${VBWD_ADMIN_PASSWORD:-admin123}"
# Plugin selection. Default mode is "all" (install the full curated demo set),
# matching the historic behaviour of this recipe. --plugins-list switches to
# an explicit subset.
PLUGIN_MODE="all"
PLUGINS_LIST=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --ssl)
            SSL=1
            shift
            ;;
        --admin-email)
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        --admin-password)
            ADMIN_PASSWORD="$2"
            shift 2
            ;;
        --all-plugins)
            PLUGIN_MODE="all"
            shift
            ;;
        --plugins-list)
            PLUGIN_MODE="list"
            shift
            # Consume every following token until the next --flag (or EOL).
            while [[ $# -gt 0 && "$1" != --* ]]; do
                PLUGINS_LIST+=("$1")
                shift
            done
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Derive protocol prefixes from SSL flag
if [ "$SSL" = "1" ]; then
    HTTP="https"
    WS="wss"
else
    HTTP="http"
    WS="ws"
fi

# ──────────────────────────────────────────────────────────────────────────
# Plugin registry — the single source of truth for the curated CE demo set.
#
# One record per LOGICAL plugin id. Pipe-delimited fields:
#
#     id | backend_dir | fe_user_plugin | fe_admin_plugin | deps
#
#   - backend_dir     on-disk dir under vbwd-backend/plugins/ (snake_case);
#                     the GitHub repo is vbwd-plugin-<dir with _→->.
#                     Empty ⇒ this plugin has no backend component.
#   - fe_user_plugin  dir under vbwd-fe-user/plugins/; repo is
#                     vbwd-fe-user-plugin-<name>. Empty ⇒ none.
#   - fe_admin_plugin dir under vbwd-fe-admin/plugins/; repo is
#                     vbwd-fe-admin-plugin-<name minus trailing -admin>.
#                     Empty ⇒ none.
#   - deps            comma-separated logical ids that MUST also be installed
#                     (resolved transitively below). These mirror each
#                     plugin's PluginMetadata.dependencies plus demo-data
#                     ordering needs (e.g. meinchat's demo data needs the
#                     `assistant` BOT seeded by bot_meinchat).
#
# RECORD ORDER IS SIGNIFICANT: it is also the demo-data population order.
# Dependencies appear before their dependents (cms early — booking/shop/ghrm
# emit CMS pages; email before shop/booking/subscription; subscription before
# tarot/meinchat/ghrm; bot_meinchat before meinchat).
#
# To add a plugin to the CE demo set, add one line here — nothing else in this
# recipe needs to change.
# ──────────────────────────────────────────────────────────────────────────
PLUGIN_REGISTRY=(
    "cms|cms|cms|cms-admin|"
    "email|email||email-admin|"
    "subscription|subscription|subscription|subscription-admin|email"
    "discount|discount||discount-admin|"
    "token_payment|token_payment|token-payment|token-payment-admin|"
    "shop|shop|shop|shop-admin|email"
    "booking|booking|booking|booking|email"
    "ghrm|ghrm|ghrm|ghrm-admin|subscription"
    "dataset|dataset|dataset|dataset|cms,subscription"
    "tarot|tarot|tarot|tarot-admin|subscription"
    "checkout|checkout|checkout||"
    "wp_import|wp_import||wp-import|cms"
    "cms_ai|cms_ai||cms-ai|cms"
    "paypal|paypal|paypal-payment||"
    "stripe|stripe|stripe-payment||"
    "bot_base|bot_base|||"
    "bot_meinchat|bot_meinchat|||bot_base"
    "meinchat|meinchat|meinchat|meinchat-admin|subscription,bot_meinchat"
    "bot_telegram|bot_telegram||bot-telegram-admin|bot_base"
    "referral|referral|||discount,meinchat"
    "bot_meinchat_llm|bot_meinchat_llm|||bot_base,meinchat,referral,discount,subscription,shop,booking"
    "landing1||landing1||"
)

# Space-padded membership set of selected logical ids ("set" semantics).
SELECTED_SET=" "
sel_contains() { case "$SELECTED_SET" in *" $1 "*) return 0 ;; esac; return 1; }
sel_add() { sel_contains "$1" || SELECTED_SET="$SELECTED_SET$1 "; }

registry_has_id() {
    local needle="$1" row id
    for row in "${PLUGIN_REGISTRY[@]}"; do
        IFS='|' read -r id _ _ _ _ <<< "$row"
        [ "$id" = "$needle" ] && return 0
    done
    return 1
}

# 1. Seed the requested set.
if [ "$PLUGIN_MODE" = "all" ]; then
    for row in "${PLUGIN_REGISTRY[@]}"; do
        IFS='|' read -r id _ _ _ _ <<< "$row"
        sel_add "$id"
    done
else
    if [ ${#PLUGINS_LIST[@]} -eq 0 ]; then
        echo "ERROR: --plugins-list requires at least one plugin id."
        echo "Available ids:"
        for row in "${PLUGIN_REGISTRY[@]}"; do
            IFS='|' read -r id _ _ _ _ <<< "$row"
            echo "  - $id"
        done
        exit 1
    fi
    for requested in "${PLUGINS_LIST[@]}"; do
        if ! registry_has_id "$requested"; then
            echo "ERROR: unknown plugin id '$requested'. Available ids:"
            for row in "${PLUGIN_REGISTRY[@]}"; do
                IFS='|' read -r id _ _ _ _ <<< "$row"
                echo "  - $id"
            done
            exit 1
        fi
        sel_add "$requested"
    done
fi

# 2. Transitively pull in declared dependencies (fixpoint loop).
deps_changed=1
while [ "$deps_changed" -eq 1 ]; do
    deps_changed=0
    for row in "${PLUGIN_REGISTRY[@]}"; do
        IFS='|' read -r id _ _ _ deps <<< "$row"
        sel_contains "$id" || continue
        [ -z "$deps" ] && continue
        IFS=',' read -ra dep_arr <<< "$deps"
        for dep in "${dep_arr[@]}"; do
            [ -z "$dep" ] && continue
            if ! sel_contains "$dep"; then
                sel_add "$dep"
                deps_changed=1
            fi
        done
    done
done

# 3. Materialise per-tier install lists, preserving registry (=populate) order.
BACKEND_PLUGINS=()
FE_USER_PLUGINS=()
FE_ADMIN_PLUGINS=()
SELECTED_IDS=()
for row in "${PLUGIN_REGISTRY[@]}"; do
    IFS='|' read -r id be fu fa deps <<< "$row"
    sel_contains "$id" || continue
    SELECTED_IDS+=("$id")
    [ -n "$be" ] && BACKEND_PLUGINS+=("$be")
    [ -n "$fu" ] && FE_USER_PLUGINS+=("$fu")
    [ -n "$fa" ] && FE_ADMIN_PLUGINS+=("$fa")
done

# Helper — write a {"plugins": {...}} manifest enabling the given dir names.
# Used for backend plugins.json + both frontend plugins.json files. Pure bash
# (no host python dependency).
write_plugins_manifest() {
    local dest="$1"
    shift
    {
        echo '{'
        echo '  "plugins": {'
        local first=1 name
        for name in "$@"; do
            if [ "$first" -eq 1 ]; then first=0; else echo ','; fi
            printf '    "%s": { "enabled": true, "version": "1.0.0", "installedAt": "", "source": "local" }' "$name"
        done
        echo ''
        echo '  }'
        echo '}'
    } > "$dest"
}

# Resolve backend plugin DIR names → their PluginMetadata.name, the key the
# backend loader ENABLES by (BasePlugin registry is keyed by metadata.name).
# Most match the dir, but the bot_* plugins and cms_ai use hyphens
# (bot_meinchat → "bot-meinchat", cms_ai → "cms-ai") while token_payment /
# wp_import keep underscores. Reading each cloned plugin's __init__.py is the
# single source of truth (no guessing). A dir-name key would leave those
# plugins registered-but-DISABLED — their routes/blueprints load yet
# get_enabled_plugins() omits them (e.g. declare_public_routes() dropped →
# route-exposure oracle false positives). Result in BACKEND_MANIFEST_KEYS.
resolve_backend_manifest_keys() {
    BACKEND_MANIFEST_KEYS=()
    local dir name
    for dir in "$@"; do
        name="$(sed -nE "s/.*name[[:space:]]*=[[:space:]]*[\"']([a-z0-9_-]+)[\"'].*/\1/p" \
            "$BACKEND_DIR/plugins/$dir/__init__.py" 2>/dev/null | head -1)"
        [ -n "$name" ] || name="$dir"
        BACKEND_MANIFEST_KEYS+=("$name")
    done
}

echo "=========================================="
echo "VBWD CE Development Environment Setup"
echo "=========================================="
echo ""
echo "Plugin selection mode: $PLUGIN_MODE"
echo "  Selected plugins (+deps): ${SELECTED_IDS[*]}"
echo "  Backend:  ${BACKEND_PLUGINS[*]:-(none)}"
echo "  fe-user:  ${FE_USER_PLUGINS[*]:-(none)}"
echo "  fe-admin: ${FE_ADMIN_PLUGINS[*]:-(none)}"

# Detect environment
if [ -n "$GITHUB_ACTIONS" ]; then
    IS_CI=true
    WORKSPACE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
    echo "Running in GitHub Actions"
else
    IS_CI=false
    WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    echo "Running in local development environment"
fi

echo "Workspace: $WORKSPACE_DIR"

# Configuration
BACKEND_REPO="https://github.com/VBWD-platform/vbwd-backend.git"
# Frontend repositories (split into 3 independent repos with git submodules)
FE_CORE_REPO="https://github.com/VBWD-platform/vbwd-fe-core.git"
FE_USER_REPO="https://github.com/VBWD-platform/vbwd-fe-user.git"
FE_ADMIN_REPO="https://github.com/VBWD-platform/vbwd-fe-admin.git"

BACKEND_DIR="$WORKSPACE_DIR/vbwd-backend"
FE_CORE_DIR="$WORKSPACE_DIR/vbwd-fe-core"
FE_USER_DIR="$WORKSPACE_DIR/vbwd-fe-user"
FE_ADMIN_DIR="$WORKSPACE_DIR/vbwd-fe-admin"

# Port configuration
FE_USER_PORT=8080
FE_ADMIN_PORT=8081

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if port is available
check_port_available() {
    local port=$1
    if command_exists lsof; then
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
            return 1  # Port in use
        fi
    elif command_exists netstat; then
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            return 1  # Port in use
        fi
    fi
    return 0  # Port available
}

# Function to wait for service
wait_for_service() {
    local service_name=$1
    local url=$2
    local max_attempts=${3:-30}
    local attempt=1

    echo "Waiting for $service_name to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if curl -sf "$url" > /dev/null 2>&1; then
            echo "$service_name is ready!"
            return 0
        fi
        echo "Attempt $attempt/$max_attempts: $service_name not ready yet..."
        sleep 2
        attempt=$((attempt + 1))
    done

    echo "ERROR: $service_name failed to start within expected time"
    return 1
}

# Check prerequisites
echo ""
echo "Checking prerequisites..."
if ! command_exists git; then
    echo "ERROR: git is not installed"
    exit 1
fi

if ! command_exists docker; then
    echo "ERROR: docker is not installed"
    exit 1
fi

if ! command_exists docker compose; then
    echo "ERROR: docker compose is not installed"
    exit 1
fi

echo "All prerequisites met"

# Clone backend repository
echo ""
echo "=========================================="
echo "Step 1: Setting up vbwd-backend"
echo "=========================================="

if [ -d "$BACKEND_DIR/.git" ]; then
    echo "Backend directory already exists, pulling latest changes..."
    cd "$BACKEND_DIR"
    git pull origin main || true
else
    echo "Cloning vbwd-backend..."
    rm -rf "$BACKEND_DIR"
    git clone --branch main "$BACKEND_REPO" "$BACKEND_DIR"
    cd "$BACKEND_DIR"
fi

# Setup backend environment
if [ ! -f "$BACKEND_DIR/.env" ]; then
    echo "Creating backend .env file..."
    if [ -f "$BACKEND_DIR/.env.example" ]; then
        cp "$BACKEND_DIR/.env.example" "$BACKEND_DIR/.env"
    else
        # Create minimal .env if example doesn't exist
        cat > "$BACKEND_DIR/.env" << 'EOF'
# Database Configuration
POSTGRES_PASSWORD=vbwd
POSTGRES_DB=vbwd
POSTGRES_USER=vbwd
DATABASE_URL=postgresql://vbwd:vbwd@postgres:5432/vbwd

# Flask Configuration
FLASK_ENV=development
FLASK_SECRET_KEY=dev-secret-key-change-in-production
FLASK_APP=src/app.py

# Redis Configuration
REDIS_URL=redis://redis:6379/0

# LoopAI Integration (Optional)
LOOPAI_API_URL=http://loopai-web:5000
LOOPAI_API_KEY=dev-api-key
LOOPAI_AGENT_ID=1

# Email Configuration (Optional)
SMTP_HOST=localhost
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD=
EOF
    fi
    echo "Backend .env file created"
else
    echo "Backend .env file already exists"
fi

# Install backend plugins (each hosted in its own repo)
echo ""
echo "=========================================="
echo "Step 1.5: Installing backend plugins"
echo "=========================================="

for plugin in "${BACKEND_PLUGINS[@]}"; do
    PLUGIN_DIR="$BACKEND_DIR/plugins/$plugin"
    # GitHub repo names are kebab-case; on-disk plugin dirs are the python
    # snake_case import names. Map underscores → hyphens for the URL only.
    plugin_repo_name="${plugin//_/-}"
    PLUGIN_REPO="https://github.com/VBWD-platform/vbwd-plugin-${plugin_repo_name}.git"
    if [ -d "$PLUGIN_DIR/.git" ]; then
        echo "Plugin $plugin already installed, pulling..."
        cd "$PLUGIN_DIR" && git pull origin main || true
    else
        echo "Cloning plugin $plugin (from vbwd-plugin-${plugin_repo_name})..."
        rm -rf "$PLUGIN_DIR"
        git clone --depth=1 "$PLUGIN_REPO" "$PLUGIN_DIR"
    fi
done
echo "✓ Backend plugins installed (${#BACKEND_PLUGINS[@]}): ${BACKEND_PLUGINS[*]}"

# Generate plugins/plugins.json — the backend's persisted enable-state
# (JsonFilePluginConfigStore reads plugins/plugins.json; a fresh DB has no
# state, so this file is what turns the selected plugins ON). NOTE: we MUST
# generate it from the selected set rather than copying plugins.json.dist —
# the dist file only enables a single bootstrap plugin, so copying it would
# leave every demo plugin disabled. We always (re)write it so the enabled set
# matches exactly what was just cloned.
# Backend manifest keys are metadata.name (NOT the on-disk dir) — see
# resolve_backend_manifest_keys. Frontend manifests keep the dir names (the Vue
# loader matches by dir), so only the backend is remapped.
resolve_backend_manifest_keys "${BACKEND_PLUGINS[@]}"
write_plugins_manifest "$BACKEND_DIR/plugins/plugins.json" "${BACKEND_MANIFEST_KEYS[@]}"
echo "✓ plugins.json generated (enables ${#BACKEND_MANIFEST_KEYS[@]} backend plugins: ${BACKEND_MANIFEST_KEYS[*]})"

# config.json holds per-plugin SAVED config overrides. Demo settings come from
# each plugin's own config.json / admin-config.json (read directly from the
# plugin dir by the backend), so an empty aggregate here is correct on a fresh
# install — every plugin falls back to its shipped DEFAULT_CONFIG.
if [ ! -f "$BACKEND_DIR/plugins/config.json" ]; then
    echo '{}' > "$BACKEND_DIR/plugins/config.json"
    echo "✓ config.json initialised (plugins use their shipped demo settings)"
fi

# Seed ${VAR_DIR}/plugins/ — the canonical, server-side plugin manifest
# directory shared across api / fe-admin / fe-user (see
# docs/architecture/plugin-management.md). All six files MUST exist
# before the backend container starts; the backend refuses to manage a
# frontend app whose env-var-configured manifest is missing.
VAR_DIR="${VBWD_VAR_DIR:-$WORKSPACE_DIR/var}"
mkdir -p "$VAR_DIR/plugins"
echo ""
echo "Seeding $VAR_DIR/plugins/ (idempotent — admin edits via UI are preserved)"

seed_manifest() {
    src="$1"
    dst="$VAR_DIR/plugins/$2"
    if [ -f "$src" ]; then
        # OVERWRITE from the freshly-generated source. The runtime backend reads
        # its enable-state from var/plugins/backend-plugins.json (VBWD_BACKEND_PLUGINS_JSON),
        # so a stale committed copy here would enable the WRONG plugin set (this
        # repo used to ship an old set — analytics/chat/taro/yookassa — which then
        # shadowed the generated one on every fresh install). The generated src
        # always matches exactly what was just cloned + enabled, so it wins.
        cp "$src" "$dst"
        echo "  seed  $(basename "$dst") ← $src (overwrite)"
    elif [ -f "$dst" ]; then
        echo "  keep  $(basename "$dst") — no generated source, existing kept"
    else
        # No source and no existing file: create an empty JSON manifest so
        # `make up` bind-mounts a real file (an absent host path is auto-created
        # by Docker as a directory, breaking the file mount).
        echo '{}' > "$dst"
        echo "  WARN  $src not found; wrote empty $(basename "$dst")"
    fi
}

# Backend manifests can be seeded now (backend repo + plugins already cloned).
# Frontend manifests are seeded later in Step 2 — AFTER the fe-user / fe-admin
# repos are cloned — because their source files (plugins/config.json) do not
# exist until then. Seeding them here would leave var/plugins/fe-*-config.json
# absent, and `make up` would then bind-mount a non-existent host path that
# Docker auto-creates as a directory, failing the file mount.
seed_manifest "$BACKEND_DIR/plugins/plugins.json"           backend-plugins.json
seed_manifest "$BACKEND_DIR/plugins/config.json"            backend-plugins-config.json

echo "✓ Backend plugin manifests seeded into $VAR_DIR/plugins/"

# ──────────────────────────────────────────────────────────────────────────
# Seed plugin ASSETS. A plugin may ship a `var/` subtree (prompts, templates,
# RAG/training docs, etc.) that must live in the host-mounted $VAR_DIR so the
# running backend can read it — e.g. bot_meinchat_llm ships
# var/bot-meinchat-llm/{prompts,rag,training}. Merge each selected plugin's
# var/ subtree into $VAR_DIR WITHOUT clobbering files an admin may have edited
# (cp -n / --no-clobber → idempotent, edits preserved).
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Seeding plugin assets (prompts / templates) into $VAR_DIR/"
asset_plugins=0
for plugin in "${BACKEND_PLUGINS[@]}"; do
    plugin_var="$BACKEND_DIR/plugins/$plugin/var"
    [ -d "$plugin_var" ] || continue
    asset_plugins=$((asset_plugins + 1))
    # Recreate the directory tree, then copy files without overwriting.
    (cd "$plugin_var" && find . -type d) | while read -r d; do
        mkdir -p "$VAR_DIR/$d"
    done
    (cd "$plugin_var" && find . -type f) | while read -r f; do
        if [ -f "$VAR_DIR/$f" ]; then
            echo "  skip  $f — already present"
        else
            cp "$plugin_var/$f" "$VAR_DIR/$f"
            echo "  seed  $f ← plugins/$plugin/var/$f"
        fi
    done
done
if [ "$asset_plugins" -eq 0 ]; then
    echo "  (no selected plugin ships a var/ asset subtree)"
fi
echo "✓ Plugin assets seeded"
echo "  Export VBWD_VAR_DIR before 'docker compose up' if you want to"
echo "  keep this directory somewhere other than $WORKSPACE_DIR/var"

# Clone and setup frontend repositories (3 independent repos with submodules)
echo ""
echo "=========================================="
echo "Step 2: Setting up Frontend (3 repos: core, user, admin)"
echo "=========================================="

# Step 2a: Clone and build vbwd-fe-core (base library - must build first)
echo ""
echo "Step 2a: Setting up vbwd-fe-core (shared component library)"
echo "==========================================================="

if [ -d "$FE_CORE_DIR/.git" ]; then
    echo "Core library directory already exists, pulling latest changes..."
    cd "$FE_CORE_DIR"
    git pull origin main || true
else
    echo "Cloning vbwd-fe-core..."
    rm -rf "$FE_CORE_DIR"
    git clone "$FE_CORE_REPO" "$FE_CORE_DIR"
    cd "$FE_CORE_DIR"
fi

echo "Building vbwd-fe-core..."
if command_exists docker compose || command_exists docker; then
    cd "$FE_CORE_DIR"
    if [ -f "docker-compose.yaml" ] || [ -f "docker-compose.yml" ]; then
        # Use Docker Compose if available
        docker compose run --rm build npm install && npm run build || true
    else
        npm install
        npm run build
    fi
else
    npm install
    npm run build
fi
echo "✓ vbwd-fe-core built successfully"

# Step 2b: Clone vbwd-fe-user with submodule
echo ""
echo "Step 2b: Setting up vbwd-fe-user (user-facing app)"
echo "=================================================="

if [ -d "$FE_USER_DIR/.git" ]; then
    echo "User app directory already exists, updating submodules..."
    cd "$FE_USER_DIR"
    git pull origin main || true
    git submodule update --init --recursive || true
else
    echo "Cloning vbwd-fe-user with submodules..."
    rm -rf "$FE_USER_DIR"
    git clone --recurse-submodules "$FE_USER_REPO" "$FE_USER_DIR"
    cd "$FE_USER_DIR"
fi

# Verify submodule
if [ -d "$FE_USER_DIR/vbwd-fe-core" ] && [ -f "$FE_USER_DIR/vbwd-fe-core/package.json" ]; then
    echo "✓ Submodule vbwd-fe-core initialized"
else
    echo "WARNING: Submodule vbwd-fe-core may not be properly initialized"
fi

echo "Building vbwd-fe-core submodule for vbwd-fe-user..."
cd "$FE_USER_DIR/vbwd-fe-core"
npm install && npm run build && rm -rf node_modules

echo "Installing dependencies for vbwd-fe-user..."
cd "$FE_USER_DIR"
# The app's package.json aliases `vbwd-view-component` to the published
# @vbwd-platform/vbwd-view-component on GitHub Packages (used by the standalone
# app CI, which authenticates with NODE_AUTH_TOKEN). The SDK install instead
# consumes fe-core from the in-tree submodule we just built, so a public clone
# needs no GitHub Packages token: repoint the alias at the local submodule and
# drop the scoped .npmrc so npm never queries npm.pkg.github.com.
npm pkg set 'dependencies.vbwd-view-component=file:vbwd-fe-core'
rm -f .npmrc
npm install
echo "✓ vbwd-fe-user dependencies installed"

echo "Installing vbwd-fe-user plugins..."
for plugin in "${FE_USER_PLUGINS[@]}"; do
    PLUGIN_DIR="$FE_USER_DIR/plugins/$plugin"
    PLUGIN_REPO="https://github.com/VBWD-platform/vbwd-fe-user-plugin-${plugin}.git"
    if [ -d "$PLUGIN_DIR/.git" ]; then
        echo "Plugin $plugin already installed, pulling..."
        cd "$PLUGIN_DIR" && git pull origin main || true
    else
        echo "Cloning fe-user plugin $plugin..."
        rm -rf "$PLUGIN_DIR"
        git clone --depth=1 "$PLUGIN_REPO" "$PLUGIN_DIR"
    fi
done
echo "✓ vbwd-fe-user plugins installed (${#FE_USER_PLUGINS[@]}): ${FE_USER_PLUGINS[*]}"

# Generate the fe-user plugin manifest to match EXACTLY the cloned set. The
# repo ships a plugins.json listing many plugins; the runtime plugin loader
# dynamic-imports every enabled entry, so any entry whose dir wasn't cloned
# would throw. We write both the build-time manifest (plugins/plugins.json,
# imported via the @plugins alias) and the runtime one (vue/public/plugins.json,
# fetched at app start).
write_plugins_manifest "$FE_USER_DIR/plugins/plugins.json" "${FE_USER_PLUGINS[@]}"
if [ -d "$FE_USER_DIR/vue/public" ]; then
    write_plugins_manifest "$FE_USER_DIR/vue/public/plugins.json" "${FE_USER_PLUGINS[@]}"
fi
echo "✓ vbwd-fe-user plugins.json generated (${#FE_USER_PLUGINS[@]} enabled)"

# Step 2c: Clone vbwd-fe-admin with submodule
echo ""
echo "Step 2c: Setting up vbwd-fe-admin (admin backoffice)"
echo "===================================================="

if [ -d "$FE_ADMIN_DIR/.git" ]; then
    echo "Admin app directory already exists, updating submodules..."
    cd "$FE_ADMIN_DIR"
    git pull origin main || true
    git submodule update --init --recursive || true
else
    echo "Cloning vbwd-fe-admin with submodules..."
    rm -rf "$FE_ADMIN_DIR"
    git clone --recurse-submodules "$FE_ADMIN_REPO" "$FE_ADMIN_DIR"
    cd "$FE_ADMIN_DIR"
fi

# Verify submodule
if [ -d "$FE_ADMIN_DIR/vbwd-fe-core" ] && [ -f "$FE_ADMIN_DIR/vbwd-fe-core/package.json" ]; then
    echo "✓ Submodule vbwd-fe-core initialized"
else
    echo "WARNING: Submodule vbwd-fe-core may not be properly initialized"
fi

echo "Building vbwd-fe-core submodule for vbwd-fe-admin..."
cd "$FE_ADMIN_DIR/vbwd-fe-core"
npm install && npm run build && rm -rf node_modules

echo "Installing dependencies for vbwd-fe-admin..."
cd "$FE_ADMIN_DIR"
# See the fe-user note above: consume fe-core from the in-tree submodule build
# rather than the token-gated @vbwd-platform GitHub Packages release.
npm pkg set 'dependencies.vbwd-view-component=file:vbwd-fe-core'
rm -f .npmrc
npm install
echo "✓ vbwd-fe-admin dependencies installed"

echo "Installing vbwd-fe-admin plugins..."
for plugin in "${FE_ADMIN_PLUGINS[@]}"; do
    PLUGIN_DIR="$FE_ADMIN_DIR/plugins/$plugin"
    # fe-admin convention: on-disk dir often ends in `-admin` (cms-admin,
    # discount-admin, …) but the GitHub repo name DOESN'T duplicate the
    # `-admin` (the repo prefix `vbwd-fe-admin-plugin-` already states the
    # role). Strip a trailing `-admin` for the URL; no-op for plugins
    # like `booking` / `analytics-widget` that never had the suffix.
    plugin_repo_name="${plugin%-admin}"
    PLUGIN_REPO="https://github.com/VBWD-platform/vbwd-fe-admin-plugin-${plugin_repo_name}.git"
    if [ -d "$PLUGIN_DIR/.git" ]; then
        echo "Plugin $plugin already installed, pulling..."
        cd "$PLUGIN_DIR" && git pull origin main || true
    else
        echo "Cloning fe-admin plugin $plugin (from vbwd-fe-admin-plugin-${plugin_repo_name})..."
        rm -rf "$PLUGIN_DIR"
        git clone --depth=1 "$PLUGIN_REPO" "$PLUGIN_DIR"
    fi
done
echo "✓ vbwd-fe-admin plugins installed (${#FE_ADMIN_PLUGINS[@]}): ${FE_ADMIN_PLUGINS[*]}"

# Generate the fe-admin plugin manifest to match the cloned set (same reason
# as fe-user above: the loader dynamic-imports every enabled entry).
write_plugins_manifest "$FE_ADMIN_DIR/plugins/plugins.json" "${FE_ADMIN_PLUGINS[@]}"
if [ -d "$FE_ADMIN_DIR/vue/public" ]; then
    write_plugins_manifest "$FE_ADMIN_DIR/vue/public/plugins.json" "${FE_ADMIN_PLUGINS[@]}"
fi
echo "✓ vbwd-fe-admin plugins.json generated (${#FE_ADMIN_PLUGINS[@]} enabled)"

# Seed the frontend plugin manifests now that the fe-user / fe-admin repos
# (and their plugins/config.json source files) exist. These MUST be present
# as files before `make up`, otherwise Docker auto-creates the missing
# var/plugins/fe-*-config.json host path as a directory and the read-only
# bind mount onto /app/vue/public/config.json fails.
echo ""
echo "Seeding frontend plugin manifests into $VAR_DIR/plugins/"
seed_manifest "$FE_ADMIN_DIR/plugins/plugins.json"          fe-admin-plugins.json
seed_manifest "$FE_ADMIN_DIR/plugins/config.json"           fe-admin-plugins-config.json
seed_manifest "$FE_USER_DIR/plugins/plugins.json"           fe-user-plugins.json
seed_manifest "$FE_USER_DIR/plugins/config.json"            fe-user-plugins-config.json
echo "✓ Frontend plugin manifests seeded into $VAR_DIR/plugins/"

# Setup frontend environment files
echo ""
echo "Setting up environment files for frontend apps..."

for FE_DIR in "$FE_USER_DIR" "$FE_ADMIN_DIR"; do
    FE_NAME=$(basename "$FE_DIR")
    if [ ! -f "$FE_DIR/.env" ]; then
        # VITE_API_URL is a relative path so it works via the nginx proxy on any domain.
        # VITE_BACKEND_URL is the Vite dev-server proxy target (only used by `npm run dev`).
        cat > "$FE_DIR/.env" << EOF
VITE_API_URL=/api/v1
VITE_BACKEND_URL=${HTTP}://${DOMAIN}:5000
VITE_WS_URL=${WS}://${DOMAIN}:5000
EOF
        echo "✓ Environment file created for $FE_NAME (domain: $DOMAIN)"
    fi
done

# Start Docker containers
echo ""
echo "=========================================="
echo "Step 3: Starting Docker containers"
echo "=========================================="

cd "$BACKEND_DIR"

# Stop any existing containers
echo "Stopping any existing containers..."
docker compose down -v || true

# Build and start containers
echo "Building and starting containers..."
if [ "$IS_CI" = true ]; then
    # In CI, use detached mode and wait for services
    docker compose up -d --build
else
    # In local dev, also use detached mode
    docker compose up -d --build
fi

# Wait for services to be ready
echo ""
echo "Waiting for services to start..."
sleep 5

# Check backend health
if wait_for_service "Backend API" "${HTTP}://${DOMAIN}:5000/api/v1/health" 60; then
    echo "Backend API is running on ${HTTP}://${DOMAIN}:5000"
else
    echo "ERROR: Backend API failed to start"
    echo "Checking backend logs..."
    docker compose logs api
    exit 1
fi

# Check database
echo "Checking database connection..."
if docker compose exec -T api python -c "from sqlalchemy import create_engine; import os; e=create_engine(os.getenv('DATABASE_URL', 'postgresql://vbwd:vbwd@postgres:5432/vbwd')); c=e.connect(); print('Database: OK'); c.close()" 2>/dev/null; then
    echo "Database is connected and ready"
else
    echo "WARNING: Database connection check failed"
    docker compose logs postgres
fi

# Run database migrations
echo ""
echo "=========================================="
echo "Step 3.5: Running database migrations"
echo "=========================================="

if [ -f "$WORKSPACE_DIR/recipes/run_migrations.sh" ]; then
    echo "Running database migrations..."
    bash "$WORKSPACE_DIR/recipes/run_migrations.sh" upgrade
    if [ $? -eq 0 ]; then
        echo "Database migrations completed!"
    else
        echo "WARNING: Database migrations may have failed - check logs"
    fi
else
    echo "WARNING: run_migrations.sh not found, skipping migrations"
fi

# Seed the RBAC catalog: permissions, the admin roles (super_admin / admin) and
# the default user access levels that back /admin/settings/access.
#
# bin/create_admin.sh (Step 3.6) already reaches the same seeder, but only as a
# side effect of creating a user. Running it explicitly here keeps the two
# concerns separate and means an install that supplies its own admin still gets
# a populated RBAC catalog. Idempotent: permissions and roles are upserted,
# access levels are create-only, so a re-run never clobbers edited grants.
#
# Operator override: a JSON array at ${VAR_DIR}/core/user_access_levels.json
# replaces the shipped default levels before they are created. To amend levels
# that already exist, place a data-exchange envelope at
# ${VAR_DIR}/data_exchange/<entity>.json — imported below with --mode upsert.
echo ""
echo "=========================================="
echo "Step 3.55: Seeding RBAC (permissions + access levels)"
echo "=========================================="

cd "$BACKEND_DIR"
if docker compose exec -T api flask --app "vbwd:create_app()" seed-rbac; then
    echo "✓ RBAC seeded (permissions, admin roles, user access levels)"
else
    echo "WARNING: RBAC seeding failed — /admin/settings/access may be empty"
fi

for rbac_entity in access_levels user_access_levels; do
    if [ -f "$VAR_DIR/data_exchange/${rbac_entity}.json" ]; then
        echo "Importing operator override for ${rbac_entity}..."
        docker compose exec -T api \
            flask --app "vbwd:create_app()" data-exchange import \
            "$rbac_entity" "/app/var/data_exchange/${rbac_entity}.json" \
            --mode upsert \
            && echo "✓ Imported ${rbac_entity} override" \
            || echo "WARNING: ${rbac_entity} override import failed"
    fi
done

# Create the default admin user.
#
# Idempotent: bin/create_admin.sh inside the backend container does an
# upsert — if the email exists it ensures the user is ACTIVE + has the
# ADMIN role; if absent it creates one with the supplied password. Re-runs
# of this recipe with different --admin-password values rotate the password
# of the existing admin to the new value, so the script stays a single
# source of truth for "what does it take to log into this stack."
#
# Defaults (admin@vbwd.local / admin123) are LOCAL DEV ONLY. Override per
# run with --admin-email / --admin-password or VBWD_ADMIN_EMAIL /
# VBWD_ADMIN_PASSWORD.
echo ""
echo "=========================================="
echo "Step 3.6: Creating default admin user"
echo "=========================================="

cd "$BACKEND_DIR"
if [ -f "$BACKEND_DIR/bin/create_admin.sh" ]; then
    echo "Creating / upserting admin: $ADMIN_EMAIL"
    if bash "$BACKEND_DIR/bin/create_admin.sh" "$ADMIN_EMAIL" "$ADMIN_PASSWORD"; then
        echo "✓ Admin user ready: $ADMIN_EMAIL"
    else
        echo "WARNING: admin-user creation failed — check backend logs"
        echo "  (you can retry with: cd $BACKEND_DIR && ./bin/create_admin.sh '$ADMIN_EMAIL' '$ADMIN_PASSWORD')"
    fi
else
    echo "WARNING: $BACKEND_DIR/bin/create_admin.sh not found — admin not created"
fi

# ──────────────────────────────────────────────────────────────────────────
# Step 3.7 — Populate plugin demo data. The list is derived from the SELECTED
# backend plugins, in registry order (= dependency order), so it always
# matches what was actually installed. A plugin is populated if it ships
# either bin/populate-db.sh or populate_db.py; plugins with no demo data are
# silently skipped. Every populate script is idempotent (upserts), so
# re-running this recipe is safe.
#
# Order matters and is guaranteed by the registry ordering: CMS first
# (creates layouts/widgets/styles/pages — required by booking + shop + ghrm
# which emit CMS layouts + pages); email before shop/booking/subscription;
# subscription before tarot/meinchat/ghrm; bot_meinchat (seeds the `assistant`
# BOT user) before meinchat (seeds the bot-widget that references it).
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "Step 3.7: Populating plugin demo data"
echo "=========================================="

cd "$BACKEND_DIR"
# BACKEND_PLUGINS is already in registry (=populate) order.
POPULATE_PLUGINS=("${BACKEND_PLUGINS[@]}")

for plugin in "${POPULATE_PLUGINS[@]}"; do
    populate_sh="$BACKEND_DIR/plugins/$plugin/bin/populate-db.sh"
    populate_py="$BACKEND_DIR/plugins/$plugin/populate_db.py"
    if [ -f "$populate_sh" ]; then
        echo ""
        echo "── Populating $plugin ──"
        if bash "$populate_sh"; then
            echo "✓ $plugin demo data populated"
        else
            echo "WARNING: $plugin populate failed — check logs"
        fi
    elif [ -f "$populate_py" ]; then
        # Fallback: plugin ships populate_db.py but no shell wrapper
        # (e.g. token_payment). Run the module's populate_db() entrypoint
        # inside an app context so db.session + plugin imports resolve.
        echo ""
        echo "── Populating $plugin (via populate_db.py fallback) ──"
        # populate_db.py comes in TWO shapes and we must handle both:
        #   (a) a module that defines a populate_db() function (e.g. token_payment,
        #       bot_meinchat, meinchat) — import and call it inside an app context;
        #   (b) a __main__-style script that does its work under
        #       `if __name__ == "__main__":` (e.g. checkout, dataset) and
        #       self-manages its app context — importing it does nothing, so run
        #       the file as __main__ instead.
        # PYTHONPATH=/app so `import vbwd` / `import plugins.*` resolve.
        if docker compose exec -T -e PYTHONPATH=/app api python -c "
import importlib, runpy
mod = importlib.import_module('plugins.${plugin}.populate_db')
if hasattr(mod, 'populate_db'):
    from vbwd.app import create_app
    with create_app().app_context():
        mod.populate_db()
    print('✓ ${plugin} populate_db() finished')
else:
    runpy.run_path('/app/plugins/${plugin}/populate_db.py', run_name='__main__')
    print('✓ ${plugin} populate_db.py executed')
"; then
            echo "✓ $plugin demo data populated"
        else
            echo "WARNING: $plugin populate (fallback) failed — check logs"
        fi
    else
        # Plugin ships no demo data (e.g. analytics, chat, paypal, stripe,
        # mailchimp, bot_base) — nothing to populate, not an error.
        echo "·· $plugin has no demo data — skipping populate"
    fi
done

# CMS pricing-card defaults — safety net. populate_cms.py already writes the
# seeded theme/highlight_slug/features onto the pricing-native-plans widget, so
# on a clean run this reports "already-current" and writes nothing. It matters
# when the cms populate above was skipped or failed (the loop only WARNs), and
# on a re-install over an existing database. Non-destructive: it fills those
# keys only when unset, keeps any operator value, and never touches cms_post.
if [ -f "$BACKEND_DIR/plugins/cms/src/bin/apply_pricing_card_defaults.py" ]; then
    echo ""
    echo "── Applying CMS pricing-card defaults ──"
    (cd "$BACKEND_DIR" && docker compose exec -T -e PYTHONPATH=/app api \
        python /app/plugins/cms/src/bin/apply_pricing_card_defaults.py) \
        || echo "WARNING: pricing-card defaults failed — check logs"
fi

# ──────────────────────────────────────────────────────────────────────────
# Step 3.8 — CMS images + default-home routing rules
#
# (a) Register every file in $BACKEND_DIR/uploads/images/ as a CmsImage row.
#     Image files are already on disk inside the container via the bind
#     mount (vbwd-backend bind-mounts the whole repo at /app); this step
#     just makes them visible in the admin media gallery + reusable in
#     widgets/pages. Idempotent: each file's slug-derived row is upserted.
#
# (b) Routing rules: ensure `/` (default) and `/index.html` both resolve
#     to the CMS page slug `home`. If a page `home` doesn't exist yet,
#     clone `home1` → `home` so the rule has a real landing target.
#     Goes through the CMS service layer — no raw SQL.
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "Step 3.8: Importing CMS images + default-home routing"
echo "=========================================="

cd "$BACKEND_DIR"
docker compose exec -T api python - <<'PYEOF'
"""dev-install-ce: register seed CMS images + ensure / and /index.html → /home.

All writes go through the CMS service / repository layer per
feedback_no_direct_db_for_test_data. Idempotent: re-running is a no-op
once seeded.
"""
import mimetypes
import os
import sys
from pathlib import Path

from vbwd.app import create_app
from vbwd.extensions import db

app = create_app()

with app.app_context():
    # ── (a) CMS image gallery seeding ──────────────────────────────────────
    try:
        from plugins.cms.src.repositories.cms_image_repository import (
            CmsImageRepository,
        )
        from plugins.cms.src.services.cms_image_service import CmsImageService
        from plugins.cms.src.services.file_storage import LocalFileStorage
    except Exception as exc:
        print(f"  CMS plugin not loadable — skipping image import ({exc})")
    else:
        seed_dir = Path("/app/uploads/images")
        if not seed_dir.is_dir():
            print(f"  No seed-image dir at {seed_dir} — skipping")
        else:
            image_repo = CmsImageRepository(db.session)
            # Match the runtime wiring in plugins/cms/src/routes.py::_image_service
            # — both args are required; base_url becomes the public URL prefix.
            storage = LocalFileStorage(
                base_path="/app/uploads", base_url="/uploads"
            )
            image_service = CmsImageService(image_repo, storage)

            files = sorted(p for p in seed_dir.iterdir() if p.is_file())
            print(f"  Found {len(files)} seed image(s) at {seed_dir}")

            from plugins.cms.src.services.cms_image_service import _slugify

            registered = skipped = failed = 0
            for path in files:
                slug = _slugify(path.stem)
                if image_repo.find_by_slug(slug):
                    skipped += 1
                    continue
                try:
                    data = path.read_bytes()
                    mime, _ = mimetypes.guess_type(str(path))
                    image_service.upload_image(
                        file_data=data,
                        filename=path.name,
                        mime_type=mime or "application/octet-stream",
                        caption=path.stem,
                    )
                    registered += 1
                except Exception as exc:
                    failed += 1
                    print(f"    ✗ {path.name}: {exc}")
            print(
                f"  Images: {registered} registered, "
                f"{skipped} already present, {failed} failed"
            )

    # ── (b) Default-home routing rules ─────────────────────────────────────
    try:
        from plugins.cms.src.models.cms_page import CmsPage
        from plugins.cms.src.models.cms_routing_rule import CmsRoutingRule
    except Exception as exc:
        print(f"  CMS routing models not loadable — skipping routing ({exc})")
        sys.exit(0)

    # Ensure a `home` page exists. If absent but `home1` exists, clone it
    # so the routing target resolves to a real published page.
    home_page = db.session.query(CmsPage).filter_by(slug="home").first()
    if home_page is None:
        home1 = db.session.query(CmsPage).filter_by(slug="home1").first()
        if home1 is not None:
            home_page = CmsPage()
            for column in CmsPage.__table__.columns:
                if column.name in ("id", "created_at", "updated_at", "version"):
                    continue
                setattr(home_page, column.name, getattr(home1, column.name))
            home_page.slug = "home"
            # `name` is the human-visible label; keep the home1 value unless
            # it literally said "Home 1" — normalise to "Home" for clarity.
            if home_page.name and "home1" in home_page.name.lower().replace(" ", ""):
                home_page.name = "Home"
            db.session.add(home_page)
            db.session.commit()
            print("  + page 'home' created (cloned from 'home1')")
        else:
            print(
                "  ! neither 'home' nor 'home1' page found — "
                "routing rules will still upsert but pages must be created later"
            )
    else:
        print("  ~ page 'home' already exists")

    def _upsert_rule(*, name, match_type, match_value, target_slug,
                     redirect_code, is_rewrite, priority):
        existing = (
            db.session.query(CmsRoutingRule)
            .filter_by(match_type=match_type, match_value=match_value,
                       layer="middleware")
            .first()
        )
        if existing is None:
            rule = CmsRoutingRule(
                name=name,
                match_type=match_type,
                match_value=match_value,
                target_slug=target_slug,
                is_active=True,
                priority=priority,
                layer="middleware",
                redirect_code=redirect_code,
                is_rewrite=is_rewrite,
            )
            db.session.add(rule)
            print(
                f"  + routing rule: {match_type}"
                + (f"={match_value}" if match_value else "")
                + f" → {target_slug}"
            )
        else:
            existing.target_slug = target_slug
            existing.is_active = True
            existing.priority = priority
            existing.redirect_code = redirect_code
            existing.is_rewrite = is_rewrite
            print(
                f"  ~ routing rule: {match_type}"
                + (f"={match_value}" if match_value else "")
                + f" → {target_slug} (updated)"
            )

    _upsert_rule(
        name="home", match_type="default", match_value=None,
        target_slug="home", redirect_code=302, is_rewrite=True, priority=0,
    )
    _upsert_rule(
        name="index.html → home", match_type="path_prefix",
        match_value="/index.html", target_slug="home",
        redirect_code=302, is_rewrite=True, priority=-10,
    )
    db.session.commit()
    print("✓ Default-home routing rules upserted")
PYEOF

if [ $? -eq 0 ]; then
    echo "✓ CMS image import + routing-rule step complete"
else
    echo "WARNING: CMS image / routing step exited non-zero — check logs"
fi

# Run backend tests
#echo ""
#echo "=========================================="
#echo "Step 4: Running backend tests"
#echo "=========================================="
#
#cd "$BACKEND_DIR"
#echo "Running all backend tests..."
#if docker compose run --rm test pytest tests/ -v --tb=short; then
#    echo "Backend tests passed!"
#else
#    echo "ERROR: Backend tests failed"
#    exit 1
#fi

# Start frontend containers
echo ""
echo "=========================================="
echo "Step 5: Starting frontend containers (dev + nginx)"
echo "=========================================="
echo ""
echo "Both frontends run two containers each:"
echo "  - dev:   Vite dev server on the container's port 5173."
echo "  - nginx: reverse proxy on the host port ($FE_USER_PORT / $FE_ADMIN_PORT)"
echo "           — this is what users hit in their browser."
echo "'make up' only starts 'dev', so we also start 'nginx' to expose"
echo "the apps on the documented URLs."
echo ""

# Helper — bring up both dev + nginx for an fe-* repo. Uses --build so
# image changes between recipe runs are picked up.
#
# Pre-clean orphans first. Docker can leave stale container records from
# prior partial runs that still reference an older network ID; when the
# compose project's default network is (re)created, those leftover
# containers try to attach to the obsolete ID and the daemon errors with
# "failed to set up container networking: network <id> not found".
# `compose down --remove-orphans` clears those records without touching
# named volumes (node_modules + plugin_api_node_modules stay intact, so
# the next `up` doesn't have to re-run `npm install`).
start_frontend() {
    local dir="$1"
    local label="$2"
    (
        cd "$dir" || exit 1
        echo "── $label (cwd: $dir) ──"
        # Stop any leftover containers + drop the project network so the
        # next up attaches everyone to a fresh, consistent network ID.
        docker compose --profile dev down --remove-orphans >/dev/null 2>&1 || true
        if ! docker compose --profile dev up dev nginx -d --build; then
            echo "WARNING: first 'docker compose up' for $label failed."
            echo "  Pruning unused networks and retrying once..."
            docker network prune -f >/dev/null 2>&1 || true
            docker compose --profile dev up dev nginx -d --build || {
                echo "ERROR: $label still failed to start — inspect:"
                echo "       cd $dir && docker compose --profile dev logs"
                return 1
            }
        fi
    )
}

start_frontend "$FE_USER_DIR"  "vbwd-fe-user"
start_frontend "$FE_ADMIN_DIR" "vbwd-fe-admin"

# Verify each app responds on its public port — the recipe's summary
# below claims they're up; this proves it before the user sees it.
if wait_for_service "vbwd-fe-user"  "${HTTP}://${DOMAIN}:${FE_USER_PORT}/"  60; then
    echo "✓ User app reachable on ${HTTP}://${DOMAIN}:${FE_USER_PORT}"
else
    echo "WARNING: User app didn't answer on ${HTTP}://${DOMAIN}:${FE_USER_PORT} yet."
    echo "  Check logs with: cd $FE_USER_DIR && docker compose logs -f dev nginx"
fi
if wait_for_service "vbwd-fe-admin" "${HTTP}://${DOMAIN}:${FE_ADMIN_PORT}/" 60; then
    echo "✓ Admin app reachable on ${HTTP}://${DOMAIN}:${FE_ADMIN_PORT}"
else
    echo "WARNING: Admin app didn't answer on ${HTTP}://${DOMAIN}:${FE_ADMIN_PORT} yet."
    echo "  Check logs with: cd $FE_ADMIN_DIR && docker compose logs -f dev nginx"
fi


# Summary
echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Services:"
echo "  - Backend API:          ${HTTP}://${DOMAIN}:5000"
echo "  - Frontend (User app):  ${HTTP}://${DOMAIN}:$FE_USER_PORT"
echo "  - Frontend (Admin app): ${HTTP}://${DOMAIN}:$FE_ADMIN_PORT"
echo "  - Database:             postgresql://vbwd:vbwd@${DOMAIN}:5432/vbwd"
echo ""
echo "Default admin login (LOCAL DEV ONLY — rotate before exposing the stack):"
echo "  - Email:    $ADMIN_EMAIL"
echo "  - Password: $ADMIN_PASSWORD"
echo "  - Admin UI: ${HTTP}://${DOMAIN}:$FE_ADMIN_PORT/admin/login"
echo ""
echo "Plugin selection mode: $PLUGIN_MODE"
echo "  Installed & enabled (with demo settings, demo data, and assets):"
echo "    ${SELECTED_IDS[*]}"
echo ""
echo "Demo data is seeded (idempotent — re-run this recipe any time) for every"
echo "selected plugin that ships a populate script, e.g.:"
echo "  - CMS:           styles, widgets, layouts, pages + image gallery"
echo "  - Booking:       resources, schemas, bookings, CMS pages, email templates"
echo "  - Shop:          products, categories, warehouses, stock, CMS pages"
echo "  - GHRM:          catalogue + detail layouts/widgets/pages"
echo "  - Discount:      demo discounts + coupons"
echo "  - Token payment: demo token bundles + invoice pricing"
echo "  - Subscription:  demo plans / bundles; Taro: 78 arcana cards; …"
echo ""
echo "CMS routing: /  and  /index.html  →  /home  (rewrite)"
echo "  Edit at: ${HTTP}://${DOMAIN}:$FE_ADMIN_PORT/admin/cms/routing"
echo ""
echo "Repository Structure:"
echo "  - Backend:    $BACKEND_DIR"
echo "  - Core Lib:   $FE_CORE_DIR"
echo "  - User App:   $FE_USER_DIR (depends on core via git submodule)"
echo "  - Admin App:  $FE_ADMIN_DIR (depends on core via git submodule)"
echo ""
echo "Frontends are already running (dev + nginx containers started above)."
echo "If you prefer a native dev server with HMR instead of the dockerised dev,"
echo "stop the 'dev' container and run 'npm run dev' from the repo root."
echo ""
echo "Useful commands:"
echo "  - Backend logs:    cd $BACKEND_DIR && docker compose logs -f api"
echo "  - User app logs:   cd $FE_USER_DIR && docker compose logs -f dev nginx"
echo "  - Admin app logs:  cd $FE_ADMIN_DIR && docker compose logs -f dev nginx"
echo "  - Stop user app:   cd $FE_USER_DIR && docker compose down"
echo "  - Stop admin app:  cd $FE_ADMIN_DIR && docker compose down"
echo "  - Stop backend:    cd $BACKEND_DIR && docker compose down"
echo "  - Run tests:       cd $BACKEND_DIR && make test"
echo ""
echo "Documentation: $WORKSPACE_DIR/docs/"
echo ""
