#!/bin/bash

# BorgOS Deployment with sudo support for aiuser@192.168.100.159

set -e

# Configuration
REMOTE_HOST="192.168.100.159"
REMOTE_USER="aiuser"
REMOTE_DIR="/home/aiuser/borgos"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  BorgOS Deployment with sudo${NC}"
echo -e "${BLUE}  User: aiuser@${REMOTE_HOST}${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Test connection
echo -e "${BLUE}Testing connection...${NC}"
ssh ${REMOTE_USER}@${REMOTE_HOST} "echo 'Connected as aiuser'"

# Create package
echo -e "${BLUE}Creating deployment package...${NC}"
tar czf borgos.tar.gz \
    webui/ \
    website/ \
    deploy/ \
    docker-compose-remote.yml \
    Dockerfile.dashboard \
    Dockerfile.website \
    .env.example \
    2>/dev/null || true

# Upload
echo -e "${BLUE}Uploading files...${NC}"
ssh ${REMOTE_USER}@${REMOTE_HOST} "mkdir -p ${REMOTE_DIR}"
scp -q borgos.tar.gz ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/

# Deploy with sudo where needed
echo -e "${BLUE}Deploying (you may need to enter password for sudo)...${NC}"
ssh -t ${REMOTE_USER}@${REMOTE_HOST} << 'DEPLOY_SCRIPT'
cd ~/borgos

# Extract
tar xzf borgos.tar.gz
rm borgos.tar.gz

# Setup
mv docker-compose-remote.yml docker-compose.yml
if [ ! -f .env ]; then
    cp .env.example .env
    sed -i "s/your-secret-key-here-change-this-in-production/$(openssl rand -hex 32)/g" .env
    sed -i "s/borgos123/$(openssl rand -base64 12)/g" .env
fi

# Ensure docker group membership
if ! groups | grep -q docker; then
    echo "Adding aiuser to docker group..."
    sudo usermod -aG docker aiuser
    echo "Group added. Using sudo for docker commands..."
    USE_SUDO="sudo"
else
    USE_SUDO=""
fi

# Build with sudo if needed
echo "Building images..."
$USE_SUDO docker build -f Dockerfile.dashboard -t borgos/dashboard:latest .
$USE_SUDO docker build -f Dockerfile.website -t borgos/website:latest .

# Deploy
echo "Starting services..."
$USE_SUDO docker-compose down 2>/dev/null || true
$USE_SUDO docker-compose up -d

# Status
sleep 5
$USE_SUDO docker-compose ps

# Install model in background
$USE_SUDO docker exec -d borgos-ollama ollama pull mistral:7b

echo ""
echo "✅ Deployment complete!"
DEPLOY_SCRIPT

# Cleanup
rm -f borgos.tar.gz

# Show info
echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  BorgOS Deployed Successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "${BLUE}Access:${NC}"
echo "  Website:   http://${REMOTE_HOST}:8000"
echo "  Dashboard: http://${REMOTE_HOST}:8080 (admin/borgos)"
echo "  Ollama:    http://${REMOTE_HOST}:11434"
echo
echo -e "${BLUE}Commands:${NC}"
echo "  Status: ssh ${REMOTE_USER}@${REMOTE_HOST} 'cd borgos && docker-compose ps'"
echo "  Logs:   ssh ${REMOTE_USER}@${REMOTE_HOST} 'cd borgos && docker-compose logs -f'"
echo
echo -e "${YELLOW}Note: If docker commands fail, prefix with 'sudo'${NC}"