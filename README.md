# VBWD SDK

**Self-hosted SaaS subscription platform** — open-source, plugin-based, CC0 licensed.

Deploy on your own server and get a complete subscription business out of the box: recurring billing, token economy, add-ons, invoicing, multi-gateway payments, user portal, and admin backoffice — all extensible via a plugin system without touching core code.

---

## What Is VBWD?

VBWD is an infrastructure kit for building subscription-based products. It is not a hosted service — you own the server, the database, and every byte of user data.

**Core capabilities:**

| Capability | Details |
|------------|---------|
| Subscription billing | Tiered plans, billing periods, multi-currency, upgrade/downgrade/cancel |
| Token economy | Credit bundles users purchase and spend on premium features |
| Add-ons | One-time or recurring extras on top of base subscriptions |
| Invoicing | Full invoice lifecycle with line-item detail and tax support |
| Payments | Stripe, PayPal, YooKassa — swappable via plugins |
| User portal | Dashboard, plans, checkout, subscription management, invoices, tokens |
| Admin backoffice | Users, plans, subscriptions, invoices, analytics, webhooks, plugin management |
| CMS | Content pages, categories, image uploads, slug routing |
| AI chat | LLM-powered assistant with token-billed usage |
| Embed widget | Pricing page embeddable on any external site via JS snippet |
| Plugin system | Extend backend and frontend without modifying core files |
| Webhooks | Outbound events for integration with any external system |
| i18n | Multi-language support (EN/DE built-in, extensible) |

---

## What Can You Build With It?

VBWD is the billing and subscriber management layer. You pick a vertical, deploy VBWD, add a niche-specific plugin, and have a production-ready SaaS product.

**Examples:**

- **Online coaching platform** — Kajabi alternative, self-hosted, 0% platform cut
- **Newsletter / creator platform** — Ghost/Substack alternative, keep 100% of revenue
- **Digital downloads marketplace** — Gumroad alternative, flat fee instead of 10% per sale
- **Agency white-label billing OS** — GoHighLevel alternative for EU agencies (EU-hosted, GDPR-compliant by architecture)
- **AI tool with metered billing** — token economy handles API call billing per user
- **Subscription box management** — recurring billing + fulfillment webhooks + member content
- **Adult content / creator platform** — self-hosted, no deplatforming risk, token pay-per-content
- **Spiritual / tarot platform** — Taro plugin ships with the platform

**Why self-hosted:**
- No transaction fees (Substack 10%, Gumroad 10%, OnlyFans 20% — vs €0)
- EU Data Act + GDPR compliance by architecture — data never leaves your server
- CC0 license — no usage restrictions, no vendor lock-in, ever
- No per-seat or revenue-based pricing from a vendor
- Full control over features via the plugin system

---

## Architecture

```
vbwd-sdk/
├── vbwd-backend/          # Python/Flask API, PostgreSQL, Redis
├── vbwd-fe-core/          # Shared Vue 3 component library (git submodule)
├── vbwd-fe-user/          # User-facing app (port 8080)
├── vbwd-fe-admin/         # Admin backoffice (port 8081)
├── recipes/               # Installation scripts
└── docs/                  # Architecture documentation and devlogs
```

**Stack:** Python 3.11 · Flask 3.0 · PostgreSQL 16 · Redis 7 · Vue 3 · TypeScript · Vite · Pinia · Docker

**Tests:** 1,851 passing (661 backend pytest + 316 core Vitest + 293 user Vitest/Playwright + 331 admin Vitest/Playwright + payment plugin suites)

---

## Quick Start

```bash
# VBWD Community Edition - Development Installation Script
# Works for both local development and GitHub Actions
# Usage: ./recipes/dev-install-ce.sh [--domain <hostname>] [--ssl]

Or set VBWD_DOMAIN / VBWD_SSL env vars before running.

# installtion with script

Examples:

./recipes/dev-install-ce.sh                              # http://localhost
./recipes/dev-install-ce.sh --domain myapp.com          # http://myapp.com
./recipes/dev-install-ce.sh --domain myapp.com --ssl    # https://myapp.com
VBWD_DOMAIN=myapp.com VBWD_SSL=1 ./recipes/dev-install-ce.sh
```

