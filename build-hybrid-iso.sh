#!/bin/bash

# BorgOS Hybrid ISO Builder
# Minimal ISO with Ollama (Gemma 2B) + SSH + Branding
# Target size: <2GB

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
VERSION="hybrid-1.0"
ARCH="amd64"
ISO_NAME="BorgOS-Hybrid-${VERSION}-${ARCH}.iso"
WORK_DIR="hybrid_build"
ISO_DIR="${WORK_DIR}/iso"
ROOTFS="${WORK_DIR}/rootfs"

# Ollama configuration
OLLAMA_VERSION="0.1.45"
MODEL_NAME="gemma:2b"
MODEL_SIZE="1.4GB"  # Gemma 2B size

# Functions
log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# ASCII Art
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔════════════════════════════════════════╗
║        BorgOS Hybrid ISO Builder       ║
║     Minimal + AI + SSH + Branding      ║
╠════════════════════════════════════════╣
║  🧠 Ollama with Gemma 2B               ║
║  🔒 SSH enabled by default             ║
║  🎨 BorgOS branding                    ║
║  📦 Target size: <2GB                  ║
╚════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Clean previous builds
cleanup() {
    log "Cleaning previous builds..."
    rm -rf ${WORK_DIR}
    mkdir -p ${WORK_DIR}/{iso,rootfs,tmp}
    mkdir -p ${ISO_DIR}/{isolinux,boot/grub,live,install}
}

# Create minimal rootfs
create_rootfs() {
    log "Creating minimal Debian rootfs..."
    
    # Essential packages only
    PACKAGES=(
        # Core system
        systemd systemd-sysv init
        linux-image-amd64 grub-pc
        
        # Network
        openssh-server network-manager
        curl wget git ca-certificates
        
        # Minimal UI
        xorg lightdm openbox
        xterm firefox-esr
        
        # System tools
        sudo htop nano vim
        bash-completion
        
        # Docker for services
        docker.io docker-compose
    )
    
    # Bootstrap minimal Debian
    debootstrap --variant=minbase \
        --include=$(IFS=,; echo "${PACKAGES[*]}") \
        bookworm ${ROOTFS} \
        http://deb.debian.org/debian/
}

# Install Ollama with Gemma 2B
install_ollama() {
    log "Installing Ollama with Gemma 2B model..."
    
    # Download Ollama binary
    curl -L https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-linux-amd64 \
        -o ${ROOTFS}/usr/local/bin/ollama
    chmod +x ${ROOTFS}/usr/local/bin/ollama
    
    # Create Ollama service
    cat > ${ROOTFS}/etc/systemd/system/ollama.service << 'SERVICE'
[Unit]
Description=Ollama AI Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ollama serve
Restart=always
User=ollama
Group=ollama
Environment="OLLAMA_HOST=0.0.0.0"
Environment="OLLAMA_MODELS=/var/lib/ollama/models"

[Install]
WantedBy=multi-user.target
SERVICE
    
    # Pre-download Gemma 2B model
    log "Downloading Gemma 2B model (${MODEL_SIZE})..."
    mkdir -p ${ROOTFS}/var/lib/ollama/models
    
    # Create model pull script for first boot
    cat > ${ROOTFS}/usr/local/bin/ollama-init << 'SCRIPT'
#!/bin/bash
# Pull Gemma 2B on first boot if not exists
if ! ollama list | grep -q gemma:2b; then
    echo "Pulling Gemma 2B model..."
    ollama pull gemma:2b
fi
SCRIPT
    chmod +x ${ROOTFS}/usr/local/bin/ollama-init
}

# Configure SSH
configure_ssh() {
    log "Configuring SSH access..."
    
    # Enable SSH by default
    chroot ${ROOTFS} systemctl enable ssh
    
    # Configure SSH for security
    cat >> ${ROOTFS}/etc/ssh/sshd_config << 'SSH'
# BorgOS SSH Configuration
PermitRootLogin prohibit-password
PasswordAuthentication yes
PubkeyAuthentication yes
X11Forwarding yes
PrintMotd yes
SSH
    
    # Create SSH banner
    cat > ${ROOTFS}/etc/ssh/banner << 'BANNER'
═══════════════════════════════════════════
    BorgOS Hybrid - AI-First System
    SSH Access Enabled
    Default: borgos/borgos
═══════════════════════════════════════════
BANNER
}

