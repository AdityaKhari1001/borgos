#!/usr/bin/env bash
# ============================================================================
#  BorgOS CI/CD - Docker Build Stage
#  Purpose: Build and push Docker images for BorgOS components
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ISO_TAG="${ISO_TAG:-borgos-$(date -u +%Y%m%d)}"
REGISTRY="${REGISTRY:-ghcr.io/borgos}"
PUSH="${PUSH:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[DOCKER]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Check Docker is available
if ! command -v docker >/dev/null 2>&1; then
    error "Docker is not installed"
fi

log "Building Docker images for BorgOS components..."
cd "$PROJECT_ROOT"

# Build WebUI image
log "Building WebUI image..."
cat > Dockerfile.webui <<'EOF'
FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy requirements first for better caching
COPY webui/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY webui/ .

# Create non-root user
RUN useradd -m -u 1000 borgos && chown -R borgos:borgos /app
USER borgos

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:6969/health')" || exit 1

# Expose port
EXPOSE 6969

# Run with gunicorn in production
CMD ["gunicorn", "--bind", "0.0.0.0:6969", "--workers", "4", "--timeout", "120", "app:app"]
EOF

docker build -f Dockerfile.webui -t "${REGISTRY}/webui:${ISO_TAG}" .
docker tag "${REGISTRY}/webui:${ISO_TAG}" "${REGISTRY}/webui:latest"

# Build MCP Server image
log "Building MCP Server image..."
cat > Dockerfile.mcp <<'EOF'
FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies
RUN pip install --no-cache-dir mcp anthropic

# Copy MCP server
COPY mcp_servers/ .

# Create non-root user
RUN useradd -m -u 1000 borgos && chown -R borgos:borgos /app
USER borgos

# Expose MCP port
EXPOSE 7300

# Run MCP server
CMD ["python", "fs_server.py", "--host", "0.0.0.0", "--port", "7300"]
EOF

docker build -f Dockerfile.mcp -t "${REGISTRY}/mcp-server:${ISO_TAG}" .
docker tag "${REGISTRY}/mcp-server:${ISO_TAG}" "${REGISTRY}/mcp-server:latest"

# Build installer image (for testing)
log "Building installer test image..."
cat > Dockerfile.installer <<'EOF'
FROM debian:12-slim

# Copy installer script
COPY installer/install_all.sh /root/

# Make executable
RUN chmod +x /root/install_all.sh

# Entry point for testing
ENTRYPOINT ["/bin/bash"]
EOF

docker build -f Dockerfile.installer -t "${REGISTRY}/installer:${ISO_TAG}" .

# List built images
log "Built images:"
docker images | grep "${REGISTRY}" | grep "${ISO_TAG}"

# Push images if requested
if [ "$PUSH" = "true" ]; then
    log "Pushing images to registry..."
    
    # Login to registry if credentials are provided
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        echo "${GITHUB_TOKEN}" | docker login ghcr.io -u "${GITHUB_ACTOR:-borgos}" --password-stdin
    fi
    
    docker push "${REGISTRY}/webui:${ISO_TAG}"
    docker push "${REGISTRY}/webui:latest"
    docker push "${REGISTRY}/mcp-server:${ISO_TAG}"
    docker push "${REGISTRY}/mcp-server:latest"
    docker push "${REGISTRY}/installer:${ISO_TAG}"
    
    log "Images pushed successfully"
else
    log "Skipping push (set PUSH=true to enable)"
fi

# Clean up Dockerfiles
rm -f Dockerfile.webui Dockerfile.mcp Dockerfile.installer

log "Docker build completed successfully!"