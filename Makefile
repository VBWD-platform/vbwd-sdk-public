.PHONY: up down up-build rebuild-backend rebuild-admin rebuild-user total-rebuild code-rebuild logs ps clean npm-install unit integration styles

# Install npm dependencies for all frontend packages
npm-install:
	@echo "Installing npm dependencies..."
	cd vbwd-fe-core && npm install
	cd vbwd-fe-user && npm install
	cd vbwd-fe-admin && npm install
	@echo "Building core shared library..."
	cd vbwd-fe-core && npm run build
	@echo "All npm dependencies installed and core library built"

# Start all containers (backend + frontend)
up:
	cd vbwd-backend && docker compose up api postgres -d --build
	cd vbwd-fe-user && docker compose build dev nginx --no-cache && docker compose up dev nginx -d
	cd vbwd-fe-admin && docker compose build dev nginx --no-cache && docker compose up dev nginx -d
	@echo "All services started"

# Start with rebuild
rebuild-backend:
	cd vbwd-backend && docker compose build --no-cache  && docker compose up -d
	@echo "All services rebuilt and started"

# Rebuild and restart only the admin frontend
rebuild-admin:
	cd vbwd-fe-admin && npm install
	cd vbwd-fe-admin && npm run build
	cd vbwd-fe-admin && docker compose down -v
	cd vbwd-fe-admin && docker compose build dev nginx --no-cache
	cd vbwd-fe-admin && docker compose up dev nginx -d
	@echo "Admin frontend rebuilt and restarted at http://localhost:8081"

rebuild-user:
	cd vbwd-fe-admin && npm install
	cd vbwd-fe-user && npm run build
	cd vbwd-fe-user && docker compose down -v
	cd vbwd-fe-user && docker compose build dev nginx --no-cache
	cd vbwd-fe-user && docker compose up dev nginx -d
	@echo "User frontend rebuilt and restarted at http://localhost:8080"

rebuild-core:
	cd vbwd-fe-core && npm install && npm run build

# Stop all containers
down:
	cd vbwd-fe-admin && docker compose down nginx dev -v
	cd vbwd-fe-user && docker compose down nginx dev -v
	cd vbwd-backend && docker compose down
	@echo "All services stopped"

# View logs from all services
be-logs:
	cd vbwd-backend && docker compose logs -f

# Show status of all containers
ps:
	@echo "=== Backend ===" && cd vbwd-backend && docker compose ps
	@echo "=== Frontend User ===" && cd vbwd-fe-user && docker compose ps
	@echo "=== Frontend Admin ===" && cd vbwd-fe-admin && docker compose ps

migrations:
	cd vbwd-backend && docker compose exec api alembic upgrade heads

reset-db:
	cd vbwd-backend && ./bin/reset-database.sh
	cd vbwd-backend && ./plugins/taro/bin/populate-db.sh
	cd vbwd-backend && ./plugins/cms/bin/populate-db.sh
	cd vbwd-backend && ./plugins/email/bin/populate-db.sh
	cd vbwd-backend && ./plugins/ghrm/bin/populate-db.sh
	cd vbwd-backend && ./plugins/booking/bin/populate-db.sh
	cd vbwd-backend && ./plugins/subscription/bin/populate-db.sh 2>/dev/null || true
	cd vbwd-backend && ./plugins/shop/bin/populate-db.sh
	cd vbwd-backend && ./plugins/discount/bin/populate-db.sh

# Run unit tests across all packages
unit:
	@echo "=== Backend unit tests ==="
	cd vbwd-backend && $(MAKE) test-unit
	@echo "=== fe-core unit tests ==="
	cd vbwd-fe-core && npm run test
	@echo "=== fe-admin unit tests ==="
	cd vbwd-fe-admin && npm run test
	@echo "=== fe-user unit tests ==="
	cd vbwd-fe-user && npm run test
	@echo "All unit tests passed"

# Run integration tests across all packages
integration:
	@echo "=== Backend integration tests ==="
	cd vbwd-backend && $(MAKE) test-integration
	@echo "All integration tests passed"

# Run style/lint checks across all packages
styles:
	@echo "=== Backend lint ==="
	cd vbwd-backend && $(MAKE) lint
	@echo "=== fe-core lint ==="
	cd vbwd-fe-core && npm run lint
	@echo "=== fe-admin lint ==="
	cd vbwd-fe-admin && npm run lint
	@echo "=== fe-user lint ==="
	cd vbwd-fe-user && npm run lint
	@echo "All style checks passed"

code-rebuild:
	$(MAKE) down
	$(MAKE) rebuild-core
	$(MAKE) rebuild-admin
	$(MAKE) rebuild-user
	$(MAKE) rebuild-backend
	@echo "Code rebuild complete"

total-rebuild:
	$(MAKE) down
	$(MAKE) rebuild-core
	$(MAKE) rebuild-admin
	$(MAKE) rebuild-user
	$(MAKE) rebuild-backend
	@echo "Waiting for api service to be healthy..."
	@cd vbwd-backend && until docker compose exec -T api python -c "import sys; sys.exit(0)" 2>/dev/null; do \
		echo "  api not ready yet, retrying in 3s..."; \
		sleep 3; \
	done
	@echo "api is ready"
	cd vbwd-backend && ./bin/reset-database.sh --force
	cd vbwd-backend && ./plugins/taro/bin/populate-db.sh
	cd vbwd-backend && ./plugins/cms/bin/populate-db.sh
	cd vbwd-backend && ./plugins/ghrm/bin/populate-db.sh
	cd vbwd-backend && ./plugins/email/bin/populate-db.sh
	cd vbwd-backend && ./plugins/booking/bin/populate-db.sh
	cd vbwd-backend && ./plugins/shop/bin/populate-db.sh
	cd vbwd-backend && ./plugins/discount/bin/populate-db.sh
	@echo "Total rebuild complete"