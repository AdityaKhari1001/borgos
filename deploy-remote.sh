#!/bin/bash

# BorgOS Remote Deployment Script for 192.168.100.159
# Automated deployment to remote server

set -e

# Configuration
REMOTE_HOST="192.168.100.159"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE_PORT="${REMOTE_PORT:-22}"
REMOTE_DIR="/opt/borgos"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  BorgOS Remote Deployment${NC}"
    echo -e "${BLUE}  Target: ${REMOTE_HOST}${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
}

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check SSH connection
check_ssh() {
    echo -e "${BLUE}Checking SSH connection to ${REMOTE_HOST}...${NC}"
    
    if ssh -o ConnectTimeout=5 -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "echo 'SSH OK'" &>/dev/null; then
        print_status "SSH connection successful"
    else
        print_error "Cannot connect to ${REMOTE_HOST}"
        echo "Please check:"
        echo "  1. Server is accessible"
        echo "  2. SSH credentials are correct"
        echo "  3. Port ${REMOTE_PORT} is open"
        exit 1
    fi
}

# Check remote requirements
check_remote_requirements() {
    echo -e "\n${BLUE}Checking remote server requirements...${NC}"
    
    ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} << 'EOF'
        # Check Docker
        if command -v docker &> /dev/null; then
            echo "[OK] Docker installed: $(docker --version)"
        else
            echo "[MISSING] Docker not installed"
            echo "Installing Docker..."
            curl -fsSL https://get.docker.com | sh
        fi
        
        # Check Docker Compose
        if command -v docker-compose &> /dev/null; then
            echo "[OK] Docker Compose installed: $(docker-compose --version)"
        elif docker compose version &> /dev/null; then
            echo "[OK] Docker Compose plugin installed"
        else
            echo "[MISSING] Docker Compose not installed"
            echo "Installing Docker Compose..."
            curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
        fi
        
        # Check available resources
        echo ""
        echo "System Resources:"
        echo "  CPU Cores: $(nproc)"
        echo "  Total RAM: $(free -h | grep Mem | awk '{print $2}')"
        echo "  Free Disk: $(df -h / | tail -1 | awk '{print $4}')"
EOF
    
    print_status "Remote requirements checked"
}

# Prepare files for deployment
prepare_deployment() {
    echo -e "\n${BLUE}Preparing deployment package...${NC}"
    
    # Create temporary deployment directory
    TEMP_DIR=$(mktemp -d)
    
    # Copy necessary files
    cp -r webui ${TEMP_DIR}/
    cp -r website ${TEMP_DIR}/
    cp -r deploy ${TEMP_DIR}/
    cp docker-compose.yml ${TEMP_DIR}/
    cp Dockerfile.dashboard ${TEMP_DIR}/
    cp Dockerfile.website ${TEMP_DIR}/
    cp .env.example ${TEMP_DIR}/.env
    
    # Update .env for remote server
    cat > ${TEMP_DIR}/.env << EOL
# BorgOS Remote Deployment Configuration
SECRET_KEY=$(openssl rand -hex 32)
DB_PASSWORD=$(openssl rand -base64 12)
N8N_PASSWORD=$(openssl rand -base64 12)

# Server Configuration
DOMAIN=${REMOTE_HOST}
DASHBOARD_DOMAIN=dashboard.${REMOTE_HOST}
N8N_DOMAIN=n8n.${REMOTE_HOST}

# API Keys (optional)
OPENROUTER_API_KEY=
HUGGINGFACE_API_KEY=
OPENAI_API_KEY=

# Resources
OLLAMA_MEMORY_LIMIT=4G
OLLAMA_MEMORY_RESERVATION=2G

# Monitoring
ENABLE_METRICS=true
ENABLE_LOGGING=true
LOG_LEVEL=info
EOL
    
    # Create deployment archive
    cd ${TEMP_DIR}
    tar czf borgos-deploy.tar.gz *
    mv borgos-deploy.tar.gz ${LOCAL_DIR}/
    cd ${LOCAL_DIR}
    rm -rf ${TEMP_DIR}
    
    print_status "Deployment package prepared"
}

