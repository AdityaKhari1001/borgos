#!/bin/bash

# Fix Docker permissions for aiuser

REMOTE_HOST="192.168.100.159"
REMOTE_USER="aiuser"

echo "🔧 Fixing Docker permissions for aiuser..."

# Add aiuser to docker group and restart docker
ssh ${REMOTE_USER}@${REMOTE_HOST} << 'EOF'
echo "Checking Docker access..."

# Try with sudo
if command -v sudo &>/dev/null; then
    echo "Using sudo to add aiuser to docker group..."
    echo "You may need to enter aiuser's password:"
    
    # Add to docker group
    sudo usermod -aG docker aiuser
    
    # Restart docker service
    sudo systemctl restart docker
    
    # Create docker directory if needed
    sudo mkdir -p /home/aiuser/.docker
    sudo chown -R aiuser:aiuser /home/aiuser/.docker
    
    echo ""
    echo "✅ Docker permissions updated!"
    echo ""
    echo "IMPORTANT: You need to logout and login again for changes to take effect."
    echo "Or run: newgrp docker"
    
    # Try to activate new group immediately
    newgrp docker << 'INNER'
    docker version
INNER
    
else
    echo "❌ sudo not available. Please ask system administrator to run:"
    echo "   sudo usermod -aG docker aiuser"
    echo "   sudo systemctl restart docker"
fi
EOF

echo ""
echo "Now trying deployment again..."