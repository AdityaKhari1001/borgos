#!/usr/bin/env python3
"""
BorgOS Enhanced WebUI Dashboard
Complete system control center with AI management, monitoring, and file management.
"""
from flask import Flask, request, jsonify, render_template_string, session, redirect, url_for, send_file
import subprocess
import os
import sys
import json
import psutil
import yaml
from datetime import datetime, timedelta
import asyncio
from pathlib import Path
import threading
import queue
import time
import logging
from typing import Dict, List, Any, Optional
import hashlib
import secrets

# Add parent directory for imports
sys.path.insert(0, '/opt/borgos')

try:
    from model_manager import ModelManager
except ImportError:
    ModelManager = None

app = Flask(__name__)
app.secret_key = os.environ.get('FLASK_SECRET_KEY', secrets.token_hex(32))

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global state
model_manager = None
usage_stats = {
    "total_queries": 0,
    "total_cost": 0.0,
    "queries_by_provider": {},
    "queries_today": 0,
    "cost_today": 0.0,
    "last_reset": datetime.now().date()
}

# Initialize ModelManager
if ModelManager:
    try:
        model_manager = ModelManager()
    except Exception as e:
        logger.error(f"Failed to initialize ModelManager: {e}")

ENHANCED_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>BorgOS Control Center</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.0/font/bootstrap-icons.css" rel="stylesheet">
    <style>
        :root {
            --bg-primary: #0a0e27;
            --bg-secondary: #151932;
            --bg-card: #1e2139;
            --text-primary: #ffffff;
            --text-secondary: #8b92b9;
            --accent-primary: #7b2ff7;
            --accent-secondary: #00d4ff;
            --success: #00ff88;
            --warning: #ffbd2e;
            --danger: #ff5f56;
        }
        
        body {
            background: linear-gradient(135deg, var(--bg-primary) 0%, var(--bg-secondary) 100%);
            color: var(--text-primary);
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            min-height: 100vh;
        }
        
        .navbar {
            background: rgba(30, 33, 57, 0.95) !important;
            backdrop-filter: blur(10px);
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        
        .navbar-brand {
            font-weight: 700;
            background: linear-gradient(135deg, var(--accent-secondary), var(--accent-primary));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        
        .nav-link {
            color: var(--text-secondary) !important;
            transition: all 0.3s;
        }
        
        .nav-link:hover, .nav-link.active {
            color: var(--text-primary) !important;
        }
        
        .card {
            background: var(--bg-card);
            border: 1px solid rgba(255,255,255,0.1);
            border-radius: 12px;
            transition: all 0.3s;
        }
        
        .card:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 40px rgba(123, 47, 247, 0.2);
        }
        
        .stat-card {
            padding: 1.5rem;
            margin-bottom: 1.5rem;
        }
        
        .stat-value {
            font-size: 2rem;
            font-weight: 600;
            color: var(--text-primary);
        }
        
        .stat-label {
            color: var(--text-secondary);
            font-size: 0.875rem;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .progress {
            background: rgba(255,255,255,0.05);
            height: 8px;
        }
        
        .progress-bar {
            background: linear-gradient(90deg, var(--accent-secondary), var(--accent-primary));
        }
        
        .btn-primary {
            background: linear-gradient(135deg, var(--accent-primary), #5a1fb8);
            border: none;
            padding: 0.5rem 1.5rem;
            transition: all 0.3s;
        }
        
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(123, 47, 247, 0.3);
        }
        
        .terminal {
            background: #000;
            border-radius: 8px;
            padding: 1rem;
            font-family: 'SF Mono', Monaco, 'Cascadia Code', monospace;
            color: var(--success);
            min-height: 200px;
            max-height: 400px;
            overflow-y: auto;
        }
        
        .model-selector {
            background: var(--bg-card);
            border: 1px solid rgba(255,255,255,0.1);
            color: var(--text-primary);
            padding: 0.5rem 1rem;
            border-radius: 8px;
        }
        
        .model-badge {
            display: inline-block;
            padding: 0.25rem 0.75rem;
            border-radius: 20px;
            font-size: 0.75rem;
            font-weight: 600;
            text-transform: uppercase;
            margin: 0.25rem;
        }
        
        .badge-free {
            background: rgba(0,255,136,0.2);
            color: var(--success);
            border: 1px solid var(--success);
        }
        
        .badge-paid {
            background: rgba(255,189,46,0.2);
            color: var(--warning);
            border: 1px solid var(--warning);
        }
        
        .badge-local {
            background: rgba(0,212,255,0.2);
            color: var(--accent-secondary);
            border: 1px solid var(--accent-secondary);
        }
        
        .service-status {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 0.75rem;
            background: rgba(255,255,255,0.03);
            border-radius: 8px;
            margin-bottom: 0.5rem;
        }
        
        .status-indicator {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            margin-right: 0.5rem;
        }
        
        .status-up { background: var(--success); }
        .status-down { background: var(--danger); }
        
        .file-browser {
            background: var(--bg-card);
            border-radius: 8px;
            padding: 1rem;
            max-height: 500px;
            overflow-y: auto;
        }
        
        .file-item {
            padding: 0.5rem;
            border-radius: 4px;
            cursor: pointer;
            transition: background 0.2s;
        }
        
        .file-item:hover {
            background: rgba(255,255,255,0.05);
        }
        
        .tab-content {
            padding-top: 2rem;
        }
        
        #costChart {
            max-height: 300px;
        }
        
        .loading-spinner {
            display: inline-block;
            width: 20px;
            height: 20px;
            border: 3px solid rgba(255,255,255,0.1);
            border-top-color: var(--accent-primary);
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
        
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
    </style>
</head>
<body>
    <nav class="navbar navbar-expand-lg navbar-dark">
        <div class="container-fluid">
            <a class="navbar-brand" href="#">
                <i class="bi bi-cpu"></i> BorgOS Control Center
            </a>
            <div class="navbar-nav ms-auto">
                <span class="navbar-text me-3">
                    <i class="bi bi-circle-fill text-success"></i> System Online
                </span>
                <select id="modelSelector" class="model-selector me-3">
                    <option value="auto">Auto Select</option>
                    <optgroup label="Local (Ollama)">
                        <option value="ollama:mistral">Mistral 7B</option>
                        <option value="ollama:llama3.2">Llama 3.2</option>
                    </optgroup>
                    <optgroup label="Free Models">
                        <option value="or:zephyr-free">Zephyr 7B (Free)</option>
                        <option value="or:openchat-free">OpenChat (Free)</option>
                        <option value="hf:mistral">HF Mistral (Free)</option>
                    </optgroup>
                </select>
                <button class="btn btn-outline-light btn-sm" onclick="toggleTheme()">
                    <i class="bi bi-moon"></i>
                </button>
            </div>
        </div>
    </nav>
    
    <div class="container-fluid mt-4">
        <ul class="nav nav-tabs" id="mainTabs" role="tablist">
            <li class="nav-item">
                <button class="nav-link active" data-bs-toggle="tab" data-bs-target="#overview">
                    <i class="bi bi-speedometer2"></i> Overview
                </button>
            </li>
            <li class="nav-item">
                <button class="nav-link" data-bs-toggle="tab" data-bs-target="#ai">
                    <i class="bi bi-robot"></i> AI Models
                </button>
            </li>
            <li class="nav-item">
                <button class="nav-link" data-bs-toggle="tab" data-bs-target="#terminal">
                    <i class="bi bi-terminal"></i> Terminal
                </button>
            </li>
            <li class="nav-item">
                <button class="nav-link" data-bs-toggle="tab" data-bs-target="#files">
                    <i class="bi bi-folder"></i> Files
                </button>
            </li>
            <li class="nav-item">
                <button class="nav-link" data-bs-toggle="tab" data-bs-target="#services">
                    <i class="bi bi-gear"></i> Services
                </button>
            </li>
            <li class="nav-item">
                <button class="nav-link" data-bs-toggle="tab" data-bs-target="#logs">
                    <i class="bi bi-file-text"></i> Logs
                </button>
            </li>
        </ul>
        
        <div class="tab-content" id="mainTabContent">
            <!-- Overview Tab -->
            <div class="tab-pane fade show active" id="overview">
                <div class="row">
                    <div class="col-md-3">
                        <div class="card stat-card">
                            <div class="stat-label">CPU Usage</div>
                            <div class="stat-value">{{ cpu }}%</div>
                            <div class="progress mt-2">
                                <div class="progress-bar" style="width: {{ cpu }}%"></div>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="card stat-card">
                            <div class="stat-label">Memory</div>
                            <div class="stat-value">{{ memory }}%</div>
                            <div class="progress mt-2">
                                <div class="progress-bar" style="width: {{ memory }}%"></div>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="card stat-card">
                            <div class="stat-label">Disk Usage</div>
                            <div class="stat-value">{{ disk }}%</div>
                            <div class="progress mt-2">
                                <div class="progress-bar" style="width: {{ disk }}%"></div>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="card stat-card">
                            <div class="stat-label">Uptime</div>
                            <div class="stat-value">{{ uptime }}</div>
                        </div>
                    </div>
                </div>
                
                <div class="row mt-4">
                    <div class="col-md-6">
                        <div class="card p-3">
                            <h5>Usage Statistics</h5>
                            <div class="row mt-3">
                                <div class="col-6">
                                    <small class="text-secondary">Total Queries</small>
                                    <h4>{{ usage_stats.total_queries }}</h4>
                                </div>
                                <div class="col-6">
                                    <small class="text-secondary">Total Cost</small>
                                    <h4>${{ "%.4f"|format(usage_stats.total_cost) }}</h4>
                                </div>
                            </div>
                            <canvas id="costChart" class="mt-3"></canvas>
                        </div>
                    </div>
                    <div class="col-md-6">
                        <div class="card p-3">
                            <h5>Quick Actions</h5>
                            <div class="d-grid gap-2 mt-3">
                                <button class="btn btn-primary" onclick="pullModel()">
                                    <i class="bi bi-download"></i> Pull New Model
                                </button>
                                <button class="btn btn-primary" onclick="clearCache()">
                                    <i class="bi bi-trash"></i> Clear Cache
                                </button>
                                <button class="btn btn-primary" onclick="exportLogs()">
                                    <i class="bi bi-file-earmark-arrow-down"></i> Export Logs
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- AI Models Tab -->
            <div class="tab-pane fade" id="ai">
                <div class="row">
                    <div class="col-md-8">
                        <div class="card p-3">
                            <h5>Available Models</h5>
                            <div id="modelList" class="mt-3">
                                {% for provider, models in available_models.items() %}
                                <h6 class="mt-3">{{ provider|upper }}</h6>
                                {% for model in models %}
                                <div class="d-flex justify-content-between align-items-center p-2">
                                    <div>
                                        <span>{{ model.name }}</span>
                                        <span class="model-badge badge-{{ model.tier }}">{{ model.tier }}</span>
                                    </div>
                                    <button class="btn btn-sm btn-primary" onclick="selectModel('{{ model.name }}', '{{ provider }}')">
                                        Select
                                    </button>
                                </div>
                                {% endfor %}
                                {% endfor %}
                            </div>
                        </div>
                    </div>
                    <div class="col-md-4">
                        <div class="card p-3">
                            <h5>Configuration</h5>
                            <form id="configForm" class="mt-3">
                                <div class="mb-3">
                                    <label class="form-label">OpenRouter API Key</label>
                                    <input type="password" class="form-control" id="orApiKey" placeholder="sk-...">
                                </div>
                                <div class="mb-3">
                                    <label class="form-label">HuggingFace API Key</label>
                                    <input type="password" class="form-control" id="hfApiKey" placeholder="hf_...">
                                </div>
                                <div class="mb-3">
                                    <div class="form-check">
                                        <input class="form-check-input" type="checkbox" id="freeOnly" checked>
                                        <label class="form-check-label">Use Free Models Only</label>
                                    </div>
                                </div>
                                <div class="mb-3">
                                    <label class="form-label">Routing Strategy</label>
                                    <select class="form-select" id="routingStrategy">
                                        <option value="cost_optimized">Cost Optimized</option>
                                        <option value="quality_first">Quality First</option>
                                        <option value="balanced">Balanced</option>
                                    </select>
                                </div>
                                <button type="submit" class="btn btn-primary w-100">Save Configuration</button>
                            </form>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- Terminal Tab -->
            <div class="tab-pane fade" id="terminal">
                <div class="card p-3">
                    <div class="input-group mb-3">
                        <input type="text" class="form-control" id="terminalInput" placeholder="Ask Borg anything...">
                        <button class="btn btn-primary" onclick="executeQuery()">
                            <i class="bi bi-send"></i> Send
                        </button>
                    </div>
                    <div class="terminal" id="terminalOutput">
                        <div>Welcome to BorgOS Terminal. Type your query above.</div>
                    </div>
                </div>
            </div>
            
            <!-- Files Tab -->
            <div class="tab-pane fade" id="files">
                <div class="row">
                    <div class="col-md-4">
                        <div class="card p-3">
                            <h5>File Browser</h5>
                            <div class="file-browser" id="fileBrowser">
                                <!-- File list will be loaded here -->
                            </div>
                        </div>
                    </div>
                    <div class="col-md-8">
                        <div class="card p-3">
                            <h5>File Editor</h5>
                            <textarea class="form-control" id="fileEditor" rows="20" style="font-family: monospace;"></textarea>
                            <div class="mt-3">
                                <button class="btn btn-primary" onclick="saveFile()">Save</button>
                                <button class="btn btn-secondary" onclick="reloadFile()">Reload</button>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- Services Tab -->
            <div class="tab-pane fade" id="services">
                <div class="card p-3">
                    <h5>System Services</h5>
                    <div id="servicesList" class="mt-3">
                        {% for service, status in services.items() %}
                        <div class="service-status">
                            <div>
                                <span class="status-indicator status-{{ 'up' if status else 'down' }}"></span>
                                {{ service }}
                            </div>
                            <div>
                                <button class="btn btn-sm btn-success" onclick="controlService('{{ service }}', 'start')">Start</button>
                                <button class="btn btn-sm btn-warning" onclick="controlService('{{ service }}', 'restart')">Restart</button>
                                <button class="btn btn-sm btn-danger" onclick="controlService('{{ service }}', 'stop')">Stop</button>
                            </div>
                        </div>
                        {% endfor %}
                    </div>
                </div>
            </div>
            
            <!-- Logs Tab -->
            <div class="tab-pane fade" id="logs">
                <div class="card p-3">
                    <div class="d-flex justify-content-between mb-3">
                        <h5>System Logs</h5>
                        <select id="logFilter" onchange="filterLogs()">
                            <option value="all">All Logs</option>
                            <option value="error">Errors Only</option>
                            <option value="warning">Warnings</option>
                            <option value="info">Info</option>
                        </select>
                    </div>
                    <div class="terminal" id="logsOutput">
                        <!-- Logs will be loaded here -->
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script>
        // Initialize charts
        const ctx = document.getElementById('costChart');
        if (ctx) {
            new Chart(ctx, {
                type: 'line',
                data: {
                    labels: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
                    datasets: [{
                        label: 'Daily Cost ($)',
                        data: [0, 0, 0, 0, 0, 0, 0],
                        borderColor: '#7b2ff7',
                        tension: 0.4
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false
                }
            });
        }
        
        // Terminal functionality
        async function executeQuery() {
            const input = document.getElementById('terminalInput');
            const output = document.getElementById('terminalOutput');
            const query = input.value;
            
            if (!query) return;
            
            // Add query to output
            output.innerHTML += `<div class="text-info">> ${query}</div>`;
            output.innerHTML += `<div class="loading-spinner"></div>`;
            
            try {
                const response = await fetch('/api/query', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({
                        query: query,
                        model: document.getElementById('modelSelector').value
                    })
                });
                
                const data = await response.json();
                output.innerHTML = output.innerHTML.replace('<div class="loading-spinner"></div>', '');
                output.innerHTML += `<div>${data.response || data.error}</div>`;
            } catch (error) {
                output.innerHTML += `<div class="text-danger">Error: ${error}</div>`;
            }
            
            input.value = '';
            output.scrollTop = output.scrollHeight;
        }
        
        // Service control
        async function controlService(service, action) {
            try {
                const response = await fetch(`/api/services/${service}/${action}`, {
                    method: 'POST'
                });
                const data = await response.json();
                if (data.success) {
                    location.reload();
                } else {
                    alert(`Failed to ${action} ${service}: ${data.error}`);
                }
            } catch (error) {
                alert(`Error: ${error}`);
            }
        }
        
        // File browser
        async function loadFiles(path = '/') {
            try {
                const response = await fetch(`/api/files?path=${encodeURIComponent(path)}`);
                const files = await response.json();
                const browser = document.getElementById('fileBrowser');
                
                browser.innerHTML = files.map(file => `
                    <div class="file-item" onclick="selectFile('${file.path}')">
                        <i class="bi bi-${file.type === 'directory' ? 'folder' : 'file-text'}"></i>
                        ${file.name}
                    </div>
                `).join('');
            } catch (error) {
                console.error('Failed to load files:', error);
            }
        }
        
        // Auto-refresh stats
        setInterval(async () => {
            try {
                const response = await fetch('/api/stats');
                const data = await response.json();
                // Update UI with new stats
            } catch (error) {
                console.error('Stats update failed:', error);
            }
        }, 5000);
        
        // Initialize
        document.addEventListener('DOMContentLoaded', () => {
            loadFiles();
        });
    </script>
</body>
</html>
"""

def get_enhanced_stats():
    """Get comprehensive system statistics."""
    cpu_percent = psutil.cpu_percent(interval=1)
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    
    stats = {
        'cpu': cpu_percent,
        'memory': memory.percent,
        'disk': disk.percent,
        'uptime': get_uptime(),
        'memory_used': f"{memory.used // (1024**3)}GB",
        'memory_total': f"{memory.total // (1024**3)}GB",
        'disk_used': f"{disk.used // (1024**3)}GB",
        'disk_total': f"{disk.total // (1024**3)}GB",
    }
    return stats

def get_uptime():
    """Get system uptime."""
    try:
        with open('/proc/uptime', 'r') as f:
            uptime_seconds = float(f.readline().split()[0])
        
        days = int(uptime_seconds // 86400)
        hours = int((uptime_seconds % 86400) // 3600)
        
        if days > 0:
            return f"{days}d {hours}h"
        else:
            return f"{hours}h"
    except:
        return "Unknown"

def check_services():
    """Check status of key services."""
    services = {
        'Ollama': check_service('ollama'),
        'Nginx': check_service('nginx'),
        'MCP Server': check_service('borgos-mcp'),
        'Docker': check_service('docker'),
        'vsftpd': check_service('vsftpd')
    }
    return services

def check_service(name):
    """Check if a service is running."""
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', name],
            capture_output=True,
            text=True,
            timeout=2
        )
        return result.stdout.strip() == 'active'
    except:
        return False

def get_available_models():
    """Get list of available models grouped by provider."""
    if model_manager:
        models = model_manager.list_available_models()
        grouped = {}
        for model in models:
            provider = model.provider.value
            if provider not in grouped:
                grouped[provider] = []
            grouped[provider].append({
                'name': model.name,
                'tier': 'free' if model.tier.value == 'free' else 'paid' if model.tier.value == 'paid' else 'local'
            })
        return grouped
    return {}

@app.route('/')
def dashboard():
    """Enhanced dashboard view."""
    stats = get_enhanced_stats()
    services = check_services()
    models = get_available_models()
    
    # Update daily stats if needed
    global usage_stats
    today = datetime.now().date()
    if usage_stats["last_reset"] != today:
        usage_stats["queries_today"] = 0
        usage_stats["cost_today"] = 0.0
        usage_stats["last_reset"] = today
    
    return render_template_string(
        ENHANCED_TEMPLATE,
        **stats,
        services=services,
        available_models=models,
        usage_stats=usage_stats
    )

@app.route('/api/query', methods=['POST'])
def api_query():
    """Execute AI query."""
    global usage_stats
    
    data = request.json
    query = data.get('query', '')
    model = data.get('model', 'auto')
    
    if not query:
        return jsonify({'error': 'No query provided'}), 400
    
    try:
        # Parse model selection
        provider = None
        model_name = None
        
        if model != 'auto':
            if ':' in model:
                provider, model_name = model.split(':', 1)
                provider = {'ollama': 'ollama', 'or': 'openrouter', 'hf': 'huggingface'}.get(provider)
        
        # Execute query
        if model_manager:
            response, metadata = asyncio.run(model_manager.query_model(
                prompt=query,
                model=model_name,
                provider=provider
            ))
            
            # Update stats
            usage_stats["total_queries"] += 1
            usage_stats["queries_today"] += 1
            usage_stats["total_cost"] += metadata.get("cost", 0)
            usage_stats["cost_today"] += metadata.get("cost", 0)
            
            provider_name = metadata.get("provider", "unknown")
            if provider_name not in usage_stats["queries_by_provider"]:
                usage_stats["queries_by_provider"][provider_name] = 0
            usage_stats["queries_by_provider"][provider_name] += 1
            
            return jsonify({
                'query': query,
                'response': response,
                'metadata': metadata
            })
        else:
            # Fallback to simple execution
            result = subprocess.run(
                ['borg', query],
                capture_output=True,
                text=True,
                timeout=30
            )
            return jsonify({
                'query': query,
                'response': result.stdout or result.stderr
            })
            
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/models', methods=['GET'])
def api_models():
    """Get available models."""
    models = get_available_models()
    return jsonify(models)

@app.route('/api/models/pull', methods=['POST'])
def api_pull_model():
    """Pull a new model."""
    data = request.json
    model = data.get('model')
    
    if not model:
        return jsonify({'error': 'No model specified'}), 400
    
    try:
        if model_manager:
            success = model_manager.pull_model(model)
            return jsonify({'success': success})
        else:
            result = subprocess.run(
                ['ollama', 'pull', model],
                capture_output=True,
                text=True
            )
            return jsonify({
                'success': result.returncode == 0,
                'output': result.stdout
            })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/config', methods=['GET', 'POST'])
def api_config():
    """Get or update configuration."""
    if request.method == 'GET':
        if model_manager:
            return jsonify(model_manager.config)
        return jsonify({})
    
    else:  # POST
        data = request.json
        
        if model_manager:
            # Update configuration
            if 'openrouter_api_key' in data:
                model_manager.config['providers']['openrouter']['api_key'] = data['openrouter_api_key']
            if 'huggingface_api_key' in data:
                model_manager.config['providers']['huggingface']['api_key'] = data['huggingface_api_key']
            if 'use_free_only' in data:
                model_manager.config['providers']['openrouter']['use_free_only'] = data['use_free_only']
                model_manager.config['providers']['huggingface']['use_free_tier'] = data['use_free_only']
            if 'routing_strategy' in data:
                model_manager.config['routing']['strategy'] = data['routing_strategy']
            
            # Save configuration
            model_manager.save_config()
            
            return jsonify({'success': True})
        
        return jsonify({'error': 'ModelManager not available'}), 500

@app.route('/api/files', methods=['GET'])
def api_files():
    """List files in a directory."""
    path = request.args.get('path', '/')
    
    try:
        files = []
        for item in Path(path).iterdir():
            files.append({
                'name': item.name,
                'path': str(item),
                'type': 'directory' if item.is_dir() else 'file',
                'size': item.stat().st_size if item.is_file() else 0
            })
        return jsonify(sorted(files, key=lambda x: (x['type'] != 'directory', x['name'])))
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/file', methods=['GET', 'POST'])
def api_file():
    """Read or write a file."""
    if request.method == 'GET':
        path = request.args.get('path')
        if not path:
            return jsonify({'error': 'No path specified'}), 400
        
        try:
            with open(path, 'r') as f:
                content = f.read()
            return jsonify({'content': content})
        except Exception as e:
            return jsonify({'error': str(e)}), 500
    
    else:  # POST
        data = request.json
        path = data.get('path')
        content = data.get('content')
        
        if not path or content is None:
            return jsonify({'error': 'Path and content required'}), 400
        
        try:
            with open(path, 'w') as f:
                f.write(content)
            return jsonify({'success': True})
        except Exception as e:
            return jsonify({'error': str(e)}), 500

@app.route('/api/services/<service>/<action>', methods=['POST'])
def manage_service(service, action):
    """Manage system services."""
    allowed_services = ['ollama', 'nginx', 'borgos-mcp', 'borgos-webui', 'vsftpd', 'docker']
    allowed_actions = ['start', 'stop', 'restart', 'status']
    
    if service not in allowed_services:
        return jsonify({'error': 'Service not allowed'}), 403
    
    if action not in allowed_actions:
        return jsonify({'error': 'Action not allowed'}), 403
    
    try:
        if action == 'status':
            cmd = ['systemctl', 'is-active', service]
        else:
            cmd = ['systemctl', action, service]
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        
        return jsonify({
            'service': service,
            'action': action,
            'success': result.returncode == 0,
            'output': result.stdout.strip()
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/logs', methods=['GET'])
def api_logs():
    """Get system logs."""
    service = request.args.get('service', 'borgos-webui')
    lines = request.args.get('lines', 100)
    
    try:
        result = subprocess.run(
            ['journalctl', '-u', service, '-n', str(lines), '--no-pager'],
            capture_output=True,
            text=True
        )
        return jsonify({'logs': result.stdout})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/stats', methods=['GET'])
def api_stats():
    """Get system statistics."""
    return jsonify({
        'system': get_enhanced_stats(),
        'services': check_services(),
        'usage': usage_stats,
        'timestamp': datetime.now().isoformat()
    })

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint."""
    return jsonify({
        'status': 'healthy',
        'version': '2.0',
        'model_manager': model_manager is not None,
        'timestamp': datetime.now().isoformat()
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=6969, debug=False)