# Upload files to remote server
upload_files() {
    echo -e "\n${BLUE}Uploading files to ${REMOTE_HOST}...${NC}"
    
    # Create remote directory
    ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "mkdir -p ${REMOTE_DIR}"
    
    # Upload deployment package
    scp -P ${REMOTE_PORT} borgos-deploy.tar.gz ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/
    
    # Extract on remote
    ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} "cd ${REMOTE_DIR} && tar xzf borgos-deploy.tar.gz && rm borgos-deploy.tar.gz"
    
    # Clean local package
    rm -f borgos-deploy.tar.gz
    
    print_status "Files uploaded successfully"
}

# Build images on remote server
build_remote_images() {
    echo -e "\n${BLUE}Building Docker images on remote server...${NC}"
    
    ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} << EOF
        cd ${REMOTE_DIR}
        
        echo "Building dashboard image..."
        docker build -f Dockerfile.dashboard -t borgos/dashboard:latest . || exit 1
        
        echo "Building website image..."
        docker build -f Dockerfile.website -t borgos/website:latest . || exit 1
        
        echo "Images built successfully"
EOF
    
    print_status "Docker images built"
}

# Deploy stack on remote server
deploy_remote_stack() {
    echo -e "\n${BLUE}Deploying BorgOS stack on ${REMOTE_HOST}...${NC}"
    
    ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} << EOF
        cd ${REMOTE_DIR}
        
        # Stop existing containers if any
        docker-compose down 2>/dev/null || true
        
        # Update docker-compose for specific ports
        sed -i 's/8080:8080/8080:8080/g' docker-compose.yml
        sed -i 's/80:80/8000:80/g' docker-compose.yml  # Change website to port 8000
        
        # Start the stack
        docker-compose up -d || exit 1
        
        # Show running containers
        docker-compose ps
EOF
    
    print_status "Stack deployed successfully"
}

# Configure firewall
configure_firewall() {
    echo -e "\n${BLUE}Configuring firewall rules...${NC}"
    
    ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} << EOF
        # Check if ufw is installed
        if command -v ufw &> /dev/null; then
            echo "Configuring UFW firewall..."
            ufw allow 22/tcp
            ufw allow 80/tcp
            ufw allow 443/tcp
            ufw allow 8000/tcp  # Website
            ufw allow 8080/tcp  # Dashboard
            ufw allow 11434/tcp # Ollama API
            ufw allow 5678/tcp  # n8n
            ufw allow 8089/tcp  # Traefik dashboard
            ufw --force enable
        elif command -v firewall-cmd &> /dev/null; then
            echo "Configuring firewalld..."
            firewall-cmd --permanent --add-port=80/tcp
            firewall-cmd --permanent --add-port=443/tcp
            firewall-cmd --permanent --add-port=8000/tcp
            firewall-cmd --permanent --add-port=8080/tcp
            firewall-cmd --permanent --add-port=11434/tcp
            firewall-cmd --permanent --add-port=5678/tcp
            firewall-cmd --permanent --add-port=8089/tcp
            firewall-cmd --reload
        else
            echo "No firewall detected, skipping configuration"
        fi
EOF
    
    print_status "Firewall configured"
}

# Install Ollama models
install_models() {
    echo -e "\n${BLUE}Installing AI models...${NC}"
    
    ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} << EOF
        cd ${REMOTE_DIR}
        
        # Wait for Ollama to be ready
        echo "Waiting for Ollama service..."
        for i in {1..30}; do
            if docker exec borgos-ollama ollama list &>/dev/null; then
                break
            fi
            sleep 2
        done
        
        # Pull Mistral model
        echo "Pulling Mistral 7B model (this may take a while)..."
        docker exec borgos-ollama ollama pull mistral:7b || echo "Model pull can be done later"
EOF
    
    print_status "AI models installation initiated"
}

# Setup monitoring
setup_monitoring() {
    echo -e "\n${BLUE}Setting up monitoring...${NC}"
    
    ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} << EOF
        cd ${REMOTE_DIR}
        
        # Create monitoring script
        cat > monitor.sh << 'SCRIPT'
#!/bin/bash
echo "BorgOS System Status"
echo "===================="
echo ""
echo "Docker Containers:"
docker-compose ps
echo ""
echo "Resource Usage:"
docker stats --no-stream
echo ""
echo "Disk Usage:"
df -h ${REMOTE_DIR}
echo ""
echo "Network Connections:"
netstat -tuln | grep -E ':(80|8000|8080|11434|5678) '
SCRIPT
        
        chmod +x monitor.sh
        
        # Create systemd service for auto-start
        cat > /etc/systemd/system/borgos.service << 'SERVICE'
