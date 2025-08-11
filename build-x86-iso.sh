#!/bin/bash

# BorgOS Hybrid ISO Builder - x86_64 Version
# Builds x86_64 ISO for standard PCs

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

# Configuration
VERSION="1.0"
TARGET_ARCH="amd64"
ISO_NAME="BorgOS-Hybrid-${VERSION}-x86_64.iso"
BUILD_DIR="$(pwd)/hybrid_build_x86"

# Show banner
echo -e "${CYAN}"
cat << 'EOF'
╔════════════════════════════════════════╗
║   BorgOS Hybrid ISO Builder (x86_64)   ║
║        For Standard PC/Laptops         ║
╚════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Create build directory
log "Creating build directory for x86_64..."
rm -rf ${BUILD_DIR}
mkdir -p ${BUILD_DIR}/{iso,scripts,output}

# Create x86_64 ISO build script
log "Creating x86_64 build script..."
cat > ${BUILD_DIR}/scripts/create-x86-iso.sh << 'SCRIPT'
#!/bin/bash

set -e

# Configuration for x86_64
VERSION="1.0"
ISO_NAME="BorgOS-Hybrid-${VERSION}-x86_64.iso"
WORK_DIR="/tmp/borgos_x86_iso"

echo "Building BorgOS Hybrid ISO for x86_64..."

# Create working directories
mkdir -p ${WORK_DIR}/{iso,rootfs,staging}
cd ${WORK_DIR}

# Download minimal Debian netboot for x86_64
echo "Downloading x86_64 netboot files..."
wget -q http://ftp.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/mini.iso -O base.iso

# Extract base ISO
echo "Extracting base ISO..."
7z x -o${WORK_DIR}/iso base.iso > /dev/null 2>&1 || \
    bsdtar -xf base.iso -C ${WORK_DIR}/iso

# Create BorgOS structure
echo "Creating BorgOS structure..."
mkdir -p ${WORK_DIR}/iso/borgos/{scripts,config,ollama}

# Create BorgOS installer with Ollama for x86_64
cat > ${WORK_DIR}/iso/borgos/scripts/install.sh << 'INSTALLER'
#!/bin/sh
# BorgOS Hybrid x86_64 Installer

echo "═══════════════════════════════════════════"
echo "    BorgOS Hybrid x86_64 Installation"
echo "═══════════════════════════════════════════"

# Detect CPU architecture
ARCH=$(uname -m)
echo "Architecture: $ARCH"

# Install base packages
echo "Installing base packages..."
apt-get update
apt-get install -y \
    openssh-server \
    docker.io \
    docker-compose \
    curl \
    wget \
    git \
    nano \
    vim \
    sudo \
    htop \
    net-tools \
    build-essential

# Create borgos user
echo "Creating borgos user..."
useradd -m -s /bin/bash -G sudo,docker borgos
echo "borgos:borgos" | chpasswd
echo "borgos ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Enable SSH
echo "Configuring SSH..."
systemctl enable ssh
systemctl start ssh
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Install Ollama for x86_64
echo "Installing Ollama..."
curl -fsSL https://ollama.ai/install.sh | sh

# Create Ollama service
cat > /etc/systemd/system/ollama.service << 'SERVICE'
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ollama serve
Restart=always
User=ollama
Group=ollama
Environment="OLLAMA_HOST=0.0.0.0"

[Install]
WantedBy=multi-user.target
SERVICE

# Start Ollama
systemctl daemon-reload
systemctl enable ollama
systemctl start ollama

# Pull Gemma 2B model
echo "Downloading Gemma 2B model (this may take a while)..."
sleep 5
ollama pull gemma:2b || echo "Model will be downloaded on first use"

# Configure Docker
systemctl enable docker
systemctl start docker

# Create welcome script
cat > /usr/local/bin/borgos-welcome << 'WELCOME'
#!/bin/bash
clear
echo "═══════════════════════════════════════════"
echo "    Welcome to BorgOS Hybrid x86_64!"
echo "═══════════════════════════════════════════"
echo ""
echo "System Info:"
echo "  CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
echo "  RAM: $(free -h | grep Mem | awk '{print $2}')"
echo "  IP:  $(ip -4 addr show | grep inet | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -1)"
echo ""
echo "Services:"
echo "  SSH:    $(systemctl is-active ssh)"
echo "  Docker: $(systemctl is-active docker)"
echo "  Ollama: $(systemctl is-active ollama)"
echo ""
echo "Default credentials: borgos/borgos"
echo ""
echo "Test Ollama: curl http://localhost:11434/api/generate -d '{"model":"gemma:2b","prompt":"Hello"}'"
echo "═══════════════════════════════════════════"
WELCOME
chmod +x /usr/local/bin/borgos-welcome

# Add to login
echo "/usr/local/bin/borgos-welcome" >> /home/borgos/.bashrc

echo ""
echo "Installation complete!"
echo "Default login: borgos/borgos"
echo "SSH enabled on all interfaces"
echo "Ollama API: http://localhost:11434"
INSTALLER
chmod +x ${WORK_DIR}/iso/borgos/scripts/install.sh

# Create preseed for automated x86_64 installation
cat > ${WORK_DIR}/iso/preseed.cfg << 'PRESEED'
# BorgOS x86_64 Automated Installation
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select us
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string borgos
d-i netcfg/get_domain string local

# Mirror
d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string

# Users
d-i passwd/root-password password borgos
d-i passwd/root-password-again password borgos
d-i passwd/user-fullname string BorgOS User
d-i passwd/username string borgos
d-i passwd/user-password password borgos
d-i passwd/user-password-again password borgos
d-i user-setup/allow-password-weak boolean true

