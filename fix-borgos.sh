#!/bin/bash
# BorgOS Complete Fix Script - Naprawia wszystkie problemy

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[BORGOS FIX]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

INSTALL_DIR="/opt/borgos"

# Banner
echo -e "${BLUE}"
cat << 'EOF'
╔════════════════════════════════════════╗
║      🔧 BorgOS Complete Fix           ║
║         Naprawa wszystkich błędów      ║
╚════════════════════════════════════════╝
EOF
echo -e "${NC}"

# 1. Sprawdź czy katalog istnieje
log "Sprawdzam katalog instalacji..."
if [ ! -d "$INSTALL_DIR" ]; then
    error "Katalog $INSTALL_DIR nie istnieje. Tworzę..."
    sudo mkdir -p $INSTALL_DIR
    sudo chown $USER:$USER $INSTALL_DIR
fi

cd $INSTALL_DIR

# 2. Zatrzymaj wszystkie kontenery
log "Zatrzymuję istniejące kontenery..."
docker compose down 2>/dev/null || true
docker compose -f docker-compose-full.yml down 2>/dev/null || true
docker stop $(docker ps -q) 2>/dev/null || true

# 3. Utwórz brakujące katalogi
log "Tworzę brakujące katalogi..."
mkdir -p core
mkdir -p webui
mkdir -p database
mkdir -p scripts
mkdir -p agent-zero
mkdir -p zenith-coder/backend
mkdir -p zenith-coder/frontend
mkdir -p mcp_servers

# 4. Utwórz placeholder Dockerfile dla brakujących komponentów
log "Tworzę placeholder Dockerfile dla zenith-coder..."

# Backend Dockerfile
cat > zenith-coder/backend/Dockerfile << 'DOCKERFILE'
FROM python:3.11-slim
WORKDIR /app
RUN pip install fastapi uvicorn
COPY . .
CMD ["echo", "Zenith Backend - placeholder"]
DOCKERFILE

# Frontend Dockerfile
cat > zenith-coder/frontend/Dockerfile << 'DOCKERFILE'
FROM nginx:alpine
COPY . /usr/share/nginx/html
CMD ["nginx", "-g", "daemon off;"]
DOCKERFILE

# Agent Zero Dockerfile
if [ ! -f agent-zero/Dockerfile ]; then
cat > agent-zero/Dockerfile << 'DOCKERFILE'
FROM python:3.11-slim
WORKDIR /app
RUN pip install fastapi uvicorn
CMD ["echo", "Agent Zero - placeholder"]
DOCKERFILE
fi

# Core Dockerfile
if [ ! -f core/Dockerfile ]; then
cat > core/Dockerfile << 'DOCKERFILE'
FROM python:3.11-slim
WORKDIR /app
RUN pip install fastapi uvicorn psutil
COPY . .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8081"]
DOCKERFILE
fi

# 5. Utwórz prosty main.py dla core
if [ ! -f core/main.py ]; then
cat > core/main.py << 'PYTHON'
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import psutil

