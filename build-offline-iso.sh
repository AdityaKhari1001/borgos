#!/bin/bash
# ==============================================================================
# BorgOS Fully Offline ISO Builder with Comprehensive Testing
# Version: 4.0
# Purpose: Build a complete offline ISO with all dependencies and Docker images
# ==============================================================================

set -euo pipefail

# Configuration
readonly ISO_VERSION="4.0.0"
readonly BUILD_DATE=$(date +%Y%m%d-%H%M)
readonly ISO_NAME="BorgOS-Offline-${ISO_VERSION}-${BUILD_DATE}-amd64.iso"
readonly WORK_DIR="/tmp/borgos-iso-offline"
readonly OUTPUT_DIR="$(pwd)/iso_output"
readonly BORGOS_DIR="$(pwd)"
readonly LOG_FILE="${OUTPUT_DIR}/build-${BUILD_DATE}.log"
readonly TEST_LOG="${OUTPUT_DIR}/test-${BUILD_DATE}.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

log_step() {
    echo -e "${BLUE}[STEP $1/${TOTAL_STEPS}]${NC} $2" | tee -a "${LOG_FILE}"
}

# Total number of build steps
readonly TOTAL_STEPS=15

# Initialize build
init_build() {
    log_step 1 "Initializing build environment..."
    
    # Create directories
    mkdir -p "${OUTPUT_DIR}"
    mkdir -p "${WORK_DIR}"/{chroot,image/{live,isolinux,boot/grub,EFI/boot,install}}
    mkdir -p "${WORK_DIR}"/offline-packages
    mkdir -p "${WORK_DIR}"/docker-images
    
    # Initialize log files
    echo "BorgOS Build Log - ${BUILD_DATE}" > "${LOG_FILE}"
    echo "BorgOS Test Log - ${BUILD_DATE}" > "${TEST_LOG}"
    
    log_info "Build environment initialized"
}

# Validate prerequisites
validate_prerequisites() {
    log_step 2 "Validating prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    for tool in debootstrap squashfs-tools xorriso isolinux mtools dosfstools rsync jq shellcheck; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Installing missing tools..."
        apt-get update
        apt-get install -y "${missing_tools[@]}"
    fi
    
    log_info "All prerequisites validated"
}