This should be enough.

After install use Makefile commands when you need.

```bash
# Backend
cd vbwd-backend && make up && make test

# Frontend
cd vbwd-frontend && make up
```

**Admin Panel:** http://localhost:8081
**User App:** http://localhost:8080

## Development Commands

```bash
# From root directory
make up              # Start all services
make up-build        # Rebuild and start all services
make rebuild-admin   # Rebuild only admin frontend (fast iteration)
make down            # Stop all services
make ps              # Show status of all containers
make logs            # View backend logs
make clean           # Remove all containers and volumes
```

## Tech Stack

| Layer | Technology |
|-------|------------|
| Backend | Python 3.11, Flask 3.0, PostgreSQL 16 |
| Frontend | Vue.js 3, Vite, Pinia, TypeScript |
| Testing | Pytest (561), Vitest (251), Playwright (108) |

## Project Structure

```
vbwd-sdk/
├── vbwd-backend/      # Flask API
├── vbwd-frontend/     # Vue.js apps (user, admin, core)
└── docs/              # Architecture documentation
```

## Plugin System

The platform supports runtime plugins for both backend (Python/Flask) and frontend (Vue.js/TypeScript). Plugins are auto-discovered, dependency-aware, and persist their state across restarts.

### Backend Plugins

#### Lifecycle

```
DISCOVERED → register_plugin() → REGISTERED → initialize_plugin() → INITIALIZED
                                                                         ↕
                                                              enable_plugin() / disable_plugin()
                                                                         ↕
                                                                  ENABLED ↔ DISABLED
```

| Status | Meaning |
|--------|---------|
| `DISCOVERED` | Plugin class found, instance created |
| `REGISTERED` | Added to PluginManager registry |
| `INITIALIZED` | Config applied, ready to enable |
| `ENABLED` | Active, routes registered, hooks fired |
| `DISABLED` | Stopped, persisted to DB for restart |
| `ERROR` | Failed during lifecycle transition |

#### Creating a Backend Plugin

Place a file in `vbwd-backend/src/plugins/providers/` — it will be auto-discovered on startup. No changes to `app.py` required.

```python
# src/plugins/providers/hello_plugin.py
from src.plugins.base import BasePlugin, PluginMetadata
from typing import Optional
from flask import Blueprint

class HelloPlugin(BasePlugin):
    @property
    def metadata(self) -> PluginMetadata:
        return PluginMetadata(
            name="hello",
            version="1.0.0",
            author="Your Name",
            description="Hello world plugin",
            dependencies=[],        # other plugin names this depends on
        )

    def on_enable(self) -> None:
        """Called when plugin is enabled. Start background tasks, etc."""
        pass

    def on_disable(self) -> None:
        """Called when plugin is disabled. Cleanup resources."""
        pass

    # Optional: expose API routes
    def get_blueprint(self) -> Optional[Blueprint]:
        from src.routes.plugins.hello import hello_bp
        return hello_bp

    def get_url_prefix(self) -> Optional[str]:
        return "/api/v1/plugins/hello"
```

#### BasePlugin API

| Method / Property | Description |
|-------------------|-------------|
| `metadata` (abstract property) | Returns `PluginMetadata(name, version, author, description, dependencies)` |
| `status` | Current `PluginStatus` enum value |
| `initialize(config)` | Apply config dict, transition to INITIALIZED |
| `enable()` | Calls `on_enable()`, transition to ENABLED |
| `disable()` | Calls `on_disable()`, transition to DISABLED |
| `on_enable()` | Override: plugin-specific activation logic |
| `on_disable()` | Override: plugin-specific cleanup logic |
| `get_blueprint()` | Override: return a Flask `Blueprint` for routes (or `None`) |
| `get_url_prefix()` | Override: return URL prefix string (or `None`) |
| `get_config(key, default)` | Read a config value |
| `set_config(key, value)` | Write a config value |

