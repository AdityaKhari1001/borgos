#!/bin/bash
# ============================================================================
#  BorgOS OFFLINE Installer - Uses pre-downloaded models
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
error() { echo -e "${RED}[!]${NC} $1" >&2; exit 1; }
warn() { echo -e "${YELLOW}[*]${NC} $1"; }

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           BorgOS OFFLINE Installation Starting               ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Check for offline models package
if [ ! -f "borgos_models_offline.tar.gz" ]; then
    warn "No offline models found. Models will be downloaded during install."
    warn "To prepare offline package, run download_models_offline.sh on a machine with internet"
else
    log "Found offline models package!"
fi

# Run main installer
bash installer/install_all.sh

# If offline models exist, install them
if [ -f "borgos_models_offline.tar.gz" ]; then
    log "Installing offline models..."
    tar -xzf borgos_models_offline.tar.gz
    
    # Create ollama models directory
    mkdir -p ~/.ollama
    
    # Copy models
    cp -r ollama_models/* ~/.ollama/models/ 2>/dev/null || {
        sudo mkdir -p /usr/share/ollama/.ollama
        sudo cp -r ollama_models/* /usr/share/ollama/.ollama/models/
    }
    
    log "Offline models installed!"
    
    # Restart ollama to recognize models
    sudo systemctl restart ollama
    
    # Verify models
    sleep 5
    ollama list
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              ✅ BorgOS INSTALLED SUCCESSFULLY!               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "🎯 System ready with:"
echo "   • Mistral 7B - main AI model"
echo "   • Llama 3.2 - backup model"
echo "   • WebUI: http://localhost:6969"
echo "   • CLI: borg 'your question'"