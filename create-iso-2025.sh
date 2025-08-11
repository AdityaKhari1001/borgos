#!/bin/bash
# ============================================================================
#  BorgOS ISO Builder 2025 - v3.0
#  Purpose: Generate a bootable ISO with the latest BorgOS multi-agent system
#  Date: January 2025
#  Includes: Agent Zero, Zenith Coder, MCP, Vector DB, and all recent updates
# ============================================================================

set -e

# Configuration
ISO_VERSION="3.0.0"
BUILD_DATE=$(date +%Y%m%d)
ISO_NAME="BorgOS-${ISO_VERSION}-${BUILD_DATE}-amd64.iso"
WORK_DIR="/tmp/borgos-iso-build"
OUTPUT_DIR="$(pwd)/iso_output"
BORGOS_DIR="$(pwd)"

echo "================================================"
echo " BorgOS ISO Builder 2025 - Version ${ISO_VERSION}"
echo "================================================"
echo " Build Date: $(date)"
echo " Output: ${OUTPUT_DIR}/${ISO_NAME}"
echo "================================================"

# Check for required tools
check_requirements() {
    echo "[1/8] Checking requirements..."
    
    # Check if running on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "⚠️  Detected macOS - Installing Linux ISO building in Docker..."
        
        # Create Dockerfile for ISO building
        cat > Dockerfile.isobuilder << 'EOF'
FROM debian:12

RUN apt-get update && apt-get install -y \
    debootstrap \
    squashfs-tools \
    xorriso \
    isolinux \
    syslinux-common \
    genisoimage \
    rsync \
    wget \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
EOF
        
        # Build Docker image
        docker build -f Dockerfile.isobuilder -t borgos-isobuilder:latest .
        
        # Run the build in Docker
        docker run --privileged -v "$(pwd):/build" borgos-isobuilder:latest bash -c "cd /build && bash create-iso-2025.sh --in-docker"
        exit 0
    fi
    
    # Linux requirements
    REQUIRED_TOOLS="debootstrap squashfs-tools xorriso isolinux"
    for tool in $REQUIRED_TOOLS; do
        if ! command -v $tool &> /dev/null; then
            echo "Installing $tool..."
            apt-get update && apt-get install -y $tool
        fi
    done
}

# Skip requirement check if running inside Docker
if [[ "$1" != "--in-docker" ]]; then
    check_requirements
fi

# Clean previous builds
echo "[2/8] Cleaning previous builds..."
rm -rf ${WORK_DIR}
mkdir -p ${WORK_DIR}/{iso,squashfs,staging}
mkdir -p ${OUTPUT_DIR}

# Create base system with debootstrap
echo "[3/8] Creating base Debian system..."
if [[ "$1" == "--in-docker" ]] || [[ "$OSTYPE" != "darwin"* ]]; then
    debootstrap --arch=amd64 --variant=minbase bookworm ${WORK_DIR}/squashfs http://deb.debian.org/debian/
fi

# Copy BorgOS files
echo "[4/8] Copying BorgOS system files..."
mkdir -p ${WORK_DIR}/squashfs/opt/borgos
cp -r ${BORGOS_DIR}/core ${WORK_DIR}/squashfs/opt/borgos/
cp -r ${BORGOS_DIR}/webui ${WORK_DIR}/squashfs/opt/borgos/
cp -r ${BORGOS_DIR}/installer ${WORK_DIR}/squashfs/opt/borgos/
cp -r ${BORGOS_DIR}/mcp_servers ${WORK_DIR}/squashfs/opt/borgos/
cp -r ${BORGOS_DIR}/database ${WORK_DIR}/squashfs/opt/borgos/
cp ${BORGOS_DIR}/docker-compose*.yml ${WORK_DIR}/squashfs/opt/borgos/
cp ${BORGOS_DIR}/.env.example ${WORK_DIR}/squashfs/opt/borgos/.env
cp ${BORGOS_DIR}/requirements.txt ${WORK_DIR}/squashfs/opt/borgos/

# Create auto-installer script
echo "[5/8] Creating auto-installer..."
cat > ${WORK_DIR}/squashfs/opt/borgos/auto-install.sh << 'INSTALLER'
#!/bin/bash
# BorgOS Auto-Installer 2025

set -e

echo "================================"
echo " BorgOS Installation Starting"
echo "================================"

# Install Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
fi

# Install Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo "Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Install Python and dependencies
apt-get update
apt-get install -y python3 python3-pip python3-venv git curl wget

# Create BorgOS user
useradd -m -s /bin/bash borgos || true
usermod -aG docker borgos || true

# Copy BorgOS files to installation directory
cp -r /opt/borgos /home/borgos/
chown -R borgos:borgos /home/borgos/borgos

# Switch to borgos user and setup
su - borgos << 'EOF'
cd ~/borgos

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
pip install --upgrade pip
pip install -r requirements.txt

# Start BorgOS services
docker-compose up -d

echo "================================"
echo " BorgOS Installation Complete!"
echo "================================"
echo " Dashboard: http://localhost:8080"
echo " API: http://localhost:8081"
echo " Agent Zero: http://localhost:8085"
echo "================================"
EOF

