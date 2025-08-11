#!/bin/bash
# Setup script to run on PC for building BorgOS ISO

set -euo pipefail

echo "================================================"
echo " BorgOS ISO Builder Setup for PC"
echo "================================================"

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo "Cannot detect OS"
    exit 1
fi

echo "Detected: $OS $VER"
echo ""

# Function to install Docker
install_docker() {
    echo "Installing Docker..."
    
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        # Remove old versions
        sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
        
        # Install prerequisites
        sudo apt-get update
        sudo apt-get install -y \
            ca-certificates \
            curl \
            gnupg \
            lsb-release
        
        # Add Docker's official GPG key
        sudo mkdir -m 0755 -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/$OS/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        
        # Set up repository
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
          $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
        # Add user to docker group
        sudo usermod -aG docker $USER
        
        echo "Docker installed. You may need to log out and back in for group changes to take effect."
        
    elif [ "$OS" = "fedora" ] || [ "$OS" = "rhel" ] || [ "$OS" = "centos" ]; then
        sudo dnf -y install dnf-plugins-core
        sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
        sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo systemctl start docker
        sudo systemctl enable docker
        sudo usermod -aG docker $USER
        
    else
        echo "Unsupported OS for automatic Docker installation"
        echo "Please install Docker manually: https://docs.docker.com/engine/install/"
        exit 1
    fi
}

# Function to install build tools
install_build_tools() {
    echo "Installing build tools..."
    
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        sudo apt-get update
        sudo apt-get install -y \
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
            jq \
            qemu-system-x86 \
            qemu-utils
            
    elif [ "$OS" = "fedora" ] || [ "$OS" = "rhel" ] || [ "$OS" = "centos" ]; then
        sudo dnf install -y \
            debootstrap \
            squashfs-tools \
            xorriso \
            syslinux \
            genisoimage \
            rsync \
            wget \
            git \
            curl \
            jq \
            qemu-system-x86
            
    else
        echo "Please install required tools manually"
        exit 1
    fi
}

# Check Docker
echo "Checking Docker..."
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing..."
    install_docker
else
    echo "Docker is installed: $(docker --version)"
fi

# Check if Docker daemon is running
if ! docker ps &> /dev/null; then
    echo "Starting Docker daemon..."
    sudo systemctl start docker
fi

# Install build tools
echo ""
echo "Installing build tools..."
install_build_tools

# Check disk space
echo ""
echo "Checking disk space..."
AVAILABLE=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$AVAILABLE" -lt 20 ]; then
    echo "WARNING: Only ${AVAILABLE}GB available. At least 20GB recommended."
else
    echo "Disk space: ${AVAILABLE}GB available ✓"
fi

# Create directories
echo ""
echo "Creating build directories..."
mkdir -p iso_output
mkdir -p build-logs

echo ""
echo "================================================"
echo " Setup Complete!"
echo "================================================"
echo ""
echo "You can now build the ISO with one of these commands:"
echo ""
echo "1. QUICK BUILD (minimal, ~200MB):"
echo "   ./build-offline-iso.sh"
echo ""
echo "2. FULL BUILD (complete system, 3-5GB):"
echo "   ./build-full-x86-iso.sh"
echo ""
echo "3. BUILD WITH DOCKER (recommended):"
echo "   docker build -f Dockerfile.isobuilder -t borgos-isobuilder ."
echo "   docker run --privileged --rm -v \$(pwd):/build borgos-isobuilder ./build-full-x86-iso.sh"
echo ""
echo "================================================"
echo ""
echo "NOTE: If you just added yourself to docker group,"
echo "      run: newgrp docker"
echo "      or logout and login again"
echo "================================================"