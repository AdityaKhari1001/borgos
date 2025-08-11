#!/bin/bash
# BorgOS Nginx Fix Script - Naprawia bad gateway i konfigurację

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[NGINX FIX]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

DOMAIN="borgtools.ddns.net"

log "Naprawiam konfigurację Nginx dla BorgOS..."

# Sprawdź czy nginx jest zainstalowany
if ! command -v nginx &> /dev/null; then
    log "Instaluję Nginx..."
    sudo apt-get update && sudo apt-get install -y nginx
fi

# Zatrzymaj nginx
log "Zatrzymuję Nginx..."
sudo systemctl stop nginx 2>/dev/null || true

# Utwórz prostą konfigurację
log "Tworzę konfigurację Nginx..."
sudo tee /etc/nginx/sites-available/borgos > /dev/null << 'NGINX'
# BorgOS Simple Configuration
server {
    listen 80;
    server_name borgtools.ddns.net localhost;
    
    # Główny dashboard - serwuj pliki statyczne
    location / {
        root /opt/borgos/webui;
        index index.html ai-panel.html;
        try_files $uri $uri/ /index.html;
    }
    
    # AI Panel
    location /ai {
        alias /opt/borgos/webui;
        try_files /ai-panel.html =404;
    }
    
    # API proxy (jeśli działa)
    location /api {
        proxy_pass http://localhost:8081;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_connect_timeout 5s;
        proxy_send_timeout 5s;
        proxy_read_timeout 5s;
        
        # Fallback jeśli API nie działa
        error_page 502 503 504 = @api_fallback;
    }
    
    location @api_fallback {
        return 503 '{"error": "API is temporarily unavailable"}';
        add_header Content-Type application/json;
    }
    
    # Ollama proxy
    location /ollama {
        proxy_pass http://localhost:11434;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        
        # Fallback
        error_page 502 503 504 = @ollama_fallback;
    }
    
    location @ollama_fallback {
        return 503 '{"error": "Ollama is not running. Start with: ollama serve"}';
        add_header Content-Type application/json;
    }
    
    # Health check endpoint
    location /health {
        return 200 '{"status": "ok", "service": "nginx"}';
        add_header Content-Type application/json;
    }
}

# Subdomeny (opcjonalne)
server {
    listen 80;
    server_name agent.borgtools.ddns.net;
    
    location / {
        proxy_pass http://localhost:8085;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        
        error_page 502 503 504 = @error;
    }
    
    location @error {
        root /opt/borgos/webui;
        try_files /index.html =503;
    }
}

server {
    listen 80;
    server_name n8n.borgtools.ddns.net;
    
    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        
        error_page 502 503 504 = @error;
    }
    
    location @error {
        return 503 '{"error": "Service not available"}';
        add_header Content-Type application/json;
    }
}

server {
    listen 80;
    server_name portainer.borgtools.ddns.net;
    
    location / {
        proxy_pass http://localhost:9000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        
        error_page 502 503 504 = @error;
    }
    
    location @error {
        return 503 '{"error": "Service not available"}';
        add_header Content-Type application/json;
    }
}
NGINX

# Upewnij się, że katalog webui istnieje
log "Tworzę katalog webui..."
sudo mkdir -p /opt/borgos/webui

# Skopiuj pliki HTML jeśli istnieją
if [ -f "/opt/borgos/webui/index.html" ]; then
    log "Pliki HTML już istnieją"
else
    log "Kopiuję pliki HTML..."
    if [ -d "$HOME/borgos-clean/webui" ]; then
        sudo cp -r $HOME/borgos-clean/webui/* /opt/borgos/webui/ 2>/dev/null || true
    fi
fi

# Ustaw uprawnienia
sudo chown -R www-data:www-data /opt/borgos/webui

# Włącz konfigurację
log "Włączam konfigurację..."
sudo ln -sf /etc/nginx/sites-available/borgos /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test konfiguracji
log "Testuję konfigurację..."
if sudo nginx -t; then
    log "Konfiguracja OK"
else
    error "Błąd w konfiguracji Nginx"
    exit 1
fi

# Uruchom nginx
log "Uruchamiam Nginx..."
sudo systemctl start nginx
sudo systemctl enable nginx

# Sprawdź status
sleep 2
if sudo systemctl is-active --quiet nginx; then
    log "✅ Nginx działa!"
else
    error "Nginx nie uruchomił się"
    sudo journalctl -u nginx -n 20
    exit 1
fi

# Test połączenia
log "Testuję połączenie..."
if curl -s http://localhost/health > /dev/null; then
    log "✅ Nginx odpowiada na localhost"
fi

echo ""
log "=== Status Nginx ==="
sudo systemctl status nginx --no-pager | head -n 10

echo ""
log "✅ Nginx naprawiony!"
log ""
log "Dostępne adresy:"
log "  http://localhost/ - Dashboard"
log "  http://localhost/ai - AI Panel"
log "  http://borgtools.ddns.net/ - Dashboard (jeśli DNS skonfigurowany)"
log ""
log "Jeśli nadal masz bad gateway, sprawdź czy serwisy działają:"
log "  sudo systemctl status ollama"
log "  docker ps"
log "  ollama serve"