#!/bin/bash
# ============================================================================
#  BorgOS Full ISO Builder - Fixed for Cross-Platform
#  Builds complete bootable ISO using Docker with proper x86_64 emulation
# ============================================================================

set -e

ISO_VERSION="3.0.0"
BUILD_DATE=$(date +%Y%m%d-%H%M)
ISO_NAME="BorgOS-Full-${ISO_VERSION}-${BUILD_DATE}-amd64.iso"
OUTPUT_DIR="$(pwd)/iso_output"

echo "================================================"
echo " BorgOS Full ISO Builder - Fixed Version"
echo " Creating complete bootable system"
echo "================================================"

# Create builder container specifically for x86_64
cat > Dockerfile.isobuilder-x86 << 'DOCKERFILE'
# Use x86_64 platform explicitly
FROM --platform=linux/amd64 debian:12

# Install build tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        debootstrap \
        squashfs-tools \
        xorriso \
        isolinux \
        syslinux-common \
        genisoimage \
        rsync \
        wget \
        curl \
        ca-certificates \
        dosfstools \
        mtools \
        grub-pc-bin \
        grub-efi-amd64-bin \
        grub-efi-amd64-signed \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Add build script
COPY build-iso-inside.sh /build/
RUN chmod +x /build/build-iso-inside.sh

CMD ["/build/build-iso-inside.sh"]
DOCKERFILE

# Create the internal build script
cat > build-iso-inside.sh << 'BUILD_SCRIPT'
#!/bin/bash
set -e

echo "[*] Starting ISO build inside container..."

WORK_DIR="/tmp/borgos-build"
ISO_DIR="/tmp/borgos-iso"
OUTPUT="/build/output"

# Clean and prepare
rm -rf ${WORK_DIR} ${ISO_DIR}
mkdir -p ${WORK_DIR}/chroot
mkdir -p ${ISO_DIR}/{isolinux,live,boot/grub,EFI/boot}
mkdir -p ${OUTPUT}

# Step 1: Create minimal Debian system
echo "[1/10] Creating base Debian system with debootstrap..."
debootstrap \
    --arch=amd64 \
    --variant=minbase \
    --include=linux-image-amd64,live-boot,systemd-sysv \
    bookworm \
    ${WORK_DIR}/chroot \
    http://deb.debian.org/debian/

# Step 2: Configure the base system
echo "[2/10] Configuring base system..."
cat > ${WORK_DIR}/chroot/etc/hostname << EOF
borgos
EOF

cat > ${WORK_DIR}/chroot/etc/hosts << EOF
127.0.0.1       localhost
127.0.1.1       borgos
EOF

# Step 3: Install packages in chroot
echo "[3/10] Installing essential packages..."
cat > ${WORK_DIR}/chroot/install.sh << 'INSTALL'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
    sudo \
    network-manager \
    ssh \
    curl \
    wget \
    git \
    nano \
    vim \
    htop \
    python3 \
    python3-pip \
    docker.io \
    docker-compose

# Create borgos user
useradd -m -s /bin/bash borgos
echo "borgos:borgos" | chpasswd
usermod -aG sudo,docker borgos
echo "borgos ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Enable services
systemctl enable ssh
systemctl enable docker
systemctl enable NetworkManager

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*
INSTALL

chmod +x ${WORK_DIR}/chroot/install.sh
chroot ${WORK_DIR}/chroot /install.sh
rm ${WORK_DIR}/chroot/install.sh

# Step 4: Copy BorgOS files
echo "[4/10] Installing BorgOS files..."
mkdir -p ${WORK_DIR}/chroot/opt/borgos

# Copy from mounted volume
if [ -d /build/core ]; then
    cp -r /build/core ${WORK_DIR}/chroot/opt/borgos/
fi
if [ -d /build/webui ]; then
    cp -r /build/webui ${WORK_DIR}/chroot/opt/borgos/
fi
if [ -d /build/installer ]; then
    cp -r /build/installer ${WORK_DIR}/chroot/opt/borgos/
fi
if [ -d /build/mcp_servers ]; then
    cp -r /build/mcp_servers ${WORK_DIR}/chroot/opt/borgos/
fi
if [ -d /build/database ]; then
    cp -r /build/database ${WORK_DIR}/chroot/opt/borgos/
fi

# Copy Docker compose files
cp /build/docker-compose*.yml ${WORK_DIR}/chroot/opt/borgos/ 2>/dev/null || true
cp /build/.env.example ${WORK_DIR}/chroot/opt/borgos/.env 2>/dev/null || true

