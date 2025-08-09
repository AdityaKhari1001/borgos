#!/usr/bin/env bash
# ============================================================================
#  BorgOS CI/CD - Test Stage
#  Purpose: Run unit tests with coverage reporting
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$PROJECT_ROOT/artifacts}"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-90}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[TEST]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Create artifacts directory
mkdir -p "$ARTIFACTS_DIR"

log "Starting test suite..."
cd "$PROJECT_ROOT"

# Set up Python environment
if [ ! -d "env" ]; then
    log "Creating Python virtual environment..."
    python3 -m venv env
fi

source env/bin/activate

# Install test dependencies
log "Installing test dependencies..."
pip install -q pytest pytest-cov pytest-asyncio pytest-mock coverage

# Install project dependencies
if [ -f "webui/requirements.txt" ]; then
    pip install -q -r webui/requirements.txt
fi

# Run tests with coverage
log "Running unit tests..."
python -m pytest tests/ \
    --cov=webui \
    --cov=mcp_servers \
    --cov=installer \
    --cov-report=term-missing \
    --cov-report=html:artifacts/coverage-html \
    --cov-report=xml:artifacts/coverage.xml \
    --junit-xml=artifacts/test-results.xml \
    -v || TEST_FAILED=1

# Check coverage threshold
log "Checking coverage threshold (>=$COVERAGE_THRESHOLD%)..."
COVERAGE_PERCENT=$(python -c "
import xml.etree.ElementTree as ET
tree = ET.parse('artifacts/coverage.xml')
root = tree.getroot()
coverage = float(root.attrib.get('line-rate', 0)) * 100
print(f'{coverage:.2f}')
" 2>/dev/null || echo "0")

log "Coverage: ${COVERAGE_PERCENT}%"

if (( $(echo "$COVERAGE_PERCENT < $COVERAGE_THRESHOLD" | bc -l) )); then
    error "Coverage ${COVERAGE_PERCENT}% is below threshold ${COVERAGE_THRESHOLD}%"
fi

# Generate test summary
cat > "$ARTIFACTS_DIR/test-summary.txt" <<EOF
BorgOS Test Report
==================
Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Project: $PROJECT_ROOT

Test Coverage: ${COVERAGE_PERCENT}%
Coverage Threshold: ${COVERAGE_THRESHOLD}%

Artifacts Generated:
- coverage.xml
- coverage-html/
- test-results.xml
- test-summary.txt

Status: $([ ${TEST_FAILED:-0} -eq 0 ] && echo "PASSED" || echo "FAILED")
EOF

if [ ${TEST_FAILED:-0} -ne 0 ]; then
    error "Tests failed. See artifacts in $ARTIFACTS_DIR"
else
    log "All tests passed with ${COVERAGE_PERCENT}% coverage!"
fi