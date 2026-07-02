#!/bin/bash
set -e

# VBWD Taro Plugin - Development Installation Script
# ==================================================
# Installs the complete VBWD CE environment and populates Taro card database
# Works for both local development and GitHub Actions
# Usage: ./recipes/dev-install-taro.sh

echo "=========================================="
echo "VBWD CE + Taro Plugin Development Setup"
echo "=========================================="
echo ""

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
echo ""

# Step 1: Run base CE installation
echo "=========================================="
echo "Step 1: Installing VBWD Community Edition"
echo "=========================================="
echo ""

if [ -f "$WORKSPACE_DIR/recipes/dev-install-ce.sh" ]; then
    bash "$WORKSPACE_DIR/recipes/dev-install-ce.sh"
    if [ $? -eq 0 ]; then
        echo ""
        echo "✓ Community Edition installation completed"
    else
        echo ""
        echo "✗ Community Edition installation failed"
        exit 1
    fi
else
    echo "ERROR: dev-install-ce.sh not found at $WORKSPACE_DIR/recipes/dev-install-ce.sh"
    exit 1
fi

# Step 2: Populate Taro database
echo ""
echo "=========================================="
echo "Step 2: Populating Taro Card Database"
echo "=========================================="
echo ""

TARO_POPULATE_SCRIPT="$WORKSPACE_DIR/vbwd-backend/plugins/taro/bin/populate-db.sh"

if [ -f "$TARO_POPULATE_SCRIPT" ]; then
    cd "$WORKSPACE_DIR/vbwd-backend"
    bash "$TARO_POPULATE_SCRIPT"
    if [ $? -eq 0 ]; then
        echo ""
        echo "✓ Taro database population completed"
    else
        echo ""
        echo "✗ Taro database population failed"
        exit 1
    fi
else
    echo "ERROR: populate-db.sh not found at $TARO_POPULATE_SCRIPT"
    exit 1
fi

# Summary
echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "VBWD CE + Taro Plugin is now ready:"
echo ""
echo "Services:"
echo "  - Backend API: http://localhost:5000"
echo "  - Frontend:    http://localhost:8080"
echo "  - Database:    postgresql://vbwd:vbwd@localhost:5432/vbwd"
echo ""
echo "Taro Plugin:"
echo "  - API: http://localhost:8080/plugins/taro"
echo "  - Cards: 78 arcana cards populated"
echo "  - SVG Assets: $WORKSPACE_DIR/vbwd-backend/plugins/taro/assets/arcana/"
echo ""
echo "Useful commands:"
echo "  - Backend logs:  cd $WORKSPACE_DIR/vbwd-backend && docker-compose logs -f api"
echo "  - Frontend logs: cd $WORKSPACE_DIR/vbwd-frontend && docker-compose logs -f"
echo "  - Run tests:     cd $WORKSPACE_DIR/vbwd-backend && make test"
echo "  - Stop all:      cd $WORKSPACE_DIR/vbwd-backend && docker-compose down"
echo "  - Repopulate DB: cd $WORKSPACE_DIR/vbwd-backend && bash plugins/taro/bin/populate-db.sh"
echo ""
echo "Documentation:"
echo "  - Main Docs: $WORKSPACE_DIR/docs/"
echo "  - Taro Docs: $WORKSPACE_DIR/docs/devlog/"
echo "  - Plugin System: $WORKSPACE_DIR/CLAUDE.md"
echo ""
