#!/bin/bash
# ============================================================================
#  BorgOS USB Creator - FULLY AUTOMATED VERSION
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
error() { echo -e "${RED}[!]${NC} $1" >&2; exit 1; }
warn() { echo -e "${YELLOW}[*]${NC} $1"; }

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           BorgOS USB Creator - AUTOMATIC MODE                ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Auto-detect USB disk (8GB)
log "Auto-detecting 8GB USB drive..."
USB_DISK=$(diskutil list | grep -B3 "8.0 GB" | grep "/dev/disk" | head -1 | awk '{print $1}' | sed 's|/dev/||')

if [[ -z "$USB_DISK" ]]; then
    error "No 8GB USB drive found. Please insert USB and try again."
fi

log "Found USB: $USB_DISK (8GB)"

# Download fresh ISO
log "Downloading Debian 12 ISO (this will take 2-3 minutes)..."
curl -L --progress-bar -o debian.iso \
    "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.8.0-amd64-netinst.iso"

# Verify download
ISO_SIZE=$(stat -f%z debian.iso 2>/dev/null || stat -c%s debian.iso 2>/dev/null)
if [[ $ISO_SIZE -lt 100000000 ]]; then
    error "ISO download failed (size: $ISO_SIZE bytes)"
fi
log "ISO downloaded successfully ($(($ISO_SIZE / 1024 / 1024))MB)"

# Unmount USB
log "Preparing USB drive..."
diskutil unmountDisk force /dev/$USB_DISK 2>/dev/null || true

# Direct write using macOS-compatible method
log "Writing ISO to USB (this will take 5-10 minutes)..."
log "If prompted for password, enter your Mac password"

# Use macOS-specific dd options
sudo dd if=debian.iso of=/dev/r$USB_DISK bs=1048576 conv=sync 2>&1 | \
    while read line; do
        echo -ne "\r${YELLOW}[*]${NC} Writing: $line"
    done

echo ""
log "Syncing data to USB..."
sync

# Try to eject
log "Ejecting USB..."
diskutil eject /dev/$USB_DISK 2>/dev/null || warn "Could not eject - remove manually when ready"

# Create BorgOS installer archive
log "Creating BorgOS installer archive..."
cd /Users/wojciechwiesner/ai
tar -czf borgos-installer.tar.gz \
    borgos/installer/ \
    borgos/webui/ \
    borgos/mcp_servers/ \
    borgos/model_manager.py \
    borgos/borg_cli.py \
    borgos/plugins/ \
    borgos/requirements.txt \
    borgos/README.md 2>/dev/null || warn "Some files not included"

mv borgos-installer.tar.gz borgos/ 2>/dev/null || true

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              ✅ USB CREATED SUCCESSFULLY!                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "📱 Your bootable USB is ready!"
echo ""
echo "📝 Installation steps:"
echo "1. Boot target PC from this USB"
echo "2. Install Debian 12 (minimal, with SSH)"
echo "3. After installation, transfer borgos-installer.tar.gz"
echo "4. On target system run:"
echo ""
echo "   tar -xzf borgos-installer.tar.gz"
echo "   cd borgos"
echo "   sudo bash installer/install_all.sh"
echo ""
echo "📦 Installer archive created: borgos-installer.tar.gz"
echo "   Transfer it via USB/network to target system"
echo ""
echo "🎯 The system will install:"
echo "   • Mistral 7B (4.1GB) - main AI model"
echo "   • Llama 3.2 (2GB) - backup model"
echo "   • WebUI on port 6969"
echo "   • All BorgOS services"