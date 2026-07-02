# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**vbwd-sdk** - SaaS marketplace platform with subscription billing, user management, and admin dashboard.

- **CE (Community Edition)**: Self-hosted subscription platform (current focus)
- **ME (Marketplace Edition)**: Cloud SaaS marketplace (planned)

**Last Updated:** 2026-02-21
**License:** BSL 1.1 (Business Source Licence)

## Repository Structure (Frontend Split into 3 Independent Repos)

As of 2026-02-20, the frontend has been split into 3 independent GitHub repositories:

```
vbwd-sdk/
├── vbwd-backend/           # Python/Flask API (292 tests)
├── vbwd-fe-core/           # Shared Vue component library (separate GitHub repo)
│   ├── src/
│   ├── dist/               # Built component library
│   ├── package.json
│   └── docker-compose.yaml
├── vbwd-fe-user/           # User-facing Vue app (separate GitHub repo)
│   ├── src/
│   ├── vbwd-fe-core/       # git submodule → vbwd-fe-core repo
│   ├── package.json
│   └── docker-compose.yaml (port 8080)
├── vbwd-fe-admin/          # Admin backoffice Vue app (separate GitHub repo)
│   ├── src/
│   ├── vbwd-fe-core/       # git submodule → vbwd-fe-core repo
│   ├── package.json
│   └── docker-compose.yaml (port 8081)
├── recipes/                # Installation scripts
│   ├── dev-install-ce.sh   # Complete setup (all 3 frontend repos + backend)
│   └── dev-install-taro.sh # Setup CE + Taro plugin database
└── docs/                   # Architecture documentation
    ├── architecture_core_server_ce/      # Backend architecture
    ├── architecture_core_view_admin/     # Admin frontend architecture
    ├── architecture_core_view_component/ # Shared component architecture
    └── devlog/                           # Development logs and reports
```

**Key Points:**
- Each frontend repo is independent with its own CI/CD pipeline
- `vbwd-fe-user` and `vbwd-fe-admin` depend on `vbwd-fe-core` via git submodules
- Build order critical: `vbwd-fe-core` must be built first (generates `dist/`)
- Installation scripts handle correct clone order and submodule initialization

## Development Commands

### Installation

```bash
# Complete development setup (all repos + backend)
./recipes/dev-install-ce.sh

# Complete setup including Taro plugin database
./recipes/dev-install-taro.sh
```

### Backend (`vbwd-backend/`)

```bash
make up                  # Start services (API, PostgreSQL, Redis)
make up-build            # Start with rebuild
make down                # Stop services
make test                # Run unit tests
make test-unit           # Unit tests only
make test-integration    # Integration tests (real PostgreSQL)
make test-coverage       # Tests with coverage report
make lint                # Static analysis (black, flake8, mypy)
make pre-commit          # Full check (lint + unit + integration)
make pre-commit-quick    # Quick check (lint + unit)
make shell               # Access API container bash
make logs                # View service logs
```

### Frontend Core Library (`vbwd-fe-core/`)

```bash
npm install              # Install dependencies
npm run build            # Build component library
npm run dev              # Start dev server
npm run test             # Run tests
npm run lint             # Run ESLint
```

### Frontend User App (`vbwd-fe-user/` - port 8080)

```bash
npm install              # Install (includes submodule)
npm run dev              # Start dev server (port 8080)
npm run build            # Production build
npm run test             # Unit tests (Vitest)
npm run test:e2e         # E2E tests (Playwright)
npm run test:e2e:ui      # E2E with Playwright UI
npm run lint             # ESLint
docker-compose up        # Start with Docker (or separate terminal)
```

### Frontend Admin App (`vbwd-fe-admin/` - port 8081)

```bash
npm install              # Install (includes submodule)
npm run dev              # Start dev server (port 8081)
npm run build            # Production build
npm run test             # Unit tests (Vitest)
npm run test:e2e         # E2E tests (Playwright)
npm run test:e2e:ui      # E2E with Playwright UI
npm run lint             # ESLint
docker-compose up        # Start with Docker (or separate terminal)
```

