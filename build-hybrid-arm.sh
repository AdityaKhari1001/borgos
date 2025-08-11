#!/bin/bash

# BorgOS Hybrid ISO Builder - ARM64 Version for Apple Silicon
# Builds ARM64 ISO with cross-compilation support

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
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Detect architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]] || [[ "$ARCH" == "aarch64" ]]; then
    TARGET_ARCH="arm64"
    QEMU_ARCH="aarch64"
    log "Building for ARM64 architecture"
else
    TARGET_ARCH="amd64"
    QEMU_ARCH="x86_64"
    log "Building for AMD64 architecture"
fi

# Configuration
VERSION="hybrid-1.0"
ISO_NAME="BorgOS-Hybrid-${VERSION}-${TARGET_ARCH}.iso"
BUILD_DIR="$(pwd)/hybrid_build_${TARGET_ARCH}"

# Show banner
echo -e "${CYAN}"
cat << 'EOF'
╔════════════════════════════════════════╗
║   BorgOS Hybrid ISO Builder (ARM64)    ║
║     Optimized for Apple Silicon        ║
╚════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Create build directory
log "Creating build directory..."
rm -rf ${BUILD_DIR}
mkdir -p ${BUILD_DIR}/{iso,scripts,output}

# Create simplified ISO build script
log "Creating build script..."
cat > ${BUILD_DIR}/scripts/create-iso.sh << 'SCRIPT'
#!/bin/bash

set -e

# Configuration
VERSION="hybrid-1.0"
TARGET_ARCH="${1:-arm64}"
ISO_NAME="BorgOS-Hybrid-${VERSION}-${TARGET_ARCH}.iso"
WORK_DIR="/tmp/borgos_iso"

echo "Building BorgOS Hybrid ISO for ${TARGET_ARCH}..."

# Create working directories
mkdir -p ${WORK_DIR}/{iso,rootfs,staging}
cd ${WORK_DIR}

# Download minimal Debian netboot files for ARM64
if [[ "$TARGET_ARCH" == "arm64" ]]; then
    echo "Downloading ARM64 netboot files..."
    wget -q http://ftp.debian.org/debian/dists/bookworm/main/installer-arm64/current/images/netboot/mini.iso -O base.iso
else
    echo "Downloading AMD64 netboot files..."
    wget -q http://ftp.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/mini.iso -O base.iso
fi

# Extract base ISO
echo "Extracting base ISO..."
7z x -o${WORK_DIR}/iso base.iso > /dev/null 2>&1 || \
    bsdtar -xf base.iso -C ${WORK_DIR}/iso

# Create BorgOS structure
echo "Creating BorgOS structure..."
mkdir -p ${WORK_DIR}/iso/borgos/{scripts,config,ollama}

# Create minimal BorgOS installer script
cat > ${WORK_DIR}/iso/borgos/scripts/install.sh << 'INSTALLER'
#!/bin/sh
# BorgOS Hybrid Installer

echo "═══════════════════════════════════════════"
echo "    BorgOS Hybrid Installation"
echo "═══════════════════════════════════════════"

# Install base packages
apt-get update
apt-get install -y \
    openssh-server \
    docker.io \
    curl \
    wget \
    git \
    nano \
    sudo

# Create borgos user
useradd -m -s /bin/bash -G sudo,docker borgos
echo "borgos:borgos" | chpasswd

# Enable SSH
systemctl enable ssh
systemctl start ssh

# Install Ollama
echo "Installing Ollama..."
curl -fsSL https://ollama.ai/install.sh | sh

# Pull Gemma 2B model
echo "Downloading Gemma 2B model..."
ollama pull gemma:2b

echo "Installation complete!"
echo "Default login: borgos/borgos"
INSTALLER
chmod +x ${WORK_DIR}/iso/borgos/scripts/install.sh

