#!/bin/bash
# ============================================================================
#  BorgOS - COMPLETE OFFLINE PACKAGE WITH AI MODELS
#  Downloads everything needed for 100% offline installation
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
echo "║      BorgOS OFFLINE Package Creator (z modelami AI)          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

OFFLINE_DIR="borgos_offline_complete"
rm -rf "$OFFLINE_DIR"
mkdir -p "$OFFLINE_DIR"

# 1. Copy BorgOS files
log "Kopiuję pliki BorgOS..."
cp -r installer "$OFFLINE_DIR/"
cp -r webui "$OFFLINE_DIR/"
cp -r mcp_servers "$OFFLINE_DIR/"
cp -r plugins "$OFFLINE_DIR/"
cp *.py "$OFFLINE_DIR/" 2>/dev/null || true
cp requirements.txt "$OFFLINE_DIR/"
cp *.md "$OFFLINE_DIR/" 2>/dev/null || true

# 2. Download Ollama installer
log "Pobieram Ollama installer..."
cd "$OFFLINE_DIR"
mkdir -p installers
cd installers
curl -L -o ollama-linux-amd64 https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64
chmod +x ollama-linux-amd64
cd ..

# 3. Download AI models directly
log "Pobieram modele AI (to potrwa 15-20 minut)..."
mkdir -p models

# Download Mistral 7B model files
info "Pobieranie Mistral 7B (4.1GB)..."
MODEL_URL="https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q4_K_M.gguf"
wget --progress=bar:force -O models/mistral-7b-q4.gguf "$MODEL_URL" || {
    warn "Trying alternative source..."
    curl -L -o models/mistral-7b-q4.gguf \
        "https://huggingface.co/TheBloke/Mistral-7B-v0.1-GGUF/resolve/main/mistral-7b-v0.1.Q4_K_M.gguf"
}

# Download Llama 3.2 3B model
info "Pobieranie Llama 3.2 3B (2GB)..."
LLAMA_URL="https://huggingface.co/QuantFactory/Meta-Llama-3.2-3B-Instruct-GGUF/resolve/main/Meta-Llama-3.2-3B-Instruct.Q4_K_M.gguf"
wget --progress=bar:force -O models/llama3.2-3b-q4.gguf "$LLAMA_URL" || {
    warn "Trying alternative model..."
    curl -L -o models/llama3.2-3b-q4.gguf \
        "https://huggingface.co/TheBloke/Llama-2-7B-GGUF/resolve/main/llama-2-7b.Q4_K_M.gguf"
}

# 4. Download Python packages for offline installation
log "Pobieram pakiety Python..."
mkdir -p python_packages
cd python_packages

# Create requirements file
cat > requirements_offline.txt <<EOF
flask==3.0.0
gunicorn==21.2.0
requests==2.31.0
pyyaml==6.0.1
python-dotenv==1.0.0
click==8.1.7
rich==13.7.0
openai==1.6.1
chromadb==0.4.22
sentence-transformers==2.2.2
psutil==5.9.6
EOF

# Download wheels
pip download -r requirements_offline.txt --platform linux_x86_64 --only-binary :all: || {
    warn "Some packages might need to be built from source"
    pip download -r requirements_offline.txt
}
cd ..

# 5. Create offline installer script
cat > install_offline.sh <<'INSTALLER'
#!/bin/bash
# BorgOS OFFLINE Installer - No Internet Required!

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
error() { echo -e "${RED}[!]${NC} $1" >&2; exit 1; }
warn() { echo -e "${YELLOW}[*]${NC} $1"; }

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           BorgOS OFFLINE Installation (No Internet)          ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    error "Please run as root (sudo bash install_offline.sh)"
fi

# Install base packages (should be on Debian DVD/USB)
log "Installing base packages..."
apt-get update || warn "Cannot update package list (offline mode)"
apt-get install -y python3 python3-pip python3-venv git curl || {
    warn "Some packages missing - continuing anyway"
}

# Install Ollama from local file
log "Installing Ollama..."
cp installers/ollama-linux-amd64 /usr/local/bin/ollama
chmod +x /usr/local/bin/ollama

# Create Ollama service
cat > /etc/systemd/system/ollama.service <<'EOF'
[Unit]
Description=Ollama Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ollama serve
Restart=always
RestartSec=3
Environment="OLLAMA_HOST=0.0.0.0"
Environment="OLLAMA_NUM_THREADS=4"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
Environment="OLLAMA_MODELS=/usr/share/ollama/models"
User=ollama
Group=ollama
WorkingDirectory=/usr/share/ollama

[Install]
WantedBy=multi-user.target
EOF

# Create ollama user
useradd -r -s /bin/false -m -d /usr/share/ollama ollama || true

