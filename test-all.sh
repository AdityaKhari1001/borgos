#!/bin/bash
# BorgOS Complete Test Script

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[TEST]${NC} $1"; }
error() { echo -e "${RED}[FAIL]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }

echo -e "${BLUE}"
cat << 'EOF'
╔════════════════════════════════════════╗
║      🧪 BorgOS Test Suite              ║
║         Complete System Test           ║
╚════════════════════════════════════════╝
EOF
echo -e "${NC}"

ERRORS=0
WARNINGS=0
PASSED=0

# Test 1: Check if scripts are executable
log "Testing script permissions..."
for script in install.sh fix-borgos.sh scripts/fix-ollama.sh scripts/fix-nginx.sh; do
    if [ -x "$script" ]; then
        success "$script is executable"
        ((PASSED++))
    else
        error "$script is not executable"
        ((ERRORS++))
    fi
done

# Test 2: Syntax check all scripts
log "Testing script syntax..."
for script in *.sh scripts/*.sh; do
    if [ -f "$script" ]; then
        if bash -n "$script" 2>/dev/null; then
            success "$(basename $script) syntax OK"
            ((PASSED++))
        else
            error "$(basename $script) has syntax errors"
            ((ERRORS++))
        fi
    fi
done

# Test 3: Check Docker
log "Testing Docker..."
if command -v docker &> /dev/null; then
    success "Docker is installed"
    ((PASSED++))
    
    if docker ps &> /dev/null; then
        success "Docker daemon is running"
        ((PASSED++))
    else
        error "Docker daemon is not running"
        ((ERRORS++))
    fi
else
    error "Docker is not installed"
    ((ERRORS++))
fi

# Test 4: Check Docker Compose
log "Testing Docker Compose..."
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    success "Docker Compose v2 is available"
    ((PASSED++))
elif docker-compose --version &> /dev/null; then
    warning "Docker Compose v1 is available (v2 recommended)"
    ((WARNINGS++))
else
    error "Docker Compose is not available"
    ((ERRORS++))
fi

# Test 5: Check required files
log "Testing required files..."
REQUIRED_FILES=(
    "docker-compose.yml OR docker-compose-simple.yml OR docker-compose-full.yml"
    ".env.example"
    "README.md"
    "install.sh"
)

for file_pattern in "${REQUIRED_FILES[@]}"; do
    if [[ "$file_pattern" == *"OR"* ]]; then
        found=false
        for file in ${file_pattern//OR/}; do
            file=$(echo $file | xargs)
            if [ -f "$file" ]; then
                success "$file exists"
                ((PASSED++))
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            error "None of: $file_pattern found"
            ((ERRORS++))
        fi
    else
        if [ -f "$file_pattern" ]; then
            success "$file_pattern exists"
            ((PASSED++))
        else
            error "$file_pattern not found"
            ((ERRORS++))
        fi
    fi
done

# Test 6: Check directories
log "Testing directory structure..."
REQUIRED_DIRS=(
    "webui"
    "scripts"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        success "$dir directory exists"
        ((PASSED++))
    else
        warning "$dir directory not found (will be created during install)"
        ((WARNINGS++))
    fi
done

# Test 7: Check ports availability
log "Testing port availability..."
PORTS=(11434 8081 80 5432 6379 9000)

for port in "${PORTS[@]}"; do
    if ! lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        success "Port $port is available"
        ((PASSED++))
    else
        warning "Port $port is already in use"
        ((WARNINGS++))
    fi
done

# Test 8: Check Ollama
log "Testing Ollama..."
if command -v ollama &> /dev/null; then
    success "Ollama CLI is installed"
    ((PASSED++))
    
    if curl -s http://localhost:11434/api/tags &> /dev/null; then
        success "Ollama service is running"
        ((PASSED++))
    else
        warning "Ollama service is not running (will be started during install)"
        ((WARNINGS++))
    fi
else
    warning "Ollama not installed (will be installed)"
    ((WARNINGS++))
fi

# Test 9: Check Node.js
log "Testing Node.js..."
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    success "Node.js is installed: $NODE_VERSION"
    ((PASSED++))
else
    warning "Node.js not installed (optional for OpenRouter)"
    ((WARNINGS++))
fi

# Test 10: Check Git
log "Testing Git..."
if command -v git &> /dev/null; then
    success "Git is installed"
    ((PASSED++))
    
    if git remote -v 2>/dev/null | grep -q "github.com"; then
        success "Git repository is configured"
        ((PASSED++))
    else
        warning "Not a git repository or no remote"
        ((WARNINGS++))
    fi
else
    error "Git is not installed"
    ((ERRORS++))
fi

# Test 11: Check disk space
log "Testing disk space..."
AVAILABLE=$(df -h . | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "${AVAILABLE%%.*}" -gt 5 ] 2>/dev/null; then
    success "Sufficient disk space: ${AVAILABLE}GB available"
    ((PASSED++))
else
    warning "Low disk space: ${AVAILABLE} available (minimum 5GB recommended)"
    ((WARNINGS++))
fi

# Test 12: Check network connectivity
log "Testing network connectivity..."
if ping -c 1 github.com &> /dev/null; then
    success "Network connectivity OK"
    ((PASSED++))
else
    error "Cannot reach github.com"
    ((ERRORS++))
fi

# Test 13: Test docker-compose files
log "Testing docker-compose configurations..."
for compose_file in docker-compose*.yml; do
    if [ -f "$compose_file" ]; then
        if docker compose -f "$compose_file" config &> /dev/null; then
            success "$compose_file is valid"
            ((PASSED++))
        else
            error "$compose_file has errors"
            ((ERRORS++))
        fi
    fi
done

# Test 14: Check webui files
log "Testing Web UI files..."
if [ -f "webui/index.html" ]; then
    success "Main dashboard exists"
    ((PASSED++))
else
    warning "Main dashboard not found"
    ((WARNINGS++))
fi

if [ -f "webui/ai-panel.html" ]; then
    success "AI panel exists"
    ((PASSED++))
else
    warning "AI panel not found"
    ((WARNINGS++))
fi

# Summary
echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}Test Summary:${NC}"
echo -e "${GREEN}✅ Passed: $PASSED${NC}"
echo -e "${YELLOW}⚠️  Warnings: $WARNINGS${NC}"
echo -e "${RED}❌ Errors: $ERRORS${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✨ All critical tests passed! System ready for installation.${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Run: ./install.sh"
    echo "2. Or fix issues: ./fix-borgos.sh"
    exit 0
else
    echo -e "${RED}⚠️  Critical errors found. Please fix before installation.${NC}"
    echo ""
    echo "To fix issues, run:"
    echo "  ./fix-borgos.sh"
    exit 1
fi