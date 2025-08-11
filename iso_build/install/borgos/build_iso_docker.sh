#!/bin/bash
# ============================================================================
#  BorgOS ISO Builder using Docker (for macOS/Windows)
# ============================================================================

set -e

echo "Building BorgOS ISO in Docker container..."

# Create Dockerfile for build environment
cat > Dockerfile.borgos-builder <<'EOF'
FROM debian:12

RUN apt-get update && apt-get install -y \
    live-build \
    debootstrap \
    squashfs-tools \
    xorriso \
    syslinux \
    isolinux \
    wget \
    curl \
    git \
    ca-certificates \
    sudo

WORKDIR /build
COPY . /build/

# Make builder executable
RUN chmod +x iso-builder/borgos_iso_builder.sh

# Run as root for live-build
USER root

CMD ["bash", "iso-builder/borgos_iso_builder.sh"]
EOF

# Build Docker image
docker build -f Dockerfile.borgos-builder -t borgos-builder .

# Run builder in container
docker run --rm \
    --privileged \
    -v $(pwd)/out:/build/out \
    -e ISO_TAG="borgos-$(date +%Y%m%d)" \
    borgos-builder

echo "ISO should be available in ./out/ISO/"

# Clean up
rm Dockerfile.borgos-builder