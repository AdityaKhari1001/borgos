#!/bin/bash

# BorgOS Hybrid ISO Builder - Docker Version
# Builds ISO inside Docker container (no sudo required)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
VERSION="hybrid-1.0"
ARCH="amd64"
ISO_NAME="BorgOS-Hybrid-${VERSION}-${ARCH}.iso"
BUILD_DIR="$(pwd)/hybrid_docker_build"

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

# Show banner
echo -e "${CYAN}"
cat << 'EOF'
╔════════════════════════════════════════╗
║     BorgOS Hybrid ISO Docker Builder    ║
║        No sudo required!               ║
╚════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Create build directory
log "Creating build directory..."
rm -rf ${BUILD_DIR}
mkdir -p ${BUILD_DIR}

# Create Dockerfile for ISO builder
log "Creating Docker build environment..."
cat > ${BUILD_DIR}/Dockerfile << 'DOCKERFILE'
FROM debian:bookworm

# Install build tools
RUN apt-get update && apt-get install -y \
    debootstrap \
    squashfs-tools \
    xorriso \
    isolinux \
    syslinux-common \
    curl \
    wget \
    git \
    cpio \
    genisoimage \
    live-build \
    systemd-container \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Copy build script
COPY build-iso-internal.sh /build/
COPY assets /build/assets/
COPY core /build/core/
COPY webui /build/webui/
COPY installer /build/installer/

# Make script executable
RUN chmod +x /build/build-iso-internal.sh

# Run build
CMD ["/build/build-iso-internal.sh"]
DOCKERFILE

# Create internal build script
log "Creating internal build script..."
cat > ${BUILD_DIR}/build-iso-internal.sh << 'BUILDSCRIPT'
#!/bin/bash

set -e

# Configuration
VERSION="hybrid-1.0"
ARCH="amd64"
ISO_NAME="BorgOS-Hybrid-${VERSION}-${ARCH}.iso"
WORK_DIR="/build/work"
ISO_DIR="${WORK_DIR}/iso"
ROOTFS="${WORK_DIR}/rootfs"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[BUILD]${NC} $1"; }

# Create directories
log "Setting up build environment..."
mkdir -p ${WORK_DIR}/{iso,rootfs,tmp}
mkdir -p ${ISO_DIR}/{isolinux,boot/grub,live,install}

# Create minimal rootfs using debootstrap
log "Creating minimal Debian rootfs..."
debootstrap --variant=minbase \
    --include=systemd,systemd-sysv,linux-image-amd64,grub-pc,openssh-server,network-manager,curl,wget,git,ca-certificates,sudo,nano,docker.io \
    bookworm ${ROOTFS} \
    http://deb.debian.org/debian/

# Configure system
log "Configuring system..."

# Create borgos user
chroot ${ROOTFS} useradd -m -s /bin/bash -G sudo,docker borgos || true
echo "borgos:borgos" | chroot ${ROOTFS} chpasswd
echo "root:borgos" | chroot ${ROOTFS} chpasswd

# Enable SSH
chroot ${ROOTFS} systemctl enable ssh || true

# Configure network
cat > ${ROOTFS}/etc/network/interfaces << 'NET'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
NET

# Install Ollama (simplified for Docker build)
log "Preparing Ollama installation..."
cat > ${ROOTFS}/usr/local/bin/install-ollama.sh << 'OLLAMA'
#!/bin/bash
# Install Ollama on first boot
if [ ! -f /usr/local/bin/ollama ]; then
    echo "Installing Ollama..."
    curl -fsSL https://ollama.ai/install.sh | sh
    systemctl enable ollama
    systemctl start ollama
    ollama pull gemma:2b
fi
OLLAMA
chmod +x ${ROOTFS}/usr/local/bin/install-ollama.sh

# Create first-boot service
cat > ${ROOTFS}/etc/systemd/system/borgos-firstboot.service << 'SERVICE'
[Unit]
Description=BorgOS First Boot Setup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/install-ollama.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE

chroot ${ROOTFS} systemctl enable borgos-firstboot.service || true

# Copy BorgOS files
log "Installing BorgOS core..."
mkdir -p ${ROOTFS}/opt/borgos
cp -r /build/core ${ROOTFS}/opt/borgos/ || true
cp -r /build/webui ${ROOTFS}/opt/borgos/ || true
cp -r /build/installer ${ROOTFS}/opt/borgos/ || true

# Create welcome message
cat > ${ROOTFS}/etc/motd << 'MOTD'
═══════════════════════════════════════════
    BorgOS Hybrid - AI-First System
    
    Default login: borgos/borgos
    SSH enabled on all interfaces
    
    Ollama will install on first boot
    Web UI: http://localhost:6969
