#!/bin/bash

# BorgOS Quick Deployment Script
# Deploy to 192.168.100.159 with single command

set -e

# Configuration
REMOTE_HOST="${1:-192.168.100.159}"
REMOTE_USER="${2:-aiuser}"
REMOTE_DIR="/home/${REMOTE_USER}/borgos-mvp"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Logo
echo -e "${BLUE}"
cat << "EOF"
    ╔══════════════════════════════════════╗
    ║        🧠 BorgOS v2.0 MVP            ║
    ║    AI-First Operating System         ║
    ╚══════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${GREEN}Deploying BorgOS MVP to ${REMOTE_HOST}${NC}"
echo

# Create package
echo -e "${BLUE}[1/6] Creating deployment package...${NC}"
tar czf borgos-mvp.tar.gz \
    core/ \
    webui/ \
    database/ \
    installer/ \
    docker-compose.yml \
    .env.example \
    2>/dev/null || true

# Upload to server
echo -e "${BLUE}[2/6] Uploading to server...${NC}"
ssh ${REMOTE_USER}@${REMOTE_HOST} "rm -rf ${REMOTE_DIR} && mkdir -p ${REMOTE_DIR}"
scp -q borgos-mvp.tar.gz ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/

# Deploy on remote
echo -e "${BLUE}[3/6] Installing on remote server...${NC}"
ssh ${REMOTE_USER}@${REMOTE_HOST} << 'REMOTE_SCRIPT'
cd ~/borgos-mvp

# Extract files
echo "Extracting files..."
tar xzf borgos-mvp.tar.gz
rm borgos-mvp.tar.gz

# Create .env from example
if [ ! -f .env ]; then
    cp .env.example .env
    # Generate secure passwords
    sed -i "s/your_secure_password_here/$(openssl rand -base64 32 | tr -d '\n')/g" .env
    sed -i "s/your_secret_key_here_min_32_chars/$(openssl rand -hex 32)/g" .env
    echo ".env file created with secure passwords"
fi

# Check Docker
if ! docker version &>/dev/null; then
    if ! sudo docker version &>/dev/null; then
        echo "Installing Docker..."
        curl -fsSL https://get.docker.com | sudo sh
        sudo usermod -aG docker $USER
    fi
    USE_SUDO="sudo"
else
    USE_SUDO=""
fi

# Build and start services
echo "Building Docker images..."
$USE_SUDO docker compose build

echo "Starting services..."
$USE_SUDO docker compose down 2>/dev/null || true
$USE_SUDO docker compose up -d

# Wait for services
echo "Waiting for services to start..."
sleep 10

# Show status
$USE_SUDO docker compose ps

echo ""
echo "✅ BorgOS MVP deployed successfully!"
REMOTE_SCRIPT

# Clean up local
rm -f borgos-mvp.tar.gz

# Show access info
echo
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}    BorgOS MVP Deployment Complete!     ${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo
echo -e "${BLUE}Access Points:${NC}"
echo -e "  Dashboard:  ${GREEN}http://${REMOTE_HOST}:8080${NC}"
echo -e "  API:        ${GREEN}http://${REMOTE_HOST}:8081${NC}"
echo -e "  ChromaDB:   ${GREEN}http://${REMOTE_HOST}:8000${NC}"
echo
echo -e "${BLUE}SSH Commands:${NC}"
echo -e "  Status:  ssh ${REMOTE_USER}@${REMOTE_HOST} 'cd borgos-mvp && docker compose ps'"
echo -e "  Logs:    ssh ${REMOTE_USER}@${REMOTE_HOST} 'cd borgos-mvp && docker compose logs -f'"
echo -e "  Stop:    ssh ${REMOTE_USER}@${REMOTE_HOST} 'cd borgos-mvp && docker compose down'"
echo
echo -e "${YELLOW}Note: First startup may take a few minutes for database initialization${NC}"