#!/usr/bin/env python3
"""
BorgOS Professional Dashboard
Advanced monitoring and management interface for BorgOS
"""

from flask import Flask, render_template, jsonify, request, session, redirect, url_for, send_file
from flask_socketio import SocketIO, emit
from flask_cors import CORS
import psutil
import subprocess
import json
import os
import time
import threading
import datetime
import logging
from collections import deque
import yaml
import secrets
from functools import wraps
import hashlib
import sqlite3
import shutil

app = Flask(__name__)
app.config['SECRET_KEY'] = secrets.token_hex(32)
socketio = SocketIO(app, cors_allowed_origins="*")
CORS(app)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
CONFIG_DIR = "/etc/borgos"
CONFIG_FILE = f"{CONFIG_DIR}/config.yaml"
DB_FILE = "/var/lib/borgos/dashboard.db"
METRICS_HISTORY_SIZE = 100

# In-memory metrics storage
metrics_history = {
    'cpu': deque(maxlen=METRICS_HISTORY_SIZE),
    'memory': deque(maxlen=METRICS_HISTORY_SIZE),
    'disk': deque(maxlen=METRICS_HISTORY_SIZE),
    'network': deque(maxlen=METRICS_HISTORY_SIZE),
    'timestamps': deque(maxlen=METRICS_HISTORY_SIZE)
}

# Active sessions tracking
active_sessions = {}
transfer_stats = {
    'uploads': [],
    'downloads': [],
    'total_uploaded': 0,
    'total_downloaded': 0,
    'current_speed': {'up': 0, 'down': 0}
}

# Services to monitor
MONITORED_SERVICES = [
    'ollama', 'nginx', 'docker', 'vsftpd', 'ssh', 
    'n8n', 'postgresql', 'redis', 'mcp-server'
]

# Initialize database
def init_db():
    """Initialize the dashboard database"""
    os.makedirs(os.path.dirname(DB_FILE), exist_ok=True)
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    
    # Create tables
    c.execute('''CREATE TABLE IF NOT EXISTS users
                 (id INTEGER PRIMARY KEY, username TEXT UNIQUE, 
                  password_hash TEXT, role TEXT, created_at TIMESTAMP)''')
    
    c.execute('''CREATE TABLE IF NOT EXISTS audit_log
                 (id INTEGER PRIMARY KEY, timestamp TIMESTAMP, 
                  user TEXT, action TEXT, details TEXT)''')
    
    c.execute('''CREATE TABLE IF NOT EXISTS api_keys
                 (id INTEGER PRIMARY KEY, name TEXT, key_hash TEXT, 
                  provider TEXT, created_at TIMESTAMP, last_used TIMESTAMP)''')
    
    c.execute('''CREATE TABLE IF NOT EXISTS metrics
                 (id INTEGER PRIMARY KEY, timestamp TIMESTAMP,
                  metric_type TEXT, value REAL, details TEXT)''')
    
    conn.commit()
    conn.close()

# Authentication decorator
def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user_id' not in session:
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated_function

# System monitoring functions
def get_system_metrics():
    """Get comprehensive system metrics"""
    try:
        # CPU metrics
        cpu_percent = psutil.cpu_percent(interval=1)
        cpu_freq = psutil.cpu_freq()
        cpu_cores = psutil.cpu_count()
        cpu_temp = get_cpu_temperature()
        
        # Memory metrics
        memory = psutil.virtual_memory()
        swap = psutil.swap_memory()
        
        # Disk metrics
        disk = psutil.disk_usage('/')
        disk_io = psutil.disk_io_counters()
        
        # Network metrics
        network = psutil.net_io_counters()
        connections = len(psutil.net_connections())
        
        # Process metrics
        processes = len(psutil.pids())
        
        # System info
        boot_time = datetime.datetime.fromtimestamp(psutil.boot_time())
        uptime = datetime.datetime.now() - boot_time
        
        return {
            'timestamp': datetime.datetime.now().isoformat(),
            'cpu': {
                'percent': cpu_percent,
                'frequency': cpu_freq.current if cpu_freq else 0,
                'cores': cpu_cores,
                'temperature': cpu_temp,
                'load_avg': os.getloadavg()
            },
            'memory': {
                'total': memory.total,
                'used': memory.used,
                'free': memory.free,
                'percent': memory.percent,
                'swap_total': swap.total,
                'swap_used': swap.used,
                'swap_percent': swap.percent
            },
            'disk': {
                'total': disk.total,
                'used': disk.used,
                'free': disk.free,
                'percent': disk.percent,
                'read_bytes': disk_io.read_bytes if disk_io else 0,
                'write_bytes': disk_io.write_bytes if disk_io else 0
            },
            'network': {
                'bytes_sent': network.bytes_sent,
                'bytes_recv': network.bytes_recv,
                'packets_sent': network.packets_sent,
                'packets_recv': network.packets_recv,
                'connections': connections
            },
            'system': {
                'uptime': str(uptime).split('.')[0],
                'boot_time': boot_time.isoformat(),
                'processes': processes,
                'platform': os.uname().sysname,
                'hostname': os.uname().nodename,
                'kernel': os.uname().release
            }
        }
    except Exception as e:
        logger.error(f"Error getting system metrics: {e}")
        return {}

