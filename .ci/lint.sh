#!/usr/bin/env bash
# ============================================================================
#  BorgOS CI/CD - Lint Stage
#  Purpose: Run linting and security checks on all code
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$PROJECT_ROOT/artifacts}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[LINT]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Create artifacts directory
mkdir -p "$ARTIFACTS_DIR"

log "Starting linting checks..."
cd "$PROJECT_ROOT"

# Track overall status
LINT_FAILED=0

# Python linting
log "Running Python linters..."
if command -v ruff >/dev/null 2>&1; then
    log "Running ruff..."
    ruff check . --output-format=json > "$ARTIFACTS_DIR/ruff-report.json" || LINT_FAILED=1
    ruff check . || true
else
    warn "ruff not installed, installing..."
    pip install ruff
    ruff check . || LINT_FAILED=1
fi

if command -v bandit >/dev/null 2>&1; then
    log "Running bandit security scan..."
    bandit -r installer webui mcp_servers \
        -f html -o "$ARTIFACTS_DIR/bandit-report.html" || LINT_FAILED=1
else
    warn "bandit not installed, installing..."
    pip install bandit
    bandit -r installer webui mcp_servers || LINT_FAILED=1
fi

# Bash/Shell linting
log "Running shellcheck..."
if command -v shellcheck >/dev/null 2>&1; then
    # Find all shell scripts
    find . -type f \( -name "*.sh" -o -name "*.bash" \) -not -path "./env/*" -not -path "./.git/*" | while read -r script; do
        log "Checking $script..."
        shellcheck "$script" || LINT_FAILED=1
    done
else
    warn "shellcheck not installed. Please install: apt-get install shellcheck"
fi

# Check Python files for common issues
log "Checking Python syntax..."
find . -name "*.py" -not -path "./env/*" -not -path "./.git/*" | while read -r pyfile; do
    python3 -m py_compile "$pyfile" || LINT_FAILED=1
done

# Check for hardcoded secrets
log "Scanning for hardcoded secrets..."
if command -v detect-secrets >/dev/null 2>&1; then
    detect-secrets scan --baseline .secrets.baseline || true
else
    warn "detect-secrets not installed, skipping secrets scan"
fi

# Generate summary report
log "Generating lint summary..."
cat > "$ARTIFACTS_DIR/lint-summary.txt" <<EOF
BorgOS Lint Report
==================
Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Project: $PROJECT_ROOT

Python Files Checked: $(find . -name "*.py" -not -path "./env/*" | wc -l)
Shell Scripts Checked: $(find . -name "*.sh" -not -path "./env/*" | wc -l)

Artifacts Generated:
- ruff-report.json
- bandit-report.html
- lint-summary.txt

Status: $([ $LINT_FAILED -eq 0 ] && echo "PASSED" || echo "FAILED")
EOF

if [ $LINT_FAILED -ne 0 ]; then
    error "Linting checks failed. See artifacts in $ARTIFACTS_DIR"
else
    log "All linting checks passed!"
fi