#### PluginManager API

```python
from src.plugins.manager import PluginManager

manager = PluginManager(event_dispatcher=dispatcher, config_repo=repo)

manager.discover("src.plugins.providers")    # Auto-scan for BasePlugin subclasses
manager.load_persisted_state()               # Restore enabled plugins from DB

manager.register_plugin(plugin)              # Register an instance
manager.initialize_plugin("name", config)    # Initialize with config
manager.enable_plugin("name")                # Enable (checks dependencies, persists to DB)
manager.disable_plugin("name")               # Disable (checks dependents, persists to DB)

manager.get_plugin("name")                   # Get plugin by name
manager.get_all_plugins()                    # List all registered plugins
manager.get_enabled_plugins()                # List only enabled plugins
manager.get_plugin_blueprints()              # Get (blueprint, prefix) tuples for route registration
```

**Dependency checking:** `enable_plugin()` verifies all declared dependencies are ENABLED first. `disable_plugin()` refuses if other enabled plugins depend on it.

**Event emission:** Events `plugin.registered`, `plugin.initialized`, `plugin.enabled`, `plugin.disabled` are dispatched at each lifecycle stage.

#### Database Persistence

Plugin state is stored in the `plugin_config` table:

| Column | Type | Description |
|--------|------|-------------|
| `plugin_name` | `String(100)` UNIQUE | Plugin identifier |
| `status` | `String(20)` | `"enabled"` or `"disabled"` |
| `config` | `JSONB` | Plugin-specific configuration |
| `enabled_at` | `DateTime` | Last enable timestamp |
| `disabled_at` | `DateTime` | Last disable timestamp |

On startup, `manager.load_persisted_state()` reads this table and re-enables previously enabled plugins. Enable/disable actions automatically persist via `PluginConfigRepository`.

#### App Startup Sequence

```python
# In app.py:
config_repo = PluginConfigRepository(db.session)
plugin_manager = PluginManager(config_repo=config_repo)
app.plugin_manager = plugin_manager

plugin_manager.discover("src.plugins.providers")  # 1. Auto-discover
plugin_manager.load_persisted_state()              # 2. Restore from DB
if not plugin_manager.get_enabled_plugins():       # 3. Default: enable analytics
    plugin_manager.enable_plugin("analytics")

for bp, prefix in plugin_manager.get_plugin_blueprints():  # 4. Register routes
    app.register_blueprint(bp, url_prefix=prefix)
```

#### CLI Commands

```bash
# Inside the API container:
docker compose exec api flask plugins list
# Output: analytics (1.0.0) — ENABLED
#         mock-payment (1.0.0) — INITIALIZED

docker compose exec api flask plugins enable <name>
docker compose exec api flask plugins disable <name>
```

#### Existing Backend Plugins

| Plugin | Description | Routes |
|--------|-------------|--------|
| `analytics` | Dashboard active sessions count | `GET /api/v1/plugins/analytics/active-sessions` |
| `mock-payment` | Mock payment provider for testing | Payment provider interface (no public routes) |

---

### Frontend Plugins (Core View Component)

The frontend plugin system lives in `@vbwd/view-component` (`vbwd-frontend/core/src/plugins/`). It provides a shared plugin architecture consumed by both user and admin Vue.js apps.

See [Core View Component Architecture](docs/architecture_core_view_component/README.md) for the full design document.

#### Architecture Decision

The plugin system is for **extensibility**, not for core features:

| Use plugins for | Use flat `src/views/` + `src/stores/` for |
|-----------------|-------------------------------------------|
| Payment provider integrations (Stripe, PayPal) | Core business features (users, plans, subscriptions) |
| Value-added services (CRM, email marketing) | CRUD operations (invoices, add-ons, webhooks) |
| Analytics widgets and dashboards | Core navigation and layouts |
| Third-party integrations | Authentication and authorization |

#### Lifecycle

```
register() → REGISTERED → install(sdk) → INSTALLED → activate() → ACTIVE
                                                                     ↕
                                                        deactivate() / activate()
                                                                     ↕
                                                                  INACTIVE
                                                      uninstall() → REGISTERED
```

