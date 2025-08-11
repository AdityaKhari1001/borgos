#!/bin/bash
# Build x86_64 ISO on ARM64 (Apple Silicon) using QEMU emulation

set -euo pipefail

echo "============================================"
echo " BorgOS x86_64 ISO Builder for ARM64 Host"
echo "============================================"

# Check if we're on ARM64
if [[ "$(uname -m)" != "arm64" && "$(uname -m)" != "aarch64" ]]; then
    echo "This script is for ARM64 hosts only"
    exit 1
fi

# Create Dockerfile with QEMU support
cat > Dockerfile.x86-builder << 'EOF'
FROM --platform=linux/amd64 debian:12

# This forces x86_64 emulation on ARM64
RUN dpkg --print-architecture && \
    apt-get update && \
    apt-get install -y \
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
    mtools \
    dosfstools \
    jq \
    dpkg-dev \
    apt-utils \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
EOF

echo "Building x86_64 Docker image (this will use QEMU emulation)..."
docker buildx create --use --name x86-builder || true
docker buildx build --platform linux/amd64 -f Dockerfile.x86-builder -t borgos-x86-builder:latest --load .

echo "Starting x86_64 ISO build in emulated container..."
echo "WARNING: This will be SLOW due to emulation!"

docker run --platform linux/amd64 --privileged --rm \
    -v "$(pwd):/build" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    borgos-x86-builder:latest \
    bash -c "cd /build && bash build-full-x86-iso.sh"