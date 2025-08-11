#!/bin/bash
# Full x86_64 BorgOS ISO Builder with ALL packages
# This creates a 3-5GB ISO with everything included

set -euo pipefail

ISO_VERSION="4.0.0"
BUILD_DATE=$(date +%Y%m%d-%H%M)
ISO_NAME="BorgOS-Full-${ISO_VERSION}-${BUILD_DATE}-amd64.iso"
WORK_DIR="/tmp/borgos-full-iso"
OUTPUT_DIR="/build"

echo "================================================"
echo " BorgOS FULL ISO Builder (x86_64)"
echo " Expected size: 3-5 GB"
echo "================================================"

# Clean and prepare
rm -rf ${WORK_DIR}
mkdir -p ${WORK_DIR}/{chroot,image/{live,isolinux,boot/grub}}
mkdir -p ${WORK_DIR}/packages

# Create comprehensive package list
cat > ${WORK_DIR}/packages.txt << 'EOF'
# Core System
linux-image-amd64
grub-pc
grub-efi-amd64
systemd
systemd-sysv
init
sudo
openssh-server
network-manager
net-tools
iproute2
ifupdown
wireless-tools
wpasupplicant
firmware-linux-free

# Development
build-essential
git
curl
wget
vim
nano
emacs
tmux
htop
gcc
g++
make
cmake
python3
python3-pip
python3-venv
python3-dev
nodejs
npm

# Docker & Containers  
docker.io
docker-compose
containerd
runc
podman

# Desktop Environment
xfce4
xfce4-goodies
lightdm
lightdm-gtk-greeter
firefox-esr
thunderbird
libreoffice
gimp
vlc
pulseaudio
pavucontrol

# System Tools
gparted
synaptic
apt-transport-https
ca-certificates
gnupg
lsb-release
software-properties-common
dbus-x11
policykit-1

# Libraries
libssl-dev
libffi-dev
libyaml-dev
libpq-dev
libmysqlclient-dev
libsqlite3-dev
libxml2-dev
libxslt1-dev
libcurl4-openssl-dev

# Database Clients
postgresql-client
mysql-client
redis-tools
mongodb-clients

# Additional Tools
zip
unzip
p7zip-full
rar
unrar
rsync
screen
nmap
netcat
tcpdump
iptables
ufw
fail2ban
EOF

echo "[1/10] Building base system with debootstrap..."
debootstrap \
    --arch=amd64 \
    --variant=minbase \
    --include=linux-image-amd64,live-boot,systemd-sysv \
    bookworm \
    ${WORK_DIR}/chroot \
    http://deb.debian.org/debian/ || {
        echo "Debootstrap failed"
        exit 1
    }

echo "[2/10] Mounting proc, sys, dev..."
mount -t proc none ${WORK_DIR}/chroot/proc
mount -t sysfs none ${WORK_DIR}/chroot/sys
mount -o bind /dev ${WORK_DIR}/chroot/dev

echo "[3/10] Installing all packages (this will take time)..."
cat > ${WORK_DIR}/chroot/install-packages.sh << 'SCRIPT'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

# Update sources
cat > /etc/apt/sources.list << EOF
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF

apt-get update

