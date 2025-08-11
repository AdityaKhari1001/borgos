#!/bin/bash
# Przygotowanie plików do przeniesienia na PC

echo "================================================"
echo " Przygotowanie BorgOS do budowy na PC"
echo "================================================"

# Utwórz archiwum z wszystkimi potrzebnymi plikami
echo "[1] Tworzenie archiwum z kodem źródłowym..."

tar -czf borgos-pc-build.tar.gz \
    --exclude='*.iso' \
    --exclude='iso_output' \
    --exclude='build-logs-*' \
    --exclude='.git' \
    --exclude='node_modules' \
    --exclude='__pycache__' \
    --exclude='*.log' \
    core/ \
    webui/ \
    installer/ \
    mcp_servers/ \
    database/ \
    docs/ \
    branding/ \
    config/ \
    docker-compose*.yml \
    requirements.txt \
    build-offline-iso.sh \
    build-full-x86-iso.sh \
    test-suite.sh \
    test-iso-vm.py \
    Dockerfile.isobuilder \
    Dockerfile.vm-test \
    BUILD_ISO_README.md

echo "[2] Archiwum utworzone: borgos-pc-build.tar.gz"
echo "    Rozmiar: $(du -h borgos-pc-build.tar.gz | cut -f1)"

echo ""
echo "================================================"
echo " INSTRUKCJE DLA PC:"
echo "================================================"
echo ""
echo "1. PRZENIEŚ ARCHIWUM NA PC:"
echo "   - Przez USB"
echo "   - Przez sieć: scp borgos-pc-build.tar.gz user@pc-ip:/home/user/"
echo "   - Przez cloud (Google Drive, Dropbox, etc.)"
echo ""
echo "2. NA PC (Linux):"
echo "   tar -xzf borgos-pc-build.tar.gz"
echo "   cd borgos-build"
echo "   ./setup-pc-build.sh"
echo ""
echo "3. NA PC (Windows z WSL2):"
echo "   wsl"
echo "   tar -xzf borgos-pc-build.tar.gz"
echo "   cd borgos-build"
echo "   ./setup-pc-build.sh"
echo "================================================"