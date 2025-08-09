# BorgOS Makefile
# Automation for common tasks

.PHONY: help build deploy test clean

# Variables
DOCKER_COMPOSE := docker-compose
KUBECTL := kubectl
PYTHON := python3
PIP := pip3

# Colors
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m

# Default target
.DEFAULT_GOAL := help

## Help
help:
	@echo "$(BLUE)BorgOS Management Commands$(NC)"
	@echo ""
	@echo "$(GREEN)Development:$(NC)"
	@echo "  make install       - Install dependencies"
	@echo "  make test         - Run tests"
	@echo "  make lint         - Run linting"
	@echo "  make format       - Format code"
	@echo ""
	@echo "$(GREEN)Docker:$(NC)"
	@echo "  make build        - Build Docker images"
	@echo "  make up           - Start services with docker-compose"
	@echo "  make down         - Stop services"
	@echo "  make logs         - View logs"
	@echo "  make clean        - Clean up containers and volumes"
	@echo ""
	@echo "$(GREEN)Kubernetes:$(NC)"
	@echo "  make k8s-deploy   - Deploy to Kubernetes"
	@echo "  make k8s-delete   - Delete from Kubernetes"
	@echo "  make k8s-status   - Show Kubernetes status"
	@echo ""
	@echo "$(GREEN)Deployment:$(NC)"
	@echo "  make deploy       - Full deployment (Docker)"
	@echo "  make deploy-prod  - Deploy to production"
	@echo "  make deploy-stage - Deploy to staging"

## Install dependencies
install:
	@echo "$(BLUE)Installing dependencies...$(NC)"
	$(PIP) install -r webui/requirements_dashboard.txt
	@echo "$(GREEN)Dependencies installed!$(NC)"

## Run tests
test:
	@echo "$(BLUE)Running tests...$(NC)"
	$(PYTHON) -m pytest tests/ -v --cov=webui
	@echo "$(GREEN)Tests completed!$(NC)"

## Run linting
lint:
	@echo "$(BLUE)Running linting...$(NC)"
	flake8 webui/ --max-line-length=120 --ignore=E501,W503
	@echo "$(GREEN)Linting completed!$(NC)"

## Format code
format:
	@echo "$(BLUE)Formatting code...$(NC)"
	black webui/
	isort webui/
	@echo "$(GREEN)Code formatted!$(NC)"

## Build Docker images
build:
	@echo "$(BLUE)Building Docker images...$(NC)"
	docker build -f Dockerfile.dashboard -t borgos/dashboard:latest .
	docker build -f Dockerfile.website -t borgos/website:latest .
	@echo "$(GREEN)Images built!$(NC)"

## Start services with docker-compose
up:
	@echo "$(BLUE)Starting services...$(NC)"
	$(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)Services started!$(NC)"
	@echo "Dashboard: http://localhost:8080"
	@echo "Website: http://localhost:80"

## Stop services
down:
	@echo "$(YELLOW)Stopping services...$(NC)"
	$(DOCKER_COMPOSE) down
	@echo "$(GREEN)Services stopped!$(NC)"

## View logs
logs:
	$(DOCKER_COMPOSE) logs -f

## Clean up containers and volumes
clean:
	@echo "$(RED)Cleaning up...$(NC)"
	$(DOCKER_COMPOSE) down -v
	docker system prune -f
	@echo "$(GREEN)Cleanup completed!$(NC)"

## Full deployment (Docker)
deploy: build up
	@echo "$(GREEN)Deployment completed!$(NC)"
	@./deploy.sh

## Deploy to Kubernetes
k8s-deploy:
	@echo "$(BLUE)Deploying to Kubernetes...$(NC)"
	cd k8s && ./deploy-k8s.sh
	@echo "$(GREEN)Kubernetes deployment completed!$(NC)"

## Delete from Kubernetes
k8s-delete:
	@echo "$(RED)Deleting from Kubernetes...$(NC)"
	$(KUBECTL) delete namespace borgos --ignore-not-found=true
	@echo "$(GREEN)Kubernetes resources deleted!$(NC)"

## Show Kubernetes status
k8s-status:
	@echo "$(BLUE)Kubernetes Status:$(NC)"
	$(KUBECTL) get all -n borgos

## Deploy to production
deploy-prod:
	@echo "$(BLUE)Deploying to production...$(NC)"
	@read -p "Are you sure you want to deploy to production? [y/N] " confirm && \
	if [ "$$confirm" = "y" ]; then \
		echo "$(GREEN)Deploying to production...$(NC)"; \
		./deploy.sh --production; \
	else \
		echo "$(YELLOW)Production deployment cancelled$(NC)"; \
	fi

## Deploy to staging
deploy-stage:
	@echo "$(BLUE)Deploying to staging...$(NC)"
	./deploy.sh --staging

## Run dashboard locally
run-dashboard:
	@echo "$(BLUE)Starting dashboard locally...$(NC)"
	cd webui && $(PYTHON) professional_dashboard.py

## Run website locally
run-website:
	@echo "$(BLUE)Starting website locally...$(NC)"
	cd website && $(PYTHON) -m http.server 8000

## Check system requirements
check:
	@echo "$(BLUE)Checking system requirements...$(NC)"
	@command -v docker >/dev/null 2>&1 && echo "$(GREEN)✓ Docker installed$(NC)" || echo "$(RED)✗ Docker not installed$(NC)"
	@command -v docker-compose >/dev/null 2>&1 && echo "$(GREEN)✓ Docker Compose installed$(NC)" || echo "$(RED)✗ Docker Compose not installed$(NC)"
	@command -v kubectl >/dev/null 2>&1 && echo "$(GREEN)✓ kubectl installed$(NC)" || echo "$(RED)✗ kubectl not installed$(NC)"
	@command -v python3 >/dev/null 2>&1 && echo "$(GREEN)✓ Python 3 installed$(NC)" || echo "$(RED)✗ Python 3 not installed$(NC)"

## Show version
version:
	@echo "BorgOS v1.0.0"