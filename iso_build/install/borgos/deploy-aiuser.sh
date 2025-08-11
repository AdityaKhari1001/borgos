#!/bin/bash

# BorgOS Deployment for aiuser@192.168.100.159
# Handles sudo requirements automatically

set -e

# Configuration
REMOTE_HOST="192.168.100.159"
REMOTE_USER="aiuser"
REMOTE_DIR="/home/aiuser/borgos-mvp"
ACTION="${1:-deploy}"  # deploy, status, logs, stop, restart

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Functions
show_logo() {
    echo -e "${BLUE}"
    cat << "EOF"
    ╔══════════════════════════════════════╗
    ║        🧠 BorgOS v2.0 MVP            ║
    ║    AI-First Operating System         ║
    ╚══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

deploy() {
    show_logo
    echo -e "${GREEN}Deploying BorgOS MVP to ${REMOTE_HOST}${NC}"
    echo -e "${YELLOW}Using user: ${REMOTE_USER}${NC}"
    echo

    # Test connection
    echo -e "${BLUE}Testing connection...${NC}"
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 ${REMOTE_USER}@${REMOTE_HOST} "echo 'Connected'" &>/dev/null; then
        echo -e "${RED}Cannot connect to ${REMOTE_USER}@${REMOTE_HOST}${NC}"
        echo "Please ensure SSH keys are configured"
        exit 1
    fi

    # Create package
    echo -e "${BLUE}Creating deployment package...${NC}"
    tar czf borgos-mvp.tar.gz \
        core/ \
        webui/ \
        database/ \
        installer/ \
        docker-compose.yml \
        .env.example \
        2>/dev/null || true

    # Upload
    echo -e "${BLUE}Uploading files...${NC}"
    ssh ${REMOTE_USER}@${REMOTE_HOST} "rm -rf ${REMOTE_DIR} && mkdir -p ${REMOTE_DIR}"
    scp -q borgos-mvp.tar.gz ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/

    # Deploy
    echo -e "${BLUE}Deploying on server...${NC}"
    ssh -t ${REMOTE_USER}@${REMOTE_HOST} << 'DEPLOY_SCRIPT'
cd ~/borgos-mvp

# Extract
tar xzf borgos-mvp.tar.gz
rm borgos-mvp.tar.gz

# Setup environment
if [ ! -f .env ]; then
    cp .env.example .env
    sed -i "s/your_secure_password_here/$(openssl rand -base64 32 | tr -d '\n')/g" .env
    sed -i "s/your_secret_key_here_min_32_chars/$(openssl rand -hex 32)/g" .env
    echo "Environment configured"
fi

# Docker check and use sudo if needed
echo "Checking Docker access..."
if docker version &>/dev/null 2>&1; then
    echo "Docker accessible directly"
    DOCKER_CMD="docker"
else
    echo "Docker requires sudo"
    DOCKER_CMD="sudo docker"
fi

# Build
echo "Building images..."
$DOCKER_CMD compose build

# Deploy
echo "Starting services..."
$DOCKER_CMD compose down 2>/dev/null || true
$DOCKER_CMD compose up -d

# Wait
sleep 10

# Status
echo ""
echo "Container status:"
$DOCKER_CMD compose ps

echo ""
echo "✅ Deployment complete!"
DEPLOY_SCRIPT

    # Cleanup
    rm -f borgos-mvp.tar.gz

    # Show info
    echo
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}    BorgOS MVP Ready!                   ${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo
    echo -e "${BLUE}Access:${NC}"
    echo -e "  Dashboard:  ${GREEN}http://${REMOTE_HOST}:8080${NC}"
    echo -e "  API:        ${GREEN}http://${REMOTE_HOST}:8081${NC}"
    echo -e "  ChromaDB:   ${GREEN}http://${REMOTE_HOST}:8000${NC}"
    echo
}

status() {
    echo -e "${BLUE}Checking status...${NC}"
    ssh ${REMOTE_USER}@${REMOTE_HOST} << 'EOF'
cd ~/borgos-mvp
if docker version &>/dev/null 2>&1; then
    docker compose ps
else
    sudo docker compose ps
fi
EOF
}

logs() {
    echo -e "${BLUE}Showing logs (Ctrl+C to exit)...${NC}"
    ssh ${REMOTE_USER}@${REMOTE_HOST} << 'EOF'
cd ~/borgos-mvp
if docker version &>/dev/null 2>&1; then
    docker compose logs -f
else
    sudo docker compose logs -f
fi
EOF
}

stop() {
    echo -e "${YELLOW}Stopping BorgOS...${NC}"
    ssh ${REMOTE_USER}@${REMOTE_HOST} << 'EOF'
cd ~/borgos-mvp
if docker version &>/dev/null 2>&1; then
    docker compose down
else
    sudo docker compose down
fi
echo "✅ BorgOS stopped"
EOF
}

restart() {
    echo -e "${YELLOW}Restarting BorgOS...${NC}"
    ssh ${REMOTE_USER}@${REMOTE_HOST} << 'EOF'
cd ~/borgos-mvp
if docker version &>/dev/null 2>&1; then
    docker compose restart
else
    sudo docker compose restart
fi
echo "✅ BorgOS restarted"
EOF
}

# Main
case "$ACTION" in
    deploy)
        deploy
        ;;
    status)
        status
        ;;
    logs)
        logs
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    *)
        echo "Usage: $0 {deploy|status|logs|stop|restart}"
        exit 1
        ;;
esac