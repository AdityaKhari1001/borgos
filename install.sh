#!/bin/bash

# BorgOS Complete Installation Script v2.0
# One-line installer: curl -fsSL https://raw.githubusercontent.com/vizi2000/borgos/main/install.sh | bash
# Force reinstall: curl -fsSL https://raw.githubusercontent.com/vizi2000/borgos/main/install.sh | bash -s -- --force
# Installs complete AI-first system with all agents and DevOps tools

# Don't exit on errors - handle them gracefully
set +e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
REPO_URL="https://github.com/vizi2000/borgos"
AGENT_ZERO_REPO="https://github.com/vizi2000/agent-zero"
INSTALL_DIR="/opt/borgos"
VERSION="2.0"
DOMAIN="borg.tools.ddns.net"
EMAIL="admin@borg.tools"

# Parse arguments
FORCE_INSTALL=false
for arg in "$@"; do
    case $arg in
        --force)
            FORCE_INSTALL=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force    Force reinstall, overwrite existing installation"
            echo "  --help     Show this help message"
            exit 0
            ;;
    esac
done

# Functions
log() { echo -e "${GREEN}[BorgOS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Banner
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔════════════════════════════════════════╗
║      🧠 BorgOS Complete v2.0          ║
║    AI-First Multi-Agent System        ║
║     borg.tools.ddns.net               ║
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

# Download BorgOS and Agent Zero
download_borgos() {
    log "Preparing BorgOS installation..."
    
    # Backup existing configuration if exists
    if [ -d "${INSTALL_DIR}" ]; then
        warning "Directory ${INSTALL_DIR} exists. Backing up configuration..."
        # Backup existing .env if exists
        if [ -f "${INSTALL_DIR}/.env" ]; then
            cp ${INSTALL_DIR}/.env /tmp/.env.borgos.backup
            log "Backed up existing .env file"
        fi
        # Backup docker-compose overrides if exist
        if [ -f "${INSTALL_DIR}/docker-compose.override.yml" ]; then
            cp ${INSTALL_DIR}/docker-compose.override.yml /tmp/docker-compose.override.backup
        fi
    fi
    
    # Always use temp directory for cloning to avoid git errors
    TEMP_DIR="/tmp/borgos-install-$(date +%s)"
    log "Downloading BorgOS to temporary directory..."
    
    # Clone BorgOS repository to temp
    rm -rf ${TEMP_DIR}
    git clone ${REPO_URL} ${TEMP_DIR}/borgos || {
        error "Failed to clone BorgOS repository"
    }
    
    # Clone Agent Zero to temp
    log "Downloading Agent Zero..."
    git clone ${AGENT_ZERO_REPO} ${TEMP_DIR}/agent-zero || {
        warning "Failed to clone Agent Zero, will try to install later"
    }
    
    # Create install directory if not exists
    sudo mkdir -p ${INSTALL_DIR}
    sudo chown $USER:$USER ${INSTALL_DIR}
    
    # Clean old installation files (but keep data and configs)
    log "Cleaning old installation files..."
    cd ${INSTALL_DIR}
    # Remove directories that will be replaced
    for dir in core webui database installer k8s docs mcp_servers; do
        [ -d "$dir" ] && rm -rf "$dir"
    done
    # Remove old docker-compose files
    rm -f docker-compose.yml docker-compose-full.yml
    # Remove old scripts
    rm -f *.sh
    
    # Copy new files from temp
    log "Installing BorgOS files..."
    cp -r ${TEMP_DIR}/borgos/* ${INSTALL_DIR}/ 2>/dev/null || true
    cp -r ${TEMP_DIR}/borgos/.[^.]* ${INSTALL_DIR}/ 2>/dev/null || true
    
    # Install Agent Zero
    if [ -d "${TEMP_DIR}/agent-zero" ]; then
        rm -rf ${INSTALL_DIR}/agent-zero
        mv ${TEMP_DIR}/agent-zero ${INSTALL_DIR}/agent-zero
        log "Agent Zero installed"
    fi
    
    # Restore configuration
    if [ -f /tmp/.env.borgos.backup ]; then
        if [ ! -f "${INSTALL_DIR}/.env" ]; then
            mv /tmp/.env.borgos.backup ${INSTALL_DIR}/.env
            log "Restored .env configuration"
        else
            mv /tmp/.env.borgos.backup ${INSTALL_DIR}/.env.backup
            log "Saved old .env as .env.backup"
        fi
    fi
    
    if [ -f /tmp/docker-compose.override.backup ]; then
        mv /tmp/docker-compose.override.backup ${INSTALL_DIR}/docker-compose.override.yml
        log "Restored docker-compose.override.yml"
    fi
    
    # Clean up temp directory
    rm -rf ${TEMP_DIR}
    
    cd ${INSTALL_DIR}
    log "BorgOS downloaded successfully"
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
    
    # Pull additional models for better performance
    log "Pulling additional AI models..."
    ollama pull llama2:7b || true
    ollama pull codellama:7b || true
}

# Deploy BorgOS
deploy_borgos() {
    log "Deploying BorgOS services..."
    
    cd ${INSTALL_DIR}
    
    # Stop and remove existing containers if force install
    if [ "$FORCE_INSTALL" = true ] || [ -f docker-compose.yml ] || [ -f docker-compose-full.yml ]; then
        log "Stopping existing services..."
        docker compose down 2>/dev/null || true
        docker compose -f docker-compose-full.yml down 2>/dev/null || true
        
        # Clean up orphaned containers
        docker container prune -f 2>/dev/null || true
    fi
    
    # Create .env file with full configuration
    if [ ! -f .env ]; then
        cat > .env << ENV
# BorgOS Configuration v2.0
BORGOS_VERSION=${VERSION}
DOMAIN=${DOMAIN}

# Ports
BORGOS_PORT=6969
API_PORT=8081
AGENT_ZERO_PORT=8085
ZENITH_BACKEND_PORT=8101
ZENITH_FRONTEND_PORT=3101
N8N_PORT=5678
PORTAINER_PORT=9000

# AI Configuration
OLLAMA_HOST=http://ollama:11434
OPENAI_API_KEY=
ANTHROPIC_API_KEY=

# Database
DB_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')

# Security
JWT_SECRET=$(openssl rand -hex 32)
ENV
        log "Created .env file with secure passwords"
    fi
    
    # Use the full compose file if it exists
    if [ -f docker-compose-full.yml ]; then
        log "Starting all BorgOS services..."
        docker compose -f docker-compose-full.yml up -d
    else
        log "Starting basic BorgOS services..."
        docker compose up -d || docker-compose up -d
    fi
    
    # Wait for services
    log "Waiting for services to start..."
    sleep 15
    
    # Check services health
    docker compose ps
}

# Install DevOps tools
install_devops_tools() {
    log "Installing DevOps tools..."
    
    # n8n workflow automation
    log "Setting up n8n workflow automation..."
    docker pull n8nio/n8n:latest
    
    # Portainer Docker management
    log "Setting up Portainer..."
    docker pull portainer/portainer-ce:latest
    
    log "DevOps tools ready"
}

# Setup Nginx reverse proxy
setup_nginx() {
    log "Setting up Nginx reverse proxy..."
    
    # Install Nginx
    if ! command -v nginx &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y nginx certbot python3-certbot-nginx
    fi
    
    # Create Nginx configuration
    sudo tee /etc/nginx/sites-available/borgos > /dev/null << 'NGINX'
# BorgOS Main Dashboard
server {
    server_name borg.tools.ddns.net;
    
    location / {
        proxy_pass http://localhost:6969;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
    
    location /api {
        proxy_pass http://localhost:8081;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
    }
}

# Agent Zero
server {
    server_name agent.borg.tools.ddns.net;
    
    location / {
        proxy_pass http://localhost:8085;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
    }
}

# Zenith Coder
server {
    server_name zenith.borg.tools.ddns.net;
    
    location / {
        proxy_pass http://localhost:3101;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
    }
}

# n8n Workflows
server {
    server_name n8n.borg.tools.ddns.net;
    
    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
    }
}

# Portainer
server {
    server_name portainer.borg.tools.ddns.net;
    
    location / {
        proxy_pass http://localhost:9000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
    }
}
NGINX
    
    # Enable site
    sudo ln -sf /etc/nginx/sites-available/borgos /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl reload nginx
    
    log "Nginx configured for ${DOMAIN}"
}

# Setup SSL certificates
setup_ssl() {
    log "Setting up SSL certificates..."
    
    # Check if certbot is installed
    if command -v certbot &> /dev/null; then
        log "Obtaining SSL certificates for ${DOMAIN}..."
        sudo certbot --nginx -d ${DOMAIN} -d agent.${DOMAIN} -d zenith.${DOMAIN} -d n8n.${DOMAIN} -d portainer.${DOMAIN} \
            --non-interactive --agree-tos --email ${EMAIL} || warning "SSL setup failed, continuing without SSL"
    else
        warning "Certbot not found, skipping SSL setup"
    fi
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
        if [ -f docker-compose-full.yml ]; then
            docker compose -f docker-compose-full.yml up -d
        else
            docker compose up -d
        fi
        echo "BorgOS started at https://borg.tools.ddns.net"
        ;;
    stop)
        if [ -f docker-compose-full.yml ]; then
            docker compose -f docker-compose-full.yml down
        else
            docker compose down
        fi
        echo "BorgOS stopped"
        ;;
    status)
        if [ -f docker-compose-full.yml ]; then
            docker compose -f docker-compose-full.yml ps
        else
            docker compose ps
        fi
        ;;
    logs)
        if [ -f docker-compose-full.yml ]; then
            docker compose -f docker-compose-full.yml logs -f
        else
            docker compose logs -f
        fi
        ;;
    update)
        git pull
        cd agent-zero && git pull && cd ..
        if [ -f docker-compose-full.yml ]; then
            docker compose -f docker-compose-full.yml pull
            docker compose -f docker-compose-full.yml up -d
        else
            docker compose pull
            docker compose up -d
        fi
        echo "BorgOS updated"
        ;;
    *)
        echo "Usage: borgos {start|stop|status|logs|update}"
        echo ""
        echo "Access points:"
        echo "  Main Dashboard: https://borg.tools.ddns.net"
        echo "  Agent Zero: https://agent.borg.tools.ddns.net"
        echo "  Zenith Coder: https://zenith.borg.tools.ddns.net"
        echo "  n8n Workflows: https://n8n.borg.tools.ddns.net"
        echo "  Portainer: https://portainer.borg.tools.ddns.net"
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
    install_devops_tools
    deploy_borgos
    
    # Setup networking
    setup_nginx
    setup_ssl
    
    # Create shortcuts
    create_shortcuts
    
    # Success message
    echo -e "${GREEN}"
    echo "═══════════════════════════════════════════════════════════════"
    echo "  ✅ BorgOS v2.0 Installation Complete!"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "  🌐 Main Dashboard: https://borg.tools.ddns.net"
    echo "  🤖 Agent Zero: https://agent.borg.tools.ddns.net"
    echo "  💻 Zenith Coder: https://zenith.borg.tools.ddns.net"
    echo "  🔄 n8n Workflows: https://n8n.borg.tools.ddns.net"
    echo "  🐳 Portainer: https://portainer.borg.tools.ddns.net"
    echo ""
    echo "  📡 API Endpoints:"
    echo "    • BorgOS API: http://localhost:8081"
    echo "    • Ollama API: http://localhost:11434"
    echo "    • Agent Zero: http://localhost:8085"
    echo ""
    echo "  🔐 Default Credentials:"
    echo "    • SSH: borgos/borgos"
    echo "    • Dashboard: admin/admin (change on first login)"
    echo ""
    echo "  ⚡ Commands:"
    echo "    borgos start   - Start all services"
    echo "    borgos stop    - Stop all services"
    echo "    borgos status  - Check status"
    echo "    borgos logs    - View logs"
    echo "    borgos update  - Update system"
    echo ""
    echo "  📚 Documentation: https://github.com/vizi2000/borgos"
    echo "═══════════════════════════════════════════════════════════════"
    echo -e "${NC}"
    
    # Show service status
    log "Service status:"
    borgos status
}

# Run installation
main "$@"