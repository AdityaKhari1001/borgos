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
DOMAIN="borgtools.ddns.net"
EMAIL="admin@borgtools.ddns.net"

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
║     borgtools.ddns.net               ║
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
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        warning "Node.js not found. Installing..."
        if [[ "$OS" == "linux" ]]; then
            log "Installing Node.js 20.x..."
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
            sudo apt-get install -y nodejs || \
            sudo yum install -y nodejs || \
            sudo dnf install -y nodejs
        elif [[ "$OS" == "macos" ]]; then
            if command -v brew &> /dev/null; then
                brew install node
            else
                error "Please install Node.js from https://nodejs.org"
            fi
        fi
    else
        log "Node.js found: $(node --version)"
    fi
    
    # Install pnpm (faster npm alternative)
    if ! command -v pnpm &> /dev/null; then
        log "Installing pnpm..."
        npm install -g pnpm 2>/dev/null || true
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
    
    # Copy simple docker-compose if zenith directories don't exist
    if [ ! -d "${INSTALL_DIR}/zenith-coder/frontend" ] || [ ! -d "${INSTALL_DIR}/zenith-coder/backend" ]; then
        log "Using simplified docker-compose without zenith..."
        if [ -f "${TEMP_DIR}/borgos/docker-compose-simple.yml" ]; then
            cp ${TEMP_DIR}/borgos/docker-compose-simple.yml ${INSTALL_DIR}/docker-compose.yml
        fi
    fi
    
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
        log "Downloading and installing Ollama..."
        curl -fsSL https://ollama.ai/install.sh | sh
        
        # Wait for installation to complete
        sleep 3
    else
        log "Ollama already installed: $(ollama --version 2>/dev/null || echo 'version unknown')"
    fi
    
    # Configure and start Ollama service on Linux
    if [[ "$OS" == "linux" ]]; then
        log "Configuring Ollama systemd service..."
        
        # Create systemd service file if it doesn't exist
        if [ ! -f /etc/systemd/system/ollama.service ]; then
            log "Creating Ollama systemd service file..."
            sudo tee /etc/systemd/system/ollama.service > /dev/null << 'SERVICE'
[Unit]
Description=Ollama Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ollama
Group=ollama
ExecStart=/usr/local/bin/ollama serve
Restart=always
RestartSec=10
Environment="HOME=/usr/share/ollama"
Environment="OLLAMA_HOST=0.0.0.0"
WorkingDirectory=/usr/share/ollama

[Install]
WantedBy=multi-user.target
SERVICE
        fi
        
        # Create ollama user if doesn't exist
        if ! id -u ollama > /dev/null 2>&1; then
            log "Creating ollama user..."
            sudo useradd -r -s /bin/false -m -d /usr/share/ollama ollama
        fi
        
        # Create necessary directories
        sudo mkdir -p /usr/share/ollama
        sudo chown -R ollama:ollama /usr/share/ollama
        
        # Reload systemd and enable service
        log "Enabling and starting Ollama service..."
        sudo systemctl daemon-reload
        sudo systemctl enable ollama.service
        sudo systemctl restart ollama.service
        
        # Check service status
        sleep 2
        if sudo systemctl is-active --quiet ollama.service; then
            log "Ollama service is running"
        else
            warning "Ollama service failed to start, trying alternative method..."
            # Try to start directly
            sudo -u ollama /usr/local/bin/ollama serve > /dev/null 2>&1 &
            sleep 3
        fi
    elif [[ "$OS" == "macos" ]]; then
        # On macOS, create a launchd service
        log "Starting Ollama on macOS..."
        ollama serve > /dev/null 2>&1 &
    fi
}