| Status | Meaning |
|--------|---------|
| `REGISTERED` | Plugin added to registry, validated (name, semver) |
| `INSTALLED` | `install(sdk)` called, routes/stores/components registered via SDK |
| `ACTIVE` | `activate()` called, plugin running, event listeners started |
| `INACTIVE` | `deactivate()` called, plugin paused |
| `ERROR` | Failed during lifecycle transition |

#### IPlugin Interface

Located in `vbwd-frontend/core/src/plugins/types.ts`:

```typescript
interface IPlugin {
  name: string;                                        // required, unique
  version: string;                                     // required, semver
  description?: string;
  author?: string;
  homepage?: string;
  keywords?: string[];
  dependencies?: string[] | Record<string, string>;    // version constraints

  install?(sdk: IPlatformSDK): void | Promise<void>;   // register resources
  activate?(): void | Promise<void>;                    // start plugin
  deactivate?(): void | Promise<void>;                  // pause plugin
  uninstall?(): void | Promise<void>;                   // remove resources
}
```

All hooks are optional. Only `name` and `version` are required.

#### IPlatformSDK Interface

The SDK is the API surface plugins use during `install()` to register their resources:

```typescript
interface IPlatformSDK {
  api: IApiClient;                                       // API client instance
  events: IEventBus;                                     // Event bus instance

  addRoute(route: IRouteConfig): void;                   // Register Vue Router route
  getRoutes(): IRouteConfig[];                           // Get all registered routes

  addComponent(name: string, component: ComponentDefinition): void;  // Register global component
  getComponents(): Record<string, ComponentDefinition>;              // Get all components

  createStore(id: string, options: IStoreOptions): string;           // Create Pinia store
  getStores(): Record<string, IStoreOptions>;                        // Get all stores
}
```

**Route config:** `{ path: string, name: string, component: () => Promise<{ default: unknown }> }`
**Store options:** `{ state?: () => Record, getters?: Record, actions?: Record }`

#### Creating a Frontend Plugin

```typescript
import type { IPlugin, IPlatformSDK } from '@vbwd/view-component';

const myPlugin: IPlugin = {
  name: 'my-plugin',
  version: '1.0.0',
  description: 'My custom plugin',
  author: 'Your Name',
  dependencies: [],                     // or { 'other-plugin': '^1.0.0' }

  install(sdk: IPlatformSDK) {
    // Register routes (injected into Vue Router)
    sdk.addRoute({
      path: '/my-page',
      name: 'MyPage',
      component: () => import('./views/MyPage.vue')
    });

    // Register Pinia stores
    sdk.createStore('myStore', {
      state: () => ({ count: 0 }),
      actions: { increment() { this.count++; } }
    });

    // Register global components (rendered dynamically on Dashboard, etc.)
    sdk.addComponent('MyWidget', () => import('./components/MyWidget.vue'));
  },

  activate() {
    // Start background tasks, subscribe to events
  },

  deactivate() {
    // Cleanup, unsubscribe from events
  },

  uninstall() {
    // Remove all registered resources
  }
};
```

#### PluginRegistry API

Manages plugin registration, validation, lifecycle, and dependency resolution:

```typescript
import { PluginRegistry, PlatformSDK } from '@vbwd/view-component';

const registry = new PluginRegistry();
const sdk = new PlatformSDK();

// Registration (validates name, semver format, rejects duplicates)
registry.register(myPlugin);

// Query
registry.get('my-plugin');               // Get plugin metadata (IPluginMetadata) or undefined
registry.getAll();                       // List all registered plugins

// Installation (resolves dependencies via topological sort)
await registry.installAll(sdk);          // Install all in dependency order
await registry.install('name', sdk);     // Install a specific plugin

// Lifecycle
await registry.activate('name');         // Activate plugin → ACTIVE
await registry.deactivate('name');       // Deactivate plugin → INACTIVE
await registry.uninstall('name');        // Uninstall plugin → REGISTERED
```

