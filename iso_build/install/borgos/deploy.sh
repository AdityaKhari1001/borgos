#!/bin/bash

# BorgOS Deployment Script
# Automated deployment for production environment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Functions
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}    BorgOS Deployment System${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
}

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

check_requirements() {
    echo -e "${BLUE}Checking requirements...${NC}"
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        echo "Please install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    print_status "Docker installed"
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        if ! docker compose version &> /dev/null; then
            print_error "Docker Compose is not installed"
            echo "Please install Docker Compose: https://docs.docker.com/compose/install/"
            exit 1
        fi
        COMPOSE_CMD="docker compose"
    else
        COMPOSE_CMD="docker-compose"
    fi
    print_status "Docker Compose installed"
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        echo "Please start Docker daemon"
        exit 1
    fi
    print_status "Docker daemon running"
}

setup_environment() {
    echo -e "\n${BLUE}Setting up environment...${NC}"
    
    # Create .env file if it doesn't exist
    if [ ! -f .env ]; then
        cp .env.example .env
        print_status "Created .env file from template"
        print_warning "Please update .env file with your configuration"
        
        # Generate secret key
        SECRET_KEY=$(openssl rand -hex 32 2>/dev/null || cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
        sed -i.bak "s/your-secret-key-here-change-this-in-production/$SECRET_KEY/g" .env
        rm -f .env.bak
        print_status "Generated secret key"
    else
        print_status ".env file already exists"
    fi
    
    # Create necessary directories
    mkdir -p config logs
    print_status "Created required directories"
}

build_images() {
    echo -e "\n${BLUE}Building Docker images...${NC}"
    
    # Build dashboard image
    echo "Building dashboard image..."
    docker build -f Dockerfile.dashboard -t borgos/dashboard:latest . || {
        print_error "Failed to build dashboard image"
        exit 1
    }
    print_status "Dashboard image built"
    
    # Build website image
    echo "Building website image..."
    docker build -f Dockerfile.website -t borgos/website:latest . || {
        print_error "Failed to build website image"
        exit 1
    }
    print_status "Website image built"
}

deploy_stack() {
    echo -e "\n${BLUE}Deploying BorgOS stack...${NC}"
    
    # Stop existing containers if any
    $COMPOSE_CMD down 2>/dev/null || true
    
    # Start the stack
    $COMPOSE_CMD up -d || {
        print_error "Failed to deploy stack"
        exit 1
    }
    
    print_status "Stack deployed successfully"
}

wait_for_services() {
    echo -e "\n${BLUE}Waiting for services to be ready...${NC}"
    
    # Wait for dashboard
    echo -n "Waiting for dashboard..."
    for i in {1..30}; do
        if curl -f http://localhost:8080 &>/dev/null; then
            echo " Ready!"
            print_status "Dashboard is running at http://localhost:8080"
            break
        fi
        echo -n "."
        sleep 2
    done
    
    # Wait for website
    echo -n "Waiting for website..."
    for i in {1..30}; do
        if curl -f http://localhost:80 &>/dev/null; then
            echo " Ready!"
            print_status "Website is running at http://localhost:80"
            break
        fi
        echo -n "."
        sleep 2
    done
    
    # Wait for Ollama
    echo -n "Waiting for Ollama..."
    for i in {1..30}; do
        if curl -f http://localhost:11434 &>/dev/null; then
            echo " Ready!"
            print_status "Ollama is running at http://localhost:11434"
            break
        fi
        echo -n "."
        sleep 2
    done
}

install_ollama_models() {
    echo -e "\n${BLUE}Installing AI models...${NC}"
    
    # Pull Mistral model
    echo "Pulling Mistral 7B model (this may take a while)..."
    docker exec borgos-ollama ollama pull mistral:7b || {
        print_warning "Failed to pull Mistral model, you can do this later"
    }
    
    print_status "AI models installation complete"
}

show_info() {
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}    BorgOS Deployment Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo -e "${BLUE}Access Points:${NC}"
    echo -e "  Dashboard:    ${GREEN}http://localhost:8080${NC}"
    echo -e "  Website:      ${GREEN}http://localhost:80${NC}"
    echo -e "  Ollama API:   ${GREEN}http://localhost:11434${NC}"
    echo -e "  n8n:          ${GREEN}http://localhost:5678${NC}"
    echo -e "  ChromaDB:     ${GREEN}http://localhost:8000${NC}"
    echo -e "  Traefik:      ${GREEN}http://localhost:8089${NC}"
    echo
    echo -e "${BLUE}Default Credentials:${NC}"
    echo -e "  Dashboard:    admin / borgos"
    echo -e "  n8n:          admin / borgos123"
    echo
    echo -e "${BLUE}Useful Commands:${NC}"
    echo -e "  View logs:    ${YELLOW}$COMPOSE_CMD logs -f [service]${NC}"
    echo -e "  Stop stack:   ${YELLOW}$COMPOSE_CMD down${NC}"
    echo -e "  Restart:      ${YELLOW}$COMPOSE_CMD restart${NC}"
    echo -e "  Status:       ${YELLOW}$COMPOSE_CMD ps${NC}"
    echo
    echo -e "${GREEN}Happy coding with BorgOS!${NC}"
}

# Main execution
main() {
    print_header
    
    # Parse arguments
    case "${1:-}" in
        --build-only)
            check_requirements
            setup_environment
            build_images
            print_status "Images built successfully"
            ;;
        --quick)
            check_requirements
            deploy_stack
            wait_for_services
            show_info
            ;;
        --stop)
            $COMPOSE_CMD down
            print_status "BorgOS stack stopped"
            ;;
        --clean)
            $COMPOSE_CMD down -v
            print_status "BorgOS stack stopped and volumes removed"
            ;;
        --logs)
            $COMPOSE_CMD logs -f ${2:-}
            ;;
        --status)
            $COMPOSE_CMD ps
            ;;
        *)
            check_requirements
            setup_environment
            build_images
            deploy_stack
            wait_for_services
            install_ollama_models
            show_info
            ;;
    esac
}

# Run main function
main "$@"