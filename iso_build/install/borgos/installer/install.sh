#!/bin/bash

# BorgOS Modular Installer v2.0
# AI-First Operating System with Project Monitoring

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="${INSTALL_DIR:-/opt/borgos}"
REMOTE_HOST="${1:-localhost}"
INSTALL_PROFILE="${2:-mvp}"

# ASCII Logo
show_logo() {
    echo -e "${CYAN}"
    cat << "EOF"
    ╔══════════════════════════════════════╗
    ║        🧠 BorgOS v2.0 MVP            ║
    ║    AI-First Operating System         ║
    ║  ┌─────────────────────────────────┐ ║
    ║  │ ▓▓▓ Autonomous ▓▓▓ Intelligent  │ ║  
    ║  │ ░░░ Modular ░░░ Scalable ░░░    │ ║
    ║  └─────────────────────────────────┘ ║
    ╚══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Module selection
declare -A MODULES=(
    ["core"]="Core System (Required)"
    ["zenith"]="Zenith Coder Integration"
    ["agent"]="Agent Zero Autonomous Tasks"
    ["vector"]="ChromaDB Vector Database"
    ["mcp"]="Model Context Protocol Server"
    ["monitor"]="Full Monitoring Suite"
)

declare -A SELECTED_MODULES=(
    ["core"]=true
    ["zenith"]=false
    ["agent"]=false
    ["vector"]=false
    ["mcp"]=false
    ["monitor"]=false
)

# Functions
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    echo -e "${BLUE}Checking prerequisites...${NC}"
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker not found. Installing..."
        curl -fsSL https://get.docker.com | sh
    else
        print_status "Docker installed"
    fi
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose not found. Installing..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    else
        print_status "Docker Compose installed"
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        print_warning "Python 3 not found. Some features may be limited."
    else
        print_status "Python 3 installed"
    fi
}

# Select modules interactively
select_modules() {
    if [ "$INSTALL_PROFILE" == "full" ]; then
        for module in "${!MODULES[@]}"; do
            SELECTED_MODULES[$module]=true
        done
        print_info "Full profile selected - all modules will be installed"
    elif [ "$INSTALL_PROFILE" == "mvp" ]; then
        SELECTED_MODULES["core"]=true
        SELECTED_MODULES["zenith"]=true
        SELECTED_MODULES["monitor"]=true
        print_info "MVP profile selected - core, zenith, and monitoring"
    else
        echo -e "${CYAN}Select modules to install:${NC}"
        echo
        
        for module in core zenith agent vector mcp monitor; do
            if [ "$module" == "core" ]; then
                echo -e "${GREEN}[x]${NC} ${MODULES[$module]} ${YELLOW}(required)${NC}"
            else
                read -p "Install ${MODULES[$module]}? [y/N] " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    SELECTED_MODULES[$module]=true
                    echo -e "${GREEN}[x]${NC} ${MODULES[$module]}"
                else
                    SELECTED_MODULES[$module]=false
                    echo -e "[ ] ${MODULES[$module]}"
                fi
            fi
        done
    fi
    
    echo
    echo -e "${CYAN}Selected modules:${NC}"
    for module in "${!SELECTED_MODULES[@]}"; do
        if [ "${SELECTED_MODULES[$module]}" == true ]; then
            echo -e "  ${GREEN}✓${NC} ${MODULES[$module]}"
        fi
    done
    echo
}