**Dependency resolution:** `installAll()` performs topological sort on the dependency graph. Throws on:
- Circular dependencies
- Missing dependencies
- Version constraint violations (semver)

#### Admin App Integration

```typescript
// In admin/vue/src/main.ts:
import { PluginRegistry, PlatformSDK } from '@vbwd/view-component';
import { analyticsWidgetPlugin } from './plugins/analytics-widget';

const registry = new PluginRegistry();
const sdk = new PlatformSDK();

// Register plugins
registry.register(analyticsWidgetPlugin);

// Install all (resolves dependencies, calls install hooks)
await registry.installAll(sdk);

// Inject plugin routes into Vue Router
for (const route of sdk.getRoutes()) {
  router.addRoute('admin', route);
}

// Activate all installed plugins
for (const plugin of registry.getAll()) {
  if (plugin.status === 'INSTALLED') {
    await registry.activate(plugin.name);
  }
}
```

The Dashboard dynamically renders widgets registered via `sdk.addComponent()`.

#### Planned Architecture (Core View Component Roadmap)

The [architecture spec](docs/architecture_core_view_component/sprints/sprint-1-plugin-system.md) defines a richer design being implemented in phases:

| Component | Status | Description |
|-----------|--------|-------------|
| `IPlugin` + `PluginRegistry` + `PlatformSDK` | Implemented | Core plugin system |
| `PluginLoader` | Planned | Unified install + activate orchestrator with status tracking |
| `PlatformSDKImpl` | Planned | Full DI: `app`, `router`, `pinia`, `api`, `auth`, `events`, `validation` |
| Declarative registration | Planned | `registerRoutes()`, `registerComponents()`, `registerStores()` on IPlugin |
| CLI Plugin Manager | Planned | `plugin list/install/activate/deactivate` commands |
| Plugin config file | Planned | `plugins.json` for persisting frontend plugin state |

The planned `PlatformSDKImpl` will provide full dependency injection:

```typescript
// Planned: Full SDK with all core services
const sdk = new PlatformSDKImpl(
  app,                    // Vue app instance
  router,                 // Vue Router
  pinia,                  // Pinia store
  apiClient,              // IApiClient — HTTP client
  authService,            // IAuthService — JWT auth
  eventBus,               // IEventBus — plugin communication
  validationService       // IValidationService — Zod schemas
);
```

#### Existing Frontend Plugins

| Plugin | Description | Registration |
|--------|-------------|--------------|
| `analytics-widget` | Dashboard analytics widget | Adds component via `sdk.addComponent()` |

---

### Plugin System File Structure

```
vbwd-backend/src/plugins/
├── base.py                 # BasePlugin, PluginMetadata, PluginStatus
├── manager.py              # PluginManager (lifecycle, discovery, persistence)
└── providers/              # Auto-discovered plugins (drop files here)
    ├── __init__.py
    ├── analytics_plugin.py
    └── mock_payment_plugin.py

vbwd-backend/src/cli/
└── plugins.py              # flask plugins list|enable|disable

vbwd-backend/src/models/
└── plugin_config.py        # DB persistence model (plugin_config table)

vbwd-backend/src/repositories/
└── plugin_config_repository.py  # CRUD for plugin_config table

vbwd-frontend/core/src/plugins/
├── index.ts                # Public exports (PluginRegistry, PlatformSDK, types)
├── types.ts                # IPlugin, IPlatformSDK, IPluginRegistry, PluginStatus
├── PluginRegistry.ts       # Registry with dependency resolution (topological sort)
├── PlatformSDK.ts          # SDK: addRoute, addComponent, createStore
└── utils/
    └── semver.ts           # isValidSemver(), satisfiesVersion()
```

## Documentation

- [Development Guide](CLAUDE.md)
- [Backend Architecture](docs/architecture_core_server_ce/README.md)
- [Admin Architecture](docs/architecture_core_view_admin/README.md)
- [Core View Component Architecture](docs/architecture_core_view_component/README.md) — shared SDK, plugin system, API client, event bus

## License

BSL-1.1 Business Source License
