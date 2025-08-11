#!/bin/bash
# BorgOS Installer Script

echo "================================"
echo " BorgOS ${ISO_VERSION} Installer"
echo "================================"

# Function to install Docker
install_docker() {
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
}

# Function to install Docker Compose
install_docker_compose() {
    echo "Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
}

# Check for Docker
if ! command -v docker &> /dev/null; then
    install_docker
fi

# Check for Docker Compose
if ! command -v docker-compose &> /dev/null; then
    install_docker_compose
fi

# Install base packages
apt-get update
apt-get install -y python3 python3-pip git curl wget

# Clone BorgOS from GitHub
echo "Downloading BorgOS..."
git clone https://github.com/vizi2000/borgos /opt/borgos
cd /opt/borgos

# Create .env from example
cp .env.example .env

# Start BorgOS services
echo "Starting BorgOS services..."
docker-compose up -d

echo "================================"
echo " BorgOS Installation Complete!"
echo "================================"
echo " Dashboard: http://localhost:8080"
echo " API: http://localhost:8081"
echo " Agent Zero: http://localhost:8085"
echo "================================"