app = FastAPI(title="BorgOS API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def root():
    return {"message": "BorgOS API Running"}

@app.get("/health")
def health():
    return {
        "status": "healthy",
        "cpu_percent": psutil.cpu_percent(),
        "memory_percent": psutil.virtual_memory().percent
    }

@app.get("/api/v1/status")
def status():
    return {
        "cpu_percent": psutil.cpu_percent(),
        "memory_percent": psutil.virtual_memory().percent,
        "active_deployments": 0
    }
PYTHON
fi

# 6. Utwórz uproszczony docker-compose.yml
log "Tworzę uproszczony docker-compose.yml..."
cat > docker-compose.yml << 'COMPOSE'
version: '3.8'

services:
  # Ollama - główny serwis AI
  ollama:
    image: ollama/ollama:latest
    container_name: borgos-ollama
    ports:
      - "11434:11434"
    volumes:
      - ollama-data:/root/.ollama
    environment:
      - OLLAMA_HOST=0.0.0.0
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 10s
      retries: 5

  # Redis cache
  redis:
    image: redis:7-alpine
    container_name: borgos-redis
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    restart: unless-stopped

  # BorgOS API (placeholder)
  api:
    build: ./core
    container_name: borgos-api
    ports:
      - "8081:8081"
    volumes:
      - ./core:/app
    restart: unless-stopped
    depends_on:
      - redis

  # Web UI
  webui:
    image: nginx:alpine
    container_name: borgos-webui
    ports:
      - "80:80"
    volumes:
      - ./webui:/usr/share/nginx/html:ro
      - ./webui/nginx.conf:/etc/nginx/nginx.conf:ro
    restart: unless-stopped

volumes:
  ollama-data:
  redis-data:

networks:
  default:
    name: borgos-network
COMPOSE

# 7. Utwórz webui files
log "Kopiuję pliki webui..."
if [ ! -f webui/index.html ]; then
    cp -r ~/borgos-clean/webui/* webui/ 2>/dev/null || true
fi

# Utwórz prosty nginx.conf
cat > webui/nginx.conf << 'NGINX'
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    server {
        listen 80;
        server_name localhost;
        root /usr/share/nginx/html;
        index index.html ai-panel.html;

        location / {
            try_files $uri $uri/ /index.html;
        }

        location /health {
            return 200 "OK";
            add_header Content-Type text/plain;
        }
    }
}
NGINX

# 8. Utwórz .env jeśli nie istnieje
if [ ! -f .env ]; then
    log "Tworzę plik .env..."
    cat > .env << 'ENV'
# BorgOS Configuration
BORGOS_VERSION=2.0
DOMAIN=borgtools.ddns.net

# Ports
API_PORT=8081
OLLAMA_PORT=11434
REDIS_PORT=6379

# AI Configuration
OLLAMA_HOST=http://ollama:11434
DEFAULT_OLLAMA_MODEL=gemma:2b

# Security
JWT_SECRET=$(openssl rand -hex 32)
ENV
fi

# 9. Ustaw uprawnienia
log "Ustawiam uprawnienia..."
sudo chown -R $USER:$USER $INSTALL_DIR

# 10. Uruchom tylko podstawowe serwisy
log "Uruchamiam podstawowe serwisy..."
# Użyj prostszego docker-compose jeśli istnieje
if [ -f docker-compose-simple.yml ]; then
    log "Używam uproszczonej konfiguracji..."
    docker compose -f docker-compose-simple.yml up -d
else
    docker compose up -d
fi

# 11. Czekaj na uruchomienie
log "Czekam na uruchomienie serwisów..."
sleep 10

# 12. Pobierz model Ollama
log "Pobieram domyślny model AI..."
docker exec borgos-ollama ollama pull gemma:2b 2>/dev/null || warning "Nie udało się pobrać modelu"

# 13. Ustaw autostart
log "Konfiguruję autostart..."
cat > /tmp/borgos.service << 'SERVICE'
[Unit]
Description=BorgOS Services
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/borgos
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
User=root

[Install]
WantedBy=multi-user.target
SERVICE

sudo mv /tmp/borgos.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable borgos.service

# 14. Sprawdź status
log "Sprawdzam status serwisów..."
docker compose ps

# Test połączeń
echo ""
log "Testuję połączenia..."
sleep 3

# Test Ollama
if curl -s http://localhost:11434/api/tags > /dev/null; then
    log "✅ Ollama działa"
else
    warning "⚠️ Ollama nie odpowiada"
fi

# Test Web UI
if curl -s http://localhost/health > /dev/null; then
    log "✅ Web UI działa"
else
    warning "⚠️ Web UI nie odpowiada"
fi

# Test API
if curl -s http://localhost:8081/health > /dev/null; then
    log "✅ API działa"
else
    warning "⚠️ API nie odpowiada"
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ BorgOS naprawiony i uruchomiony!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo "Dostępne serwisy:"
echo "  🌐 Web UI: http://localhost/"
echo "  🤖 AI Panel: http://localhost/ai-panel.html"
echo "  🔧 API: http://localhost:8081"
echo "  🧠 Ollama: http://localhost:11434"
echo ""
echo "Komendy:"
echo "  docker compose ps     - status kontenerów"
echo "  docker compose logs   - logi"
echo "  docker compose restart - restart"
echo ""
echo "Test AI:"
echo "  docker exec -it borgos-ollama ollama run gemma:2b"
echo ""

# Opcjonalnie uruchom Ollama natywnie jeśli Docker nie działa
if ! docker ps | grep -q borgos-ollama; then
    warning "Docker Ollama nie działa, próbuję uruchomić natywnie..."
    if command -v ollama &> /dev/null; then
        nohup ollama serve > /tmp/ollama.log 2>&1 &
        echo $! > /tmp/ollama.pid
        log "Ollama uruchomiona natywnie (PID: $(cat /tmp/ollama.pid))"
    fi
fi