## Tech Stack

**Backend**: Python 3.11, Flask 3.0, PostgreSQL 16, Redis 7, SQLAlchemy 2.0
**Frontend**: Vue.js 3, Vite, Pinia, Vue Router, TypeScript
**Testing**: Pytest (backend), Vitest (unit), Playwright (E2E)
**Infrastructure**: Docker, Alembic migrations, Gunicorn, Nginx

## Backend Architecture

### Layered Architecture
Routes → Services → Repositories → Models

- **Routes** (`src/routes/`): API endpoints, input validation
- **Services** (`src/services/`): Business logic with dependency injection
- **Repositories** (`src/repositories/`): Data access layer
- **Models** (`src/models/`): SQLAlchemy ORM entities

### Key Patterns
- Dependency injection via `dependency-injector`
- Event-driven architecture for async operations
- SDK adapter pattern for payment providers
- Plugin system for extensibility

### Plugin Management (single source of truth)

Plugin enable/disable state for **all three apps** (backend / fe-admin /
fe-user) is persisted in one directory on the host: `${VAR_DIR}/plugins/`.
All three containers bind-mount it. The backend is the only writer via
`POST /api/v1/admin/frontend-plugins/<app>/<plugin>/{enable,disable}`;
the frontends mount the files read-only. No localStorage, no per-browser
drift. See `docs/architecture/plugin-management.md` for the full design.

**Env vars the backend reads** (set in each compose file):
```
VBWD_VAR_DIR=/app/var
VBWD_BACKEND_PLUGINS_JSON=/app/var/plugins/backend-plugins.json
VBWD_FE_ADMIN_PLUGINS_JSON=/app/var/plugins/fe-admin-plugins.json
VBWD_FE_USER_PLUGINS_JSON=/app/var/plugins/fe-user-plugins.json
# ...plus the three *-config.json counterparts
```

### Plugin System (Backend)

Located in `vbwd-backend/src/plugins/`:
```python
from src.plugins.manager import PluginManager
from src.plugins.base import BasePlugin, PluginMetadata

class MyPlugin(BasePlugin):
    @property
    def metadata(self) -> PluginMetadata:
        return PluginMetadata(name="my-plugin", version="1.0.0", ...)

    def on_enable(self): ...
    def on_disable(self): ...

manager = PluginManager(event_dispatcher)
manager.register_plugin(MyPlugin())
manager.initialize_plugin("my-plugin")
manager.enable_plugin("my-plugin")
```

### API Routes
All routes under `/api/v1/`:
- `/auth/` - register, login, logout, refresh
- `/user/` - profile, subscriptions
- `/tarif-plans/` - plan listing
- `/invoices/` - invoice management
- `/admin/` - admin operations (requires admin role)

## Frontend Architecture

### Core Library (`vbwd-fe-core/`)

Shared Vue component library (exported as `vbwd-view-component`):
```
vbwd-fe-core/
├── src/
│   ├── components/       # Reusable Vue components
│   ├── plugins/          # Plugin system
│   ├── stores/           # Pinia stores
│   └── types/            # TypeScript type definitions
├── dist/                 # Built library (generated by npm run build)
├── package.json          # Exports as vbwd-view-component
└── docker-compose.yaml   # Development docker setup
```

### User App Plugin System (`vbwd-fe-user/`)

Located in `vbwd-fe-user/src/plugins/`:
```typescript
import { PluginRegistry, PlatformSDK, IPlugin } from 'vbwd-view-component';

const myPlugin: IPlugin = {
  name: 'my-plugin',
  version: '1.0.0',
  install(sdk) {
    sdk.addRoute({ path: '/my-page', name: 'MyPage', component: () => import('./MyPage.vue') });
    sdk.createStore('myStore', { state: () => ({ count: 0 }) });
    sdk.addTranslations('en', { /* translations */ });
  },
  activate() { console.log('Plugin activated'); },
  deactivate() { console.log('Plugin deactivated'); }
};

const registry = new PluginRegistry();
registry.register(myPlugin);
await registry.installAll(sdk);
await registry.activate('my-plugin');
```

