#!/usr/bin/env bash
# ============================================================================
#  BorgOS Installer – v1.0 (Modified for external drive)
#  Target HW : x86_64 systems
#  Goal      : offline-first AI OS with online fallback (OpenRouter),
#              vector memory, MCP client+server, natural-language CLI,
#              headless + WebUI, plus common dev services (nginx/FTP/n8n).
#  License   : MIT – hack away!
# ----------------------------------------------------------------------------
#  BIG STEPS
#     0.  Run on fresh Debian 12 netinst (64-bit, minimal, SSH enabled)
#     1.  Base packages + dev toolchain
#     2.  Python env + dependencies
#     3.  Ollama (local LLMs) + pull tiny models
#     4.  Online LLM via OpenRouter (OpenAI-compatible)
#     5.  Vector DB (Chroma) + embedding model
#     6.  MCP Python SDK – both server & client helpers
#     7.  Natural-language CLI alias "borg" (offline ↔ online auto-switch)
#     8.  Services: nginx, vsftpd, n8n (Docker), watchdog systemd units
#     9.  WebUI dashboard (Flask) port 6969
#    10.  Plugin system initialization
# ============================================================================

set -e  # stop on error
set -o pipefail

# Configuration
BORGOS_VERSION="1.0"
INSTALL_PREFIX="/opt/borgos"
VENV_PATH="$INSTALL_PREFIX/env"
LOG_FILE="/var/log/borgos-install.log"
PROFILE="${1:-default}"  # Support profile-based installation

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[+]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[!]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warn() {
    echo -e "${YELLOW}[*]${NC} $1" | tee -a "$LOG_FILE"
}

# 0. DETECT ROOT --------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    error "Run as root (sudo su)"
fi

log "BorgOS Installer v${BORGOS_VERSION} - Profile: ${PROFILE}"
log "Installation started at $(date)"

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

# 1. UPDATE & BASE TOOLS ------------------------------------------------------
log "Installing base packages..."
apt-get update -y >> "$LOG_FILE" 2>&1
apt-get upgrade -y >> "$LOG_FILE" 2>&1
apt-get install -y \
    build-essential git curl wget unzip htop tmux vim \
    python3 python3-venv python3-pip python3-dev \
    gcc g++ make pkg-config cmake \
    ca-certificates gnupg lsb-release \
    sqlite3 dnsutils net-tools ufw neofetch \
    jq ripgrep fd-find bat \
    >> "$LOG_FILE" 2>&1

# 2. PYTHON VENV + DEPENDENCIES ----------------------------------------------
log "Setting up Python environment..."
mkdir -p "$INSTALL_PREFIX"
cd "$INSTALL_PREFIX"

# Create virtual environment
python3 -m venv "$VENV_PATH"
source "$VENV_PATH/bin/activate"

# Upgrade pip
pip install --upgrade pip wheel setuptools >> "$LOG_FILE" 2>&1

# Install core Python packages
pip install \
    flask \
    gunicorn \
    requests \
    pyyaml \
    python-dotenv \
    click \
    rich \
    >> "$LOG_FILE" 2>&1

# 3. OLLAMA (LOCAL LLM) -------------------------------------------------------
log "Installing Ollama..."
if ! command -v ollama &>/dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh >> "$LOG_FILE" 2>&1
fi

# Create systemd service for Ollama with optimizations for 8GB RAM and external drive
log "Configuring Ollama to use external drive /mnt/data/ollama"
mkdir -p /mnt/data/ollama/models
cat > /etc/systemd/system/ollama.service <<'EOF'
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ollama serve
Restart=always
RestartSec=3
Environment="OLLAMA_HOST=0.0.0.0"
Environment="OLLAMA_MODELS=/mnt/data/ollama/models"
Environment="OLLAMA_NUM_THREADS=4"
Environment="OLLAMA_MAX_LOADED_MODELS=1"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ollama.service >> "$LOG_FILE" 2>&1

# Pull optimized models for 8GB RAM
log "Pulling optimized models for offline use (this may take 10-15 minutes)..."
sleep 5  # Give Ollama time to start

