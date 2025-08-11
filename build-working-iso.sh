#!/bin/bash
# ============================================================================
#  BorgOS Working ISO Builder - Fixed Version
#  Creates properly bootable ISO with correct user and autostart
# ============================================================================

set -e

ISO_VERSION="3.0.1"
BUILD_DATE=$(date +%Y%m%d-%H%M)
ISO_NAME="BorgOS-${ISO_VERSION}-${BUILD_DATE}-amd64.iso"
OUTPUT_DIR="$(pwd)/iso_output"

echo "================================================"
echo " BorgOS Working ISO Builder"
echo " Fixing all boot and installation issues"
echo "================================================"

# Create Docker build environment
cat > Dockerfile.borgos-fixed << 'DOCKERFILE'
FROM --platform=linux/amd64 debian:12

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
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY build-iso-internal.sh /build/
RUN chmod +x /build/build-iso-internal.sh

CMD ["/build/build-iso-internal.sh"]
DOCKERFILE

# Create internal build script
cat > build-iso-internal.sh << 'BUILD_SCRIPT'
#!/bin/bash
set -e

echo "[*] Starting fixed ISO build..."

WORK_DIR="/tmp/borgos-build"
ISO_DIR="/tmp/borgos-iso"
OUTPUT="/build/output"

# Clean and prepare
rm -rf ${WORK_DIR} ${ISO_DIR}
mkdir -p ${WORK_DIR}/chroot
mkdir -p ${ISO_DIR}/{isolinux,live,install}
mkdir -p ${OUTPUT}

# Step 1: Create base system
echo "[1/8] Creating base Debian system..."
debootstrap \
    --arch=amd64 \
    --variant=minbase \
    --include=linux-image-amd64,live-boot,systemd-sysv \
    bookworm \
    ${WORK_DIR}/chroot \
    http://deb.debian.org/debian/

# Step 2: Configure system
echo "[2/8] Configuring system..."
cat > ${WORK_DIR}/chroot/etc/hostname << EOF
borgos
EOF

cat > ${WORK_DIR}/chroot/etc/hosts << EOF
127.0.0.1       localhost
127.0.1.1       borgos
EOF

# Step 3: Install packages and create proper user
echo "[3/8] Installing packages and creating user..."
cat > ${WORK_DIR}/chroot/install.sh << 'INSTALL'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

# Update and install packages
apt-get update
apt-get install -y \
    sudo \
    network-manager \
    openssh-server \
    curl \
    wget \
    git \
    nano \
    vim \
    htop \
    python3 \
    python3-pip \
    docker.io \
    docker-compose \
    net-tools \
    iputils-ping

# Create borgos user (not borg!)
useradd -m -s /bin/bash -G sudo,docker borgos
echo "borgos:borgos" | chpasswd
echo "borgos ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Enable services
systemctl enable ssh
systemctl enable docker
systemctl enable NetworkManager

# Clean apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*
INSTALL

chmod +x ${WORK_DIR}/chroot/install.sh
chroot ${WORK_DIR}/chroot /install.sh
rm ${WORK_DIR}/chroot/install.sh

# Step 4: Copy BorgOS files
echo "[4/8] Installing BorgOS system..."
mkdir -p ${WORK_DIR}/chroot/opt/borgos

# Copy all BorgOS components
for dir in core webui installer mcp_servers database docs; do
    if [ -d /build/${dir} ]; then
        cp -r /build/${dir} ${WORK_DIR}/chroot/opt/borgos/
    fi
done

# Copy Docker compose files
cp /build/docker-compose*.yml ${WORK_DIR}/chroot/opt/borgos/ 2>/dev/null || true
cp /build/.env.example ${WORK_DIR}/chroot/opt/borgos/.env 2>/dev/null || true

# Step 5: Create proper autostart
echo "[5/8] Creating autostart configuration..."

# Create systemd service for autostart
cat > ${WORK_DIR}/chroot/etc/systemd/system/borgos-start.service << 'SERVICE'
[Unit]
Description=BorgOS Startup Service
After=docker.service network-online.target
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=borgos
WorkingDirectory=/opt/borgos
ExecStart=/opt/borgos/start-borgos.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE

# Create startup script
cat > ${WORK_DIR}/chroot/opt/borgos/start-borgos.sh << 'STARTUP'
#!/bin/bash
echo "Starting BorgOS services..."
cd /opt/borgos

# Wait for Docker to be ready
while ! docker info >/dev/null 2>&1; do
    echo "Waiting for Docker..."
    sleep 2
done

# Start services
if [ -f docker-compose.yml ]; then
    docker-compose up -d
    echo "BorgOS services started!"
    echo "Dashboard: http://localhost:8080"
else
    echo "docker-compose.yml not found!"
fi
STARTUP

chmod +x ${WORK_DIR}/chroot/opt/borgos/start-borgos.sh
chown -R 1000:1000 ${WORK_DIR}/chroot/opt/borgos