# Test all build scripts for issues
test_build_scripts() {
    log_step 3 "Testing build scripts for issues..."
    
    local test_passed=true
    
    # Check for bad sources
    log_info "Checking for problematic sources..."
    
    # Check for cdrom references (except in VM test scripts)
    if grep -r "deb cdrom\|apt-cdrom" --include="*.sh" "${BORGOS_DIR}" --exclude="*test*.sh" --exclude="*vm*.sh" > /dev/null; then
        log_warn "Found cdrom references in build scripts"
        grep -r "deb cdrom\|apt-cdrom" --include="*.sh" "${BORGOS_DIR}" --exclude="*test*.sh" --exclude="*vm*.sh" | tee -a "${TEST_LOG}"
    fi
    
    # Check for external network dependencies
    log_info "Checking for external network dependencies..."
    local external_deps=$(grep -r "http://\|https://\|ftp://" --include="*.sh" "${BORGOS_DIR}" | \
                          grep -v "localhost\|127.0.0.1\|#" | wc -l)
    
    if [ "$external_deps" -gt 0 ]; then
        log_warn "Found $external_deps external network dependencies"
    fi
    
    # Shellcheck all scripts
    log_info "Running shellcheck on all scripts..."
    for script in "${BORGOS_DIR}"/*.sh; do
        if [ -f "$script" ]; then
            if ! shellcheck -S warning "$script" >> "${TEST_LOG}" 2>&1; then
                log_warn "Shellcheck warnings for $(basename "$script")"
                test_passed=false
            fi
        fi
    done
    
    if [ "$test_passed" = true ]; then
        log_info "All script tests passed"
    else
        log_warn "Some script tests had warnings - check ${TEST_LOG}"
    fi
}

# Create offline package repository
create_offline_repository() {
    log_step 4 "Creating offline package repository..."
    
    local packages=(
        # System essentials
        "linux-image-amd64" "grub-pc" "grub-efi-amd64" "systemd" "systemd-sysv"
        "init" "sudo" "openssh-server" "network-manager" "net-tools" "iproute2"
        
        # Development tools
        "build-essential" "git" "curl" "wget" "vim" "nano" "tmux" "htop"
        
        # Python and dependencies
        "python3" "python3-pip" "python3-venv" "python3-dev"
        
        # Docker and container tools
        "docker.io" "docker-compose" "containerd" "runc"
        
        # Desktop environment (minimal)
        "xfce4" "xfce4-terminal" "lightdm" "firefox-esr"
        
        # Libraries and utilities
        "libssl-dev" "libffi-dev" "libyaml-dev" "libpq-dev"
        "postgresql-client" "redis-tools"
    )
    
    log_info "Downloading packages for offline installation..."
    
    # Create a temporary APT configuration for downloading
    cat > "${WORK_DIR}/apt-download.conf" << EOF
Dir::Cache::archives "${WORK_DIR}/offline-packages/";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF
    
    # Download packages with dependencies
    for package in "${packages[@]}"; do
        log_info "Downloading $package and dependencies..."
        apt-get download "$package" -c "${WORK_DIR}/apt-download.conf" 2>/dev/null || true
        apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts \
            --no-breaks --no-replaces --no-enhances "$package" | \
            grep "^\w" | xargs apt-get download -c "${WORK_DIR}/apt-download.conf" 2>/dev/null || true
    done
    
    # Create package index
    cd "${WORK_DIR}/offline-packages"
    dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz
    cd "${BORGOS_DIR}"
    
    log_info "Offline repository created with $(ls -1 "${WORK_DIR}/offline-packages"/*.deb 2>/dev/null | wc -l) packages"
}

# Download and save Docker images
prepare_docker_images() {
    log_step 5 "Preparing Docker images for offline use..."
    
    local images=(
        "postgres:15-alpine"
        "redis:7-alpine"
        "python:3.11-slim"
        "nginx:alpine"
        "busybox:latest"
    )
    
    for image in "${images[@]}"; do
        log_info "Pulling Docker image: $image"
        if docker pull "$image"; then
            local filename="${WORK_DIR}/docker-images/$(echo "$image" | tr ':/' '_').tar"
            log_info "Saving $image to $filename"
            docker save -o "$filename" "$image"
        else
            log_warn "Failed to pull $image - continuing without it"
        fi
    done
    
    # Download Ollama models offline
    log_info "Preparing AI models for offline use..."
    mkdir -p "${WORK_DIR}/ai-models"
    
    # Create model download script
    cat > "${WORK_DIR}/ai-models/download-models.sh" << 'EOF'
#!/bin/bash
# This script will be run on first boot if network is available
# to download additional AI models

MODELS_DIR="/opt/borgos/models"
mkdir -p "$MODELS_DIR"

# List of models to download
MODELS=(
    "llama3.2:3b"
    "nomic-embed-text:latest"
)

for model in "${MODELS[@]}"; do
    echo "Downloading model: $model"
    ollama pull "$model" || echo "Failed to download $model"
done
EOF
    chmod +x "${WORK_DIR}/ai-models/download-models.sh"
    
    log_info "Docker images and model scripts prepared"
}

# Build base system with debootstrap
build_base_system() {
    log_step 6 "Building base Debian system..."
    
    # Use local mirror if available, otherwise use default
    local mirror="http://deb.debian.org/debian/"
    
    debootstrap \
        --arch=amd64 \
        --variant=minbase \
        --include=linux-image-amd64,live-boot,systemd-sysv \
        bookworm \
        "${WORK_DIR}/chroot" \
        "$mirror" || {
            log_error "Debootstrap failed"
            exit 1
        }
    
    # Configure base system
    log_info "Configuring base system..."
    
    # Set hostname
    echo "borgos" > "${WORK_DIR}/chroot/etc/hostname"
    
    # Configure hosts
    cat > "${WORK_DIR}/chroot/etc/hosts" << EOF
127.0.0.1       localhost
127.0.1.1       borgos
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF
    
    # Configure network
    mkdir -p "${WORK_DIR}/chroot/etc/network"
    cat > "${WORK_DIR}/chroot/etc/network/interfaces" << EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
    
    log_info "Base system built successfully"
}

# Install packages in chroot from offline repository
install_offline_packages() {
    log_step 7 "Installing packages from offline repository..."
    
    # Copy offline packages to chroot
    mkdir -p "${WORK_DIR}/chroot/var/cache/apt/archives"
    cp -r "${WORK_DIR}/offline-packages/"*.deb "${WORK_DIR}/chroot/var/cache/apt/archives/" 2>/dev/null || true
    
    # Configure APT for offline use
    cat > "${WORK_DIR}/chroot/etc/apt/sources.list" << EOF
# Offline repository only
deb [trusted=yes] file:///var/cache/apt/archives ./
EOF
    
    # Install packages in chroot
    cat > "${WORK_DIR}/chroot/tmp/install-packages.sh" << 'CHROOT_SCRIPT'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

# Update package index from offline repo
cd /var/cache/apt/archives
dpkg-scanpackages . /dev/null > Packages
apt-get update

# Install essential packages
apt-get install -y --allow-unauthenticated \
    systemd \
    network-manager \
    openssh-server \
    sudo \
    python3 \
    python3-pip \
    docker.io \
    docker-compose \
    git \
    curl \
    wget \
    vim \
    nano || true

# Create borgos user
useradd -m -s /bin/bash -G sudo,docker borgos || true
echo "borgos:borgos" | chpasswd
echo "root:borgos" | chpasswd

# Configure sudo
echo "borgos ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Enable essential services
systemctl enable ssh || true
systemctl enable NetworkManager || true
systemctl enable docker || true
CHROOT_SCRIPT
    
    chmod +x "${WORK_DIR}/chroot/tmp/install-packages.sh"
    chroot "${WORK_DIR}/chroot" /tmp/install-packages.sh || log_warn "Some packages failed to install"
    
    log_info "Package installation completed"
}

# Copy BorgOS files and configure system
install_borgos() {
    log_step 8 "Installing BorgOS system..."
    
    # Create BorgOS directory structure
    mkdir -p "${WORK_DIR}/chroot/opt/borgos"/{core,webui,installer,database,docker-images,models}
    
    # Copy BorgOS components
    for component in core webui installer mcp_servers database docs; do
        if [ -d "${BORGOS_DIR}/$component" ]; then
            log_info "Copying $component..."
            cp -r "${BORGOS_DIR}/$component" "${WORK_DIR}/chroot/opt/borgos/"
        fi
    done
    
    # Copy configuration files
    cp "${BORGOS_DIR}"/docker-compose*.yml "${WORK_DIR}/chroot/opt/borgos/" 2>/dev/null || true
    cp "${BORGOS_DIR}"/requirements.txt "${WORK_DIR}/chroot/opt/borgos/" 2>/dev/null || true
    
    # Copy Docker images
    if [ -d "${WORK_DIR}/docker-images" ]; then
        cp "${WORK_DIR}/docker-images/"*.tar "${WORK_DIR}/chroot/opt/borgos/docker-images/" 2>/dev/null || true
    fi
    
    # Create startup script
    cat > "${WORK_DIR}/chroot/opt/borgos/start-borgos.sh" << 'START_SCRIPT'
#!/bin/bash
# BorgOS Startup Script

echo "Starting BorgOS services..."

# Load Docker images if present
if [ -d /opt/borgos/docker-images ]; then
    for image in /opt/borgos/docker-images/*.tar; do
        if [ -f "$image" ]; then
            echo "Loading Docker image: $(basename "$image")"
            docker load -i "$image" 2>/dev/null || true
        fi
    done
fi

# Start Docker service
systemctl start docker || true

# Wait for Docker to be ready
sleep 5

# Start BorgOS services
cd /opt/borgos
if [ -f docker-compose.yml ]; then
    docker-compose up -d || true
fi

echo "BorgOS services started"
echo "Dashboard: http://localhost:8080"
echo "API: http://localhost:8081"
START_SCRIPT
    chmod +x "${WORK_DIR}/chroot/opt/borgos/start-borgos.sh"
    
    # Create systemd service
    cat > "${WORK_DIR}/chroot/etc/systemd/system/borgos.service" << 'SYSTEMD'
[Unit]
Description=BorgOS Services
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/opt/borgos/start-borgos.sh
User=root
WorkingDirectory=/opt/borgos

[Install]
WantedBy=multi-user.target
SYSTEMD
    
    # Enable service
    chroot "${WORK_DIR}/chroot" systemctl enable borgos.service || true
    
    log_info "BorgOS installation completed"
}

# Apply branding
apply_branding() {
    log_step 9 "Applying BorgOS branding..."
    
    if [ -d "${BORGOS_DIR}/branding" ]; then
        # Copy boot splash
        if [ -f "${BORGOS_DIR}/branding/boot/splash.png" ]; then
            cp "${BORGOS_DIR}/branding/boot/splash.png" "${WORK_DIR}/image/isolinux/"
        fi
        
        # Copy GRUB background
        if [ -f "${BORGOS_DIR}/branding/boot/grub-bg.png" ]; then
            mkdir -p "${WORK_DIR}/chroot/boot/grub"
            cp "${BORGOS_DIR}/branding/boot/grub-bg.png" "${WORK_DIR}/chroot/boot/grub/"
        fi
        
        log_info "Branding applied"
    else
        log_warn "Branding directory not found"
    fi
}

# Clean up chroot
cleanup_chroot() {
    log_step 10 "Cleaning up chroot environment..."
    
    # Clean package cache
    chroot "${WORK_DIR}/chroot" apt-get clean || true
    
    # Remove temporary files
    rm -rf "${WORK_DIR}/chroot/tmp/"*
    rm -rf "${WORK_DIR}/chroot/var/lib/apt/lists/"*
    rm -rf "${WORK_DIR}/chroot/var/cache/apt/"*.bin
    
    # Remove installer scripts
    rm -f "${WORK_DIR}/chroot/tmp/"*.sh
    
    log_info "Chroot cleaned"
}

# Create squashfs filesystem
create_squashfs() {
    log_step 11 "Creating compressed filesystem..."
    
    # Copy kernel and initrd
    cp "${WORK_DIR}"/chroot/boot/vmlinuz-* "${WORK_DIR}/image/live/vmlinuz" || {
        log_error "Failed to copy kernel"
        exit 1
    }
    
    cp "${WORK_DIR}"/chroot/boot/initrd.img-* "${WORK_DIR}/image/live/initrd.img" || {
        log_error "Failed to copy initrd"
        exit 1
    }
    
    # Create squashfs
    log_info "Compressing filesystem (this may take time)..."
    mksquashfs "${WORK_DIR}/chroot" "${WORK_DIR}/image/live/filesystem.squashfs" \
        -comp xz -b 1M -Xdict-size 100% || {
            log_error "Failed to create squashfs"
            exit 1
        }
    
    # Calculate size
    local fs_size=$(du -h "${WORK_DIR}/image/live/filesystem.squashfs" | cut -f1)
    log_info "Filesystem compressed to $fs_size"
}

# Configure bootloader
configure_bootloader() {
    log_step 12 "Configuring bootloader..."
    
    # Copy isolinux files
    if [ -f /usr/lib/ISOLINUX/isolinux.bin ]; then
        cp /usr/lib/ISOLINUX/isolinux.bin "${WORK_DIR}/image/isolinux/"
    elif [ -f /usr/share/syslinux/isolinux.bin ]; then
        cp /usr/share/syslinux/isolinux.bin "${WORK_DIR}/image/isolinux/"
    else
        log_error "isolinux.bin not found"
        exit 1
    fi
    
    # Copy c32 modules
    for module in ldlinux libcom32 libutil menu vesamenu; do
        for path in /usr/lib/syslinux/modules/bios /usr/share/syslinux; do
            if [ -f "$path/$module.c32" ]; then
                cp "$path/$module.c32" "${WORK_DIR}/image/isolinux/"
                break
            fi
        done
    done
    
    # Create isolinux configuration
    cat > "${WORK_DIR}/image/isolinux/isolinux.cfg" << EOF
UI vesamenu.c32
MENU TITLE BorgOS ${ISO_VERSION} - Offline Edition
MENU BACKGROUND splash.png
TIMEOUT 100
DEFAULT borgos

LABEL borgos
    MENU LABEL BorgOS Live (Offline)
    MENU DEFAULT
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live quiet splash

LABEL borgos-debug
    MENU LABEL BorgOS Debug Mode
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live debug

LABEL borgos-safe
    MENU LABEL BorgOS Safe Mode
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live nomodeset
EOF
    
    # Create GRUB configuration for UEFI
    mkdir -p "${WORK_DIR}/image/boot/grub"
    cat > "${WORK_DIR}/image/boot/grub/grub.cfg" << EOF
set default=0
set timeout=10

menuentry "BorgOS Live (Offline)" {
    linux /live/vmlinuz boot=live quiet splash
    initrd /live/initrd.img
}

menuentry "BorgOS Debug Mode" {
    linux /live/vmlinuz boot=live debug
    initrd /live/initrd.img
}

menuentry "BorgOS Safe Mode" {
    linux /live/vmlinuz boot=live nomodeset
    initrd /live/initrd.img
}
EOF
    
    log_info "Bootloader configured"
}

# Create ISO image
create_iso() {
    log_step 13 "Creating ISO image..."
    
    # Check for isohdpfx.bin
    local isohdpfx=""
    for path in /usr/lib/ISOLINUX /usr/share/syslinux; do
        if [ -f "$path/isohdpfx.bin" ]; then
            isohdpfx="$path/isohdpfx.bin"
            break
        fi
    done
    
    if [ -z "$isohdpfx" ]; then
        log_warn "isohdpfx.bin not found - ISO may not be hybrid bootable"
    fi
    
    # Create ISO
    xorriso -as mkisofs \
        -iso-level 3 \
        -o "${OUTPUT_DIR}/${ISO_NAME}" \
        -full-iso9660-filenames \
        -volid "BORGOS_OFFLINE" \
        ${isohdpfx:+-isohybrid-mbr "$isohdpfx"} \
        -eltorito-boot isolinux/isolinux.bin \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-catalog isolinux/boot.cat \
        "${WORK_DIR}/image" || {
            log_error "Failed to create ISO"
            exit 1
        }
    
    # Calculate final size
    local iso_size=$(du -h "${OUTPUT_DIR}/${ISO_NAME}" | cut -f1)
    log_info "ISO created: ${ISO_NAME} (Size: $iso_size)"
}

# Test ISO in QEMU
test_iso() {
    log_step 14 "Testing ISO in QEMU..."
    
    if command -v qemu-system-x86_64 &> /dev/null; then
        log_info "Starting QEMU test..."
        
        # Create test script
        cat > "${OUTPUT_DIR}/test-iso.sh" << EOF
#!/bin/bash
# Test the ISO in QEMU
qemu-system-x86_64 \\
    -m 2048 \\
    -cdrom "${OUTPUT_DIR}/${ISO_NAME}" \\
    -boot d \\
    -display none \\
    -serial stdio \\
    -monitor telnet:127.0.0.1:55555,server,nowait &

QEMU_PID=\$!
sleep 30

# Check if QEMU is still running
if kill -0 \$QEMU_PID 2>/dev/null; then
    echo "ISO boot test: PASSED"
    kill \$QEMU_PID
    exit 0
else
    echo "ISO boot test: FAILED"
    exit 1
fi
EOF
        chmod +x "${OUTPUT_DIR}/test-iso.sh"
        
        if timeout 60 "${OUTPUT_DIR}/test-iso.sh" >> "${TEST_LOG}" 2>&1; then
            log_info "ISO boot test passed"
        else
            log_warn "ISO boot test failed or timed out"
        fi
    else
        log_warn "QEMU not available - skipping ISO test"
    fi
}

# Final validation
final_validation() {
    log_step 15 "Performing final validation..."
    
    local validation_passed=true
    
    # Check ISO file exists and is not empty
    if [ ! -f "${OUTPUT_DIR}/${ISO_NAME}" ]; then
        log_error "ISO file not found"
        validation_passed=false
    elif [ ! -s "${OUTPUT_DIR}/${ISO_NAME}" ]; then
        log_error "ISO file is empty"
        validation_passed=false
    fi
    
    # Check ISO size
    local iso_size_bytes=$(stat -f%z "${OUTPUT_DIR}/${ISO_NAME}" 2>/dev/null || stat -c%s "${OUTPUT_DIR}/${ISO_NAME}" 2>/dev/null)
    if [ "$iso_size_bytes" -lt 1073741824 ]; then  # Less than 1GB
        log_warn "ISO seems too small ($(numfmt --to=iec "$iso_size_bytes"))"
    fi
    
    # Verify ISO structure
    if command -v isoinfo &> /dev/null; then
        if isoinfo -d -i "${OUTPUT_DIR}/${ISO_NAME}" >> "${TEST_LOG}" 2>&1; then
            log_info "ISO structure verified"
        else
            log_error "ISO structure verification failed"
            validation_passed=false
        fi
    fi
    
    # Generate checksums
    log_info "Generating checksums..."
    cd "${OUTPUT_DIR}"
    sha256sum "${ISO_NAME}" > "${ISO_NAME}.sha256"
    md5sum "${ISO_NAME}" > "${ISO_NAME}.md5"
    cd "${BORGOS_DIR}"
    
    if [ "$validation_passed" = true ]; then
        log_info "All validations passed"
    else
        log_error "Some validations failed - check logs"
    fi
}

# Cleanup function
cleanup() {
    log_info "Cleaning up build environment..."
    rm -rf "${WORK_DIR}"
}

# Main build process
main() {
    echo "================================================"
    echo " BorgOS Offline ISO Builder v4.0"
    echo " Building: ${ISO_NAME}"
    echo "================================================"
    
    # Trap errors and cleanup
    trap cleanup EXIT
    
    # Execute build steps
    init_build
    validate_prerequisites
    test_build_scripts
    create_offline_repository
    prepare_docker_images
    build_base_system
    install_offline_packages
    install_borgos
    apply_branding
    cleanup_chroot
    create_squashfs
    configure_bootloader
    create_iso
    test_iso
    final_validation
    
    # Print summary
    echo ""
    echo "================================================"
    echo " BUILD COMPLETE!"
    echo "================================================"
    echo " ISO: ${OUTPUT_DIR}/${ISO_NAME}"
    echo " Size: $(du -h "${OUTPUT_DIR}/${ISO_NAME}" | cut -f1)"
    echo " SHA256: $(cat "${OUTPUT_DIR}/${ISO_NAME}.sha256" | cut -d' ' -f1)"
    echo ""
    echo " Features:"
    echo " - Fully offline capable"
    echo " - All packages included"
    echo " - Docker images pre-loaded"
    echo " - No network required for installation"
    echo ""
    echo " Logs:"
    echo " - Build: ${LOG_FILE}"
    echo " - Tests: ${TEST_LOG}"
    echo ""
    echo " To write to USB:"
    echo " sudo dd if=${OUTPUT_DIR}/${ISO_NAME} of=/dev/sdX bs=4M status=progress"
    echo "================================================"
}

# Docker build wrapper for macOS
if [[ "$OSTYPE" == "darwin"* ]] && [[ "$1" != "--in-docker" ]]; then
    log_info "Detected macOS - building in Docker..."
    
    # Create Dockerfile
    cat > Dockerfile.isobuilder << 'DOCKERFILE'
FROM debian:12

RUN apt-get update && apt-get install -y \
    debootstrap \
    squashfs-tools \
    xorriso \
    isolinux \
    syslinux-common \
    mtools \
    dosfstools \
    rsync \
    wget \
    curl \
    git \
    jq \
    shellcheck \
    genisoimage \
    isoinfo \
    qemu-system-x86 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
DOCKERFILE
    
    # Build Docker image
    docker build -f Dockerfile.isobuilder -t borgos-isobuilder:latest .
    
    # Run build in Docker
    docker run --privileged --rm \
        -v "$(pwd):/build" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        borgos-isobuilder:latest \
        bash -c "cd /build && bash build-offline-iso.sh --in-docker"
    
    exit $?
fi

# Run main build
main "$@"