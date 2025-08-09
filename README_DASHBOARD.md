# BorgOS Professional Dashboard & Website

## Overview

This package contains two main components for BorgOS:

1. **Professional Dashboard** - Advanced DevOps monitoring and management interface
2. **Marketing Website** - Professional landing page for BorgOS

## Features

### Professional Dashboard (`webui/professional_dashboard.py`)

#### Real-time Monitoring
- **Live System Metrics**: CPU, Memory, Disk, Network usage with historical graphs
- **Service Monitoring**: Track status of Ollama, nginx, Docker, and other services
- **Container Management**: View and control Docker containers
- **Network Transfer**: Real-time upload/download speeds and totals
- **Active Sessions**: Monitor connected users and sessions

#### AI Model Management
- View installed Ollama models
- Monitor model usage and costs
- Test and configure AI models
- Support for multiple providers (Ollama, OpenRouter, HuggingFace)

#### Configuration Center
- Secure API key management
- System settings configuration
- Service configuration
- Offline/Online mode switching

#### DevOps Features
- Service control (start/stop/restart)
- Log viewer with filtering
- System diagnostics
- Performance analytics
- WebSocket real-time updates

### Marketing Website (`website/index.html`)

- **Modern Design**: Gradient backgrounds, animations, particle effects
- **Responsive Layout**: Mobile-friendly, works on all devices
- **Feature Showcase**: Highlights BorgOS capabilities
- **Architecture Diagram**: Visual system overview
- **Installation Guide**: Step-by-step instructions
- **Download Options**: ISO, Docker, Source code

## Installation

### Dashboard Setup

1. Navigate to the webui directory:
```bash
cd webui
```

2. Run the startup script:
```bash
./start_dashboard.sh
```

3. Access the dashboard:
```
http://localhost:8080
```

Default credentials:
- Username: `admin`
- Password: `borgos`

### Website Deployment

1. Navigate to the website directory:
```bash
cd website
```

2. Serve with any web server:
```bash
# Python simple server
python3 -m http.server 8000

# Or use nginx/apache
```

3. Access the website:
```
http://localhost:8000
```

## Dashboard API Endpoints

- `GET /api/metrics` - System metrics
- `GET /api/services` - Service status
- `GET /api/models` - AI models information
- `GET /api/containers` - Docker containers
- `GET /api/sessions` - Active sessions
- `GET /api/config` - Configuration
- `POST /api/config` - Update configuration
- `GET /api/logs/<service>` - Service logs
- `POST /api/service/<action>/<service>` - Service control

## WebSocket Events

The dashboard uses Socket.IO for real-time updates:

- `connect` - Client connection
- `disconnect` - Client disconnection
- `metrics_update` - System metrics update
- `transfer_update` - Network transfer update
- `request_metrics` - Request current metrics

## Configuration

### Dashboard Configuration

Configuration file: `/etc/borgos/config.yaml`

```yaml
api_keys:
  openrouter: "sk-or-v1-..."
  huggingface: "hf_..."
  openai: "sk-..."

models:
  - name: mistral:7b
    provider: Ollama
    default: true
  - name: llama2:7b
    provider: Ollama

system:
  offline_mode: true
  max_memory_gb: 8
  default_model: mistral:7b
```

### Security

- Session-based authentication
- Password hashing (in production)
- API key encryption
- Input validation
- CORS protection
- Zero-trust architecture

## Monitoring Features

### Metrics Collected

- **CPU**: Usage percentage, frequency, temperature, load average
- **Memory**: Total, used, free, swap usage
- **Disk**: Total, used, free, I/O statistics
- **Network**: Bytes sent/received, packet statistics
- **System**: Uptime, processes, kernel info

### Historical Data

- Stores last 100 data points for each metric
- 2-second update interval
- Real-time chart updates
- Persistent storage in SQLite

## Customization

### Dashboard Themes

Edit `/webui/static/css/dashboard.css` to customize:
- Color scheme
- Card styles
- Chart colors
- Animations

### Website Content

Edit `/website/index.html` to update:
- Feature descriptions
- System requirements
- Download links
- Documentation links

## Troubleshooting

### Dashboard Issues

1. **Port already in use**:
   ```bash
   # Find process using port 8080
   lsof -i :8080
   # Kill the process
   kill -9 <PID>
   ```

2. **WebSocket connection failed**:
   - Check firewall settings
   - Ensure eventlet is installed
   - Verify CORS settings

3. **Services not showing**:
   - Check systemctl permissions
   - Verify service names in MONITORED_SERVICES

### Website Issues

1. **Animations not working**:
   - Enable JavaScript
   - Check browser compatibility

2. **Fonts not loading**:
   - Check internet connection
   - Use local font files

## Development

### Running in Development Mode

Dashboard:
```bash
cd webui
python professional_dashboard.py
```

Website:
```bash
cd website
python3 -m http.server 8000
```

### Adding New Features

1. **New Dashboard Section**:
   - Add navigation item in sidebar
   - Create content section in HTML
   - Add data loading in JavaScript
   - Create API endpoint in Python

2. **New Metrics**:
   - Add collection in `get_system_metrics()`
   - Update WebSocket emission
   - Add chart in JavaScript
   - Update HTML display

## Performance

- Dashboard uses ~50MB RAM
- Updates every 2 seconds (configurable)
- Supports 100+ concurrent connections
- Chart history limited to 100 points
- WebSocket compression enabled

## License

MIT License - See LICENSE file for details

## Support

For issues or questions:
- GitHub Issues: https://github.com/borgos/borgos/issues
- Documentation: https://docs.borgos.ai
- Community Forum: https://forum.borgos.ai