# Partitioning
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman-lvm/confirm boolean true
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

# Package selection
tasksel tasksel/first multiselect standard, ssh-server
d-i pkgsel/include string openssh-server docker.io curl wget git nano sudo net-tools
d-i pkgsel/upgrade select full-upgrade
d-i pkgsel/update-policy select unattended-upgrades

# GRUB
d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean true

# Finish
d-i finish-install/reboot_in_progress note

# Run BorgOS installer after base install
d-i preseed/late_command string \
    in-target sh /cdrom/borgos/scripts/install.sh; \
    in-target systemctl enable ssh; \
    in-target systemctl enable docker
PRESEED

# Modify boot menu for x86_64
if [ -d ${WORK_DIR}/iso/install.amd ]; then
    # For AMD64 installer
    cat > ${WORK_DIR}/iso/isolinux/txt.cfg << 'BOOTMENU'
default borgos
label borgos
    menu label ^BorgOS Hybrid x86_64 (Auto Install)
    kernel /install.amd/vmlinuz
    append vga=788 initrd=/install.amd/initrd.gz auto=true priority=critical file=/cdrom/preseed.cfg --- quiet

label borgos-expert
    menu label ^BorgOS Expert Install
    kernel /install.amd/vmlinuz
    append vga=788 initrd=/install.amd/initrd.gz priority=low --- 

label rescue
    menu label ^Rescue mode
    kernel /install.amd/vmlinuz
    append vga=788 initrd=/install.amd/initrd.gz rescue/enable=true --- quiet
BOOTMENU
elif [ -f ${WORK_DIR}/iso/linux ]; then
    # For mini.iso structure
    cat > ${WORK_DIR}/iso/isolinux.cfg << 'BOOTMENU'
DEFAULT borgos
PROMPT 1
TIMEOUT 50

LABEL borgos
    MENU LABEL BorgOS Hybrid x86_64 Auto Install
    KERNEL linux
    APPEND vga=788 initrd=initrd.gz auto=true priority=critical file=/cdrom/preseed.cfg --- quiet

LABEL manual
    MENU LABEL Manual Install
    KERNEL linux
    APPEND vga=788 initrd=initrd.gz --- quiet
BOOTMENU
fi

# Create ISO for x86_64
echo "Building x86_64 ISO image..."
cd ${WORK_DIR}

# Try xorriso first (better compatibility)
if command -v xorriso >/dev/null 2>&1; then
    xorriso -as mkisofs \
        -r -V "BorgOS-x86_64" \
        -cache-inodes -J -l \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -o /output/${ISO_NAME} \
        ${WORK_DIR}/iso 2>/dev/null
else
    # Fallback to genisoimage
    genisoimage -r -V "BorgOS-x86_64" \
        -cache-inodes -J -l \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -o /output/${ISO_NAME} \
        ${WORK_DIR}/iso
fi

# Report
if [ -f /output/${ISO_NAME} ]; then
    SIZE=$(du -h /output/${ISO_NAME} | cut -f1)
    echo ""
    echo "✅ x86_64 ISO created: ${ISO_NAME} (${SIZE})"
    echo ""
    echo "Features:"
    echo "  - Debian 12 base system"
    echo "  - SSH enabled by default"
    echo "  - Docker pre-installed"
    echo "  - Ollama with Gemma 2B"
    echo "  - Auto-install via preseed"
else
    echo "❌ Failed to create x86_64 ISO"
    exit 1
fi
SCRIPT

chmod +x ${BUILD_DIR}/scripts/create-x86-iso.sh

# Create Dockerfile for x86_64 build
log "Creating Docker environment for x86_64..."
cat > ${BUILD_DIR}/Dockerfile << 'DOCKERFILE'
FROM debian:bookworm

RUN apt-get update && apt-get install -y \
    wget \
    xorriso \
    genisoimage \
    isolinux \
    p7zip-full \
    libarchive-tools \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY scripts/create-x86-iso.sh /build/
RUN chmod +x /build/create-x86-iso.sh

CMD ["/build/create-x86-iso.sh"]
DOCKERFILE

# Build Docker image
log "Building Docker image for x86_64 ISO creation..."
docker build -t borgos-x86-builder ${BUILD_DIR}

# Run build
log "Creating x86_64 ISO in Docker container..."
docker run --rm \
    -v ${BUILD_DIR}/output:/output \
    borgos-x86-builder

# Check result
if [ -f ${BUILD_DIR}/output/${ISO_NAME} ]; then
    mv ${BUILD_DIR}/output/${ISO_NAME} ./
    echo -e "${GREEN}"
    echo "═══════════════════════════════════════════"
    echo "  ✅ BorgOS x86_64 ISO Created!"
    echo "  📦 File: ${ISO_NAME}"
    echo "  📏 Size: $(du -h ${ISO_NAME} | cut -f1)"
    echo "  🏗️ Architecture: x86_64"
    echo ""
    echo "  Features:"
    echo "  • Debian 12 minimal base"
    echo "  • SSH enabled (borgos/borgos)"
    echo "  • Docker & Docker Compose"
    echo "  • Ollama with Gemma 2B model"
    echo "  • Auto-install via preseed"
    echo ""
    echo "  Test with:"
    echo "  qemu-system-x86_64 -m 4G -cdrom ${ISO_NAME}"
    echo ""
    echo "  Burn to USB:"
    echo "  sudo dd if=${ISO_NAME} of=/dev/sdX bs=4M"
    echo "═══════════════════════════════════════════"
    echo -e "${NC}"
else
    error "x86_64 ISO build failed"
fi

# Cleanup
log "Cleaning up..."
rm -rf ${BUILD_DIR}