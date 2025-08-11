#!/bin/bash
# ============================================================================
#  BorgOS USB Creator for macOS - FIXED VERSION
#  Uses alternative method for macOS compatibility
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
echo "║         BorgOS USB Creator for macOS - FIXED VERSION         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check for Debian ISO
DEBIAN_ISO="debian-12.8.0-amd64-netinst.iso"
if [ ! -f "$DEBIAN_ISO" ]; then
    log "Downloading Debian 12 netinst..."
    curl -L -o "$DEBIAN_ISO" "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/$DEBIAN_ISO"
fi

log "Available USB drives:"
diskutil list external

echo ""
read -p "Enter disk identifier (e.g., disk4): " DISK

if [[ -z "$DISK" ]]; then
    error "No disk specified"
fi

# Confirm
DISK_INFO=$(diskutil info /dev/$DISK | grep "Media Name" || echo "Unknown")
warn "Selected disk: /dev/$DISK"
warn "Disk info: $DISK_INFO"
echo ""
read -p "⚠️  This will ERASE /dev/$DISK! Continue? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    error "Aborted by user"
fi

log "Preparing USB drive..."

# Unmount
diskutil unmountDisk /dev/$DISK

# Convert ISO to IMG format for macOS
log "Converting ISO to IMG format..."
hdiutil convert -format UDRW -o debian-usb.img "$DEBIAN_ISO"

# Rename the output file
mv debian-usb.img.dmg debian-usb.img 2>/dev/null || true

log "Writing to USB (this will take 5-10 minutes)..."
log "You may see 'Permission denied' - enter your password when prompted"

# Use correct block size and raw disk for speed
sudo dd if=debian-usb.img of=/dev/r$DISK bs=1m

# Sync to ensure all data is written
sync

log "Ejecting disk..."
diskutil eject /dev/$DISK

# Clean up
rm -f debian-usb.img

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  ✅ USB CREATED SUCCESSFULLY!                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "📝 Next Steps:"
echo "1. Boot target PC from USB"
echo "2. Install Debian 12 minimal"
echo "3. After installation, download BorgOS:"
echo ""
echo "   wget https://github.com/borgos/borgos/archive/main.zip"
echo "   unzip main.zip && cd borgos-main"
echo "   sudo bash installer/install_all.sh"
echo ""
echo "Or copy files manually from another USB"