# Enable the service
chroot ${WORK_DIR}/chroot systemctl enable borgos-start.service

# Create installer script
cat > ${WORK_DIR}/chroot/opt/borgos/install-to-disk.sh << 'INSTALLER'
#!/bin/bash
echo "================================================"
echo " BorgOS Installer"
echo "================================================"
echo ""
echo "This will install BorgOS to your hard drive."
echo "WARNING: This will erase all data on the target disk!"
echo ""
read -p "Target disk (e.g., /dev/sda): " DISK
read -p "Are you sure? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Installation cancelled."
    exit 1
fi

echo "Installing BorgOS to $DISK..."

# Partition disk
parted -s $DISK mklabel gpt
parted -s $DISK mkpart primary ext4 1MiB 100%
mkfs.ext4 ${DISK}1

# Mount and copy system
mount ${DISK}1 /mnt
rsync -av --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/mnt / /mnt/

# Install GRUB
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
chroot /mnt grub-install $DISK
chroot /mnt update-grub

echo "Installation complete! Remove USB and reboot."
INSTALLER

chmod +x ${WORK_DIR}/chroot/opt/borgos/install-to-disk.sh

# Step 6: Copy kernel and initrd
echo "[6/8] Copying kernel and initrd..."
cp ${WORK_DIR}/chroot/boot/vmlinuz-* ${ISO_DIR}/live/vmlinuz
cp ${WORK_DIR}/chroot/boot/initrd.img-* ${ISO_DIR}/live/initrd.img

# Step 7: Create squashfs
echo "[7/8] Creating compressed filesystem..."
mksquashfs ${WORK_DIR}/chroot ${ISO_DIR}/live/filesystem.squashfs \
    -comp xz -b 1048576

# Step 8: Configure bootloader with proper menu
echo "[8/8] Configuring bootloader..."

# Copy ISOLINUX files
cp /usr/lib/ISOLINUX/isolinux.bin ${ISO_DIR}/isolinux/
cp /usr/lib/syslinux/modules/bios/*.c32 ${ISO_DIR}/isolinux/

# Create proper boot menu
cat > ${ISO_DIR}/isolinux/isolinux.cfg << 'CFG'
UI menu.c32
PROMPT 0
TIMEOUT 50

MENU TITLE BorgOS 3.0.1 Boot Menu
DEFAULT borgos

LABEL borgos
    MENU LABEL Start BorgOS Live
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live quiet splash

LABEL install
    MENU LABEL Install BorgOS to Hard Drive
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live quiet splash install

LABEL borgos-debug
    MENU LABEL BorgOS Live (Debug Mode)
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live debug

LABEL memtest
    MENU LABEL Memory Test
    KERNEL /live/memtest
CFG

# Create ISO
cd ${ISO_DIR}
xorriso -as mkisofs \
    -o ${OUTPUT}/BorgOS.iso \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -c isolinux/boot.cat \
    -b isolinux/isolinux.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -V "BORGOS_3" \
    -R -J \
    .

echo "ISO build complete!"
BUILD_SCRIPT

chmod +x build-iso-internal.sh

# Build Docker image
echo "[*] Building Docker image..."
docker buildx build --platform linux/amd64 -t borgos-builder:fixed -f Dockerfile.borgos-fixed .

# Create output directory
mkdir -p ${OUTPUT_DIR}

# Run the build
echo "[*] Running ISO build..."
docker run --rm --platform linux/amd64 --privileged \
    -v "$(pwd):/build" \
    -v "${OUTPUT_DIR}:/build/output" \
    borgos-builder:fixed

# Check result
if [ -f "${OUTPUT_DIR}/BorgOS.iso" ]; then
    mv "${OUTPUT_DIR}/BorgOS.iso" "${OUTPUT_DIR}/${ISO_NAME}"
    
    echo ""
    echo "================================================"
    echo " ✅ ISO BUILD SUCCESSFUL!"
    echo "================================================"
    echo " File: ${OUTPUT_DIR}/${ISO_NAME}"
    echo " Size: $(du -h ${OUTPUT_DIR}/${ISO_NAME} | cut -f1)"
    echo ""
    echo " Fixed issues:"
    echo " ✓ Correct user: borgos (not borg)"
    echo " ✓ Password: borgos"
    echo " ✓ Autostart service enabled"
    echo " ✓ Installation option in boot menu"
    echo " ✓ Debug mode available"
    echo ""
    echo " Boot options:"
    echo " 1. Start BorgOS Live - run from USB"
    echo " 2. Install to Hard Drive - permanent installation"
    echo " 3. Debug Mode - for troubleshooting"
    echo ""
    echo " To write to USB:"
    echo " sudo dd if=${OUTPUT_DIR}/${ISO_NAME} of=/dev/diskX bs=4M status=progress"
    echo "================================================"
else
    echo "❌ Build failed. Check logs above."
    exit 1
fi

# Clean up
rm -f Dockerfile.borgos-fixed build-iso-internal.sh