def get_cpu_temperature():
    """Get CPU temperature if available"""
    try:
        temps = psutil.sensors_temperatures()
        if temps:
            for name, entries in temps.items():
                for entry in entries:
                    if entry.label in ['Core 0', 'CPU', 'Package id 0']:
                        return entry.current
        return None
    except:
        return None

def get_service_status(service_name):
    """Check if a service is running"""
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', service_name],
            capture_output=True, text=True, timeout=2
        )
        return result.stdout.strip() == 'active'
    except:
        # Fallback to checking process
        for proc in psutil.process_iter(['name']):
            if service_name in proc.info['name'].lower():
                return True
        return False

def get_docker_containers():
    """Get Docker container information"""
    try:
        result = subprocess.run(
            ['docker', 'ps', '--format', 'json'],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            containers = []
            for line in result.stdout.strip().split('\n'):
                if line:
                    containers.append(json.loads(line))
            return containers
        return []
    except:
        return []

def get_ai_model_status():
    """Get AI model status and information"""
    models = []
    
    # Check Ollama models
    try:
        result = subprocess.run(
            ['ollama', 'list'],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            lines = result.stdout.strip().split('\n')[1:]  # Skip header
            for line in lines:
                if line:
                    parts = line.split()
                    if len(parts) >= 4:
                        models.append({
                            'name': parts[0],
                            'provider': 'Ollama',
                            'size': parts[1],
                            'status': 'active',
                            'last_used': parts[-1]
                        })
    except:
        pass
    
    # Check for other configured models
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r') as f:
                config = yaml.safe_load(f)
                if 'models' in config:
                    for model in config['models']:
                        models.append({
                            'name': model.get('name', 'Unknown'),
                            'provider': model.get('provider', 'Unknown'),
                            'status': 'configured',
                            'api_key': '***' if model.get('api_key') else 'Not set'
                        })
        except:
            pass
    
    return models

def get_transfer_stats():
    """Get network transfer statistics"""
    global transfer_stats
    
    try:
        net_io = psutil.net_io_counters()
        
        # Calculate speed (if we have previous data)
        if hasattr(get_transfer_stats, 'last_check'):
            time_diff = time.time() - get_transfer_stats.last_check
            bytes_sent_diff = net_io.bytes_sent - get_transfer_stats.last_bytes_sent
            bytes_recv_diff = net_io.bytes_recv - get_transfer_stats.last_bytes_recv
            
            transfer_stats['current_speed']['up'] = bytes_sent_diff / time_diff
            transfer_stats['current_speed']['down'] = bytes_recv_diff / time_diff
        
        get_transfer_stats.last_check = time.time()
        get_transfer_stats.last_bytes_sent = net_io.bytes_sent
        get_transfer_stats.last_bytes_recv = net_io.bytes_recv
        
        transfer_stats['total_uploaded'] = net_io.bytes_sent
        transfer_stats['total_downloaded'] = net_io.bytes_recv
        
        return transfer_stats
    except Exception as e:
        logger.error(f"Error getting transfer stats: {e}")
        return transfer_stats

# Background monitoring thread
def monitor_system():
    """Background thread to continuously monitor system"""
    while True:
        try:
            metrics = get_system_metrics()
            timestamp = time.time()
            
            # Store in history
            metrics_history['cpu'].append(metrics['cpu']['percent'])
            metrics_history['memory'].append(metrics['memory']['percent'])
            metrics_history['disk'].append(metrics['disk']['percent'])
            metrics_history['network'].append({
                'sent': metrics['network']['bytes_sent'],
                'recv': metrics['network']['bytes_recv']
            })
            metrics_history['timestamps'].append(timestamp)
            
            # Emit to connected clients
            socketio.emit('metrics_update', {
                'metrics': metrics,
                'history': {
                    'cpu': list(metrics_history['cpu']),
                    'memory': list(metrics_history['memory']),
                    'disk': list(metrics_history['disk']),
                    'timestamps': list(metrics_history['timestamps'])
                }
            })
            
            # Also emit transfer stats
            transfer_stats = get_transfer_stats()
            socketio.emit('transfer_update', transfer_stats)
            
            time.sleep(2)  # Update every 2 seconds
        except Exception as e:
            logger.error(f"Error in monitoring thread: {e}")
            time.sleep(5)

# Routes
@app.route('/')
@login_required
def dashboard():
    return render_template('dashboard.html')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        # Simple authentication (in production, use proper hashing)
        if username == 'admin' and password == 'borgos':
            session['user_id'] = 1
            session['username'] = username
            return redirect(url_for('dashboard'))
        
        return render_template('login.html', error='Invalid credentials')
    
    return render_template('login.html')

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

@app.route('/api/metrics')
@login_required
def api_metrics():
    """API endpoint for getting current metrics"""
    return jsonify(get_system_metrics())

@app.route('/api/services')
@login_required
def api_services():
    """API endpoint for service status"""
    services = []
    for service in MONITORED_SERVICES:
        services.append({
            'name': service,
            'status': 'running' if get_service_status(service) else 'stopped',
            'uptime': 'N/A'  # Could calculate if needed
        })
    return jsonify(services)

@app.route('/api/models')
@login_required
def api_models():
    """API endpoint for AI models"""
    return jsonify(get_ai_model_status())

@app.route('/api/containers')
@login_required
def api_containers():
    """API endpoint for Docker containers"""
    return jsonify(get_docker_containers())

@app.route('/api/sessions')
@login_required
def api_sessions():
    """API endpoint for active sessions"""
    return jsonify(list(active_sessions.values()))

@app.route('/api/config', methods=['GET', 'POST'])
@login_required
def api_config():
    """API endpoint for configuration management"""
    if request.method == 'GET':
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, 'r') as f:
                config = yaml.safe_load(f)
                # Hide sensitive data
                if 'api_keys' in config:
                    for key in config['api_keys']:
                        if 'value' in config['api_keys'][key]:
                            config['api_keys'][key]['value'] = '***'
                return jsonify(config)
        return jsonify({})
    
    elif request.method == 'POST':
        config = request.json
        os.makedirs(CONFIG_DIR, exist_ok=True)
        with open(CONFIG_FILE, 'w') as f:
            yaml.dump(config, f)
        return jsonify({'status': 'success'})

@app.route('/api/logs/<service>')
@login_required
def api_logs(service):
    """API endpoint for service logs"""
    try:
        if service == 'system':
            result = subprocess.run(
                ['journalctl', '-n', '100', '--no-pager'],
                capture_output=True, text=True, timeout=5
            )
        else:
            result = subprocess.run(
                ['journalctl', '-u', service, '-n', '100', '--no-pager'],
                capture_output=True, text=True, timeout=5
            )
        return jsonify({'logs': result.stdout})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/service/<action>/<service>', methods=['POST'])
@login_required
def service_control(action, service):
    """Control services (start/stop/restart)"""
    if service not in MONITORED_SERVICES:
        return jsonify({'error': 'Invalid service'}), 400
    
    try:
        result = subprocess.run(
            ['systemctl', action, service],
            capture_output=True, text=True, timeout=10
        )
        return jsonify({
            'status': 'success' if result.returncode == 0 else 'failed',
            'output': result.stdout,
            'error': result.stderr
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

# WebSocket events
@socketio.on('connect')
def handle_connect():
    """Handle client connection"""
    session_id = request.sid
    active_sessions[session_id] = {
        'id': session_id,
        'connected_at': datetime.datetime.now().isoformat(),
        'ip': request.remote_addr,
        'user': session.get('username', 'anonymous')
    }
    emit('connected', {'session_id': session_id})
    logger.info(f"Client connected: {session_id}")

@socketio.on('disconnect')
def handle_disconnect():
    """Handle client disconnection"""
    session_id = request.sid
    if session_id in active_sessions:
        del active_sessions[session_id]
    logger.info(f"Client disconnected: {session_id}")

@socketio.on('request_metrics')
def handle_metrics_request():
    """Handle metrics request from client"""
    emit('metrics_update', {
        'metrics': get_system_metrics(),
        'history': {
            'cpu': list(metrics_history['cpu']),
            'memory': list(metrics_history['memory']),
            'disk': list(metrics_history['disk']),
            'timestamps': list(metrics_history['timestamps'])
        }
    })

if __name__ == '__main__':
    # Initialize database
    init_db()
    
    # Start monitoring thread
    monitor_thread = threading.Thread(target=monitor_system, daemon=True)
    monitor_thread.start()
    
    # Run the app
    socketio.run(app, host='0.0.0.0', port=8080, debug=False)