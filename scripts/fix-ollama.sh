#!/bin/bash
# BorgOS Ollama Fix Script - Repairs and configures Ollama service

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[OLLAMA FIX]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

log "Starting Ollama repair and configuration..."

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
else
    error "Unsupported OS: $OSTYPE"
    exit 1
fi

# Stop any running Ollama processes
log "Stopping existing Ollama processes..."
sudo pkill ollama 2>/dev/null || true
sudo systemctl stop ollama 2>/dev/null || true
sleep 2

# Install Ollama if not present
if ! command -v ollama &> /dev/null; then
    log "Ollama not found, installing..."
    curl -fsSL https://ollama.ai/install.sh | sh
    sleep 3
fi

if [[ "$OS" == "linux" ]]; then
    log "Configuring Ollama for Linux with systemd..."
    
    # Create ollama user
    if ! id -u ollama > /dev/null 2>&1; then
        log "Creating ollama user..."
        sudo useradd -r -s /bin/false -m -d /usr/share/ollama ollama
    fi
    
    # Create directories with correct permissions
    log "Setting up directories..."
    sudo mkdir -p /usr/share/ollama/.ollama/models
    sudo mkdir -p /var/log/ollama
    sudo chown -R ollama:ollama /usr/share/ollama
    sudo chown -R ollama:ollama /var/log/ollama
    
    # Create improved systemd service
    log "Creating systemd service..."
    sudo tee /etc/systemd/system/ollama.service > /dev/null << 'EOF'
[Unit]
Description=Ollama Service
Documentation=https://github.com/ollama/ollama
After=network-online.target
Wants=network-online.target
AssertFileIsExecutable=/usr/local/bin/ollama

[Service]
Type=notify
NotifyAccess=all
User=ollama
Group=ollama
ExecStart=/usr/local/bin/ollama serve
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=10
TimeoutStartSec=90s
Environment="HOME=/usr/share/ollama"
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_MODELS=/usr/share/ollama/.ollama/models"
Environment="OLLAMA_KEEP_ALIVE=5m"
WorkingDirectory=/usr/share/ollama
StandardOutput=append:/var/log/ollama/ollama.log
StandardError=append:/var/log/ollama/ollama-error.log
SyslogIdentifier=ollama
KillMode=mixed
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF
    
    # Alternative: Create a simpler service that runs as current user
    log "Creating alternative user service..."
    sudo tee /etc/systemd/system/ollama-user.service > /dev/null << EOF
[Unit]
Description=Ollama Service (User Mode)
After=network.target

[Service]
Type=simple
User=$USER
Group=$USER
ExecStart=/usr/local/bin/ollama serve
Restart=always
RestartSec=10
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="HOME=$HOME"

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd
    log "Reloading systemd configuration..."
    sudo systemctl daemon-reload
    
    # Try the main service first
    log "Starting Ollama service..."
    if sudo systemctl start ollama.service 2>/dev/null; then
        sudo systemctl enable ollama.service
        log "Main Ollama service started successfully"
    else
        warning "Main service failed, trying user service..."
        sudo systemctl start ollama-user.service
        sudo systemctl enable ollama-user.service
        log "User Ollama service started"
    fi
    
    # Wait for service to be ready
    sleep 5
    
    # Check status
    if sudo systemctl is-active --quiet ollama.service || sudo systemctl is-active --quiet ollama-user.service; then
        log "Ollama service is running!"
    else
        warning "Service not running via systemd, starting directly..."
        nohup ollama serve > /var/log/ollama-direct.log 2>&1 &
        echo $! > /tmp/ollama.pid
        log "Started Ollama directly (PID: $(cat /tmp/ollama.pid))"
    fi
    
elif [[ "$OS" == "macos" ]]; then
    log "Configuring Ollama for macOS..."
    
    # Create LaunchAgent for macOS
    mkdir -p ~/Library/LaunchAgents
    cat > ~/Library/LaunchAgents/com.ollama.server.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ollama.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/ollama</string>
        <string>serve</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OLLAMA_HOST</key>
        <string>0.0.0.0:11434</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/ollama.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/ollama-error.log</string>
</dict>
</plist>
EOF
    
    # Load the service
    launchctl load ~/Library/LaunchAgents/com.ollama.server.plist 2>/dev/null || true
    launchctl start com.ollama.server
    log "Ollama LaunchAgent configured and started"
fi

# Wait for API to be ready
log "Waiting for Ollama API..."
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        log "Ollama API is ready!"
        break
    fi
    sleep 2
    attempt=$((attempt + 1))
    echo -n "."
done
echo ""

if [ $attempt -eq $max_attempts ]; then
    error "Ollama API failed to start"
    error "Check logs:"
    if [[ "$OS" == "linux" ]]; then
        echo "  sudo journalctl -u ollama -n 50"
        echo "  sudo systemctl status ollama"
        echo "  cat /var/log/ollama/ollama-error.log"
    else
        echo "  cat /tmp/ollama-error.log"
    fi
    exit 1
fi

# Pull default model
log "Pulling default model (gemma:2b)..."
ollama pull gemma:2b || warning "Failed to pull gemma:2b"

# Test the installation
log "Testing Ollama..."
echo "Testing with prompt: 'Hello, are you working?'" | ollama run gemma:2b || warning "Test failed"

# Show final status
echo ""
log "=== Ollama Status ==="
if [[ "$OS" == "linux" ]]; then
    sudo systemctl status ollama --no-pager 2>/dev/null || sudo systemctl status ollama-user --no-pager 2>/dev/null || echo "Running directly"
fi

echo ""
log "Available models:"
ollama list

echo ""
log "✅ Ollama fix complete!"
log "API endpoint: http://localhost:11434"
log ""
log "Test with: curl http://localhost:11434/api/tags"
log "Or run: ollama run gemma:2b"