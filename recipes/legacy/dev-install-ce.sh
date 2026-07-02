#!/bin/bash
set -e

# VBWD Community Edition - Development Installation Script
# Works for both local development and GitHub Actions
# Usage: ./recipes/dev-install-ce.sh

echo "=========================================="
echo "VBWD CE Development Environment Setup"
echo "=========================================="

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
BACKEND_REPO="https://github.com/dantweb/vbwd-backend.git"
FRONTEND_REPO="https://github.com/dantweb/vbwd-frontend.git"
BACKEND_DIR="$WORKSPACE_DIR/vbwd-backend"
FRONTEND_DIR="$WORKSPACE_DIR/vbwd-frontend"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
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

if ! command_exists docker-compose; then
    echo "ERROR: docker-compose is not installed"
    exit 1
fi

echo "All prerequisites met"

# Clone backend repository
echo ""
echo "=========================================="
echo "Step 1: Setting up vbwd-backend"
echo "=========================================="

if [ -d "$BACKEND_DIR" ]; then
    echo "Backend directory already exists, pulling latest changes..."
    cd "$BACKEND_DIR"
    git pull origin main || true
else
    echo "Cloning vbwd-backend..."
    git clone "$BACKEND_REPO" "$BACKEND_DIR"
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

# Clone frontend repository
echo ""
echo "=========================================="
echo "Step 2: Setting up vbwd-frontend"
echo "=========================================="

if [ -d "$FRONTEND_DIR" ]; then
    echo "Frontend directory already exists, pulling latest changes..."
    cd "$FRONTEND_DIR"
    git pull origin main || true
else
    echo "Cloning vbwd-frontend..."
    git clone "$FRONTEND_REPO" "$FRONTEND_DIR"
    cd "$FRONTEND_DIR"
fi

# Setup frontend environment
if [ ! -f "$FRONTEND_DIR/.env" ]; then
    echo "Creating frontend .env file..."
    if [ -f "$FRONTEND_DIR/.env.example" ]; then
        cp "$FRONTEND_DIR/.env.example" "$FRONTEND_DIR/.env"
    else
        # Create minimal .env if example doesn't exist
        cat > "$FRONTEND_DIR/.env" << 'EOF'
VITE_API_URL=http://localhost:5000
VITE_WS_URL=ws://localhost:5000
EOF
    fi
    echo "Frontend .env file created"
else
    echo "Frontend .env file already exists"
fi

# Start Docker containers
echo ""
echo "=========================================="
echo "Step 3: Starting Docker containers"
echo "=========================================="

cd "$BACKEND_DIR"

# Stop any existing containers
echo "Stopping any existing containers..."
docker-compose down -v || true

# Build and start containers
echo "Building and starting containers..."
if [ "$IS_CI" = true ]; then
    # In CI, use detached mode and wait for services
    docker-compose up -d --build
else
    # In local dev, also use detached mode
    docker-compose up -d --build
fi

# Wait for services to be ready
echo ""
echo "Waiting for services to start..."
sleep 5

# Check backend health
if wait_for_service "Backend API" "http://localhost:5000/health" 60; then
    echo "Backend API is running on http://localhost:5000"
else
    echo "ERROR: Backend API failed to start"
    echo "Checking backend logs..."
    docker-compose logs api
    exit 1
fi

# Check database
echo "Checking database connection..."
if docker-compose exec -T api python -c "from sqlalchemy import create_engine; import os; e=create_engine(os.getenv('DATABASE_URL', 'postgresql://vbwd:vbwd@postgres:5432/vbwd')); c=e.connect(); print('Database: OK'); c.close()" 2>/dev/null; then
    echo "Database is connected and ready"
else
    echo "WARNING: Database connection check failed"
    docker-compose logs postgres
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

# Run backend tests
echo ""
echo "=========================================="
echo "Step 4: Running backend tests"
echo "=========================================="

cd "$BACKEND_DIR"
echo "Running all backend tests..."
if docker-compose run --rm python-test pytest tests/ -v --tb=short; then
    echo "Backend tests passed!"
else
    echo "ERROR: Backend tests failed"
    exit 1
fi

# Setup frontend
echo ""
echo "=========================================="
echo "Step 5: Setting up frontend"
echo "=========================================="

cd "$FRONTEND_DIR"

# Check if frontend has docker-compose
if [ -f "$FRONTEND_DIR/docker-compose.yml" ]; then
    echo "Starting frontend containers..."
    docker-compose up -d --build

    # Wait for frontend
    if wait_for_service "Frontend" "http://localhost:8080" 30; then
        echo "Frontend is running on http://localhost:8080"
    else
        echo "WARNING: Frontend failed to start"
        docker-compose logs
    fi
else
    echo "No docker-compose.yml found in frontend, skipping container start"
fi

# Summary
echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Services:"
echo "  - Backend API: http://localhost:5000"
echo "  - Frontend:    http://localhost:8080"
echo "  - Database:    postgresql://vbwd:vbwd@localhost:5432/vbwd"
echo ""
echo "Useful commands:"
echo "  - Backend logs:  cd $BACKEND_DIR && docker-compose logs -f api"
echo "  - Frontend logs: cd $FRONTEND_DIR && docker-compose logs -f"
echo "  - Run tests:     cd $BACKEND_DIR && make test"
echo "  - Stop all:      cd $BACKEND_DIR && docker-compose down"
echo ""
echo "Documentation: $WORKSPACE_DIR/docs/"
echo ""