# Ensure Ollama is running and pull default model
ensure_ollama_running() {
    log "Ensuring Ollama is running with default model..."
    
    # First check if systemd service is running (Linux only)
    if [[ "$OS" == "linux" ]]; then
        if ! sudo systemctl is-active --quiet ollama.service; then
            log "Ollama service not active, starting it..."
            sudo systemctl start ollama.service
            sleep 3
            
            # Check again
            if ! sudo systemctl is-active --quiet ollama.service; then
                warning "Systemd service failed, trying direct launch..."
                # Try running as current user with proper permissions
                OLLAMA_HOST=0.0.0.0 ollama serve > /var/log/ollama.log 2>&1 &
                echo $! > /tmp/ollama.pid
                sleep 5
            fi
        fi
    fi
    
    # Wait for Ollama API to be ready
    local max_attempts=30
    local attempt=0
    
    log "Waiting for Ollama API to be ready..."
    while [ $attempt -lt $max_attempts ]; do
        if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
            log "Ollama API is responding"
            break
        fi
        
        # On attempt 10, try one more restart
        if [ $attempt -eq 10 ]; then
            warning "Ollama not responding, attempting restart..."
            if [[ "$OS" == "linux" ]]; then
                sudo systemctl restart ollama.service 2>/dev/null || {
                    pkill ollama 2>/dev/null || true
                    sleep 2
                    OLLAMA_HOST=0.0.0.0 ollama serve > /var/log/ollama.log 2>&1 &
                }
            else
                pkill ollama 2>/dev/null || true
                sleep 2
                ollama serve > /dev/null 2>&1 &
            fi
        fi
        
        sleep 2
        attempt=$((attempt + 1))
        echo -n "."
    done
    echo ""
    
    if [ $attempt -eq $max_attempts ]; then
        warning "Ollama not responding via systemd, trying fix script..."
        # Try to fix Ollama installation
        if [ -f "${INSTALL_DIR}/scripts/fix-ollama.sh" ]; then
            bash "${INSTALL_DIR}/scripts/fix-ollama.sh"
        else
            error "Ollama failed to start properly."
            warning "You can try manually:"
            warning "  sudo systemctl status ollama"
            warning "  ollama serve"
            warning "Or download fix script:"
            warning "  curl -fsSL https://raw.githubusercontent.com/vizi2000/borgos/main/scripts/fix-ollama.sh | bash"
        fi
        return 1
    fi
    
    # Pull default model (gemma:2b) - using sudo if needed
    log "Pulling default AI model (gemma:2b)..."
    if [[ "$OS" == "linux" ]]; then
        # Try with ollama user first
        sudo -u ollama ollama pull gemma:2b 2>/dev/null || \
        # If fails, try as current user
        ollama pull gemma:2b || \
        warning "Failed to pull gemma:2b - you may need to run: ollama pull gemma:2b"
    else
        ollama pull gemma:2b || warning "Failed to pull gemma:2b"
    fi
    
    # Try to pull additional useful models (optional)
    log "Pulling additional AI models (optional)..."
    ollama pull llama2:7b 2>/dev/null || true
    ollama pull codellama:7b 2>/dev/null || true
    
    # Set default model in environment if .env exists
    if [ -f "${INSTALL_DIR}/.env" ]; then
        if ! grep -q "DEFAULT_OLLAMA_MODEL" "${INSTALL_DIR}/.env"; then
            echo "" >> ${INSTALL_DIR}/.env
            echo "# Default Ollama model" >> ${INSTALL_DIR}/.env
            echo "DEFAULT_OLLAMA_MODEL=gemma:2b" >> ${INSTALL_DIR}/.env
        fi
    fi
    
    # Verify Ollama is working by listing models
    log "Verifying Ollama installation..."
    if ollama list > /dev/null 2>&1; then
        log "Ollama is working correctly!"
        ollama list
    else
        warning "Ollama installed but may need manual configuration"
    fi
    
    log "Ollama setup complete"
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
    
    # Use appropriate compose file
    if [ -f docker-compose-simple.yml ] && [ ! -d zenith-coder/frontend ]; then
        log "Starting BorgOS services (simplified mode)..."
        docker compose -f docker-compose-simple.yml up -d
    elif [ -f docker-compose-full.yml ] && [ -d zenith-coder/frontend ]; then
        log "Starting all BorgOS services (full mode)..."
        docker compose -f docker-compose-full.yml up -d
    elif [ -f docker-compose.yml ]; then
        log "Starting BorgOS services..."
        docker compose up -d || docker-compose up -d
    else
        error "No docker-compose file found!"
        return 1
    fi
    
    # Wait for services
    log "Waiting for services to start..."
    sleep 15
    
    # Check services health
    docker compose ps
}

