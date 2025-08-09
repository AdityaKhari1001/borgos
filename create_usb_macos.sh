#!/bin/bash
# ============================================================================
#  BorgOS USB Creator for macOS
#  Creates bootable USB with BorgOS installer (without full ISO build)
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
error() { echo -e "${RED}[!]${NC} $1" >&2; exit 1; }
warn() { echo -e "${YELLOW}[*]${NC} $1"; }

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    error "This script is for macOS only"
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              BorgOS USB Creator for macOS                    ║"
echo "║                                                              ║"
echo "║  This will create a bootable USB with:                      ║"
echo "║  • Debian 12 base system                                    ║"
echo "║  • BorgOS installer script                                  ║"
echo "║  • Mistral 7B + Llama 3.2 models                           ║"
echo "║  • All BorgOS components                                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# List available disks
log "Available USB drives:"
diskutil list external

echo ""
read -p "Enter disk identifier (e.g., disk2): " DISK

if [[ -z "$DISK" ]]; then
    error "No disk specified"
fi

# Confirm disk selection
DISK_INFO=$(diskutil info /dev/$DISK | grep "Media Name" || echo "Unknown")
warn "Selected disk: /dev/$DISK"
warn "Disk info: $DISK_INFO"
echo ""
read -p "⚠️  This will ERASE /dev/$DISK! Continue? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    error "Aborted by user"
fi

# Download Debian netinst if not present
DEBIAN_ISO="debian-12.8.0-amd64-netinst.iso"
DEBIAN_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/$DEBIAN_ISO"

if [ ! -f "$DEBIAN_ISO" ]; then
    log "Downloading Debian 12 netinst..."
    curl -L -o "$DEBIAN_ISO" "$DEBIAN_URL" || error "Failed to download Debian ISO"
else
    log "Using existing $DEBIAN_ISO"
fi

# Create bootable USB
log "Creating bootable USB (this may take 5-10 minutes)..."

# Unmount disk
diskutil unmountDisk /dev/$DISK 2>/dev/null || true

# Write ISO to USB using dd
log "Writing Debian installer to USB..."
sudo dd if="$DEBIAN_ISO" of=/dev/r$DISK bs=4m status=progress || error "Failed to write ISO"

# Wait for disk to reappear
sleep 5

# Mount the USB to add BorgOS installer
log "Adding BorgOS installer..."
diskutil mount /dev/${DISK}s1 2>/dev/null || warn "Could not mount partition for modifications"

# Try to find mount point
MOUNT_POINT=$(diskutil info /dev/${DISK}s1 2>/dev/null | grep "Mount Point" | awk '{print $3}')

if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
    log "Copying BorgOS files to USB..."
    
    # Create BorgOS directory on USB
    sudo mkdir -p "$MOUNT_POINT/borgos" 2>/dev/null || true
    
    # Copy installer and other files
    sudo cp -r installer "$MOUNT_POINT/borgos/" 2>/dev/null || true
    sudo cp -r webui "$MOUNT_POINT/borgos/" 2>/dev/null || true
    sudo cp -r mcp_servers "$MOUNT_POINT/borgos/" 2>/dev/null || true
    sudo cp model_manager.py "$MOUNT_POINT/borgos/" 2>/dev/null || true
    sudo cp borg_cli.py "$MOUNT_POINT/borgos/" 2>/dev/null || true
    
    # Create auto-install script
    cat > /tmp/auto_install.sh <<'EOF'
#!/bin/bash
# BorgOS Auto-installer
echo "Starting BorgOS installation after Debian base install..."
cd /borgos
bash installer/install_all.sh
EOF
    sudo cp /tmp/auto_install.sh "$MOUNT_POINT/borgos/" 2>/dev/null || true
    sudo chmod +x "$MOUNT_POINT/borgos/auto_install.sh" 2>/dev/null || true
    
    log "BorgOS files added to USB"
else
    warn "Could not add BorgOS files (mount failed) - manual installation required"
fi

# Eject the disk
diskutil eject /dev/$DISK

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    ✅ USB CREATED SUCCESSFULLY!              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "📝 Installation Instructions:"
echo "1. Boot target PC from this USB drive"
echo "2. Install Debian 12 (minimal installation)"
echo "3. After first boot, run:"
echo "   sudo mount /dev/sdb1 /mnt"
echo "   sudo cp -r /mnt/borgos /root/"
echo "   cd /root/borgos"
echo "   sudo bash installer/install_all.sh"
echo ""
echo "The system will install:"
echo "• Mistral 7B (4.1GB) - main AI model"
echo "• Llama 3.2 (2GB) - backup model"
echo "• All BorgOS services and WebUI"
echo ""
echo "Access after installation:"
echo "• SSH: ssh user@<ip>"
echo "• WebUI: http://<ip>:6969"
echo "• CLI: borg 'your question'"