#!/bin/bash
set -e

# VBWD Database Migrations Script
# Runs Alembic migrations against the database
# Usage: ./recipes/run_migrations.sh [options]
#
# Options:
#   upgrade       Run pending migrations (default)
#   downgrade     Rollback last migration
#   revision      Create a new migration
#   current       Show current migration revision
#   history       Show migration history

echo "=========================================="
echo "VBWD Database Migrations"
echo "=========================================="

# Detect environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="${BACKEND_DIR:-$WORKSPACE_DIR/vbwd-backend}"

if [ ! -d "$BACKEND_DIR" ]; then
    echo "ERROR: Backend directory not found at $BACKEND_DIR"
    echo "Make sure vbwd-backend is set up or set BACKEND_DIR environment variable"
    exit 1
fi

cd "$BACKEND_DIR"

# Check if docker compose services are running
if ! docker compose ps | grep -q "api.*Up"; then
    echo "ERROR: Backend API container is not running"
    echo "Start the containers first with: docker compose up -d"
    exit 1
fi

# Parse arguments
COMMAND="${1:-upgrade}"

case "$COMMAND" in
    upgrade)
        echo "Running database migrations..."
        docker compose exec -T api alembic upgrade heads
        if [ $? -eq 0 ]; then
            echo "Migrations completed successfully!"
        else
            echo "ERROR: Migration failed"
            exit 1
        fi
        ;;
    downgrade)
        REVISION="${2:--1}"
        echo "Rolling back migration to: $REVISION"
        docker compose exec -T api alembic downgrade "$REVISION"
        if [ $? -eq 0 ]; then
            echo "Rollback completed successfully!"
        else
            echo "ERROR: Rollback failed"
            exit 1
        fi
        ;;
    revision)
        MESSAGE="${2:-auto migration}"
        echo "Creating new migration: $MESSAGE"
        docker compose exec -T api alembic revision --autogenerate -m "$MESSAGE"
        if [ $? -eq 0 ]; then
            echo "Migration file created successfully!"
        else
            echo "ERROR: Failed to create migration"
            exit 1
        fi
        ;;
    current)
        echo "Current migration revision:"
        docker compose exec -T api alembic current
        ;;
    history)
        echo "Migration history:"
        docker compose exec -T api alembic history
        ;;
    help|--help|-h)
        echo ""
        echo "Usage: $0 [command] [args]"
        echo ""
        echo "Commands:"
        echo "  upgrade              - Run pending migrations to head (default)"
        echo "  downgrade [rev]      - Rollback to revision (default: -1 for previous)"
        echo "  revision [message]   - Create new migration with autogenerate"
        echo "  current              - Show current migration revision"
        echo "  history              - Show migration history"
        echo "  help                 - Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0                   # Run all pending migrations"
        echo "  $0 upgrade           # Same as above"
        echo "  $0 downgrade         # Rollback one migration"
        echo "  $0 downgrade base    # Rollback all migrations"
        echo "  $0 revision 'Add users table'"
        echo ""
        ;;
    *)
        echo "Unknown command: $COMMAND"
        echo "Use 'help' for usage information"
        exit 1
        ;;
esac