# Install OpenRouter API integration
install_openrouter() {
    log "Setting up OpenRouter API integration..."
    
    # Create scripts directory
    mkdir -p ${INSTALL_DIR}/scripts
    
    # Add OpenRouter configuration to .env
    cat >> ${INSTALL_DIR}/.env << 'ENV'

# OpenRouter API Configuration
OPENROUTER_API_KEY=${OPENROUTER_API_KEY:-}
OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
OPENROUTER_DEFAULT_MODEL=google/gemma-2b-it:free
OPENROUTER_FALLBACK_ENABLED=true

# Available free models on OpenRouter
# - google/gemma-2b-it:free
# - meta-llama/llama-3.2-3b-instruct:free
# - mistralai/mistral-7b-instruct:free
# - huggingfaceh4/zephyr-7b-beta:free
ENV
    
    # Create Node.js OpenRouter client
    cat > ${INSTALL_DIR}/scripts/openrouter.js << 'SCRIPT'
#!/usr/bin/env node
const https = require('https');

class OpenRouterClient {
    constructor(apiKey) {
        this.apiKey = apiKey || process.env.OPENROUTER_API_KEY;
        this.baseUrl = 'openrouter.ai';
    }
    
    async chat(prompt, model = 'google/gemma-2b-it:free') {
        const data = JSON.stringify({
            model: model,
            messages: [{ role: 'user', content: prompt }]
        });
        
        const options = {
            hostname: this.baseUrl,
            path: '/api/v1/chat/completions',
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${this.apiKey}`,
                'Content-Type': 'application/json',
                'HTTP-Referer': 'https://borgtools.ddns.net',
                'X-Title': 'BorgOS'
            }
        };
        
        return new Promise((resolve, reject) => {
            const req = https.request(options, (res) => {
                let body = '';
                res.on('data', chunk => body += chunk);
                res.on('end', () => resolve(JSON.parse(body)));
            });
            req.on('error', reject);
            req.write(data);
            req.end();
        });
    }
}

module.exports = OpenRouterClient;

// CLI usage
if (require.main === module) {
    const client = new OpenRouterClient();
    const prompt = process.argv.slice(2).join(' ');
    if (prompt) {
        client.chat(prompt).then(console.log).catch(console.error);
    } else {
        console.log('Usage: openrouter "your prompt here"');
    }
}
SCRIPT
    
    chmod +x ${INSTALL_DIR}/scripts/openrouter.js
    
    # Create Python OpenRouter client
    cat > ${INSTALL_DIR}/scripts/openrouter.py << 'PYTHON'
#!/usr/bin/env python3
import os
import json
import sys
try:
    import requests
except ImportError:
    print("Installing requests...")
    os.system("pip install requests")
    import requests

class OpenRouterClient:
    def __init__(self, api_key=None):
        self.api_key = api_key or os.getenv('OPENROUTER_API_KEY')
        self.base_url = 'https://openrouter.ai/api/v1'
        
    def chat(self, prompt, model='google/gemma-2b-it:free'):
        headers = {
            'Authorization': f'Bearer {self.api_key}',
            'Content-Type': 'application/json',
            'HTTP-Referer': 'https://borgtools.ddns.net',
            'X-Title': 'BorgOS'
        }
        
        data = {
            'model': model,
            'messages': [{'role': 'user', 'content': prompt}]
        }
        
        response = requests.post(
            f'{self.base_url}/chat/completions',
            headers=headers,
            json=data
        )
        return response.json()

if __name__ == '__main__':
    client = OpenRouterClient()
    if len(sys.argv) > 1:
        prompt = ' '.join(sys.argv[1:])
        result = client.chat(prompt)
        if 'choices' in result:
            print(result['choices'][0]['message']['content'])
        else:
            print(json.dumps(result, indent=2))
    else:
        print('Usage: openrouter.py "your prompt here"')
PYTHON
    
    chmod +x ${INSTALL_DIR}/scripts/openrouter.py
    
    # Create unified AI CLI wrapper
    cat > ${INSTALL_DIR}/scripts/ai << 'AI_WRAPPER'
#!/bin/bash
# Unified AI CLI - tries Ollama first, falls back to OpenRouter

prompt="$*"

if [ -z "$prompt" ]; then
    echo "Usage: ai <your prompt>"
    exit 1
fi

# Try Ollama first
if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "$prompt" | ollama run gemma:2b 2>/dev/null
    exit_code=$?
    if [ $exit_code -eq 0 ]; then
        exit 0
    fi
fi

# Fall back to OpenRouter if configured
if [ -n "$OPENROUTER_API_KEY" ]; then
    python3 /opt/borgos/scripts/openrouter.py "$prompt"
else
    echo "No AI service available. Set OPENROUTER_API_KEY or ensure Ollama is running."
    exit 1
fi
AI_WRAPPER
    
    chmod +x ${INSTALL_DIR}/scripts/ai
    sudo ln -sf ${INSTALL_DIR}/scripts/ai /usr/local/bin/ai
    
    log "OpenRouter API configured. Add your API key to .env to enable."
    log "Use 'ai <prompt>' command for unified AI access"
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
    server_name borgtools.ddns.net;
    
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
    server_name agent.borgtools.ddns.net;
    
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
    server_name zenith.borgtools.ddns.net;
    
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
    server_name n8n.borgtools.ddns.net;
    
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
    server_name portainer.borgtools.ddns.net;
    
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
        echo "BorgOS started at https://borgtools.ddns.net"
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
        echo "  Main Dashboard: https://borgtools.ddns.net"
        echo "  Agent Zero: https://agent.borgtools.ddns.net"
        echo "  Zenith Coder: https://zenith.borgtools.ddns.net"
        echo "  n8n Workflows: https://n8n.borgtools.ddns.net"
        echo "  Portainer: https://portainer.borgtools.ddns.net"
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
    ensure_ollama_running
    install_openrouter
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
    echo "  🌐 Main Dashboard: https://borgtools.ddns.net"
    echo "  🤖 Agent Zero: https://agent.borgtools.ddns.net"
    echo "  💻 Zenith Coder: https://zenith.borgtools.ddns.net"
    echo "  🔄 n8n Workflows: https://n8n.borgtools.ddns.net"
    echo "  🐳 Portainer: https://portainer.borgtools.ddns.net"
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