[Unit]
Description=BorgOS Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${REMOTE_DIR}
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
ExecReload=/usr/local/bin/docker-compose restart

[Install]
WantedBy=multi-user.target
SERVICE
        
        systemctl daemon-reload
        systemctl enable borgos.service
EOF
    
    print_status "Monitoring setup complete"
}

# Test deployment
test_deployment() {
    echo -e "\n${BLUE}Testing deployment...${NC}"
    
    # Test endpoints
    echo -n "Testing website... "
    if curl -f -s -o /dev/null http://${REMOTE_HOST}:8000; then
        print_status "Website is accessible"
    else
        print_warning "Website might need more time to start"
    fi
    
    echo -n "Testing dashboard... "
    if curl -f -s -o /dev/null http://${REMOTE_HOST}:8080; then
        print_status "Dashboard is accessible"
    else
        print_warning "Dashboard might need more time to start"
    fi
    
    echo -n "Testing Ollama API... "
    if curl -f -s -o /dev/null http://${REMOTE_HOST}:11434; then
        print_status "Ollama API is accessible"
    else
        print_warning "Ollama might need more time to start"
    fi
}

# Show deployment info
show_info() {
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}  BorgOS Deployed Successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo -e "${BLUE}Access Points:${NC}"
    echo -e "  Website:      ${GREEN}http://${REMOTE_HOST}:8000${NC}"
    echo -e "  Dashboard:    ${GREEN}http://${REMOTE_HOST}:8080${NC}"
    echo -e "    Username: admin"
    echo -e "    Password: borgos"
    echo -e "  Ollama API:   ${GREEN}http://${REMOTE_HOST}:11434${NC}"
    echo -e "  n8n:          ${GREEN}http://${REMOTE_HOST}:5678${NC}"
    echo -e "  Traefik:      ${GREEN}http://${REMOTE_HOST}:8089${NC}"
    echo
    echo -e "${BLUE}Management Commands:${NC}"
    echo -e "  SSH to server:  ${YELLOW}ssh ${REMOTE_USER}@${REMOTE_HOST}${NC}"
    echo -e "  View logs:      ${YELLOW}ssh ${REMOTE_USER}@${REMOTE_HOST} 'cd ${REMOTE_DIR} && docker-compose logs -f'${NC}"
    echo -e "  Restart:        ${YELLOW}ssh ${REMOTE_USER}@${REMOTE_HOST} 'cd ${REMOTE_DIR} && docker-compose restart'${NC}"
    echo -e "  Monitor:        ${YELLOW}ssh ${REMOTE_USER}@${REMOTE_HOST} '${REMOTE_DIR}/monitor.sh'${NC}"
    echo
    echo -e "${GREEN}Deployment completed at $(date)${NC}"
}

# Cleanup on remote
cleanup_remote() {
    echo -e "\n${RED}Cleaning up remote deployment...${NC}"
    
    ssh -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST} << EOF
        cd ${REMOTE_DIR}
        docker-compose down -v
        cd /
        rm -rf ${REMOTE_DIR}
        systemctl disable borgos.service 2>/dev/null || true
        rm -f /etc/systemd/system/borgos.service
EOF
    
    print_status "Remote cleanup complete"
}

# Main execution
main() {
    case "${1:-}" in
        --clean)
            print_header
            cleanup_remote
            ;;
        --status)
            ssh ${REMOTE_USER}@${REMOTE_HOST} "${REMOTE_DIR}/monitor.sh"
            ;;
        --logs)
            ssh ${REMOTE_USER}@${REMOTE_HOST} "cd ${REMOTE_DIR} && docker-compose logs -f ${2:-}"
            ;;
        --restart)
            ssh ${REMOTE_USER}@${REMOTE_HOST} "cd ${REMOTE_DIR} && docker-compose restart"
            print_status "Services restarted"
            ;;
        --stop)
            ssh ${REMOTE_USER}@${REMOTE_HOST} "cd ${REMOTE_DIR} && docker-compose down"
            print_status "Services stopped"
            ;;
        *)
            print_header
            check_ssh
            check_remote_requirements
            prepare_deployment
            upload_files
            build_remote_images
            deploy_remote_stack
            configure_firewall
            install_models
            setup_monitoring
            test_deployment
            show_info
            ;;
    esac
}

# Run main function
main "$@"