#!/bin/bash
# ============================================================================
#  BorgOS USB Flasher for macOS - Fixes permission issues
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
echo "║          BorgOS USB Flasher - macOS Permission Fix           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check for ISO
if [ ! -f "iso_output/BorgOS-Live-amd64.iso" ]; then
    error "ISO not found at iso_output/BorgOS-Live-amd64.iso"
fi

ISO_SIZE=$(ls -lh iso_output/BorgOS-Live-amd64.iso | awk '{print $5}')
log "Found ISO: BorgOS-Live-amd64.iso ($ISO_SIZE)"

# Find USB disk
log "Looking for 8GB USB drive..."
USB_INFO=$(diskutil list | grep -B3 "8.0 GB")
if [ -z "$USB_INFO" ]; then
    error "No 8GB USB drive found"
fi

echo "$USB_INFO"
USB_DISK=$(echo "$USB_INFO" | grep "^/dev/disk" | head -1 | awk '{print $1}' | sed 's|/dev/||')
log "Found USB: $USB_DISK"

warn "⚠️  THIS WILL ERASE /dev/$USB_DISK!"
echo ""
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    error "Cancelled by user"
fi

# Method 1: Try with diskutil unmountDisk
log "Method 1: Unmounting disk..."
sudo diskutil unmountDisk force /dev/$USB_DISK || true
sleep 2

log "Attempting to write ISO..."
sudo dd if=iso_output/BorgOS-Live-amd64.iso of=/dev/r$USB_DISK bs=1m 2>&1 | \
    while IFS= read -r line; do
        if [[ $line == *"Operation not permitted"* ]]; then
            warn "Permission denied. Trying alternative method..."
            break
        fi
        if [[ $line == *"bytes transferred"* ]]; then
            echo -ne "\r${GREEN}[+]${NC} $line"
        fi
    done

# Check if dd failed
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    warn "Method 1 failed. Trying Method 2..."
    
    # Method 2: Complete erase first
    log "Method 2: Complete disk erase..."
    sudo diskutil eraseDisk FREE UNTITLED MBR /dev/$USB_DISK
    sleep 2
    
    log "Writing ISO (this will take 5-10 minutes)..."
    sudo dd if=iso_output/BorgOS-Live-amd64.iso of=/dev/r$USB_DISK bs=1m || {
        warn "Method 2 failed. Trying Method 3..."
        
        # Method 3: Use raw disk without unmounting
        log "Method 3: Direct raw write..."
        sudo killall -STOP diskutil || true
        sudo dd if=iso_output/BorgOS-Live-amd64.iso of=/dev/r$USB_DISK bs=1m
        sudo killall -CONT diskutil || true
    }
fi

echo ""
log "Syncing data..."
sync

# Try to eject
sudo diskutil eject /dev/$USB_DISK 2>/dev/null || {
    warn "Could not eject. Please remove USB manually when ready."
}

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    ✅ USB FLASH COMPLETE!                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "📱 Next steps:"
echo "1. Remove USB from Mac"
echo "2. Insert into target PC"
echo "3. Boot from USB (F12/F2/Del)"
echo "4. Select 'Install BorgOS (Automated)'"
echo ""
echo "⚠️  Note: USB may appear empty on macOS - this is NORMAL!"
echo "    It will work on PC x86 systems."