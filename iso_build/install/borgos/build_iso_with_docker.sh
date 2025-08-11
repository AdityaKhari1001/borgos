#!/bin/bash
# ============================================================================
#  BorgOS ISO Builder - Main script to run on macOS
#  Builds complete bootable ISO using Docker
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
error() { echo -e "${RED}[!]${NC} $1" >&2; exit 1; }
warn() { echo -e "${YELLOW}[*]${NC} $1"; }
info() { echo -e "${BLUE}[i]${NC} $1"; }

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         BorgOS ISO Builder dla macOS (via Docker)            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check Docker
if ! command -v docker &>/dev/null; then
    error "Docker not installed! Install from https://docker.com"
fi

# Check if Docker is running
if ! docker info &>/dev/null; then
    error "Docker is not running! Start Docker Desktop"
fi

# Ask about including models
echo "Include AI models in ISO? (makes ISO ~7GB larger)"
echo "1) No - download models on first boot (smaller ISO, ~1GB)"
echo "2) Yes - include models offline (larger ISO, ~7GB)"
read -p "Choose [1/2]: " CHOICE

if [ "$CHOICE" = "2" ]; then
    export INCLUDE_MODELS="yes"
    info "Will include AI models (ISO will be ~7-8GB)"
else
    export INCLUDE_MODELS="no"
    info "Models will download on first boot (ISO will be ~1-2GB)"
fi

# Build Docker image
log "Building Docker image..."
docker build -f Dockerfile.iso-builder -t borgos-iso-builder .

# Create output directory
mkdir -p iso_output

# Make build script executable
chmod +x docker_build_iso.sh

# Run ISO builder in Docker
log "Starting ISO build in Docker (this will take 30-45 minutes)..."
docker run --rm \
    --privileged \
    -v "$(pwd):/borgos-source:ro" \
    -v "$(pwd)/iso_output:/output" \
    -e INCLUDE_MODELS="$INCLUDE_MODELS" \
    borgos-iso-builder

# Check output
if [ -f "iso_output/BorgOS-Live-amd64.iso" ]; then
    ISO_SIZE=$(ls -lh iso_output/BorgOS-Live-amd64.iso | awk '{print $5}')
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              ✅ ISO CREATED SUCCESSFULLY!                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "📀 ISO: iso_output/BorgOS-Live-amd64.iso ($ISO_SIZE)"
    echo ""
    echo "🔥 To create bootable USB:"
    echo ""
    echo "   Option 1 - dd command:"
    echo "   ${YELLOW}sudo dd if=iso_output/BorgOS-Live-amd64.iso of=/dev/rdisk4 bs=1m${NC}"
    echo ""
    echo "   Option 2 - Balena Etcher (GUI):"
    echo "   Download from https://etcher.balena.io/"
    echo ""
    echo "📝 Features:"
    echo "   • Live bootable system"
    echo "   • BorgOS pre-installed"
    echo "   • Auto-setup on first boot"
    echo "   • Works completely offline"
    if [ "$INCLUDE_MODELS" = "yes" ]; then
        echo "   • AI models included (Mistral 7B + Llama 3.2)"
    else
        echo "   • AI models download on first boot"
    fi
    echo ""
    echo "💾 Usage:"
    echo "   1. Boot from USB"
    echo "   2. Select 'Install BorgOS'"
    echo "   3. System auto-configures"
    echo "   4. Access via http://IP:6969"
else
    error "ISO build failed - check Docker logs above"
fi