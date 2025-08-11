#!/usr/bin/env bash
# ============================================================================
#  BorgOS CI/CD - Release Stage
#  Purpose: Create GitHub release with artifacts
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ISO_TAG="${ISO_TAG:-borgos-$(date -u +%Y%m%d)}"
OUTDIR="${OUTDIR:-$PROJECT_ROOT/out/ISO}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$PROJECT_ROOT/artifacts}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[RELEASE]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Check gh CLI is available
if ! command -v gh >/dev/null 2>&1; then
    error "GitHub CLI (gh) is not installed. Install from: https://cli.github.com/"
fi

log "Creating release for ${ISO_TAG}..."
cd "$PROJECT_ROOT"

# Find ISO file
ISO_FILE="${OUTDIR}/${ISO_TAG}.iso"
if [ ! -f "$ISO_FILE" ]; then
    error "ISO file not found: $ISO_FILE"
fi

# Generate checksums
log "Generating checksums..."
cd "$OUTDIR"
sha256sum "${ISO_TAG}.iso" > "${ISO_TAG}.iso.sha256"
md5sum "${ISO_TAG}.iso" > "${ISO_TAG}.iso.md5"

# Generate release notes
log "Generating release notes..."
cat > "$PROJECT_ROOT/release_notes.md" <<EOF
# BorgOS Release ${ISO_TAG}

## 🚀 Features
- Offline-first AI operating system
- Natural language CLI with Borg command
- Web dashboard on port 6969
- MCP server infrastructure
- Ollama for local LLM inference
- ChromaDB for vector memory
- Plugin system for extensibility

## 📦 What's Included
- **ISO Image**: Bootable ISO for x86_64 systems
- **Docker Images**: Pre-built containers for WebUI and MCP server
- **Documentation**: Complete setup and usage guides

## 🔧 Installation
1. Download the ISO file and verify checksum
2. Flash to USB drive using balenaEtcher or dd
3. Boot from USB and follow installation prompts
4. Access dashboard at http://localhost:6969 after installation

## 📝 Checksums
\`\`\`
$(cat "${ISO_TAG}.iso.sha256")
$(cat "${ISO_TAG}.iso.md5")
\`\`\`

## 🐳 Docker Images
- \`ghcr.io/borgos/webui:${ISO_TAG}\`
- \`ghcr.io/borgos/mcp-server:${ISO_TAG}\`

## 📚 Documentation
- [Installation Guide](https://github.com/borgos/docs/wiki/Installation)
- [User Manual](https://github.com/borgos/docs/wiki/User-Manual)
- [API Reference](https://github.com/borgos/docs/wiki/API)

## 🔄 Changelog
- Initial release of BorgOS v1.0
- Core system components implemented
- WebUI dashboard with system monitoring
- MCP filesystem server
- Plugin system framework
- CI/CD pipeline established

## ⚠️ Known Issues
- n8n container may require manual start on some systems
- Ollama model download requires internet on first run

## 🤝 Contributing
We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md).

---
*Built with ❤️ by the BorgOS Team*
EOF

# Create GitHub release
log "Creating GitHub release..."
gh release create "${ISO_TAG}" \
    "$ISO_FILE" \
    "${ISO_TAG}.iso.sha256" \
    "${ISO_TAG}.iso.md5" \
    --title "BorgOS ${ISO_TAG}" \
    --notes-file "$PROJECT_ROOT/release_notes.md" \
    --draft || warn "Failed to create release (may already exist)"

# Upload additional artifacts if they exist
if [ -d "$ARTIFACTS_DIR" ]; then
    log "Uploading additional artifacts..."
    
    # Create tarball of artifacts
    tar -czf "$ARTIFACTS_DIR/test-artifacts.tar.gz" -C "$ARTIFACTS_DIR" .
    
    gh release upload "${ISO_TAG}" \
        "$ARTIFACTS_DIR/test-artifacts.tar.gz" \
        --clobber || warn "Failed to upload test artifacts"
fi

# Upload documentation
if [ -d "$PROJECT_ROOT/docs" ]; then
    log "Creating documentation archive..."
    tar -czf "$PROJECT_ROOT/docs.tar.gz" -C "$PROJECT_ROOT" docs/
    
    gh release upload "${ISO_TAG}" \
        "$PROJECT_ROOT/docs.tar.gz" \
        --clobber || warn "Failed to upload documentation"
fi

log "Release ${ISO_TAG} created successfully!"
log "View at: https://github.com/borgos/borgos/releases/tag/${ISO_TAG}"

# Clean up
rm -f "$PROJECT_ROOT/release_notes.md" "$PROJECT_ROOT/docs.tar.gz"