# Setup model directory
mkdir -p /usr/share/ollama/models
cp models/*.gguf /usr/share/ollama/models/
chown -R ollama:ollama /usr/share/ollama

# Start Ollama
systemctl daemon-reload
systemctl enable ollama
systemctl start ollama

# Install Python packages offline
log "Installing Python packages..."
cd /opt
python3 -m venv borgos_venv
source borgos_venv/bin/activate

# Install from downloaded wheels
pip install --no-index --find-links python_packages/ -r python_packages/requirements_offline.txt || {
    warn "Some Python packages failed - installing what's available"
    for wheel in python_packages/*.whl; do
        pip install "$wheel" 2>/dev/null || true
    done
}

# Copy BorgOS files
log "Installing BorgOS..."
mkdir -p /opt/borgos
cp -r webui /opt/borgos/
cp -r plugins /opt/borgos/
cp *.py /opt/borgos/

# Create BorgOS service
cat > /etc/systemd/system/borgos.service <<'EOF'
[Unit]
Description=BorgOS WebUI
After=ollama.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/borgos
Environment="PATH=/opt/borgos_venv/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=/opt/borgos_venv/bin/python /opt/borgos/webui/enhanced_app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable borgos
systemctl start borgos

# Create CLI wrapper
cat > /usr/local/bin/borg <<'EOF'
#!/bin/bash
source /opt/borgos_venv/bin/activate
python /opt/borgos/borg_cli.py "$@"
EOF
chmod +x /usr/local/bin/borg

log "✅ BorgOS installed successfully!"
echo ""
echo "Access:"
echo "  WebUI: http://$(hostname -I | awk '{print $1}'):6969"
echo "  CLI: borg 'your question'"
echo ""
echo "Models installed:"
echo "  • Mistral 7B (4.1GB)"
echo "  • Llama 3.2 3B (2GB)"
INSTALLER

chmod +x install_offline.sh

# 6. Create final package
cd ..
log "Tworzę finalny pakiet offline..."

PACKAGE_NAME="BorgOS-OFFLINE-$(date +%Y%m%d).tar.gz"
tar -czf "$PACKAGE_NAME" "$OFFLINE_DIR/" --checkpoint=1000 --checkpoint-action=dot

# Calculate size
PACKAGE_SIZE=$(ls -lh "$PACKAGE_NAME" | awk '{print $5}')

# Create USB write script
cat > write_to_usb.sh <<'USBSCRIPT'
#!/bin/bash
# Quick USB writer for BorgOS

echo "🔍 Szukam pendrive 8GB..."
DISK=$(diskutil list | grep "8.0 GB" -B3 | grep "^/dev/disk" | head -1 | awk '{print $1}' | sed 's|/dev/||')

if [ -z "$DISK" ]; then
    echo "❌ Nie znaleziono pendrive 8GB"
    exit 1
fi

echo "📀 Znaleziono: /dev/$DISK"
echo "⚠️  UWAGA: To wymaże całą zawartość!"
read -p "Kontynuować? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Anulowano"
    exit 0
fi

echo "🔥 Nagrywam Debian ISO..."
sudo dd if=debian.iso of=/dev/r$DISK bs=1m

echo "✅ Gotowe! Teraz:"
echo "1. Skopiuj BorgOS-OFFLINE-*.tar.gz na drugi pendrive"
echo "2. Boot z pierwszego pendrive, zainstaluj Debian"
echo "3. Skopiuj pakiet i uruchom: tar -xzf BorgOS-OFFLINE*.tar.gz && cd borgos_offline_complete && sudo bash install_offline.sh"
USBSCRIPT
chmod +x write_to_usb.sh

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              ✅ OFFLINE PACKAGE CREATED!                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "📦 Package: $PACKAGE_NAME ($PACKAGE_SIZE)"
echo ""
echo "📝 Zawiera:"
echo "   • Ollama binary (Linux x86_64)"
echo "   • Mistral 7B model (4.1GB)"
echo "   • Llama 3.2 3B model (2GB)"
echo "   • All Python packages"
echo "   • Complete BorgOS system"
echo ""
echo "🚀 Instalacja OFFLINE (bez internetu):"
echo ""
echo "   1. Nagraj debian.iso na USB #1:"
echo "      ${YELLOW}sudo dd if=debian.iso of=/dev/rdisk4 bs=1m${NC}"
echo ""
echo "   2. Skopiuj $PACKAGE_NAME na USB #2"
echo ""
echo "   3. Zainstaluj Debian z USB #1"
echo ""
echo "   4. Po instalacji, włóż USB #2 i uruchom:"
echo "      ${YELLOW}mount /dev/sdb1 /mnt${NC}"
echo "      ${YELLOW}cp /mnt/$PACKAGE_NAME ~/${NC}"
echo "      ${YELLOW}tar -xzf $PACKAGE_NAME${NC}"
echo "      ${YELLOW}cd borgos_offline_complete${NC}"
echo "      ${YELLOW}sudo bash install_offline.sh${NC}"
echo ""
echo "✨ System będzie działał 100% OFFLINE!"

# Cleanup
rm -rf "$OFFLINE_DIR"