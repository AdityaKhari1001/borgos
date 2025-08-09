#!/bin/bash
# ============================================================================
#  BorgOS - Download LLM Models for Offline Installation
#  Run this on a machine with internet to prepare offline package
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
echo "║        BorgOS - Pobieranie Modeli AI dla Offline             ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Check if ollama is installed
if ! command -v ollama &>/dev/null; then
    log "Installing Ollama first..."
    curl -fsSL https://ollama.com/install.sh | sh
fi

# Start ollama service
log "Starting Ollama service..."
ollama serve &
OLLAMA_PID=$!
sleep 5

# Create models directory
MODELS_DIR="borgos_offline_models"
mkdir -p "$MODELS_DIR"

# Download models
log "Downloading Mistral 7B (4.1GB) - this will take 10-15 minutes..."
ollama pull mistral:7b-instruct-q4_K_M

log "Downloading Llama 3.2 3B (2GB) - this will take 5-10 minutes..."
ollama pull llama3.2:3b-instruct-q4_K_M

# Export models to files
log "Exporting models to files..."
cd "$MODELS_DIR"

# Find ollama models location
OLLAMA_MODELS_PATH="$HOME/.ollama/models"
if [ -d "$OLLAMA_MODELS_PATH" ]; then
    log "Copying model files from $OLLAMA_MODELS_PATH..."
    cp -r "$OLLAMA_MODELS_PATH" ./ollama_models
    
    # Create tar archive
    log "Creating offline models package..."
    tar -czf ../borgos_models_offline.tar.gz ollama_models/
    
    cd ..
    ls -lh borgos_models_offline.tar.gz
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              ✅ MODELS DOWNLOADED SUCCESSFULLY!              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "📦 Package created: borgos_models_offline.tar.gz"
    echo ""
    echo "📝 To install on offline system:"
    echo "1. Copy borgos_models_offline.tar.gz to target system"
    echo "2. On target system run:"
    echo "   tar -xzf borgos_models_offline.tar.gz"
    echo "   cp -r ollama_models/* ~/.ollama/models/"
    echo ""
    echo "Models included:"
    echo "• Mistral 7B (4.1GB) - main AI model"
    echo "• Llama 3.2 3B (2GB) - backup model"
else
    error "Could not find Ollama models directory"
fi

# Stop ollama
kill $OLLAMA_PID 2>/dev/null || true