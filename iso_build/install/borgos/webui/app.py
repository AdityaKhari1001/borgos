#!/usr/bin/env python3
from flask import Flask, request, jsonify, render_template_string, session
import subprocess
import os
import json
import psutil
from datetime import datetime

app = Flask(__name__)
app.secret_key = os.urandom(24)

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>BorgOS Dashboard</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); margin: 0; padding: 20px; color: white; }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 { text-align: center; font-size: 3em; margin-bottom: 30px; text-shadow: 2px 2px 4px rgba(0,0,0,0.3); }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-bottom: 40px; }
        .stat-card { background: rgba(255,255,255,0.1); backdrop-filter: blur(10px); border-radius: 15px; padding: 20px; box-shadow: 0 8px 32px 0 rgba(31, 38, 135, 0.37); }
        .stat-title { font-size: 0.9em; opacity: 0.8; margin-bottom: 5px; }
        .stat-value { font-size: 2em; font-weight: bold; }
        .terminal { background: rgba(0,0,0,0.8); border-radius: 15px; padding: 20px; margin-top: 20px; box-shadow: 0 8px 32px 0 rgba(31, 38, 135, 0.37); }
        .terminal-header { display: flex; align-items: center; margin-bottom: 15px; }
        .terminal-dot { width: 12px; height: 12px; border-radius: 50%; margin-right: 8px; }
        .dot-red { background: #ff5f56; }
        .dot-yellow { background: #ffbd2e; }
        .dot-green { background: #27c93f; }
        form { display: flex; gap: 10px; }
        input[name="q"] { flex: 1; padding: 12px; border: none; border-radius: 8px; background: rgba(255,255,255,0.1); color: white; font-size: 16px; }
        input[name="q"]::placeholder { color: rgba(255,255,255,0.5); }
        button { padding: 12px 30px; border: none; border-radius: 8px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; font-size: 16px; cursor: pointer; transition: transform 0.2s; }
        button:hover { transform: translateY(-2px); }
        pre { background: transparent; color: #0f0; font-family: 'Courier New', monospace; margin: 0; padding: 10px; white-space: pre-wrap; word-wrap: break-word; }
        .services { display: flex; gap: 10px; margin-top: 20px; }
        .service { padding: 8px 16px; border-radius: 20px; font-size: 0.9em; }
        .service-up { background: rgba(39, 201, 63, 0.3); border: 1px solid #27c93f; }
        .service-down { background: rgba(255, 95, 86, 0.3); border: 1px solid #ff5f56; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🤖 BorgOS Dashboard</h1>
        
        <div class="stats">
            <div class="stat-card">
                <div class="stat-title">CPU Usage</div>
                <div class="stat-value">{{ cpu }}%</div>
            </div>
            <div class="stat-card">
                <div class="stat-title">Memory</div>
                <div class="stat-value">{{ memory }}%</div>
            </div>
            <div class="stat-card">
                <div class="stat-title">Disk</div>
                <div class="stat-value">{{ disk }}%</div>
            </div>
            <div class="stat-card">
                <div class="stat-title">Uptime</div>
                <div class="stat-value">{{ uptime }}</div>
            </div>
        </div>
        
        <div class="terminal">
            <div class="terminal-header">
                <div class="terminal-dot dot-red"></div>
                <div class="terminal-dot dot-yellow"></div>
                <div class="terminal-dot dot-green"></div>
            </div>
            <form method="post">
                <input name="q" placeholder="Ask Borg anything..." autocomplete="off">
                <button type="submit">Send</button>
            </form>
            {% if output %}
            <pre>{{ output }}</pre>
            {% endif %}
        </div>
        
        <div class="services">
            {% for service, status in services.items() %}
            <div class="service {{ 'service-up' if status else 'service-down' }}">
                {{ service }}: {{ 'UP' if status else 'DOWN' }}
            </div>
            {% endfor %}
        </div>
    </div>
</body>
</html>
"""

def get_system_stats():
    """Get system statistics."""
    stats = {
        'cpu': psutil.cpu_percent(interval=1),
        'memory': psutil.virtual_memory().percent,
        'disk': psutil.disk_usage('/').percent,
        'uptime': get_uptime()
    }
    return stats

def get_uptime():
    """Get system uptime."""
    with open('/proc/uptime', 'r') as f:
        uptime_seconds = float(f.readline().split()[0])
    
    days = int(uptime_seconds // 86400)
    hours = int((uptime_seconds % 86400) // 3600)
    
    if days > 0:
        return f"{days}d {hours}h"
    else:
        return f"{hours}h"

def check_services():
    """Check status of key services."""
    services = {
        'Ollama': check_service('ollama'),
        'Nginx': check_service('nginx'),
        'MCP': check_service('borgos-mcp'),
        'Docker': check_service('docker')
    }
    return services

def check_service(name):
    """Check if a service is running."""
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', name],
            capture_output=True,
            text=True
        )
        return result.stdout.strip() == 'active'
    except:
        return False

@app.route('/', methods=['GET', 'POST'])
def home():
    output = ""
    if request.method == 'POST':
        query = request.form.get('q', '')
        if query:
            try:
                result = subprocess.run(
                    ['/opt/borgos/env/bin/python3', '/usr/local/bin/borg', query],
                    capture_output=True,
                    text=True,
                    timeout=30
                )
                output = result.stdout or result.stderr
            except subprocess.TimeoutExpired:
                output = "Command timed out after 30 seconds"
            except Exception as e:
                output = f"Error: {str(e)}"

    stats = get_system_stats()
    services = check_services()
    
    return render_template_string(
        HTML_TEMPLATE,
        output=output,
        services=services,
        **stats
    )

@app.route('/api/query', methods=['POST'])
def api_query():
    """API endpoint for queries."""
    data = request.json
    query = data.get('query', '')
    
    if not query:
        return jsonify({'error': 'No query provided'}), 400
    
    try:
        result = subprocess.run(
            ['borg', query],
            capture_output=True,
            text=True,
            timeout=30
        )
        return jsonify({
            'query': query,
            'response': result.stdout,
            'error': result.stderr if result.returncode != 0 else None
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/stats', methods=['GET'])
def api_stats():
    """API endpoint for system statistics."""
    return jsonify({
        'stats': get_system_stats(),
        'services': check_services(),
        'timestamp': datetime.now().isoformat()
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=6969, debug=False)