═══════════════════════════════════════════
MOTD

# Clean up
log "Cleaning up..."
chroot ${ROOTFS} apt-get clean
rm -rf ${ROOTFS}/var/cache/apt/archives/*
rm -rf ${ROOTFS}/tmp/*

# Create squashfs
log "Creating compressed filesystem..."
mksquashfs ${ROOTFS} ${ISO_DIR}/live/filesystem.squashfs \
    -comp xz -b 1M \
    -e boot || exit 1

# Copy kernel and initrd
cp ${ROOTFS}/boot/vmlinuz-* ${ISO_DIR}/live/vmlinuz || \
    cp ${ROOTFS}/vmlinuz ${ISO_DIR}/live/vmlinuz || \
    echo "Warning: vmlinuz not found"

cp ${ROOTFS}/boot/initrd.img-* ${ISO_DIR}/live/initrd.img || \
    cp ${ROOTFS}/initrd.img ${ISO_DIR}/live/initrd.img || \
    echo "Warning: initrd not found"

# Create boot configuration
log "Creating boot configuration..."
cat > ${ISO_DIR}/isolinux/isolinux.cfg << 'BOOTCFG'
DEFAULT borgos
PROMPT 1
TIMEOUT 50

LABEL borgos
    MENU LABEL BorgOS Hybrid Live
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live quiet splash

LABEL install
    MENU LABEL Install BorgOS
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live install quiet

LABEL safe
    MENU LABEL Safe Mode
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live nomodeset
BOOTCFG

# Copy isolinux files
cp /usr/lib/ISOLINUX/isolinux.bin ${ISO_DIR}/isolinux/ || \
    cp /usr/share/syslinux/isolinux.bin ${ISO_DIR}/isolinux/
cp /usr/lib/syslinux/modules/bios/*.c32 ${ISO_DIR}/isolinux/ || \
    echo "Warning: c32 modules not found"

# Build ISO
log "Building ISO image..."
cd ${WORK_DIR}
xorriso -as mkisofs \
    -r -V "BorgOS-Hybrid" \
    -cache-inodes -J -l \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -o /output/${ISO_NAME} \
    ${ISO_DIR} || \
genisoimage -r -V "BorgOS-Hybrid" \
    -cache-inodes -J -l \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -o /output/${ISO_NAME} \
    ${ISO_DIR}

# Report success
if [ -f /output/${ISO_NAME} ]; then
    SIZE=$(du -h /output/${ISO_NAME} | cut -f1)
    echo ""
    echo "═══════════════════════════════════════════"
    echo "  ✅ Build Complete!"
    echo "  📦 ISO: ${ISO_NAME}"
    echo "  📏 Size: ${SIZE}"
    echo "═══════════════════════════════════════════"
else
    echo "❌ Build failed - ISO not created"
    exit 1
fi
BUILDSCRIPT

# Copy required files to build directory
log "Copying BorgOS files..."
cp -r assets ${BUILD_DIR}/ 2>/dev/null || echo "No assets directory"
cp -r core ${BUILD_DIR}/ 2>/dev/null || echo "No core directory"
cp -r webui ${BUILD_DIR}/ 2>/dev/null || echo "No webui directory"  
cp -r installer ${BUILD_DIR}/ 2>/dev/null || echo "No installer directory"

# Build Docker image
log "Building Docker image..."
docker build -t borgos-iso-builder ${BUILD_DIR}

# Run build in container
log "Running ISO build in container..."
docker run --rm \
    -v ${BUILD_DIR}:/output \
    --privileged \
    borgos-iso-builder

# Check result
if [ -f ${BUILD_DIR}/${ISO_NAME} ]; then
    mv ${BUILD_DIR}/${ISO_NAME} ./
    log "✅ ISO created successfully: ${ISO_NAME}"
    log "📏 Size: $(du -h ${ISO_NAME} | cut -f1)"
    
    echo -e "${GREEN}"
    echo "═══════════════════════════════════════════"
    echo "  Next steps:"
    echo "  1. Test: qemu-system-x86_64 -m 4G -cdrom ${ISO_NAME}"
    echo "  2. Burn: sudo dd if=${ISO_NAME} of=/dev/sdX bs=4M"
    echo "═══════════════════════════════════════════"
    echo -e "${NC}"
else
    error "Build failed - ISO not found"
fi

# Cleanup
log "Cleaning up..."
rm -rf ${BUILD_DIR}