#!/bin/bash
# Quick validation before full ISO build

set -euo pipefail

echo "========================================="
echo " BorgOS Build Environment Validator"
echo "========================================="

# Check Docker
echo -n "Checking Docker... "
if docker --version &>/dev/null; then
    echo "✓ $(docker --version)"
else
    echo "✗ Not installed"
    exit 1
fi

# Check Docker daemon
echo -n "Checking Docker daemon... "
if docker ps &>/dev/null; then
    echo "✓ Running"
else
    echo "✗ Not running"
    exit 1
fi

# Check disk space
echo -n "Checking disk space... "
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    SPACE=$(df -g . | awk 'NR==2 {print $4}')
else
    # Linux
    SPACE=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
fi
if [ "$SPACE" -ge 20 ]; then
    echo "✓ ${SPACE}GB available"
else
    echo "⚠ Only ${SPACE}GB available (20GB recommended)"
fi

# Check required files
echo "Checking required files..."
FILES=(
    "build-offline-iso.sh"
    "build-and-test-iso.sh"
    "test-suite.sh"
    "test-iso-vm.py"
    "docker-compose-build.yml"
)

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $file"
    else
        echo "  ✗ Missing: $file"
    fi
done

# Check for problematic sources
echo -n "Checking for cdrom sources... "
if grep -r "deb cdrom" --include="*.sh" . 2>/dev/null | grep -v test >/dev/null 2>&1; then
    echo "⚠ Found some references (will be handled)"
else
    echo "✓ Clean"
fi

echo ""
echo "========================================="
echo " Environment ready for build!"
echo "========================================="
echo ""
echo "To build the ISO, run:"
echo "  ./build-and-test-iso.sh"
echo ""
echo "For quick build without tests:"
echo "  ./build-and-test-iso.sh --skip-tests"
echo ""