#!/bin/bash
# Quick BorgOS ISO Builder - Creates installer ISO without full live system
# Uses existing Docker images for faster build

set -e

ISO_VERSION="3.0.0"
BUILD_DATE=$(date +%Y%m%d-%H%M)
ISO_NAME="BorgOS-Installer-${ISO_VERSION}-${BUILD_DATE}.iso"
OUTPUT_DIR="$(pwd)/iso_output"

echo "================================================"
echo " BorgOS Quick ISO Builder - v${ISO_VERSION}"
echo "================================================"
echo " This creates an installer ISO (not live system)"
echo " Output: ${OUTPUT_DIR}/${ISO_NAME}"
echo "================================================"

# Create directory structure
mkdir -p iso_build/{isolinux,install,scripts}
mkdir -p ${OUTPUT_DIR}

# Create installer script
cat > iso_build/install/install.sh << 'EOF'
#!/bin/bash
# BorgOS Installer Script

echo "================================"
echo " BorgOS ${ISO_VERSION} Installer"
echo "================================"

# Function to install Docker
install_docker() {
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
}

# Function to install Docker Compose
install_docker_compose() {
    echo "Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
}

# Check for Docker
if ! command -v docker &> /dev/null; then
    install_docker
fi

# Check for Docker Compose
if ! command -v docker-compose &> /dev/null; then
    install_docker_compose
fi

# Install base packages
apt-get update
apt-get install -y python3 python3-pip git curl wget

# Clone BorgOS from GitHub
echo "Downloading BorgOS..."
git clone https://github.com/vizi2000/borgos /opt/borgos
cd /opt/borgos

# Create .env from example
cp .env.example .env

# Start BorgOS services
echo "Starting BorgOS services..."
docker-compose up -d

echo "================================"
echo " BorgOS Installation Complete!"
echo "================================"
echo " Dashboard: http://localhost:8080"
echo " API: http://localhost:8081"
echo " Agent Zero: http://localhost:8085"
echo "================================"
EOF

chmod +x iso_build/install/install.sh

# Copy all BorgOS files
echo "[1/4] Copying BorgOS files..."
rsync -av --exclude='.git' --exclude='*.iso' --exclude='iso_*' \
    --exclude='*.dmg' --exclude='*.log' \
    . iso_build/install/borgos/

# Create minimal bootloader config
echo "[2/4] Creating boot configuration..."
cat > iso_build/isolinux/isolinux.cfg << 'BOOTCFG'
DEFAULT install
PROMPT 1
TIMEOUT 100

LABEL install
    MENU LABEL Install BorgOS ${ISO_VERSION}
    KERNEL /install/vmlinuz
    APPEND initrd=/install/initrd.gz auto=true priority=critical

LABEL expert
    MENU LABEL Expert Install
    KERNEL /install/vmlinuz
    APPEND initrd=/install/initrd.gz priority=low
BOOTCFG

# Create autorun for Windows
cat > iso_build/autorun.inf << 'AUTORUN'
[autorun]
open=install\install.bat
icon=borgos.ico
label=BorgOS Installer
AUTORUN

# Create Windows batch installer
cat > iso_build/install/install.bat << 'WINBAT'
@echo off
echo ================================
echo  BorgOS Installer for Windows
echo ================================
echo.
echo This will install BorgOS using WSL2
echo.
pause
wsl --install
echo Please restart your computer and run this installer again.
pause
WINBAT

# Create README
cat > iso_build/README.txt << 'README'
BorgOS Multi-Agent Operating System
Version: ${ISO_VERSION}
====================================

INSTALLATION INSTRUCTIONS:

For Linux:
1. Boot from this ISO
2. Select "Install BorgOS"
3. Follow the prompts

For Windows:
1. Enable WSL2 first
2. Run install/install.bat
3. Follow the prompts

For Manual Installation:
1. Copy the borgos folder to your system
2. Run: cd borgos && ./installer/install.sh

REQUIREMENTS:
- 64-bit processor
- 8GB RAM minimum (16GB recommended)
- 50GB free disk space
- Internet connection for downloading Docker images

DOCUMENTATION:
See docs/ folder or visit:
https://github.com/vizi2000/borgos

====================================
README

# Create ISO using genisoimage (works on macOS via Docker)
echo "[3/4] Building ISO image..."
if command -v genisoimage &> /dev/null; then
    genisoimage -o ${OUTPUT_DIR}/${ISO_NAME} \
        -V "BorgOS_${ISO_VERSION}" \
        -J -R -l \
        iso_build/
elif command -v mkisofs &> /dev/null; then
    mkisofs -o ${OUTPUT_DIR}/${ISO_NAME} \
        -V "BorgOS_${ISO_VERSION}" \
        -J -R -l \
        iso_build/
else
    # Use Docker to create ISO
    docker run --rm -v "$(pwd):/work" debian:12 bash -c "
        apt-get update && apt-get install -y genisoimage
        cd /work
        genisoimage -o ${OUTPUT_DIR}/${ISO_NAME} \
            -V 'BorgOS_${ISO_VERSION}' \
            -J -R -l \
            iso_build/
    "
fi

# Clean up
echo "[4/4] Cleaning up..."
rm -rf iso_build

# Display result
if [[ -f ${OUTPUT_DIR}/${ISO_NAME} ]]; then
    echo "================================================"
    echo " ✅ ISO BUILD COMPLETE!"
    echo "================================================"
    echo " File: ${OUTPUT_DIR}/${ISO_NAME}"
    echo " Size: $(du -h ${OUTPUT_DIR}/${ISO_NAME} | cut -f1)"
    echo ""
    echo " This is an installer ISO that includes:"
    echo " - BorgOS source code"
    echo " - Installation scripts"
    echo " - Documentation"
    echo ""
    echo " To use:"
    echo " 1. Burn to CD/DVD or write to USB"
    echo " 2. Boot from media"
    echo " 3. Run installer"
    echo "================================================"
else
    echo "❌ ISO build failed!"
    exit 1
fi