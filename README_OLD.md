# 🧠 BorgOS - AI-First Multi-Agent Operating System

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.11+](https://img.shields.io/badge/python-3.11+-blue.svg)](https://www.python.org/downloads/)
[![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?logo=docker&logoColor=white)](https://www.docker.com/)
[![FastAPI](https://img.shields.io/badge/FastAPI-005571?logo=fastapi)](https://fastapi.tiangolo.com/)
[![Agent Zero](https://img.shields.io/badge/Agent-Zero-purple)](https://github.com/frdel/agent-zero)
[![Zenith Coder](https://img.shields.io/badge/Zenith-Coder-orange)](https://github.com/zenith/coder)

BorgOS is an AI-first operating system that integrates multiple AI agents, project management, and deployment automation into a unified platform. It combines the power of **Agent Zero**, **Zenith Coder**, and **MCP (Model Context Protocol)** to create an autonomous development and operations environment.

## ✨ Key Features

### 🤖 Multi-Agent System
- **Agent Zero**: Autonomous AI with code execution, web browsing, and memory
- **Zenith Coder**: Specialized coding assistant with project analysis
- **MCP Server**: Model Context Protocol for enhanced AI interactions
- **Custom Agents**: Create specialized agents for specific tasks

### 📊 Project & Deployment Management
- **Real-time Monitoring**: Track all projects and deployments
- **Auto-deployment**: One-click deployment with port management
- **Health Tracking**: Automatic health checks and error monitoring
- **Resource Management**: CPU and memory limits per deployment

### 🔍 AI-Powered Search & Memory
- **Semantic Search**: ChromaDB vector database integration
- **Persistent Memory**: Long-term learning and context retention
- **Knowledge Base**: Automatic documentation indexing
- **Cross-agent Memory**: Shared knowledge between agents

### 🛠️ Developer Experience
- **Web Dashboard**: Beautiful real-time monitoring interface
- **REST API**: Comprehensive API with WebSocket support
- **Docker-First**: Fully containerized architecture
- **CLI Tools**: Command-line interface for all operations

## 📋 System Requirements

### Minimum Requirements
- **OS**: Linux (Ubuntu 20.04+, Debian 11+), macOS 12+, Windows with WSL2
- **RAM**: 4GB (8GB recommended for full agent capabilities)
- **Storage**: 20GB free space
- **CPU**: 2+ cores (4+ recommended)
- **Docker**: Version 20.10+
- **Docker Compose**: Version 2.0+

### For AI Features
- **API Keys**: OpenAI, Anthropic, or local Ollama
- **GPU**: Optional - NVIDIA GPU for local model inference
- **Network**: Internet for API-based models

## 🚀 Quick Start

### Option 1: Docker Compose (Recommended)

```bash
# Clone the repository
git clone https://github.com/yourusername/borgos.git
cd borgos

# Copy environment template and add your API keys
cp .env.example .env
nano .env  # Add your OpenAI/Anthropic API keys

# Start all services
docker-compose up -d

# Access the dashboard
open http://localhost:8080
```

### Option 2: Quick Install Script

```bash
# One-line installation
curl -fsSL https://raw.githubusercontent.com/yourusername/borgos/main/install.sh | bash
```

### Option 3: Build from Source

```bash
# Clone and build
git clone https://github.com/yourusername/borgos.git
cd borgos
make build
make install
```

## 🏗️ Architecture

BorgOS uses a microservices architecture with AI agents at its core:
   ```bash
   # Using dd (replace /dev/sdX with your USB device)
   sudo dd if=out/ISO/borgos-*.iso of=/dev/sdX bs=4M status=progress
   ```

2. Boot from the USB drive

3. Follow the automated installation process

4. After installation, access the system:
   - SSH: `ssh user@borgos-ip`
   - Web Dashboard: `http://borgos-ip:6969`

### Using BorgOS

```bash
# Natural language queries
borg "What's the system status?"
borg "Show me running processes"
borg "Create a Python hello world script"

# Set OpenRouter API key for online mode (optional)
export OPENAI_API_KEY="your-key-here"

# Access web dashboard
firefox http://localhost:6969
```

## 🏗️ Architecture

```
┌─────────────┐
│  User / CLI │
└──────┬──────┘
       │
  borg wrapper ←→ Ollama/OpenRouter
       │
┌──────┴──────────────────┐
│     Core Services       │
├─────────────────────────┤
│ • ChromaDB (vectors)    │
│ • MCP Server (fs ops)   │
│ • Flask WebUI           │
│ • Plugin System         │
└─────────────────────────┘
```

## 📁 Project Structure

```
borgos/
├── iso-builder/          # ISO generation scripts
│   └── borgos_iso_builder.sh
├── installer/            # System installation scripts
│   └── install_all.sh
├── webui/               # Flask dashboard application
│   ├── app.py
│   └── requirements.txt
├── mcp_servers/         # MCP server implementations
│   └── fs_server.py
├── plugins/             # Plugin modules
├── tests/              # Test suites
├── .ci/                # CI/CD pipeline
└── docs/               # Documentation
```

## 🔌 Plugin Development

Create custom plugins by dropping Python files in `/opt/borgos/plugins/`:

```python
# /opt/borgos/plugins/my_tool.py
from borg.plugin import Tool

@Tool(name="my_tool", desc="Description")
async def my_tool(param: str = "default"):
    return f"Result: {param}"
```

## 🐳 Docker Images

Pre-built containers are available:

```bash
# WebUI Dashboard
docker run -p 6969:6969 ghcr.io/borgos/webui:latest

# MCP Server
docker run -p 7300:7300 ghcr.io/borgos/mcp-server:latest
```

## 🧪 Development

### Running Tests

```bash
# Install dependencies
pip install -r requirements-dev.txt

# Run test suite
pytest tests/ --cov=webui --cov=mcp_servers

# Run linting
ruff check .
shellcheck **/*.sh
```

### Building Components

```bash
# Build Docker images
bash .ci/docker_build.sh

# Run CI pipeline locally
bash .ci/lint.sh
bash .ci/test.sh
```

## 📚 Documentation

- [Installation Guide](docs/installation.md)
- [User Manual](docs/user-manual.md)
- [API Reference](docs/api-reference.md)
- [Plugin Development](docs/plugin-development.md)
- [Architecture Overview](docs/architecture.md)

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Ollama for local LLM inference
- OpenRouter for online LLM access
- ChromaDB for vector storage
- Flask for the web framework
- The open-source community

## 📞 Support

- Issues: [GitHub Issues](https://github.com/borgos/borgos/issues)
- Discussions: [GitHub Discussions](https://github.com/borgos/borgos/discussions)
- Wiki: [Project Wiki](https://github.com/borgos/borgos/wiki)

## 🚦 Status

- Current Version: 1.0
- Build: Stable
- Tests: Passing
- Coverage: >90%

---

Built with ❤️ by the BorgOS Team