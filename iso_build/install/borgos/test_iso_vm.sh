#!/bin/bash
# ============================================================================
#  BorgOS ISO Tester - Run in Virtual Machine
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
echo "║            BorgOS ISO Virtual Machine Tester                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check for ISO
if [ ! -f "iso_output/BorgOS-Live-amd64.iso" ]; then
    error "ISO not found! Build it first."
fi

ISO_SIZE=$(ls -lh iso_output/BorgOS-Live-amd64.iso | awk '{print $5}')
log "Found ISO: BorgOS-Live-amd64.iso ($ISO_SIZE)"

# Option 1: QEMU in Docker (headless)
test_with_qemu() {
    log "Starting QEMU VM in Docker..."
    
    docker run -it --rm \
        --name borgos-vm \
        -v "$(pwd)/iso_output:/iso:ro" \
        -p 5900:5900 \
        -p 2222:22 \
        -p 6969:6969 \
        --platform linux/amd64 \
        --device /dev/kvm \
        qemux/qemu-docker \
        -m 8G \
        -cdrom /iso/BorgOS-Live-amd64.iso \
        -boot d \
        -vnc :0 \
        -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::6969-:6969 \
        -device e1000,netdev=net0
}

# Option 2: VirtualBox (if installed)
test_with_virtualbox() {
    log "Creating VirtualBox VM..."
    
    VM_NAME="BorgOS-Test"
    
    # Create VM
    VBoxManage createvm --name "$VM_NAME" --ostype "Debian_64" --register
    
    # Configure VM
    VBoxManage modifyvm "$VM_NAME" \
        --memory 8192 \
        --cpus 2 \
        --vram 128 \
        --nic1 nat \
        --natpf1 "ssh,tcp,,2222,,22" \
        --natpf1 "webui,tcp,,6969,,6969"
    
    # Create disk
    VBoxManage createhd --filename "$VM_NAME.vdi" --size 20000
    
    # Attach storage
    VBoxManage storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci
    VBoxManage storageattach "$VM_NAME" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "$VM_NAME.vdi"
    
    # Attach ISO
    VBoxManage storagectl "$VM_NAME" --name "IDE" --add ide
    VBoxManage storageattach "$VM_NAME" --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium "$(pwd)/iso_output/BorgOS-Live-amd64.iso"
    
    # Start VM
    log "Starting VM..."
    VBoxManage startvm "$VM_NAME"
    
    info "VM started! Access:"
    info "  VirtualBox GUI: Open VirtualBox app"
    info "  SSH: ssh -p 2222 borg@localhost"
    info "  WebUI: http://localhost:6969"
}

# Option 3: UTM for Mac (GUI)
test_with_utm() {
    log "Instructions for UTM (macOS):"
    echo ""
    echo "1. Download UTM: https://mac.getutm.app/"
    echo "2. Open UTM"
    echo "3. Click '+' → 'Virtualize'"
    echo "4. Select 'Linux'"
    echo "5. Browse → Select: iso_output/BorgOS-Live-amd64.iso"
    echo "6. Memory: 8192 MB"
    echo "7. Storage: 20 GB"
    echo "8. Name: BorgOS"
    echo "9. Save and Start"
    echo ""
    echo "Access after boot:"
    echo "  Console: In UTM window"
    echo "  WebUI: http://[VM-IP]:6969"
}

# Option 4: Docker with VNC
test_with_docker_vnc() {
    log "Starting Docker VM with VNC access..."
    
    # Create Dockerfile for QEMU
    cat > Dockerfile.vm <<'EOF'
FROM --platform=linux/amd64 debian:12

RUN apt-get update && apt-get install -y \
    qemu-system-x86 \
    qemu-utils \
    novnc \
    websockify \
    supervisor \
    net-tools \
    && rm -rf /var/lib/apt/lists/*

# VNC setup
RUN mkdir -p /var/log/supervisor
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

EXPOSE 5900 6080 22 6969

CMD ["/usr/bin/supervisord"]
EOF

    cat > supervisord.conf <<'EOF'
[supervisord]
nodaemon=true

[program:qemu]
command=qemu-system-x86_64 -m 8G -cdrom /iso/BorgOS-Live-amd64.iso -boot d -vnc :0 -netdev user,id=net0,hostfwd=tcp::22-:22,hostfwd=tcp::6969-:6969 -device e1000,netdev=net0
autorestart=true

[program:novnc]
command=websockify --web /usr/share/novnc 6080 localhost:5900
autorestart=true
EOF

    docker build -f Dockerfile.vm -t borgos-vm .
    
    log "Starting VM with VNC..."
    docker run -d --rm \
        --name borgos-vm \
        --platform linux/amd64 \
        -v "$(pwd)/iso_output:/iso:ro" \
        -p 5900:5900 \
        -p 6080:6080 \
        -p 2222:22 \
        -p 6969:6969 \
        borgos-vm
    
    sleep 5
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    ✅ VM STARTED!                            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "📱 Access VM:"
    echo "  VNC Browser: http://localhost:6080/vnc.html"
    echo "  VNC Client: localhost:5900"
    echo "  SSH: ssh -p 2222 borg@localhost (after install)"
    echo "  WebUI: http://localhost:6969 (after install)"
    echo ""
    echo "📝 In VM console:"
    echo "  1. Select 'Install BorgOS (Automated)'"
    echo "  2. Follow installer"
    echo ""
    echo "🛑 Stop VM: docker stop borgos-vm"
    
    # Cleanup
    rm -f Dockerfile.vm supervisord.conf
}

# Menu
echo "Select VM type:"
echo "1) Docker with VNC (recommended)"
echo "2) VirtualBox (needs VirtualBox installed)"
echo "3) UTM for macOS (manual setup)"
echo "4) QEMU in Docker (advanced)"
echo ""
read -p "Choice [1-4]: " CHOICE

case $CHOICE in
    1) test_with_docker_vnc ;;
    2) test_with_virtualbox ;;
    3) test_with_utm ;;
    4) test_with_qemu ;;
    *) test_with_docker_vnc ;;
esac