**Note:** User app uses plugin architecture; Admin app uses flat structure.

### Admin App Structure (`vbwd-fe-admin/`)
```
vbwd-fe-admin/
├── src/
│   ├── api/              # API client
│   ├── stores/           # Pinia stores
│   │   ├── auth.ts       # Authentication
│   │   ├── users.ts      # User management
│   │   ├── planAdmin.ts  # Plan management
│   │   ├── subscriptions.ts
│   │   ├── invoices.ts
│   │   ├── webhooks.ts
│   │   └── analytics.ts
│   ├── views/            # Page components
│   │   ├── Dashboard.vue
│   │   ├── Users.vue, UserDetails.vue
│   │   ├── Plans.vue, PlanForm.vue
│   │   ├── Subscriptions.vue, SubscriptionDetails.vue
│   │   ├── Invoices.vue, InvoiceDetails.vue
│   │   ├── Webhooks.vue, WebhookDetails.vue
│   │   ├── Analytics.vue
│   │   └── Settings.vue
│   └── router/           # Vue Router config
└── tests/
    ├── unit/             # Vitest unit tests
    └── e2e/              # Playwright E2E tests
```

## Testing

### Backend
```bash
cd vbwd-backend
docker-compose run --rm test pytest tests/unit/ -v
docker-compose run --rm test pytest tests/unit/services/test_auth_service.py -v
```

### Frontend - User App (`vbwd-fe-user/`)
```bash
cd vbwd-fe-user
npm run test                           # Unit tests (Vitest)
npm run test:e2e                       # E2E tests (Playwright)
npx playwright test --ui               # Interactive UI mode
E2E_BASE_URL=http://localhost:8080 npx playwright test  # Against local server
```

### Frontend - Admin App (`vbwd-fe-admin/`)
```bash
cd vbwd-fe-admin
npm run test                           # Unit tests (Vitest)
npm run test:e2e                       # E2E tests (Playwright)
npx playwright test --ui               # Interactive UI mode
E2E_BASE_URL=http://localhost:8081 npx playwright test  # Against local server
```

### Frontend - Core Library (`vbwd-fe-core/`)
```bash
cd vbwd-fe-core
npm run test                           # Unit tests
npm run lint                           # ESLint
```

Test credentials:
- Admin: `admin@example.com` / `AdminPass123@`
- User: `test@example.com` / `TestPass123@`

## Database

PostgreSQL 16 with Alembic migrations.

```bash
# Run migrations
docker-compose exec api flask db upgrade

# Create migration
docker-compose exec api flask db migrate -m "description"

# Access database
docker-compose exec postgres psql -U vbwd -d vbwd
```

## Key Configuration

### Environment Variables (`.env`)
- `DATABASE_URL` - PostgreSQL connection
- `REDIS_URL` - Redis connection
- `JWT_SECRET_KEY` - JWT signing key
- `FLASK_ENV` - development/production

### Nginx Proxy
The frontend nginx proxies `/api/` to the backend:
- User app: port 8080
- Admin app: port 8081
- Backend API: port 5000 (internal)

## Known Issues

1. **E2E Tests in Docker**: Need `E2E_BASE_URL` env var to run against docker container (for frontend apps)
2. **Admin App Architecture**: Uses flat structure instead of plugin system (user app uses plugins)
3. **Submodule Initialization**: Must clone frontend apps with `git clone --recurse-submodules` or manually init
4. **Build Order Dependency**: `vbwd-fe-core` must complete `npm run build` before other apps can `npm install`
5. **Multiple Frontend Ports**: User app (8080) and Admin app (8081) must run in separate terminals

## Documentation

- **Backend Architecture**: `docs/architecture_core_server_ce/README.md`
- **Admin Architecture**: `docs/architecture_core_view_admin/README.md`
- **Component Architecture**: `docs/architecture_core_view_component/README.md`
- **Development Logs**: `docs/devlog/YYYYMMDD/`