# Create preseed file for automated installation
cat > ${WORK_DIR}/iso/preseed.cfg << 'PRESEED'
# BorgOS Automated Installation
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select us
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string borgos
d-i netcfg/get_domain string local
d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i passwd/root-password password borgos
d-i passwd/root-password-again password borgos
d-i passwd/user-fullname string BorgOS User
d-i passwd/username string borgos
d-i passwd/user-password password borgos
d-i passwd/user-password-again password borgos
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
d-i apt-setup/non-free boolean true
d-i apt-setup/contrib boolean true
tasksel tasksel/first multiselect standard, ssh-server
d-i pkgsel/include string openssh-server docker.io curl wget git nano sudo
d-i finish-install/reboot_in_progress note
d-i preseed/late_command string \
    in-target sh /cdrom/borgos/scripts/install.sh
PRESEED

# Create custom boot menu
if [ -f ${WORK_DIR}/iso/isolinux/txt.cfg ]; then
    cat > ${WORK_DIR}/iso/isolinux/txt.cfg << 'BOOTMENU'
default borgos
label borgos
    menu label ^BorgOS Hybrid (Auto Install)
    kernel /install.arm/vmlinuz
    append vga=788 initrd=/install.arm/initrd.gz auto=true priority=critical file=/cdrom/preseed.cfg --- quiet

label manual
    menu label ^Manual Install
    kernel /install.arm/vmlinuz
    append vga=788 initrd=/install.arm/initrd.gz --- quiet
BOOTMENU
fi

# Create ISO
echo "Building ISO image..."
cd ${WORK_DIR}
genisoimage -r -V "BorgOS-Hybrid" \
    -cache-inodes -J -l \
    -o /output/${ISO_NAME} \
    ${WORK_DIR}/iso 2>/dev/null || \
xorriso -as mkisofs \
    -r -V "BorgOS-Hybrid" \
    -o /output/${ISO_NAME} \
    ${WORK_DIR}/iso

# Report
if [ -f /output/${ISO_NAME} ]; then
    SIZE=$(du -h /output/${ISO_NAME} | cut -f1)
    echo ""
    echo "✅ ISO created: ${ISO_NAME} (${SIZE})"
else
    echo "❌ Failed to create ISO"
    exit 1
fi
SCRIPT

chmod +x ${BUILD_DIR}/scripts/create-iso.sh

# Create Dockerfile for cross-platform build
log "Creating Docker environment..."
cat > ${BUILD_DIR}/Dockerfile << 'DOCKERFILE'
FROM debian:bookworm

RUN apt-get update && apt-get install -y \
    wget \
    xorriso \
    genisoimage \
    p7zip-full \
    libarchive-tools \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY scripts/create-iso.sh /build/
RUN chmod +x /build/create-iso.sh

CMD ["/build/create-iso.sh", "arm64"]
DOCKERFILE

# Build and run in Docker
log "Building Docker image..."
docker build -t borgos-hybrid-builder ${BUILD_DIR}

log "Creating ISO in Docker container..."
docker run --rm \
    -v ${BUILD_DIR}/output:/output \
    -e TARGET_ARCH=${TARGET_ARCH} \
    borgos-hybrid-builder /build/create-iso.sh ${TARGET_ARCH}

# Check result
if [ -f ${BUILD_DIR}/output/${ISO_NAME} ]; then
    mv ${BUILD_DIR}/output/${ISO_NAME} ./
    echo -e "${GREEN}"
    echo "═══════════════════════════════════════════"
    echo "  ✅ BorgOS Hybrid ISO Created!"
    echo "  📦 File: ${ISO_NAME}"
    echo "  📏 Size: $(du -h ${ISO_NAME} | cut -f1)"
    echo "  🏗️ Architecture: ${TARGET_ARCH}"
    echo ""
    echo "  Test with:"
    if [[ "$TARGET_ARCH" == "arm64" ]]; then
        echo "  qemu-system-aarch64 -M virt -cpu cortex-a72 -m 4G -cdrom ${ISO_NAME}"
    else
        echo "  qemu-system-x86_64 -m 4G -cdrom ${ISO_NAME}"
    fi
    echo "═══════════════════════════════════════════"
    echo -e "${NC}"
else
    error "ISO build failed"
fi

# Cleanup
log "Cleaning up..."
rm -rf ${BUILD_DIR}