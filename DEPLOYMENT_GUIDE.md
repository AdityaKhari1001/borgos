# BorgOS Deployment Guide for 192.168.100.159

## 🚀 Quick Deployment

### Option 1: Automated Deployment (Recommended)
```bash
# Run the quick deployment script
./deploy-quick.sh [username]

# Example:
./deploy-quick.sh root
```

### Option 2: Step-by-Step Manual Deployment

#### 1. SSH to the server
```bash
ssh root@192.168.100.159
```

#### 2. Create deployment directory
```bash
mkdir -p /opt/borgos
cd /opt/borgos
```

#### 3. Copy files to server (from local machine)
```bash
# Create archive on local machine
tar czf borgos.tar.gz webui/ website/ deploy/ docker-compose-remote.yml Dockerfile.*

# Upload to server
scp borgos.tar.gz root@192.168.100.159:/opt/borgos/

# Extract on server
ssh root@192.168.100.159 'cd /opt/borgos && tar xzf borgos.tar.gz'
```

#### 4. Install Docker on server (if not installed)
```bash
# On the server
curl -fsSL https://get.docker.com | sh
systemctl start docker
systemctl enable docker
```

#### 5. Setup environment
```bash
# On the server
cd /opt/borgos
mv docker-compose-remote.yml docker-compose.yml
cp .env.example .env

# Edit .env file
nano .env
# Set your passwords and API keys
```

#### 6. Build and deploy
```bash
# Build images
docker build -f Dockerfile.dashboard -t borgos/dashboard:latest .
docker build -f Dockerfile.website -t borgos/website:latest .

# Start services
docker-compose up -d

# Check status
docker-compose ps
```

#### 7. Install AI models
```bash
docker exec borgos-ollama ollama pull mistral:7b
```

## 📊 Access Points

After deployment, access BorgOS at:

| Service | URL | Credentials |
|---------|-----|-------------|
| **Website** | http://192.168.100.159:8000 | - |
| **Dashboard** | http://192.168.100.159:8080 | admin / borgos |
| **Ollama API** | http://192.168.100.159:11434 | - |
| **PostgreSQL** | 192.168.100.159:5432 | borgos / [from .env] |
| **Redis** | 192.168.100.159:6379 | - |
| **ChromaDB** | http://192.168.100.159:8001 | - |

## 🔧 Management Commands

### Check status
```bash
ssh root@192.168.100.159 'cd /opt/borgos && docker-compose ps'
```

### View logs
```bash
# All services
ssh root@192.168.100.159 'cd /opt/borgos && docker-compose logs -f'

# Specific service
ssh root@192.168.100.159 'cd /opt/borgos && docker-compose logs -f dashboard'
```

### Restart services
```bash
ssh root@192.168.100.159 'cd /opt/borgos && docker-compose restart'
```

### Stop services
```bash
ssh root@192.168.100.159 'cd /opt/borgos && docker-compose down'
```

### Update deployment
```bash
# Pull latest changes
ssh root@192.168.100.159 'cd /opt/borgos && git pull'

# Rebuild and restart
ssh root@192.168.100.159 'cd /opt/borgos && docker-compose build && docker-compose up -d'
```

## 🔒 Security Configuration

### 1. Configure firewall
```bash
# On the server
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw allow 8000/tcp  # Website
ufw allow 8080/tcp  # Dashboard
ufw allow 11434/tcp # Ollama
ufw enable
```

### 2. Set strong passwords
Edit `/opt/borgos/.env` and set:
- `SECRET_KEY` - Random 32+ character string
- `DB_PASSWORD` - Strong database password
- `N8N_PASSWORD` - n8n admin password

### 3. Enable SSL (optional)
```bash
# Install certbot
apt-get install certbot

# Get certificate
certbot certonly --standalone -d your-domain.com

# Update nginx config to use SSL
```

## 🐛 Troubleshooting

### Docker not starting
```bash
systemctl status docker
systemctl restart docker
journalctl -u docker -n 50
```

### Port already in use
```bash
# Find process using port
lsof -i :8080
# Kill process
kill -9 [PID]
```

### Container not starting
```bash
# Check logs
docker-compose logs [service-name]

# Recreate container
docker-compose up -d --force-recreate [service-name]
```

### Out of disk space
```bash
# Check disk usage
df -h

# Clean Docker
docker system prune -a
```

### Memory issues
```bash
# Check memory
free -h

# Adjust memory limits in docker-compose.yml
```

## 📈 Monitoring

### System resources
```bash
ssh root@192.168.100.159 << 'EOF'
echo "=== System Resources ==="
echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')"
echo "Memory: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
echo "Disk: $(df -h / | tail -1 | awk '{print $3 "/" $2}')"
echo ""
echo "=== Docker Containers ==="
docker stats --no-stream
EOF
```

### Create monitoring script
```bash
# On server at /opt/borgos/monitor.sh
#!/bin/bash
while true; do
    clear
    echo "BorgOS Monitor - $(date)"
    echo "========================"
    docker-compose ps
    echo ""
    docker stats --no-stream
    sleep 5
done
```

## 🔄 Backup & Restore

### Backup
```bash
# On server
cd /opt/borgos
docker-compose down
tar czf borgos-backup-$(date +%Y%m%d).tar.gz .
docker-compose up -d
```

### Restore
```bash
cd /opt/borgos
docker-compose down
tar xzf borgos-backup-[date].tar.gz
docker-compose up -d
```

## 🆘 Support

If you encounter issues:

1. Check logs: `docker-compose logs -f`
2. Verify network: `ping 192.168.100.159`
3. Check Docker: `docker version`
4. Verify ports: `netstat -tlpn`

## 📝 Notes

- Default configuration uses 4GB RAM for Ollama
- Adjust memory limits in `docker-compose.yml` based on server capacity
- Website runs on port 8000 (not 80) to avoid conflicts
- All data is stored in Docker volumes for persistence