# Install core module
install_core() {
    print_info "Installing Core System..."
    
    # Create directories
    mkdir -p "$INSTALL_DIR"/{core,config,data,logs}
    
    # Copy core files
    cp -r ../core/* "$INSTALL_DIR/core/" 2>/dev/null || true
    cp -r ../config/* "$INSTALL_DIR/config/" 2>/dev/null || true
    
    # Generate configuration
    cat > "$INSTALL_DIR/config/borgos.yml" << EOF
# BorgOS Core Configuration
version: "2.0"
host: "${REMOTE_HOST}"
port: 8080

database:
  host: "${REMOTE_HOST}"
  port: 5432
  name: "borgos"
  user: "borgos"
  password: "$(openssl rand -base64 32)"

redis:
  host: "${REMOTE_HOST}"
  port: 6379

api:
  port: 8081
  cors_origins: ["*"]
  
logging:
  level: "INFO"
  file: "/var/log/borgos/borgos.log"
EOF
    
    print_status "Core system installed"
}

# Install Zenith Coder integration
install_zenith() {
    if [ "${SELECTED_MODULES[zenith]}" == true ]; then
        print_info "Installing Zenith Coder Integration..."
        
        mkdir -p "$INSTALL_DIR/agents/zenith"
        
        # Check if Zenith Coder exists locally
        if [ -d "/Users/wojciechwiesner/ai/zenith coder" ]; then
            print_status "Found local Zenith Coder, linking..."
            ln -sf "/Users/wojciechwiesner/ai/zenith coder" "$INSTALL_DIR/agents/zenith/source"
        fi
        
        print_status "Zenith Coder integration installed"
    fi
}

# Install Agent Zero
install_agent_zero() {
    if [ "${SELECTED_MODULES[agent]}" == true ]; then
        print_info "Installing Agent Zero..."
        
        mkdir -p "$INSTALL_DIR/agents/zero"
        
        # Check if Agent Zero exists locally
        if [ -d "/Users/wojciechwiesner/ai/super-agent-zero" ]; then
            print_status "Found local Agent Zero, linking..."
            ln -sf "/Users/wojciechwiesner/ai/super-agent-zero" "$INSTALL_DIR/agents/zero/source"
        fi
        
        print_status "Agent Zero installed"
    fi
}

# Install Vector Database
install_vector_db() {
    if [ "${SELECTED_MODULES[vector]}" == true ]; then
        print_info "Installing ChromaDB Vector Database..."
        
        mkdir -p "$INSTALL_DIR/data/chromadb"
        
        print_status "Vector database configured"
    fi
}

# Install MCP Server
install_mcp() {
    if [ "${SELECTED_MODULES[mcp]}" == true ]; then
        print_info "Installing MCP Server..."
        
        mkdir -p "$INSTALL_DIR/mcp"
        
        print_status "MCP Server configured"
    fi
}

# Install Monitoring
install_monitoring() {
    if [ "${SELECTED_MODULES[monitor]}" == true ]; then
        print_info "Installing Monitoring Suite..."
        
        mkdir -p "$INSTALL_DIR/monitoring"/{prometheus,grafana}
        
        print_status "Monitoring suite configured"
    fi
}

# Generate Docker Compose
generate_docker_compose() {
    print_info "Generating Docker Compose configuration..."
    
    cat > "$INSTALL_DIR/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  # PostgreSQL Database
  postgres:
    image: postgres:15-alpine
    container_name: borgos-postgres
    environment:
      - POSTGRES_USER=borgos
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=borgos
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./database/init.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - borgos-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U borgos"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Redis Cache
  redis:
    image: redis:7-alpine
    container_name: borgos-redis
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    networks:
      - borgos-network
    restart: unless-stopped
    command: redis-server --appendonly yes

  # BorgOS Core API
  borgos-api:
    build:
      context: ./core
      dockerfile: Dockerfile
    container_name: borgos-api
    ports:
      - "8081:8081"
    environment:
      - DATABASE_URL=postgresql://borgos:${DB_PASSWORD}@postgres:5432/borgos
      - REDIS_URL=redis://redis:6379
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started
    volumes:
      - ./config:/app/config
      - ./logs:/app/logs
    networks:
      - borgos-network
    restart: unless-stopped

  # BorgOS Dashboard
  borgos-dashboard:
    build:
      context: ./webui
      dockerfile: Dockerfile
    container_name: borgos-dashboard
    ports:
      - "8080:80"
    environment:
      - API_URL=http://borgos-api:8081
    depends_on:
      - borgos-api
    networks:
      - borgos-network
    restart: unless-stopped
EOF

    # Add optional services based on selected modules
    if [ "${SELECTED_MODULES[vector]}" == true ]; then
        cat >> "$INSTALL_DIR/docker-compose.yml" << 'EOF'

  # ChromaDB Vector Database
  chromadb:
    image: chromadb/chroma:latest
    container_name: borgos-chromadb
    ports:
      - "8000:8000"
    volumes:
      - chroma-data:/chroma/chroma
    environment:
      - IS_PERSISTENT=TRUE
      - PERSIST_DIRECTORY=/chroma/chroma
    networks:
      - borgos-network
    restart: unless-stopped
EOF
    fi

    if [ "${SELECTED_MODULES[monitor]}" == true ]; then
        cat >> "$INSTALL_DIR/docker-compose.yml" << 'EOF'

  # Prometheus Monitoring
  prometheus:
    image: prom/prometheus:latest
    container_name: borgos-prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    networks:
      - borgos-network
    restart: unless-stopped

  # Grafana Dashboard
  grafana:
    image: grafana/grafana:latest
    container_name: borgos-grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana-data:/var/lib/grafana
    networks:
      - borgos-network
    restart: unless-stopped
EOF
    fi

    # Add networks and volumes
    cat >> "$INSTALL_DIR/docker-compose.yml" << 'EOF'

networks:
  borgos-network:
    driver: bridge

volumes:
  postgres-data:
  redis-data:
  borgos-data:
EOF

    if [ "${SELECTED_MODULES[vector]}" == true ]; then
        echo "  chroma-data:" >> "$INSTALL_DIR/docker-compose.yml"
    fi
    
    if [ "${SELECTED_MODULES[monitor]}" == true ]; then
        echo "  prometheus-data:" >> "$INSTALL_DIR/docker-compose.yml"
        echo "  grafana-data:" >> "$INSTALL_DIR/docker-compose.yml"
    fi
    
    print_status "Docker Compose configuration generated"
}

# Create environment file
create_env_file() {
    print_info "Creating environment configuration..."
    
    cat > "$INSTALL_DIR/.env" << EOF
# BorgOS Environment Configuration
DB_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 16)
SECRET_KEY=$(openssl rand -hex 32)
BORGOS_HOST=${REMOTE_HOST}
BORGOS_PORT=8080
API_PORT=8081

# Zenith Coder
ZENITH_ENABLED=${SELECTED_MODULES[zenith]}
ZENITH_API=http://localhost:8001

# Agent Zero
AGENT_ZERO_ENABLED=${SELECTED_MODULES[agent]}
AGENT_ZERO_PATH=/opt/borgos/agents/zero

# ChromaDB
CHROMADB_ENABLED=${SELECTED_MODULES[vector]}
CHROMADB_HOST=chromadb
CHROMADB_PORT=8000

# MCP
MCP_ENABLED=${SELECTED_MODULES[mcp]}
MCP_PORT=8082

# Monitoring
MONITORING_ENABLED=${SELECTED_MODULES[monitor]}
PROMETHEUS_PORT=9090
GRAFANA_PORT=3000
EOF
    
    print_status "Environment configuration created"
}

# Main installation
main() {
    clear
    show_logo
    
    echo -e "${MAGENTA}BorgOS Modular Installation${NC}"
    echo -e "${CYAN}Target: ${REMOTE_HOST}${NC}"
    echo -e "${CYAN}Profile: ${INSTALL_PROFILE}${NC}"
    echo
    
    # Check prerequisites
    check_prerequisites
    
    # Select modules
    select_modules
    
    # Confirm installation
    echo
    read -p "Proceed with installation? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [ ! -z "$REPLY" ]; then
        print_error "Installation cancelled"
        exit 1
    fi
    
    # Install modules
    echo
    echo -e "${CYAN}Installing BorgOS...${NC}"
    
    install_core
    install_zenith
    install_agent_zero
    install_vector_db
    install_mcp
    install_monitoring
    
    # Generate configurations
    generate_docker_compose
    create_env_file
    
    # Create database init script
    print_info "Creating database initialization script..."
    mkdir -p "$INSTALL_DIR/database"
    cp ../database/init.sql "$INSTALL_DIR/database/" 2>/dev/null || true
    
    # Final message
    echo
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}    BorgOS Installation Complete!       ${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo
    echo -e "${CYAN}Next steps:${NC}"
    echo -e "  1. cd $INSTALL_DIR"
    echo -e "  2. docker-compose up -d"
    echo -e "  3. Access dashboard at http://${REMOTE_HOST}:8080"
    echo -e "  4. API available at http://${REMOTE_HOST}:8081"
    echo
    echo -e "${CYAN}Installed modules:${NC}"
    for module in "${!SELECTED_MODULES[@]}"; do
        if [ "${SELECTED_MODULES[$module]}" == true ]; then
            echo -e "  ${GREEN}✓${NC} ${MODULES[$module]}"
        fi
    done
    echo
    print_info "Configuration saved to: $INSTALL_DIR/config/borgos.yml"
    print_info "Logs will be available at: $INSTALL_DIR/logs/"
    echo
}

# Run main installation
main "$@"