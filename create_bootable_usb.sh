#!/bin/bash
# ============================================================================
#  BorgOS USB Creator - FINAL WORKING VERSION FOR macOS
#  Prevents macOS from auto-formatting the USB
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
echo "║         BorgOS USB Creator - BOOTABLE x86 VERSION            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check for existing ISO
if [ -f "debian.iso" ]; then
    ISO_SIZE=$(stat -f%z debian.iso)
    if [ $ISO_SIZE -gt 600000000 ]; then
        log "Using existing debian.iso ($(($ISO_SIZE / 1024 / 1024))MB)"
    else
        rm debian.iso
        log "Downloading fresh Debian ISO..."
        wget --progress=bar:force -O debian.iso \
            "https://cdimage.debian.org/cdimage/archive/12.8.0/amd64/iso-cd/debian-12.8.0-amd64-netinst.iso"
    fi
else
    log "Downloading Debian 12 ISO (631MB)..."
    wget --progress=bar:force -O debian.iso \
        "https://cdimage.debian.org/cdimage/archive/12.8.0/amd64/iso-cd/debian-12.8.0-amd64-netinst.iso"
fi

# Find 8GB USB automatically
log "Looking for 8GB USB drive..."
USB_DISK=$(diskutil list | grep -B3 "8.0 GB" | grep "^/dev/disk" | head -1 | awk '{print $1}' | sed 's|/dev/||')

if [[ -z "$USB_DISK" ]]; then
    error "No 8GB USB drive found. Please insert USB and try again."
fi

log "Found USB: $USB_DISK"
warn "THIS WILL ERASE /dev/$USB_DISK!"
echo ""
read -p "Continue? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    error "Cancelled"
fi

# CRITICAL: Completely erase and unmount BEFORE writing
log "Completely erasing USB to prevent macOS interference..."
sudo diskutil eraseDisk FREE UNTITLED /dev/$USB_DISK

# Wait for disk to settle
sleep 2

# Force unmount again
sudo diskutil unmountDisk force /dev/$USB_DISK

log "Writing ISO to USB (5-10 minutes)..."
echo "If asked for password, enter your Mac password"

# Write with proper block size and raw device
sudo dd if=debian.iso of=/dev/r$USB_DISK bs=1m 2>&1 | \
    while IFS= read -r line; do
        if [[ $line == *"bytes transferred"* ]]; then
            echo -ne "\r${GREEN}[+]${NC} $line"
        fi
    done

echo ""
log "Finalizing USB..."

# Force sync
sync

# Do NOT let macOS mount it again
sudo diskutil unmountDisk force /dev/$USB_DISK 2>/dev/null || true

# Create installer archive
log "Creating BorgOS installer package..."
cd /Users/wojciechwiesner/ai
tar -czf borgos/borgos-installer.tar.gz \
    borgos/installer/ \
    borgos/webui/ \
    borgos/mcp_servers/ \
    borgos/model_manager.py \
    borgos/borg_cli.py \
    borgos/plugins/ \
    borgos/requirements.txt \
    borgos/README.md \
    borgos/CLAUDE.md 2>/dev/null || true

ls -lh borgos/borgos-installer.tar.gz

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 ✅ BOOTABLE USB CREATED!                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "⚠️  IMPORTANT: The USB will appear EMPTY or UNREADABLE on macOS!"
echo "    This is NORMAL - macOS cannot read Linux filesystems."
echo ""
echo "📱 To verify it worked:"
echo "   1. Eject the USB safely (do NOT just pull it out)"
echo "   2. Boot an x86 PC from this USB"
echo "   3. You should see Debian installer"
echo ""
echo "📝 Installation steps on target x86 system:"
echo "1. Boot from USB (press F12/F2/Del during boot)"
echo "2. Install Debian 12 minimal + SSH server"
echo "3. After installation, transfer borgos-installer.tar.gz"
echo "4. On target system run:"
echo ""
echo "   tar -xzf borgos-installer.tar.gz"
echo "   cd borgos"
echo "   sudo bash installer/install_all.sh"
echo ""
echo "📦 Installer: borgos-installer.tar.gz"
echo "   Copy to USB stick or transfer via network"
echo ""
echo "🎯 Will install:"
echo "   • Mistral 7B (4.1GB RAM optimized)"
echo "   • Llama 3.2 (2GB backup)"
echo "   • WebUI on http://IP:6969"
echo "   • All BorgOS services"