# Primary model - Mistral 7B (best for coding and general use)
log "Pulling Mistral 7B (4.1GB)..."
ollama pull mistral:7b-instruct-q4_K_M >> "$LOG_FILE" 2>&1 || warn "Failed to pull Mistral 7B"

# Backup model - Llama 3.2 3B (faster, lighter)
log "Pulling Llama 3.2 3B backup model (2GB)..."
ollama pull llama3.2:3b-instruct-q4_K_M >> "$LOG_FILE" 2>&1 || warn "Failed to pull Llama 3.2"

# Set default model
export BORG_OFFLINE_MODEL="mistral:7b-instruct-q4_K_M"
echo 'export BORG_OFFLINE_MODEL="mistral:7b-instruct-q4_K_M"' >> /etc/profile.d/borgos.sh

# 4. OPENROUTER CONFIG --------------------------------------------------------
log "Configuring OpenRouter..."
pip install openai >> "$LOG_FILE" 2>&1

cat <<'EOF' > /etc/profile.d/openrouter.sh
export OPENAI_API_BASE="https://openrouter.ai/api/v1"
# Set OPENAI_API_KEY environment variable with your key
EOF
chmod +x /etc/profile.d/openrouter.sh

# 5. VECTOR MEMORY (CHROMA) --------------------------------------------------
log "Installing ChromaDB..."
pip install chromadb sentence-transformers >> "$LOG_FILE" 2>&1

# Create database directory
mkdir -p "$INSTALL_PREFIX/chroma_db"

# Install additional AI dependencies
log "Installing AI provider libraries..."
pip install huggingface-hub transformers >> "$LOG_FILE" 2>&1

# Copy model manager
if [ -f "../model_manager.py" ]; then
    cp ../model_manager.py "$INSTALL_PREFIX/"
else
    log "Model manager not found in repo, will be created later"
fi

# Create configuration directory
mkdir -p /etc/borgos
cat > /etc/borgos/config.yaml <<'YAML'
providers:
  ollama:
    enabled: true
    default_model: mistral:7b-instruct-q4_K_M
    fallback_model: llama3.2:3b-instruct-q4_K_M
    host: http://localhost:11434
    
  openrouter:
    enabled: true
    api_key: ${OPENROUTER_API_KEY}
    use_free_only: true
    max_cost_per_day: 0.00
    preferred_free_models:
      - huggingfaceh4/zephyr-7b-beta:free
      - openchat/openchat-7b:free
      - mistralai/mistral-7b-instruct:free
    
  huggingface:
    enabled: true
    api_key: ${HF_API_KEY}
    use_free_tier: true
    preferred_models:
      - mistralai/Mistral-7B-Instruct-v0.2
      - google/flan-t5-xxl
      - codellama/CodeLlama-7b-Instruct-hf
      
routing:
  strategy: cost_optimized  # cost_optimized | quality_first | balanced
  fallback_enabled: true
  complexity_routing: true
  auto_select_threshold: 0.7
  
ui:
  port: 6969
  theme: dark
  auth:
    enabled: false
  features:
    model_switcher: true
    cost_tracker: true
    system_monitor: true
    file_manager: true
YAML

# 6. MCP CLIENT & SERVER ------------------------------------------------------
log "Setting up MCP infrastructure..."
pip install mcp anthropic >> "$LOG_FILE" 2>&1

# Copy MCP server from repo if it exists
if [ -f "../mcp_servers/fs_server.py" ]; then
    cp -r ../mcp_servers "$INSTALL_PREFIX/"
else
    # Create default MCP server
    mkdir -p "$INSTALL_PREFIX/mcp_servers"
    cat <<'PY' > "$INSTALL_PREFIX/mcp_servers/fs_server.py"
#!/usr/bin/env python3
from mcp.server import Server, Resource, Tool
import os
import asyncio
import json
from pathlib import Path

srv = Server(name="filesystem", description="Expose filesystem operations")

@srv.tool(name="listdir", description="List files in a directory")
async def listdir(path: str = "."):
    try:
        return {"files": os.listdir(path)}
    except Exception as e:
        return {"error": str(e)}

@srv.tool(name="read_file", description="Read contents of a file")
async def read_file(path: str):
    try:
        with open(path, 'r') as f:
            return {"content": f.read()}
    except Exception as e:
        return {"error": str(e)}

@srv.tool(name="write_file", description="Write contents to a file")
async def write_file(path: str, content: str):
    try:
        with open(path, 'w') as f:
            f.write(content)
        return {"success": True}
    except Exception as e:
        return {"error": str(e)}

if __name__ == "__main__":
    asyncio.run(srv.serve("127.0.0.1", 7300))
PY
fi

# Create systemd service for MCP server
cat > /etc/systemd/system/borgos-mcp.service <<EOF
[Unit]
Description=BorgOS MCP Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_PREFIX/mcp_servers
ExecStart=$VENV_PATH/bin/python fs_server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# 7. NATURAL LANGUAGE CLI WRAPPER --------------------------------------------
log "Installing Borg CLI..."
cat <<'PY' > /usr/local/bin/borg
#!/usr/bin/env python3
"""Borg CLI – Natural language interface to BorgOS."""
import os
import sys
import subprocess
import json
import socket
import requests
from pathlib import Path

OFFLINE_MODEL = os.getenv("BORG_OFFLINE_MODEL", "mistral:7b-instruct-q4_K_M")
OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://localhost:11434")

def check_online():
    """Check if we have internet connectivity."""
    try:
        requests.get("https://1.1.1.1", timeout=2)
        return True
    except requests.exceptions.RequestException:
        return False

def query_ollama(prompt):
    """Query local Ollama instance."""
    try:
        import ollama
        response = ollama.chat(
            model=OFFLINE_MODEL,
            messages=[{"role": "user", "content": prompt}]
        )
        return response['message']['content']
    except Exception as e:
        return f"Error querying Ollama: {e}"

def query_openrouter(prompt):
    """Query OpenRouter API."""
    try:
        import openai
        openai.api_key = os.getenv("OPENAI_API_KEY")
        openai.base_url = os.getenv("OPENAI_API_BASE", "https://openrouter.ai/api/v1")
        
        response = openai.chat.completions.create(
            model="openrouter/auto",
            messages=[{"role": "user", "content": prompt}]
        )
        return response.choices[0].message.content
    except Exception as e:
        return f"Error querying OpenRouter: {e}"

def main():
    # Get prompt from arguments or stdin
    if len(sys.argv) > 1:
        prompt = " ".join(sys.argv[1:])
    else:
        prompt = input("borg> ")
    
    # Determine which backend to use
    online = check_online()
    has_api_key = bool(os.getenv("OPENAI_API_KEY"))
    
    if online and has_api_key:
        print("[Using OpenRouter]")
        result = query_openrouter(prompt)
    else:
        print("[Using Ollama]")
        result = query_ollama(prompt)
    
    print(result)

if __name__ == "__main__":
    main()
PY
chmod +x /usr/local/bin/borg

# Install ollama Python client
pip install ollama >> "$LOG_FILE" 2>&1

# 8. SERVICES: NGINX, VSFTPD, N8N --------------------------------------------
log "Installing services..."

# Nginx
apt-get install -y nginx >> "$LOG_FILE" 2>&1
systemctl enable nginx >> "$LOG_FILE" 2>&1

# vsftpd
apt-get install -y vsftpd >> "$LOG_FILE" 2>&1
sed -i 's/^#anonymous_enable=.*/anonymous_enable=YES/' /etc/vsftpd.conf
sed -i 's/^#write_enable=.*/write_enable=YES/' /etc/vsftpd.conf
systemctl enable vsftpd >> "$LOG_FILE" 2>&1

# Docker for n8n
if ! command -v docker &>/dev/null; then
    log "Installing Docker..."
    curl -fsSL https://get.docker.com | sh >> "$LOG_FILE" 2>&1
    systemctl enable docker >> "$LOG_FILE" 2>&1
fi

log "Configuring Docker to use external drive /mnt/data/docker"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "data-root": "/mnt/data/docker"
}
EOF
systemctl restart docker

# Run n8n in Docker
log "Starting n8n workflow automation..."
docker run -d \
    --name n8n \
    --restart always \
    -p 5678:5678 \
    -v n8n_data:/home/node/.n8n \
    n8nio/n8n >> "$LOG_FILE" 2>&1 || warn "n8n container failed to start"