# Step 5: Apply branding if available
echo "[5/10] Applying branding..."
if [ -d /build/branding ]; then
    # Copy splash screen
    if [ -f /build/branding/boot/splash.png ]; then
        cp /build/branding/boot/splash.png ${ISO_DIR}/isolinux/
    fi
    
    # Copy wallpapers
    if [ -d /build/branding/wallpapers ]; then
        mkdir -p ${WORK_DIR}/chroot/usr/share/backgrounds
        cp /build/branding/wallpapers/*.png ${WORK_DIR}/chroot/usr/share/backgrounds/ 2>/dev/null || true
    fi
fi

# Step 6: Create startup script
echo "[6/10] Creating startup configuration..."
cat > ${WORK_DIR}/chroot/opt/borgos/start.sh << 'STARTUP'
#!/bin/bash
cd /opt/borgos
docker-compose up -d
echo "BorgOS started!"
STARTUP
chmod +x ${WORK_DIR}/chroot/opt/borgos/start.sh

# Step 7: Copy kernel and initrd
echo "[7/10] Copying kernel and initrd..."
cp ${WORK_DIR}/chroot/boot/vmlinuz-* ${ISO_DIR}/live/vmlinuz
cp ${WORK_DIR}/chroot/boot/initrd.img-* ${ISO_DIR}/live/initrd.img

# Step 8: Create squashfs
echo "[8/10] Creating compressed filesystem..."
mksquashfs ${WORK_DIR}/chroot ${ISO_DIR}/live/filesystem.squashfs \
    -comp xz -b 1048576

# Step 9: Setup bootloader
echo "[9/10] Configuring bootloader..."

# Copy ISOLINUX files
cp /usr/lib/ISOLINUX/isolinux.bin ${ISO_DIR}/isolinux/
cp /usr/lib/syslinux/modules/bios/*.c32 ${ISO_DIR}/isolinux/

# Create ISOLINUX config
cat > ${ISO_DIR}/isolinux/isolinux.cfg << 'CFG'
UI menu.c32
PROMPT 0
TIMEOUT 100

MENU TITLE BorgOS v3.0.0 - AI-First Operating System
DEFAULT borgos

LABEL borgos
    MENU LABEL BorgOS Live
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live quiet splash

LABEL install
    MENU LABEL Install BorgOS
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live quiet splash install
CFG

# Step 10: Create ISO
echo "[10/10] Building ISO image..."
cd ${ISO_DIR}
xorriso -as mkisofs \
    -o ${OUTPUT}/BorgOS-Full.iso \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -c isolinux/boot.cat \
    -b isolinux/isolinux.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -V "BORGOS_3" \
    -R -J \
    .

echo "================================================"
echo " ISO BUILD COMPLETE!"
echo " Output: ${OUTPUT}/BorgOS-Full.iso"
echo "================================================"
BUILD_SCRIPT

chmod +x build-iso-inside.sh

# Build the Docker image
echo "[*] Building Docker image for x86_64..."
docker buildx build --platform linux/amd64 -t borgos-isobuilder-x86:latest -f Dockerfile.isobuilder-x86 .

# Create output directory
mkdir -p ${OUTPUT_DIR}

# Run the build
echo "[*] Running ISO build (this will take 15-30 minutes)..."
docker run --rm --platform linux/amd64 --privileged \
    -v "$(pwd):/build" \
    -v "${OUTPUT_DIR}:/build/output" \
    borgos-isobuilder-x86:latest

# Check result
if [ -f "${OUTPUT_DIR}/BorgOS-Full.iso" ]; then
    # Rename to final name
    mv "${OUTPUT_DIR}/BorgOS-Full.iso" "${OUTPUT_DIR}/${ISO_NAME}"
    
    echo ""
    echo "================================================"
    echo " ✅ SUCCESS! Full ISO Created"
    echo "================================================"
    echo " File: ${OUTPUT_DIR}/${ISO_NAME}"
    echo " Size: $(du -h ${OUTPUT_DIR}/${ISO_NAME} | cut -f1)"
    echo ""
    echo " This ISO contains:"
    echo " • Complete Debian Linux system"
    echo " • Docker & Docker Compose"
    echo " • BorgOS with all components"
    echo " • Latest code from January 2025"
    echo " • Borg.tools branding"
    echo ""
    echo " To write to USB:"
    echo " sudo dd if=${OUTPUT_DIR}/${ISO_NAME} of=/dev/diskX bs=4M"
    echo ""
    echo " Default login:"
    echo " Username: borgos"
    echo " Password: borgos"
    echo "================================================"
else
    echo "❌ Build failed. Check logs above."
    exit 1
fi

# Clean up
rm -f Dockerfile.isobuilder-x86 build-iso-inside.sh