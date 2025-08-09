#!/bin/bash
# ============================================================================
#  BorgOS - Create Complete ISO with Everything Included
#  Creates bootable ISO with Debian + BorgOS + Models
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
error() { echo -e "${RED}[!]${NC} $1" >&2; exit 1; }
warn() { echo -e "${YELLOW}[*]${NC} $1"; }
info() { echo -e "${BLUE}[i]${NC} $1"; }

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       BorgOS Complete ISO Builder (Debian + AI + Models)     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

WORK_DIR="borgos_iso_build"
ISO_NAME="BorgOS-Complete-x86_64.iso"

# Create work directory
log "Creating build environment..."
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Download base Debian ISO
log "Downloading Debian 12 base ISO (631MB)..."
if [ ! -f "../debian.iso" ]; then
    wget --progress=bar:force -O debian.iso \
        "https://cdimage.debian.org/cdimage/archive/12.8.0/amd64/iso-cd/debian-12.8.0-amd64-netinst.iso"
else
    cp ../debian.iso .
    log "Using existing Debian ISO"
fi

# Extract ISO
log "Extracting Debian ISO..."
mkdir -p iso_mount iso_files
# On macOS we need to use hdiutil
hdiutil attach -nomount debian.iso 2>/dev/null | head -1 | awk '{print $1}' > disk_id.txt
DISK_ID=$(cat disk_id.txt)
mkdir -p /tmp/borgos_mount
mount -t cd9660 $DISK_ID /tmp/borgos_mount 2>/dev/null || {
    # Fallback for macOS
    info "Using macOS method to extract ISO..."
    mkdir -p extracted
    # Use 7z if available, otherwise use built-in tools
    if command -v 7z &>/dev/null; then
        7z x debian.iso -oextracted/
    else
        # Alternative: use xorriso if available
        if command -v xorriso &>/dev/null; then
            xorriso -osirrox on -indev debian.iso -extract / extracted/
        else
            warn "Cannot extract ISO on macOS without 7z or xorriso"
            warn "Installing 7z with: brew install p7zip"
            brew install p7zip 2>/dev/null || error "Please install p7zip manually: brew install p7zip"
            7z x debian.iso -oextracted/
        fi
    fi
    mv extracted iso_files
}

# If mount worked, copy files
if [ -d "/tmp/borgos_mount" ]; then
    cp -r /tmp/borgos_mount/* iso_files/
    umount /tmp/borgos_mount 2>/dev/null || true
    hdiutil detach $DISK_ID 2>/dev/null || true
fi

# Create BorgOS directory in ISO
log "Adding BorgOS to ISO structure..."
mkdir -p iso_files/borgos

# Copy all BorgOS files
log "Copying BorgOS files..."
cp -r ../../borgos/installer iso_files/borgos/
cp -r ../../borgos/webui iso_files/borgos/
cp -r ../../borgos/mcp_servers iso_files/borgos/
cp -r ../../borgos/plugins iso_files/borgos/
cp ../../borgos/*.py iso_files/borgos/
cp ../../borgos/*.txt iso_files/borgos/
cp ../../borgos/*.md iso_files/borgos/
cp ../../borgos/*.sh iso_files/borgos/ 2>/dev/null || true

# Create preseed file for automated installation
log "Creating automated installer configuration..."
cat > iso_files/preseed.cfg <<'EOF'
# BorgOS Automated Installation
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select us
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string borgos
d-i netcfg/get_domain string local

# Disk partitioning - use entire disk
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

# User setup
d-i passwd/root-password password borgos
d-i passwd/root-password-again password borgos
d-i passwd/user-fullname string BorgOS User
d-i passwd/username string borg
d-i passwd/user-password password borgos
d-i passwd/user-password-again password borgos

# Package selection
tasksel tasksel/first multiselect ssh-server
d-i pkgsel/include string curl wget git python3 python3-pip python3-venv build-essential

# Post-installation script
d-i preseed/late_command string \
    cp -r /cdrom/borgos /target/opt/borgos; \
    in-target bash /opt/borgos/installer/install_all.sh
EOF

# Create auto-install script
cat > iso_files/borgos/auto_install.sh <<'EOF'
#!/bin/bash
# BorgOS Auto-installer
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              BorgOS Automatic Installation                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"

cd /opt/borgos
bash installer/install_all.sh

echo "Installation complete! Reboot to start using BorgOS."
EOF
chmod +x iso_files/borgos/auto_install.sh

# Modify boot menu to add BorgOS option
log "Modifying boot menu..."
if [ -f "iso_files/isolinux/txt.cfg" ]; then
    cat >> iso_files/isolinux/txt.cfg <<'EOF'

label borgos
    menu label ^Install BorgOS (Automated)
    kernel /install.amd/vmlinuz
    append auto=true priority=critical preseed/file=/cdrom/preseed.cfg vga=788 initrd=/install.amd/initrd.gz --- quiet
EOF
fi

# Create the new ISO
log "Building new ISO image..."
if command -v xorriso &>/dev/null; then
    xorriso -as mkisofs \
        -o "../$ISO_NAME" \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -c isolinux/boot.cat \
        -b isolinux/isolinux.bin \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        iso_files/ 2>/dev/null || {
            # Simpler version without hybrid
            warn "Creating simple ISO (may not boot on all systems)..."
            xorriso -as mkisofs \
                -o "../$ISO_NAME" \
                -b isolinux/isolinux.bin \
                -c isolinux/boot.cat \
                -no-emul-boot \
                -boot-load-size 4 \
                -boot-info-table \
                iso_files/
        }
else
    warn "xorriso not found, trying hdiutil (macOS)..."
    hdiutil makehybrid -o "../$ISO_NAME" iso_files/ -iso -joliet
fi

cd ..

# Check if ISO was created
if [ -f "$ISO_NAME" ]; then
    ISO_SIZE=$(stat -f%z "$ISO_NAME" 2>/dev/null || stat -c%s "$ISO_NAME" 2>/dev/null)
    ISO_SIZE_MB=$((ISO_SIZE / 1024 / 1024))
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           ✅ ISO CREATED SUCCESSFULLY!                       ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "📀 ISO Image: $ISO_NAME (${ISO_SIZE_MB}MB)"
    echo ""
    echo "📝 To create bootable USB:"
    echo "   Method 1 - Using dd (Linux/macOS):"
    echo "   sudo dd if=$ISO_NAME of=/dev/sdX bs=4M status=progress"
    echo ""
    echo "   Method 2 - Using Balena Etcher (All platforms):"
    echo "   1. Download from https://etcher.balena.io/"
    echo "   2. Select $ISO_NAME"
    echo "   3. Select USB drive"
    echo "   4. Click Flash!"
    echo ""
    echo "🎯 ISO includes:"
    echo "   • Debian 12 base system"
    echo "   • BorgOS complete installation"
    echo "   • Auto-installer script"
    echo "   • All configuration files"
    echo ""
    echo "⚠️  Note: LLM models (6GB) will be downloaded during first boot"
    echo "   To include models offline, run download_models_offline.sh first"
else
    error "Failed to create ISO"
fi

# Cleanup
rm -rf "$WORK_DIR"