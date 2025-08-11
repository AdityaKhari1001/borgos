#!/bin/bash

# BorgOS Quick Install Script
# One-line installer: curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/borgos/main/quick-install.sh | bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
REPO_URL="https://github.com/vizi2000/borgos"
INSTALL_DIR="/opt/borgos"
VERSION="latest"

# Functions
log() { echo -e "${GREEN}[BorgOS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Banner
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔════════════════════════════════════════╗
║        BorgOS Quick Installer          ║
║     AI-First Operating System          ║
╚════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Check system
check_system() {
    log "Checking system requirements..."
    
    # Check OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        error "Unsupported operating system: $OSTYPE"
    fi
    
    # Check architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        ARCH="amd64"
    elif [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
        ARCH="arm64"
    else
        error "Unsupported architecture: $ARCH"
    fi
    
    log "Detected: $OS $ARCH"
}

# Check dependencies
check_dependencies() {
    log "Checking dependencies..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        warning "Docker not found. Installing..."
        if [[ "$OS" == "linux" ]]; then
            curl -fsSL https://get.docker.com | sh
            sudo usermod -aG docker $USER
        elif [[ "$OS" == "macos" ]]; then
            error "Please install Docker Desktop from https://docker.com"
        fi
    else
        log "Docker found: $(docker --version)"
    fi
    
    # Check Git
    if ! command -v git &> /dev/null; then
        warning "Git not found. Installing..."
        if [[ "$OS" == "linux" ]]; then
            sudo apt-get update && sudo apt-get install -y git || \
            sudo yum install -y git || \
            sudo dnf install -y git
        elif [[ "$OS" == "macos" ]]; then
            error "Please install Git or Xcode Command Line Tools"
        fi
    else
        log "Git found: $(git --version)"
    fi
}

# Download BorgOS
download_borgos() {
    log "Downloading BorgOS..."
    
    # Create directory
    sudo mkdir -p ${INSTALL_DIR}
    sudo chown $USER:$USER ${INSTALL_DIR}
    
    # Clone repository
    if [ -d "${INSTALL_DIR}/.git" ]; then
        log "Updating existing installation..."
        cd ${INSTALL_DIR}
        git pull
    else
        log "Cloning BorgOS repository..."
        git clone ${REPO_URL} ${INSTALL_DIR}
        cd ${INSTALL_DIR}
    fi
}

# Install Ollama
install_ollama() {
    log "Installing Ollama..."
    
    if ! command -v ollama &> /dev/null; then
        curl -fsSL https://ollama.ai/install.sh | sh
    else
        log "Ollama already installed"
    fi
    
    # Start Ollama service
    if [[ "$OS" == "linux" ]]; then
        sudo systemctl enable ollama
        sudo systemctl start ollama
    fi
    
    # Pull Gemma 2B model
    log "Pulling Gemma 2B model..."
    ollama pull gemma:2b || warning "Model will be downloaded on first use"
}

# Deploy BorgOS
deploy_borgos() {
    log "Deploying BorgOS services..."
    
    cd ${INSTALL_DIR}
    
    # Create .env file
    if [ ! -f .env ]; then
        cat > .env << ENV
# BorgOS Configuration
BORGOS_VERSION=${VERSION}
BORGOS_PORT=6969
OLLAMA_HOST=http://localhost:11434
DB_PASSWORD=borgos123
ENV
    fi
    
    # Start services
    log "Starting BorgOS services..."
    docker compose up -d || docker-compose up -d
    
    # Wait for services
    log "Waiting for services to start..."
    sleep 10
}

# Create shortcuts
create_shortcuts() {
    log "Creating shortcuts..."
    
    # Create borgos command
    sudo tee /usr/local/bin/borgos > /dev/null << 'SCRIPT'
#!/bin/bash
cd /opt/borgos
case "$1" in
    start)
        docker compose up -d
        echo "BorgOS started at http://localhost:6969"
        ;;
    stop)
        docker compose down
        echo "BorgOS stopped"
        ;;
    status)
        docker compose ps
        ;;
    logs)
        docker compose logs -f
        ;;
    update)
        git pull
        docker compose pull
        docker compose up -d
        echo "BorgOS updated"
        ;;
    *)
        echo "Usage: borgos {start|stop|status|logs|update}"
        ;;
esac
SCRIPT
    
    sudo chmod +x /usr/local/bin/borgos
}

# Main installation
main() {
    show_banner
    
    # Run checks
    check_system
    check_dependencies
    
    # Install components
    download_borgos
    install_ollama
    deploy_borgos
    create_shortcuts
    
    # Success message
    echo -e "${GREEN}"
    echo "═══════════════════════════════════════════"
    echo "  ✅ BorgOS Installation Complete!"
    echo "═══════════════════════════════════════════"
    echo ""
    echo "  Access BorgOS at: http://localhost:6969"
    echo "  Default login: borgos/borgos"
    echo ""
    echo "  Commands:"
    echo "    borgos start   - Start BorgOS"
    echo "    borgos stop    - Stop BorgOS"
    echo "    borgos status  - Check status"
    echo "    borgos logs    - View logs"
    echo "    borgos update  - Update BorgOS"
    echo ""
    echo "  Ollama API: http://localhost:11434"
    echo "═══════════════════════════════════════════"
    echo -e "${NC}"
}

# Run installation
main "$@"