# Read package list and install everything
while IFS= read -r package; do
    # Skip comments and empty lines
    [[ "$package" =~ ^#.*$ ]] && continue
    [[ -z "$package" ]] && continue
    
    echo "Installing: $package"
    apt-get install -y $package || echo "Failed: $package"
done < /packages.txt

# Download additional packages for offline use
apt-get install -y --download-only \
    chromium \
    vscode \
    sublime-text \
    atom \
    discord \
    slack-desktop \
    zoom \
    teams || true

# Clean up
apt-get clean
SCRIPT

cp ${WORK_DIR}/packages.txt ${WORK_DIR}/chroot/
chmod +x ${WORK_DIR}/chroot/install-packages.sh
chroot ${WORK_DIR}/chroot /install-packages.sh

echo "[4/10] Downloading Docker images..."
cat > ${WORK_DIR}/chroot/download-images.sh << 'SCRIPT'
#!/bin/bash
# Download and save Docker images
systemctl start docker || true

IMAGES=(
    "postgres:15-alpine"
    "mysql:8"
    "redis:7-alpine"
    "nginx:alpine"
    "python:3.11-slim"
    "node:18-alpine"
    "ubuntu:22.04"
    "debian:12"
    "alpine:latest"
    "busybox:latest"
)

mkdir -p /opt/docker-images

for image in "${IMAGES[@]}"; do
    echo "Pulling $image..."
    docker pull $image || continue
    echo "Saving $image..."
    docker save -o "/opt/docker-images/$(echo $image | tr ':/' '_').tar" $image
done
SCRIPT

chmod +x ${WORK_DIR}/chroot/download-images.sh
chroot ${WORK_DIR}/chroot /download-images.sh || true

echo "[5/10] Installing BorgOS..."
mkdir -p ${WORK_DIR}/chroot/opt/borgos
cp -r /build/core ${WORK_DIR}/chroot/opt/borgos/ 2>/dev/null || true
cp -r /build/webui ${WORK_DIR}/chroot/opt/borgos/ 2>/dev/null || true
cp -r /build/installer ${WORK_DIR}/chroot/opt/borgos/ 2>/dev/null || true

echo "[6/10] Creating users and configuring system..."
chroot ${WORK_DIR}/chroot useradd -m -s /bin/bash -G sudo,docker borgos || true
echo "borgos:borgos" | chroot ${WORK_DIR}/chroot chpasswd
echo "root:borgos" | chroot ${WORK_DIR}/chroot chpasswd
echo "borgos ALL=(ALL) NOPASSWD: ALL" >> ${WORK_DIR}/chroot/etc/sudoers

echo "[7/10] Cleaning up..."
umount ${WORK_DIR}/chroot/proc || true
umount ${WORK_DIR}/chroot/sys || true
umount ${WORK_DIR}/chroot/dev || true

rm -rf ${WORK_DIR}/chroot/tmp/*
rm -rf ${WORK_DIR}/chroot/var/lib/apt/lists/*
rm -f ${WORK_DIR}/chroot/*.sh
rm -f ${WORK_DIR}/chroot/packages.txt

echo "[8/10] Creating squashfs (this will take time)..."
# Copy kernel and initrd
cp ${WORK_DIR}/chroot/boot/vmlinuz-* ${WORK_DIR}/image/live/vmlinuz
cp ${WORK_DIR}/chroot/boot/initrd.img-* ${WORK_DIR}/image/live/initrd.img

# Create squashfs with maximum compression
mksquashfs ${WORK_DIR}/chroot ${WORK_DIR}/image/live/filesystem.squashfs \
    -comp xz -b 1M -Xdict-size 100%

echo "[9/10] Configuring bootloader..."
# Copy isolinux files
cp /usr/lib/ISOLINUX/isolinux.bin ${WORK_DIR}/image/isolinux/ || \
cp /usr/share/syslinux/isolinux.bin ${WORK_DIR}/image/isolinux/

cp /usr/lib/syslinux/modules/bios/*.c32 ${WORK_DIR}/image/isolinux/ 2>/dev/null || true

cat > ${WORK_DIR}/image/isolinux/isolinux.cfg << EOF
DEFAULT borgos
LABEL borgos
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live quiet splash
EOF

echo "[10/10] Creating ISO..."
xorriso -as mkisofs \
    -iso-level 3 \
    -o ${OUTPUT_DIR}/${ISO_NAME} \
    -full-iso9660-filenames \
    -volid "BORGOS_FULL" \
    -eltorito-boot isolinux/isolinux.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-catalog isolinux/boot.cat \
    ${WORK_DIR}/image

# Clean up
rm -rf ${WORK_DIR}

echo "================================================"
echo " FULL ISO BUILD COMPLETE!"
echo " File: ${OUTPUT_DIR}/${ISO_NAME}"
echo " Size: $(du -h ${OUTPUT_DIR}/${ISO_NAME} | cut -f1)"
echo "================================================"