# Apply BorgOS branding
apply_branding() {
    log "Applying BorgOS branding..."
    
    # Copy logo
    cp /Users/wojciechwiesner/ai/borgos-clean/assets/logo.svg ${ROOTFS}/usr/share/pixmaps/borgos-logo.svg
    
    # Create boot splash
    mkdir -p ${ROOTFS}/usr/share/plymouth/themes/borgos
    
    # Generate Plymouth theme
    cat > ${ROOTFS}/usr/share/plymouth/themes/borgos/borgos.plymouth << 'PLYMOUTH'
[Plymouth Theme]
Name=BorgOS
Description=BorgOS Boot Splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/borgos
ScriptFile=/usr/share/plymouth/themes/borgos/borgos.script
PLYMOUTH
    
    # Boot menu branding
    cat > ${ISO_DIR}/isolinux/isolinux.cfg << 'BOOTMENU'
DEFAULT borgos
PROMPT 1
TIMEOUT 50

MENU TITLE BorgOS Hybrid Boot Menu
MENU BACKGROUND /isolinux/borgos-bg.png
MENU COLOR border 30;44 #40ffffff #a0000000 std
MENU COLOR title 1;36;44 #9033ccff #a0000000 std
MENU COLOR sel 7;37;40 #e0ffffff #20ffffff all

LABEL borgos
    MENU LABEL ^BorgOS Hybrid (Ollama + SSH)
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live quiet splash

LABEL install
    MENU LABEL ^Install BorgOS
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live install quiet

LABEL safe
    MENU LABEL Safe Mode
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd.img boot=live nomodeset
BOOTMENU
    
    # LightDM branding
    cat > ${ROOTFS}/etc/lightdm/lightdm-gtk-greeter.conf << 'LIGHTDM'
[greeter]
background = /usr/share/backgrounds/borgos-wallpaper.png
logo = /usr/share/pixmaps/borgos-logo.svg
theme-name = BorgOS
icon-theme-name = BorgOS
font-name = Ubuntu 11
LIGHTDM
}

# Create BorgOS user
create_user() {
    log "Creating BorgOS user..."
    
    chroot ${ROOTFS} useradd -m -s /bin/bash -G sudo,docker borgos
    echo "borgos:borgos" | chroot ${ROOTFS} chpasswd
    echo "root:borgos" | chroot ${ROOTFS} chpasswd
    
    # Auto-login for Live mode
    cat > ${ROOTFS}/etc/lightdm/lightdm.conf.d/50-borgos.conf << 'AUTOLOGIN'
[Seat:*]
autologin-user=borgos
autologin-user-timeout=0
AUTOLOGIN
}

# Install BorgOS core
install_borgos_core() {
    log "Installing BorgOS core components..."
    
    # Copy core files
    cp -r core ${ROOTFS}/opt/borgos/
    cp -r webui ${ROOTFS}/opt/borgos/
    cp -r installer ${ROOTFS}/opt/borgos/
    
    # Create startup script
    cat > ${ROOTFS}/usr/local/bin/borgos-init << 'INIT'
#!/bin/bash
# BorgOS Initialization

echo "Initializing BorgOS Hybrid..."

# Start Ollama
systemctl start ollama
sleep 5

# Initialize Ollama model
/usr/local/bin/ollama-init &

# Start SSH
systemctl start ssh

# Show status
echo "═══════════════════════════════════════"
echo "  BorgOS Hybrid Ready!"
echo "  SSH: $(ip -4 addr show | grep inet | grep -v 127.0.0.1 | awk '{print $2}')"
echo "  Ollama: http://localhost:11434"
echo "═══════════════════════════════════════"
INIT
    chmod +x ${ROOTFS}/usr/local/bin/borgos-init
    
    # Create systemd service
    cat > ${ROOTFS}/etc/systemd/system/borgos.service << 'SERVICE'
[Unit]
Description=BorgOS Initialization
After=network.target ollama.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/borgos-init
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE
    
    chroot ${ROOTFS} systemctl enable borgos
}

# Create squashfs
create_squashfs() {
    log "Creating compressed filesystem..."
    
    # Clean apt cache
    chroot ${ROOTFS} apt-get clean
    rm -rf ${ROOTFS}/var/cache/apt/archives/*
    
    # Create squashfs
    mksquashfs ${ROOTFS} ${ISO_DIR}/live/filesystem.squashfs \
        -comp xz -b 1M \
        -e boot
    
    # Copy kernel and initrd
    cp ${ROOTFS}/boot/vmlinuz-* ${ISO_DIR}/live/vmlinuz
    cp ${ROOTFS}/boot/initrd.img-* ${ISO_DIR}/live/initrd.img
}

# Build ISO
build_iso() {
    log "Building hybrid ISO..."
    
    # Install syslinux files
    cp /usr/lib/ISOLINUX/isolinux.bin ${ISO_DIR}/isolinux/
    cp /usr/lib/syslinux/modules/bios/*.c32 ${ISO_DIR}/isolinux/
    
    # Create ISO
    xorriso -as mkisofs \
        -r -V "BorgOS-Hybrid" \
        -cache-inodes -J -l \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -o ${ISO_NAME} \
        ${ISO_DIR}
    
    # Show size
    SIZE=$(du -h ${ISO_NAME} | cut -f1)
    log "ISO created: ${ISO_NAME} (${SIZE})"
}

# Main execution
main() {
    show_banner
    
    # Check requirements
    command -v debootstrap >/dev/null || error "debootstrap not installed"
    command -v mksquashfs >/dev/null || error "squashfs-tools not installed"
    command -v xorriso >/dev/null || error "xorriso not installed"
    
    # Build steps
    cleanup
    create_rootfs
    install_ollama
    configure_ssh
    apply_branding
    create_user
    install_borgos_core
    create_squashfs
    build_iso
    
    echo -e "${GREEN}"
    echo "═══════════════════════════════════════════"
    echo "  ✅ BorgOS Hybrid ISO Build Complete!"
    echo "  📦 File: ${ISO_NAME}"
    echo "  📏 Size: ${SIZE}"
    echo "  🧠 AI: Ollama with Gemma 2B"
    echo "  🔒 SSH: Enabled (borgos/borgos)"
    echo "═══════════════════════════════════════════"
    echo -e "${NC}"
}

# Run if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi