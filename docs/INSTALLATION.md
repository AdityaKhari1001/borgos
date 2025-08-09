# Installation Guide

This guide covers multiple installation methods for BorgOS.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Quick Install](#quick-install)
- [Docker Installation](#docker-installation)
- [Manual Installation](#manual-installation)
- [Create Bootable USB](#create-bootable-usb)
- [Bare Metal Installation](#bare-metal-installation)
- [Configuration](#configuration)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### System Requirements
- **OS**: Linux (Ubuntu 20.04+, Debian 11+), macOS 12+, or Windows with WSL2
- **RAM**: 4GB minimum (8GB recommended)
- **Storage**: 20GB free space
- **CPU**: 2+ cores (4+ recommended)

### Software Requirements
- Docker 20.10+ and Docker Compose 2.0+
- Python 3.11+ (for manual installation)
- Git

### API Keys
At least one AI provider API key:
- OpenAI API key
- Anthropic API key
- Or local Ollama installation

## Quick Install

### One-Line Installation

```bash
curl -fsSL https://raw.githubusercontent.com/yourusername/borgos/main/install.sh | bash
```

This script will:
1. Check system requirements
2. Install Docker if needed
3. Download BorgOS
4. Configure environment
5. Start all services

## Docker Installation

### 1. Clone Repository

```bash
git clone https://github.com/yourusername/borgos.git
cd borgos
```

### 2. Configure Environment

```bash
# Copy environment template
cp .env.example .env

# Edit with your API keys
nano .env
```

Required configuration:
```env
OPENAI_API_KEY=sk-...
# OR
ANTHROPIC_API_KEY=sk-ant-...

DB_PASSWORD=your-secure-password
SECRET_KEY=your-secret-key
```

### 3. Start Services

```bash
# Start all services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f
```

### 4. Access BorgOS

- Dashboard: http://localhost:8080
- API: http://localhost:8081
- Agent Zero UI: http://localhost:8085

## Manual Installation

### 1. Install System Dependencies

#### Ubuntu/Debian
```bash
sudo apt update
sudo apt install -y \
    python3.11 python3.11-venv python3-pip \
    postgresql-14 redis-server \
    git curl wget build-essential
```

#### macOS
```bash
brew install python@3.11 postgresql@14 redis git
```

### 2. Clone and Setup

```bash
# Clone repository
git clone https://github.com/yourusername/borgos.git
cd borgos

# Create virtual environment
python3.11 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r core/requirements.txt
```

### 3. Setup Database

```bash
# Start PostgreSQL
sudo systemctl start postgresql

# Create database and user
sudo -u postgres psql << EOF
CREATE DATABASE borgos;
CREATE USER borgos WITH PASSWORD 'your-password';
GRANT ALL PRIVILEGES ON DATABASE borgos TO borgos;
EOF

# Initialize schema
psql -U borgos -d borgos -f database/init.sql
```

### 4. Start Services

```bash
# Start Redis
redis-server &

# Start ChromaDB
docker run -d -p 8010:8000 chromadb/chroma

# Start BorgOS API
cd core
python main.py &

# Start Dashboard
cd ../webui
python -m http.server 8080 &
```

## Create Bootable USB

### 1. Download or Build ISO

```bash
# Option A: Download pre-built ISO
wget https://github.com/yourusername/borgos/releases/latest/borgos-v2.0.iso

# Option B: Build ISO locally
cd borgos
sudo ./create_borgos_linux_usb.sh
```

### 2. Create Bootable USB

#### Using the Script
```bash
sudo ./burn-to-usb.sh
```

#### Manual Method
```bash
# Find your USB device
lsblk

# Write ISO to USB (replace /dev/sdX with your device)
sudo dd if=borgos-v2.0.iso of=/dev/sdX bs=4M status=progress
sync
```

### 3. Boot and Install

1. Insert USB into target computer
2. Boot from USB (press F12/F2/ESC during startup)
3. Select "Install BorgOS" from menu
4. Follow installation wizard

## Bare Metal Installation

For permanent installation on a dedicated machine:

### 1. Boot from USB

Create bootable USB as described above and boot from it.

### 2. Run Installer

```bash
# Quick install with defaults
sudo ./quick-install.sh

# Or custom installation
sudo ./install-to-disk.sh
```

### 3. Installation Options

The installer will prompt for:
- Target disk
- Installation type (Full/Server/Minimal)
- Username and password
- Timezone
- Network configuration

### 4. Post-Installation

After installation completes:
1. Remove USB drive
2. Reboot system
3. Login with created credentials
4. BorgOS starts automatically

## Configuration

### Essential Configuration

Edit `.env` file:

```env
# Required: AI Provider (choose one)
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
OLLAMA_API_BASE_URL=http://localhost:11434

# Database (change password!)
DB_PASSWORD=secure-password-here

# Security (generate new keys!)
SECRET_KEY=generate-random-32-char-key
JWT_SECRET_KEY=generate-another-key
```

### Generate Secure Keys

```bash
# Generate secret key
python -c "import secrets; print(secrets.token_hex(32))"

# Generate JWT key
openssl rand -base64 32
```

### Agent Configuration

```env
# Enable/disable agents
AGENT_ZERO_ENABLED=true
ZENITH_ENABLED=true
MCP_ENABLED=true

# Auto-start Agent Zero
AGENT_ZERO_AUTOSTART=false

# Model selection
CHAT_MODEL=gpt-4o-mini
EMBEDDING_MODEL=text-embedding-3-small
```

### Resource Limits

```env
# API Resources
API_WORKERS=4
MAX_CONTEXT_LENGTH=128000
MAX_TOKENS=4000

# Database
POSTGRES_MAX_CONNECTIONS=100
REDIS_MAX_MEMORY=512mb

# Docker
DOCKER_CPU_LIMIT=2
DOCKER_MEMORY_LIMIT=2g
```

## Verification

### Check Installation

```bash
# Check all services are running
docker-compose ps

# Test API health
curl http://localhost:8081/health

# Test Agent Zero
curl http://localhost:8081/api/v1/agent-zero/status

# Check logs for errors
docker-compose logs | grep ERROR
```

### Run Test Suite

```bash
# Install test dependencies
pip install pytest pytest-asyncio pytest-cov

# Run tests
pytest tests/

# With coverage
pytest --cov=core tests/
```

## Troubleshooting

### Common Issues

#### Docker Permission Denied
```bash
# Add user to docker group
sudo usermod -aG docker $USER
# Log out and back in
```

#### Port Already in Use
```bash
# Find process using port
sudo lsof -i :8080
# Kill process
sudo kill -9 <PID>
```

#### Database Connection Failed
```bash
# Check PostgreSQL is running
docker-compose logs postgres

# Reset database
docker-compose down -v
docker-compose up -d
```

#### Agent Zero Not Starting
```bash
# Check Agent Zero logs
docker-compose logs agent-zero-exe

# Restart Agent Zero
curl -X POST http://localhost:8081/api/v1/agent-zero/restart
```

#### Insufficient Memory
```bash
# Check available memory
free -h

# Reduce resource limits in .env
API_WORKERS=2
DOCKER_MEMORY_LIMIT=1g
```

### Getting Help

- Check logs: `docker-compose logs -f`
- Documentation: [docs.borgos.ai](https://docs.borgos.ai)
- GitHub Issues: [github.com/yourusername/borgos/issues](https://github.com/yourusername/borgos/issues)
- Discord: [discord.gg/borgos](https://discord.gg/borgos)

## Next Steps

After successful installation:

1. **Configure Agents**: Set up Agent Zero and Zenith Coder
2. **Create First Project**: Use the dashboard to create and scan projects
3. **Deploy Applications**: Use auto-deployment features
4. **Explore API**: Check [API documentation](API.md)
5. **Customize**: Add custom agents and tools

## Updating BorgOS

### Docker Update
```bash
cd borgos
git pull
docker-compose pull
docker-compose up -d
```

### Manual Update
```bash
cd borgos
git pull
pip install -r core/requirements.txt --upgrade
# Restart services
```

## Uninstalling

### Docker Uninstall
```bash
# Stop and remove containers
docker-compose down -v

# Remove images
docker rmi $(docker images -q borgos-*)

# Remove directory
rm -rf borgos/
```

### Manual Uninstall
```bash
# Stop services
pkill -f borgos

# Remove database
sudo -u postgres dropdb borgos
sudo -u postgres dropuser borgos

# Remove files
rm -rf /opt/borgos
rm -rf ~/borgos
```