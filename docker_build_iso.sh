#!/bin/bash
# ============================================================================
#  BorgOS ISO Builder - Runs inside Docker container
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
echo "║          BorgOS ISO Builder (Docker Container)               ║"
echo "╚══════════════════════════════════════════════════════════════╝"

cd /build

# Configure live-build for Debian 12
log "Configuring live-build..."
lb config \
    --architectures amd64 \
    --distribution bookworm \
    --debian-installer live \
    --debian-installer-gui false \
    --archive-areas "main contrib non-free non-free-firmware" \
    --iso-application "BorgOS" \
    --iso-volume "BorgOS" \
    --bootappend-live "boot=live components quiet splash" \
    --memtest none \
    --mirror-bootstrap http://deb.debian.org/debian/ \
    --mirror-binary http://deb.debian.org/debian/ \
    --mirror-binary-security http://security.debian.org/debian-security

# Add required packages
log "Adding packages to ISO..."
cat > config/package-lists/borgos.list.chroot <<EOF
# Core system
openssh-server
curl
wget
git
htop
vim
net-tools
sudo
build-essential

# Python and dependencies
python3
python3-pip
python3-venv
python3-dev

# System utilities
systemd
ufw
rsync
screen
tmux

# Hardware support
firmware-linux-nonfree
firmware-misc-nonfree
EOF

# Create hooks for BorgOS installation
log "Creating installation hooks..."
mkdir -p config/hooks/live
cat > config/hooks/live/9999-install-borgos.hook.chroot <<'HOOK'
#!/bin/bash
# Install BorgOS during ISO build

echo "Installing BorgOS components..."

# Create BorgOS directory
mkdir -p /opt/borgos

# Create installer that will run on first boot
cat > /opt/borgos/first_boot_install.sh <<'INSTALLER'
#!/bin/bash
# BorgOS First Boot Installer

if [ -f /opt/borgos/.installed ]; then
    echo "BorgOS already installed"
    exit 0
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              BorgOS First Boot Installation                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Start Ollama service
systemctl enable ollama
systemctl start ollama

# Pull models
ollama pull mistral:7b-instruct-q4_K_M
ollama pull llama3.2:3b-instruct-q4_K_M

# Mark as installed
touch /opt/borgos/.installed

echo "BorgOS installation complete!"
INSTALLER

chmod +x /opt/borgos/first_boot_install.sh

# Create systemd service for first boot
cat > /etc/systemd/system/borgos-firstboot.service <<EOF
[Unit]
Description=BorgOS First Boot Setup
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/opt/borgos/.installed

[Service]
Type=oneshot
ExecStart=/opt/borgos/first_boot_install.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable borgos-firstboot.service
HOOK

chmod +x config/hooks/live/9999-install-borgos.hook.chroot

# Copy BorgOS files to includes
log "Adding BorgOS files to ISO..."
mkdir -p config/includes.chroot/opt/borgos
cp -r /borgos-source/installer config/includes.chroot/opt/borgos/
cp -r /borgos-source/webui config/includes.chroot/opt/borgos/
cp -r /borgos-source/mcp_servers config/includes.chroot/opt/borgos/
cp -r /borgos-source/plugins config/includes.chroot/opt/borgos/
cp /borgos-source/*.py config/includes.chroot/opt/borgos/ 2>/dev/null || true
cp /borgos-source/requirements.txt config/includes.chroot/opt/borgos/ 2>/dev/null || true

# Create auto-installer script
cat > config/includes.chroot/opt/borgos/install.sh <<'AUTOINSTALL'
#!/bin/bash
# BorgOS Manual Installation Script

echo "Installing BorgOS..."
cd /opt/borgos
bash installer/install_all.sh
echo "Installation complete!"
AUTOINSTALL
chmod +x config/includes.chroot/opt/borgos/install.sh

# Customize boot menu
log "Customizing boot menu..."
mkdir -p config/bootloaders/isolinux
cat > config/bootloaders/isolinux/install.cfg <<EOF
label borgos
    menu label ^Install BorgOS (Automated)
    linux /live/vmlinuz
    initrd /live/initrd.img
    append boot=live components quiet splash persistence
    
label borgos-expert
    menu label Install BorgOS (Expert Mode)
    linux /live/vmlinuz
    initrd /live/initrd.img
    append boot=live components
EOF

# Download models for offline inclusion (optional - makes ISO much larger)
if [ "${INCLUDE_MODELS}" = "yes" ]; then
    log "Downloading AI models for offline inclusion..."
    mkdir -p config/includes.chroot/opt/borgos/models
    
    # Download Mistral 7B
    wget -O config/includes.chroot/opt/borgos/models/mistral-7b.gguf \
        "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q4_K_M.gguf" || \
        warn "Could not download Mistral model"
    
    # Download Llama 3.2
    wget -O config/includes.chroot/opt/borgos/models/llama3.2-3b.gguf \
        "https://huggingface.co/QuantFactory/Meta-Llama-3.2-3B-Instruct-GGUF/resolve/main/Meta-Llama-3.2-3B-Instruct.Q4_K_M.gguf" || \
        warn "Could not download Llama model"
fi

# Build the ISO
log "Building ISO (this will take 20-30 minutes)..."
lb build

# Find the generated ISO
ISO_FILE=$(find . -name "*.iso" -type f | head -1)

if [ -f "$ISO_FILE" ]; then
    # Copy to output directory
    cp "$ISO_FILE" /output/BorgOS-Live-amd64.iso
    
    ISO_SIZE=$(stat -c%s /output/BorgOS-Live-amd64.iso)
    ISO_SIZE_MB=$((ISO_SIZE / 1024 / 1024))
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║               ✅ ISO BUILD SUCCESSFUL!                       ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "📀 ISO Created: BorgOS-Live-amd64.iso (${ISO_SIZE_MB}MB)"
    echo ""
    echo "Features:"
    echo "  • Live bootable Debian 12 system"
    echo "  • BorgOS pre-installed"
    echo "  • Auto-installer on first boot"
    echo "  • SSH server enabled"
    echo ""
    if [ "${INCLUDE_MODELS}" = "yes" ]; then
        echo "  • AI models included (offline ready)"
    else
        echo "  • AI models will download on first boot"
    fi
else
    error "ISO build failed - no ISO file found"
fi