# 9. BORGOS DASHBOARD (Flask) ------------------------------------------------
log "Setting up WebUI dashboard..."

# Copy WebUI from repo if it exists
if [ -f "../webui/app.py" ]; then
    cp -r ../webui "$INSTALL_PREFIX/"
else
    # Create default WebUI
    mkdir -p "$INSTALL_PREFIX/webui"
    cat <<'PY' > "$INSTALL_PREFIX/webui/app.py"
#!/usr/bin/env python3
from flask import Flask, request, jsonify, render_template_string, session
import subprocess
import os
import json
import psutil
from datetime import datetime

app = Flask(__name__)
app.secret_key = os.urandom(24)

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>BorgOS Dashboard</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); margin: 0; padding: 20px; color: white; }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 { text-align: center; font-size: 3em; margin-bottom: 30px; text-shadow: 2px 2px 4px rgba(0,0,0,0.3); }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-bottom: 40px; }
        .stat-card { background: rgba(255,255,255,0.1); backdrop-filter: blur(10px); border-radius: 15px; padding: 20px; box-shadow: 0 8px 32px 0 rgba(31, 38, 135, 0.37); }
        .stat-title { font-size: 0.9em; opacity: 0.8; margin-bottom: 5px; }
        .stat-value { font-size: 2em; font-weight: bold; }
        .terminal { background: rgba(0,0,0,0.8); border-radius: 15px; padding: 20px; margin-top: 20px; box-shadow: 0 8px 32px 0 rgba(31, 38, 135, 0.37); }
        .terminal-header { display: flex; align-items: center; margin-bottom: 15px; }
        .terminal-dot { width: 12px; height: 12px; border-radius: 50%; margin-right: 8px; }
        .dot-red { background: #ff5f56; }
        .dot-yellow { background: #ffbd2e; }
        .dot-green { background: #27c93f; }
        form { display: flex; gap: 10px; }
        input[name="q"] { flex: 1; padding: 12px; border: none; border-radius: 8px; background: rgba(255,255,255,0.1); color: white; font-size: 16px; }
        input[name="q"]::placeholder { color: rgba(255,255,255,0.5); }
        button { padding: 12px 30px; border: none; border-radius: 8px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; font-size: 16px; cursor: pointer; transition: transform 0.2s; }
        button:hover { transform: translateY(-2px); }
        pre { background: transparent; color: #0f0; font-family: 'Courier New', monospace; margin: 0; padding: 10px; white-space: pre-wrap; word-wrap: break-word; }
        .services { display: flex; gap: 10px; margin-top: 20px; }
        .service { padding: 8px 16px; border-radius: 20px; font-size: 0.9em; }
        .service-up { background: rgba(39, 201, 63, 0.3); border: 1px solid #27c93f; }
        .service-down { background: rgba(255, 95, 86, 0.3); border: 1px solid #ff5f56; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🤖 BorgOS Dashboard</h1>
        
        <div class="stats">
            <div class="stat-card">
                <div class="stat-title">CPU Usage</div>
                <div class="stat-value">{{ cpu }}%</div>
            </div>
            <div class="stat-card">
                <div class="stat-title">Memory</div>
                <div class="stat-value">{{ memory }}%</div>
            </div>
            <div class="stat-card">
                <div class="stat-title">Disk</div>
                <div class="stat-value">{{ disk }}%</div>
            </div>
            <div class="stat-card">
                <div class="stat-title">Uptime</div>
                <div class="stat-value">{{ uptime }}</div>
            </div>
        </div>
        
        <div class="terminal">
            <div class="terminal-header">
                <div class="terminal-dot dot-red"></div>
                <div class="terminal-dot dot-yellow"></div>
                <div class="terminal-dot dot-green"></div>
            </div>
            <form method="post">
                <input name="q" placeholder="Ask Borg anything..." autocomplete="off">
                <button type="submit">Send</button>
            </form>
            {% if output %}
            <pre>{{ output }}</pre>
            {% endif %}
        </div>
        
        <div class="services">
            {% for service, status in services.items() %}
            <div class="service {{ 'service-up' if status else 'service-down' }}">
                {{ service }}: {{ 'UP' if status else 'DOWN' }}
            </div>
            {% endfor %}
        </div>
    </div>
</body>
</html>
"

def get_system_stats():
    """Get system statistics."""
    stats = {
        'cpu': psutil.cpu_percent(interval=1),
        'memory': psutil.virtual_memory().percent,
        'disk': psutil.disk_usage('/').percent,
        'uptime': get_uptime()
    }
    return stats

def get_uptime():
    """Get system uptime."""
    with open('/proc/uptime', 'r') as f:
        uptime_seconds = float(f.readline().split()[0])
    
    days = int(uptime_seconds // 86400)
    hours = int((uptime_seconds % 86400) // 3600)
    
    if days > 0:
        return f"{days}d {hours}h"
    else:
        return f"{hours}h"

def check_services():
    """Check status of key services."""
    services = {
        'Ollama': check_service('ollama'),
        'Nginx': check_service('nginx'),
        'MCP': check_service('borgos-mcp'),
        'Docker': check_service('docker')
    }
    return services

def check_service(name):
    """Check if a service is running."""
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', name],
            capture_output=True,
            text=True
        )
        return result.stdout.strip() == 'active'
    except:
        return False

@app.route('/', methods=['GET', 'POST'])
def home():
    output = ""
    if request.method == 'POST':
        query = request.form.get('q', '')
        if query:
            try:
                result = subprocess.run(
                    ['borg', query],
                    capture_output=True,
                    text=True,
                    timeout=30
                )
                output = result.stdout or result.stderr
            except subprocess.TimeoutExpired:
                output = "Command timed out after 30 seconds"
            except Exception as e:
                output = f"Error: {str(e)}"
    
    stats = get_system_stats()
    services = check_services()
    
    return render_template_string(
        HTML_TEMPLATE,
        output=output,
        services=services,
        **stats
    )

@app.route('/api/query', methods=['POST'])
def api_query():
    """API endpoint for queries."""
    data = request.json
    query = data.get('query', '')
    
    if not query:
        return jsonify({'error': 'No query provided'}), 400
    
    try:
        result = subprocess.run(
            ['borg', query],
            capture_output=True,
            text=True,
            timeout=30
        )
        return jsonify({
            'query': query,
            'response': result.stdout,
            'error': result.stderr if result.returncode != 0 else None
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/stats', methods=['GET'])
def api_stats():
    """API endpoint for system statistics."""
    return jsonify({
        'stats': get_system_stats(),
        'services': check_services(),
        'timestamp': datetime.now().isoformat()
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=6969, debug=False)
PY
fi

# Install psutil for system monitoring
pip install psutil >> "$LOG_FILE" 2>&1

# Create systemd service for WebUI
cat > /etc/systemd/system/borgos-webui.service <<EOF
[Unit]
Description=BorgOS WebUI Dashboard
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_PREFIX/webui
ExecStart=$VENV_PATH/bin/python app.py
Restart=always
RestartSec=3
Environment="PYTHONPATH=$INSTALL_PREFIX"

[Install]
WantedBy=multi-user.target
EOF

# 10. PLUGIN SYSTEM ----------------------------------------------------------
log "Initializing plugin system..."
mkdir -p "$INSTALL_PREFIX/plugins"

# Create plugin loader
cat <<'PY' > "$INSTALL_PREFIX/plugin_loader.py"
#!/usr/bin/env python3
"""BorgOS Plugin Loader."""
import os
import importlib.util
from pathlib import Path

class PluginLoader:
    def __init__(self, plugin_dir="/opt/borgos/plugins"):
        self.plugin_dir = Path(plugin_dir)
        self.plugins = {}
    
    def load_plugins(self):
        """Load all Python plugins from the plugin directory."""
        if not self.plugin_dir.exists():
            return
        
        for plugin_file in self.plugin_dir.glob("*.py"):
            if plugin_file.name.startswith("_"):
                continue
            
            plugin_name = plugin_file.stem
            spec = importlib.util.spec_from_file_location(plugin_name, plugin_file)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            
            self.plugins[plugin_name] = module
            print(f"Loaded plugin: {plugin_name}")
    
    def get_plugin(self, name):
        """Get a loaded plugin by name."""
        return self.plugins.get(name)

if __name__ == "__main__":
    loader = PluginLoader()
    loader.load_plugins()
PY

# Create example plugin
cat <<'PY' > "$INSTALL_PREFIX/plugins/example.py"
#!/usr/bin/env python3
"""Example BorgOS Plugin."""

from borg.plugin import Tool

@Tool(name="hello", desc="Say hello")
async def hello(name: str = "world"):
    return f"Hello {name}! This is an example plugin."

@Tool(name="system_info", desc="Get system information")
async def system_info():
    import platform
    return {
        "system": platform.system(),
        "node": platform.node(),
        "release": platform.release(),
        "version": platform.version(),
        "machine": platform.machine(),
        "processor": platform.processor()
    }
PY

# FINALIZATION ---------------------------------------------------------------
log "Finalizing installation..."

# Enable and start all services
systemctl daemon-reload
systemctl enable borgos-mcp.service >> "$LOG_FILE" 2>&1
systemctl enable borgos-webui.service >> "$LOG_FILE" 2>&1

# Start services
systemctl start ollama.service >> "$LOG_FILE" 2>&1 || warn "Ollama service failed to start"
systemctl start borgos-mcp.service >> "$LOG_FILE" 2>&1 || warn "MCP service failed to start"
systemctl start borgos-webui.service >> "$LOG_FILE" 2>&1 || warn "WebUI service failed to start"
systemctl start nginx >> "$LOG_FILE" 2>&1 || warn "Nginx failed to start"
systemctl start vsftpd >> "$LOG_FILE" 2>&1 || warn "vsftpd failed to start"

# Configure firewall
log "Configuring firewall..."
ufw --force enable >> "$LOG_FILE" 2>&1
ufw allow 22/tcp >> "$LOG_FILE" 2>&1    # SSH
ufw allow 80/tcp >> "$LOG_FILE" 2>&1    # HTTP
ufw allow 443/tcp >> "$LOG_FILE" 2>&1   # HTTPS
ufw allow 6969/tcp >> "$LOG_FILE" 2>&1  # WebUI
ufw allow 5678/tcp >> "$LOG_FILE" 2>&1  # n8n
ufw allow 7300/tcp >> "$LOG_FILE" 2>&1  # MCP

# Create welcome message
cat > /etc/motd <<'EOF'
╔══════════════════════════════════════════════════════════════╗
║                     Welcome to BorgOS v1.0                   ║
║                                                              ║
║  Natural Language CLI: borg <your prompt>                   ║
║  Web Dashboard: http://localhost:6969                       ║
║  Workflow Automation: http://localhost:5678                 ║
║                                                              ║
║  Services:
║   • Ollama (Local LLM): systemctl status ollama            ║
║   • MCP Server: systemctl status borgos-mcp                ║
║   • WebUI: systemctl status borgos-webui                   ║
║                                                              ║
║  Docs: https://github.com/borgos/docs                      ║
╚══════════════════════════════════════════════════════════════╝
EOF

# Create uninstall script
cat > "$INSTALL_PREFIX/uninstall.sh" <<'EOF'
#!/bin/bash
echo "Uninstalling BorgOS..."
systemctl stop borgos-mcp borgos-webui ollama
systemctl disable borgos-mcp borgos-webui ollama
rm -f /etc/systemd/system/borgos-*.service
rm -f /etc/systemd/system/ollama.service
rm -rf /opt/borgos
rm -f /usr/local/bin/borg
docker stop n8n && docker rm n8n
echo "BorgOS uninstalled."
EOF
chmod +x "$INSTALL_PREFIX/uninstall.sh"

# Final summary
echo ""
echo "============================================================"
log "BorgOS installation completed successfully!"
echo "============================================================"
echo ""
echo "Quick Start:"
echo "  1. Set your OpenRouter API key (optional):"
echo "     export OPENAI_API_KEY='your-key-here'"
echo ""
echo "  2. Try the natural language CLI:"
echo "     borg 'What is the weather today?'"
echo ""
echo "  3. Access the web dashboard:"
echo "     http://$(hostname -I | awk '{print $1}'):6969"
echo ""
echo "  4. View logs:"
echo "     journalctl -u borgos-webui -f"
echo ""
echo "Installation log: $LOG_FILE"
echo "============================================================"