# Create systemd service
cat > /etc/systemd/system/borgos.service << 'SERVICE'
[Unit]
Description=BorgOS Multi-Agent System
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=borgos
WorkingDirectory=/home/borgos/borgos
ExecStart=/usr/local/bin/docker-compose up
ExecStop=/usr/local/bin/docker-compose down
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable borgos
systemctl start borgos

echo "BorgOS is now running as a system service!"
INSTALLER

chmod +x ${WORK_DIR}/squashfs/opt/borgos/auto-install.sh

# Create boot configuration
echo "[6/8] Configuring boot system..."
mkdir -p ${WORK_DIR}/iso/{boot,isolinux,EFI/boot,live}

# Copy isolinux files
if [[ -d /usr/lib/ISOLINUX ]]; then
    cp /usr/lib/ISOLINUX/isolinux.bin ${WORK_DIR}/iso/isolinux/
elif [[ -d /usr/share/syslinux ]]; then
    cp /usr/share/syslinux/isolinux.bin ${WORK_DIR}/iso/isolinux/
fi

# Copy kernel and initrd from the debootstrap chroot
if [[ "$1" == "--in-docker" ]] || [[ "$OSTYPE" != "darwin"* ]]; then
    if [[ -f ${WORK_DIR}/squashfs/vmlinuz ]]; then
        cp ${WORK_DIR}/squashfs/vmlinuz ${WORK_DIR}/iso/boot/
    elif [[ -f ${WORK_DIR}/squashfs/boot/vmlinuz* ]]; then
        cp ${WORK_DIR}/squashfs/boot/vmlinuz* ${WORK_DIR}/iso/boot/vmlinuz
    fi
    
    if [[ -f ${WORK_DIR}/squashfs/initrd.img ]]; then
        cp ${WORK_DIR}/squashfs/initrd.img ${WORK_DIR}/iso/boot/
    elif [[ -f ${WORK_DIR}/squashfs/boot/initrd.img* ]]; then  
        cp ${WORK_DIR}/squashfs/boot/initrd.img* ${WORK_DIR}/iso/boot/initrd.img
    fi
fi

if [[ -d /usr/lib/syslinux/modules/bios ]]; then
    cp /usr/lib/syslinux/modules/bios/*.c32 ${WORK_DIR}/iso/isolinux/
elif [[ -d /usr/share/syslinux ]]; then
    cp /usr/share/syslinux/*.c32 ${WORK_DIR}/iso/isolinux/ 2>/dev/null || true
fi

# Create isolinux configuration
cat > ${WORK_DIR}/iso/isolinux/isolinux.cfg << 'BOOTCFG'
DEFAULT borgos
PROMPT 1
TIMEOUT 50

LABEL borgos
    MENU LABEL BorgOS 3.0 - Multi-Agent AI Operating System
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initrd.img boot=live quiet splash

LABEL install
    MENU LABEL Install BorgOS to Hard Drive
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initrd.img boot=live quiet splash install

LABEL rescue
    MENU LABEL BorgOS Rescue Mode
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initrd.img boot=live quiet single
BOOTCFG

# Create squashfs filesystem
echo "[7/8] Creating compressed filesystem..."
if [[ "$1" == "--in-docker" ]] || [[ "$OSTYPE" != "darwin"* ]]; then
    mkdir -p ${WORK_DIR}/iso/live
    mksquashfs ${WORK_DIR}/squashfs ${WORK_DIR}/iso/live/filesystem.squashfs -comp xz
fi

# Add version info
cat > ${WORK_DIR}/iso/BorgOS-VERSION << VERSION
BorgOS Multi-Agent Operating System
Version: ${ISO_VERSION}
Build Date: $(date)
Components:
- Agent Zero Integration
- Zenith Coder Integration  
- MCP Server
- ChromaDB Vector Store
- PostgreSQL Database
- Redis Cache
- Docker Orchestration
VERSION

# Create ISO
echo "[8/8] Building ISO image..."
if command -v genisoimage &> /dev/null; then
    genisoimage \
        -o ${OUTPUT_DIR}/${ISO_NAME} \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -J -R -V "BorgOS ${ISO_VERSION}" \
        ${WORK_DIR}/iso
elif command -v xorriso &> /dev/null; then
    xorriso -as mkisofs \
        -o ${OUTPUT_DIR}/${ISO_NAME} \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -J -R -V "BorgOS ${ISO_VERSION}" \
        ${WORK_DIR}/iso
fi

# Clean up
rm -rf ${WORK_DIR}

echo "================================================"
echo " ✅ ISO BUILD COMPLETE!"
echo "================================================"
echo " File: ${OUTPUT_DIR}/${ISO_NAME}"
echo " Size: $(du -h ${OUTPUT_DIR}/${ISO_NAME} | cut -f1)"
echo ""
echo " To write to USB:"
echo " sudo dd if=${OUTPUT_DIR}/${ISO_NAME} of=/dev/sdX bs=4M status=progress"
echo "================================================"