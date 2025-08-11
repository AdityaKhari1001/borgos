#!/bin/bash
# Setup script for Windows WSL2 to build BorgOS ISO

set -euo pipefail

echo "================================================"
echo " BorgOS ISO Builder Setup for Windows WSL2"
echo "================================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if running in WSL
if ! grep -qi microsoft /proc/version; then
    echo -e "${YELLOW}Warning: This doesn't appear to be WSL${NC}"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo -e "${GREEN}[1/6]${NC} Updating package lists..."
sudo apt-get update

echo -e "${GREEN}[2/6]${NC} Installing essential build tools..."
sudo apt-get install -y \
    build-essential \
    debootstrap \
    squashfs-tools \
    xorriso \
    isolinux \
    syslinux \
    syslinux-common \
    genisoimage \
    rsync \
    wget \
    git \
    curl \
    jq \
    zip \
    unzip

echo -e "${GREEN}[3/6]${NC} Checking Docker..."
if command -v docker &> /dev/null; then
    echo "Docker is installed: $(docker --version)"
    
    # Check if Docker daemon is accessible
    if docker ps &> /dev/null; then
        echo -e "${GREEN}Docker is running and accessible${NC}"
    else
        echo -e "${YELLOW}Docker is installed but not accessible${NC}"
        echo "Make sure Docker Desktop is running on Windows"
        echo "And that 'Use the WSL 2 based engine' is enabled in Docker Desktop settings"
    fi
else
    echo -e "${YELLOW}Docker not found in WSL${NC}"
    echo "Please ensure Docker Desktop for Windows is installed and running"
    echo "Download from: https://www.docker.com/products/docker-desktop/"
fi

echo -e "${GREEN}[4/6]${NC} Checking disk space..."
AVAILABLE=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$AVAILABLE" -lt 20 ]; then
    echo -e "${YELLOW}WARNING: Only ${AVAILABLE}GB available. At least 20GB recommended.${NC}"
    echo "You may need to increase WSL disk size or clean up space"
else
    echo -e "${GREEN}Disk space: ${AVAILABLE}GB available ✓${NC}"
fi

echo -e "${GREEN}[5/6]${NC} Setting up build directories..."
mkdir -p iso_output
mkdir -p build-logs
mkdir -p docker-images

echo -e "${GREEN}[6/6]${NC} Creating build scripts..."

# Create optimized build script for WSL
cat > build-iso-wsl.sh << 'BUILDSCRIPT'
#!/bin/bash
# Optimized ISO build script for WSL2

set -euo pipefail

echo "Starting BorgOS ISO build in WSL2..."

# Use Docker if available, otherwise native
if docker ps &> /dev/null; then
    echo "Building with Docker..."
    
    # Build the Docker image
    docker build -f Dockerfile.isobuilder -t borgos-isobuilder:latest .
    
    # Run the build
    docker run --privileged --rm \
        -v "$(pwd):/build" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        borgos-isobuilder:latest \
        bash -c "cd /build && bash build-full-x86-iso.sh"
else
    echo "Docker not available, building natively..."
    echo "This requires sudo access"
    sudo bash build-full-x86-iso.sh
fi

echo "Build complete! Check iso_output/ directory"
BUILDSCRIPT

chmod +x build-iso-wsl.sh

echo ""
echo "================================================"
echo -e "${GREEN} Setup Complete!${NC}"
echo "================================================"
echo ""
echo "To build the FULL ISO (3-5GB), run:"
echo -e "${GREEN}./build-iso-wsl.sh${NC}"
echo ""
echo "The build will take 20-40 minutes depending on your system"
echo ""
echo -e "${YELLOW}IMPORTANT NOTES for Windows users:${NC}"
echo "1. Make sure Docker Desktop is running"
echo "2. Enable 'Use the WSL 2 based engine' in Docker settings"
echo "3. If you get permission errors, run: sudo usermod -aG docker \$USER"
echo "4. Then logout and login again to WSL"
echo ""
echo "================================================"