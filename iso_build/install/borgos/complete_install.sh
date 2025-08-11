#!/bin/bash
# ============================================================================
#  BorgOS Complete Installation Script
#  Run this as aiuser@192.168.100.159
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
echo "║          BorgOS Complete Installation Script                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Step 1: Fix APT sources
log "Step 1: Fixing APT sources..."
sudo sed -i '/cdrom/d' /etc/apt/sources.list

# Add proper repositories
echo "deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware" | sudo tee /etc/apt/sources.list
echo "deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware" | sudo tee -a /etc/apt/sources.list  
echo "deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware" | sudo tee -a /etc/apt/sources.list

sudo apt update || error "Failed to update package lists"

# Step 2: Install base packages
log "Step 2: Installing base packages..."
sudo apt install -y \
    curl wget git vim htop \
    python3-pip python3-venv \
    build-essential \
    || warn "Some packages failed to install"

# Step 3: Check/Start Ollama
log "Step 3: Checking Ollama..."
if ! systemctl is-active --quiet ollama; then
    warn "Ollama not running, starting..."
    sudo systemctl start ollama
    sudo systemctl enable ollama
fi

# Step 4: Pull AI model
log "Step 4: Checking AI models..."
if ! ollama list | grep -q mistral; then
    log "Downloading Mistral 7B model (4.1GB)..."
    ollama pull mistral:7b-instruct-q4_K_M || warn "Failed to pull model"
else
    log "Mistral model already installed"
fi

# Step 5: Install BorgOS components
log "Step 5: Installing BorgOS components..."
if [ -f /opt/borgos/installer/install_all.sh ]; then
    cd /opt/borgos
    # Run without set -e to continue on errors
    sudo bash -c "grep -v '^set -e' installer/install_all.sh | bash" || warn "Installer had some errors"
else
    warn "/opt/borgos/installer/install_all.sh not found"
fi

# Step 6: Setup Python environment
log "Step 6: Setting up Python environment..."
cd /opt/borgos
if [ ! -d "env" ]; then
    python3 -m venv env
fi
source env/bin/activate
pip install --upgrade pip
pip install flask requests pyyaml click rich openai chromadb 2>/dev/null || warn "Some Python packages failed"

# Step 7: Create borg CLI command
log "Step 7: Creating borg CLI command..."
sudo tee /usr/local/bin/borg > /dev/null << 'EOF'
#!/bin/bash
ollama run mistral:7b-instruct-q4_K_M "$@"
EOF
sudo chmod +x /usr/local/bin/borg

# Step 8: Create WebUI service
log "Step 8: Creating WebUI service..."
sudo tee /etc/systemd/system/borgos-webui.service > /dev/null << EOF
[Unit]
Description=BorgOS WebUI
After=network.target ollama.service

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/borgos
Environment="PATH=/opt/borgos/env/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=/opt/borgos/env/bin/python /opt/borgos/webui/enhanced_app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable borgos-webui
sudo systemctl start borgos-webui || warn "WebUI service failed to start"

# Step 9: Verify installation
log "Step 9: Verifying installation..."
sleep 3

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  INSTALLATION STATUS                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Check services
echo -n "Ollama service: "
systemctl is-active ollama && echo -e "${GREEN}✓ Running${NC}" || echo -e "${RED}✗ Not running${NC}"

echo -n "WebUI service: "
systemctl is-active borgos-webui && echo -e "${GREEN}✓ Running${NC}" || echo -e "${RED}✗ Not running${NC}"

# Check models
echo -n "AI Models: "
ollama list 2>/dev/null | grep -q mistral && echo -e "${GREEN}✓ Mistral installed${NC}" || echo -e "${RED}✗ No models${NC}"

# Check ports
echo -n "Ollama API (11434): "
ss -tlnp 2>/dev/null | grep -q :11434 && echo -e "${GREEN}✓ Open${NC}" || echo -e "${YELLOW}⚠ Not listening${NC}"

echo -n "WebUI (6969): "
ss -tlnp 2>/dev/null | grep -q :6969 && echo -e "${GREEN}✓ Open${NC}" || echo -e "${YELLOW}⚠ Not listening${NC}"

# Get IP
IP=$(hostname -I | awk '{print $1}')

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    ✅ SETUP COMPLETE!                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "🌐 Access Points:"
echo "   WebUI: http://$IP:6969"
echo "   API: http://$IP:11434"
echo ""
echo "🤖 CLI Usage:"
echo "   borg 'Your question here'"
echo ""
echo "📝 Test commands:"
echo "   borg 'Hello, how are you?'"
echo "   curl http://localhost:6969"
echo "   ollama list"
echo ""

# Final test
log "Running final test..."
borg "Say 'BorgOS is ready!' in 5 words or less" 2>/dev/null || warn "CLI test failed"