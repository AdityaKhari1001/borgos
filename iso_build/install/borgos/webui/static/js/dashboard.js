// BorgOS Dashboard JavaScript
// Real-time monitoring and management interface

// Initialize Socket.IO connection
const socket = io();

// Chart instances
let cpuChart, memoryChart, networkChart, diskChart, transferChart;

// Initialize dashboard
document.addEventListener('DOMContentLoaded', function() {
    initializeCharts();
    initializeEventListeners();
    loadInitialData();
    setupWebSocket();
    setupNavigation();
});

// Navigation handling
function setupNavigation() {
    const navLinks = document.querySelectorAll('.sidebar .nav-link');
    const sections = document.querySelectorAll('.content-section');
    
    navLinks.forEach(link => {
        link.addEventListener('click', function(e) {
            e.preventDefault();
            
            // Remove active class from all links and sections
            navLinks.forEach(l => l.classList.remove('active'));
            sections.forEach(s => s.classList.remove('active'));
            
            // Add active class to clicked link
            this.classList.add('active');
            
            // Show corresponding section
            const sectionId = this.dataset.section + '-section';
            const section = document.getElementById(sectionId);
            if (section) {
                section.classList.add('active');
                
                // Load section-specific data
                loadSectionData(this.dataset.section);
            }
        });
    });
}

// Load section-specific data
function loadSectionData(section) {
    switch(section) {
        case 'services':
            loadServices();
            break;
        case 'ai-models':
            loadModels();
            break;
        case 'containers':
            loadContainers();
            break;
        case 'sessions':
            loadSessions();
            break;
        case 'logs':
            loadLogs();
            break;
        case 'config':
            loadConfiguration();
            break;
    }
}

// Initialize Charts
function initializeCharts() {
    const chartOptions = {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
            legend: {
                display: false
            }
        },
        scales: {
            x: {
                grid: {
                    color: 'rgba(255, 255, 255, 0.1)'
                },
                ticks: {
                    color: '#a0a0a0'
                }
            },
            y: {
                grid: {
                    color: 'rgba(255, 255, 255, 0.1)'
                },
                ticks: {
                    color: '#a0a0a0'
                }
            }
        }
    };
    
    // CPU Chart
    const cpuCtx = document.getElementById('cpu-chart');
    if (cpuCtx) {
        cpuChart = new Chart(cpuCtx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    label: 'CPU Usage',
                    data: [],
                    borderColor: '#667eea',
                    backgroundColor: 'rgba(102, 126, 234, 0.1)',
                    tension: 0.4,
                    fill: true
                }]
            },
            options: {
                ...chartOptions,
                scales: {
                    ...chartOptions.scales,
                    y: {
                        ...chartOptions.scales.y,
                        min: 0,
                        max: 100
                    }
                }
            }
        });
    }
    
    // Memory Chart
    const memoryCtx = document.getElementById('memory-chart');
    if (memoryCtx) {
        memoryChart = new Chart(memoryCtx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    label: 'Memory Usage',
                    data: [],
                    borderColor: '#10b981',
                    backgroundColor: 'rgba(16, 185, 129, 0.1)',
                    tension: 0.4,
                    fill: true
                }]
            },
            options: {
                ...chartOptions,
                scales: {
                    ...chartOptions.scales,
                    y: {
                        ...chartOptions.scales.y,
                        min: 0,
                        max: 100
                    }
                }
            }
        });
    }
    
    // Network Chart
    const networkCtx = document.getElementById('network-chart');
    if (networkCtx) {
        networkChart = new Chart(networkCtx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    label: 'Upload',
                    data: [],
                    borderColor: '#f59e0b',
                    backgroundColor: 'rgba(245, 158, 11, 0.1)',
                    tension: 0.4,
                    fill: true
                }, {
                    label: 'Download',
                    data: [],
                    borderColor: '#3b82f6',
                    backgroundColor: 'rgba(59, 130, 246, 0.1)',
                    tension: 0.4,
                    fill: true
                }]
            },
            options: chartOptions
        });
    }
    
    // Transfer Chart
    const transferCtx = document.getElementById('transfer-chart');
    if (transferCtx) {
        transferChart = new Chart(transferCtx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    label: 'Upload Speed',
                    data: [],
                    borderColor: '#667eea',
                    backgroundColor: 'rgba(102, 126, 234, 0.1)',
                    tension: 0.4,
                    fill: true
                }, {
                    label: 'Download Speed',
                    data: [],
                    borderColor: '#10b981',
                    backgroundColor: 'rgba(16, 185, 129, 0.1)',
                    tension: 0.4,
                    fill: true
                }]
            },
            options: chartOptions
        });
    }
}

// WebSocket event handlers
function setupWebSocket() {
    socket.on('connect', function() {
        console.log('Connected to BorgOS Dashboard');
        socket.emit('request_metrics');
    });
    
    socket.on('metrics_update', function(data) {
        updateMetrics(data.metrics);
        updateCharts(data.history);
    });
    
    socket.on('transfer_update', function(data) {
        updateTransferStats(data);
    });
    
    socket.on('disconnect', function() {
        console.log('Disconnected from BorgOS Dashboard');
    });
}

// Update metrics display
function updateMetrics(metrics) {
    if (!metrics) return;
    
    // CPU
    if (metrics.cpu) {
        updateElement('cpu-usage', `${metrics.cpu.percent.toFixed(1)}%`);
        updateElement('cpu-progress', metrics.cpu.percent, 'width');
        updateElement('cpu-cores', metrics.cpu.cores);
    }
    
    // Memory
    if (metrics.memory) {
        updateElement('memory-usage', `${metrics.memory.percent.toFixed(1)}%`);
        updateElement('memory-progress', metrics.memory.percent, 'width');
        updateElement('total-memory', formatBytes(metrics.memory.total));
    }
    
    // Disk
    if (metrics.disk) {
        updateElement('disk-usage', `${metrics.disk.percent.toFixed(1)}%`);
        updateElement('disk-progress', metrics.disk.percent, 'width');
        updateElement('total-disk', formatBytes(metrics.disk.total));
    }
    
    // System
    if (metrics.system) {
        updateElement('uptime', formatUptime(metrics.system.uptime));
        updateElement('hostname', metrics.system.hostname);
        updateElement('platform', metrics.system.platform);
        updateElement('kernel', metrics.system.kernel);
    }
}

// Update charts with historical data
function updateCharts(history) {
    if (!history) return;
    
    const labels = history.timestamps ? history.timestamps.map(t => 
        new Date(t * 1000).toLocaleTimeString()
    ) : [];
    
    // Update CPU chart
    if (cpuChart && history.cpu) {
        cpuChart.data.labels = labels;
        cpuChart.data.datasets[0].data = history.cpu;
        cpuChart.update('none');
    }
    
    // Update Memory chart
    if (memoryChart && history.memory) {
        memoryChart.data.labels = labels;
        memoryChart.data.datasets[0].data = history.memory;
        memoryChart.update('none');
    }
}

// Update transfer statistics
function updateTransferStats(stats) {
    if (!stats) return;
    
    updateElement('upload-speed', formatSpeed(stats.current_speed.up));
    updateElement('download-speed', formatSpeed(stats.current_speed.down));
    updateElement('total-uploaded', formatBytes(stats.total_uploaded));
    updateElement('total-downloaded', formatBytes(stats.total_downloaded));
    
    // Update transfer chart
    if (transferChart) {
        const now = new Date().toLocaleTimeString();
        transferChart.data.labels.push(now);
        transferChart.data.datasets[0].data.push(stats.current_speed.up / 1024); // KB/s
        transferChart.data.datasets[1].data.push(stats.current_speed.down / 1024);
        
        // Keep only last 20 points
        if (transferChart.data.labels.length > 20) {
            transferChart.data.labels.shift();
            transferChart.data.datasets[0].data.shift();
            transferChart.data.datasets[1].data.shift();
        }
        
        transferChart.update('none');
    }
}

// Load initial data
function loadInitialData() {
    fetch('/api/metrics')
        .then(response => response.json())
        .then(data => updateMetrics(data))
        .catch(error => console.error('Error loading metrics:', error));
}

// Load services
function loadServices() {
    fetch('/api/services')
        .then(response => response.json())
        .then(services => {
            const container = document.getElementById('services-grid');
            container.innerHTML = '';
            
            services.forEach(service => {
                const card = createServiceCard(service);
                container.appendChild(card);
            });
        })
        .catch(error => console.error('Error loading services:', error));
}

// Create service card
function createServiceCard(service) {
    const col = document.createElement('div');
    col.className = 'col-md-4 mb-3';
    
    const statusClass = service.status === 'running' ? 'running' : 'stopped';
    const statusBadge = service.status === 'running' ? 
        '<span class="badge bg-success">Running</span>' : 
        '<span class="badge bg-danger">Stopped</span>';
    
    col.innerHTML = `
        <div class="service-card ${statusClass}">
            <div class="d-flex justify-content-between align-items-start mb-2">
                <h5>${service.name}</h5>
                ${statusBadge}
            </div>
            <div class="btn-group btn-group-sm" role="group">
                <button class="btn btn-outline-success" onclick="controlService('start', '${service.name}')">
                    <i class="bi bi-play-fill"></i>
                </button>
                <button class="btn btn-outline-warning" onclick="controlService('restart', '${service.name}')">
                    <i class="bi bi-arrow-clockwise"></i>
                </button>
                <button class="btn btn-outline-danger" onclick="controlService('stop', '${service.name}')">
                    <i class="bi bi-stop-fill"></i>
                </button>
            </div>
        </div>
    `;
    
    return col;
}

// Load AI models
function loadModels() {
    fetch('/api/models')
        .then(response => response.json())
        .then(models => {
            const tbody = document.getElementById('models-table');
            tbody.innerHTML = '';
            
            models.forEach(model => {
                const row = document.createElement('tr');
                row.innerHTML = `
                    <td>${model.name}</td>
                    <td>${model.provider}</td>
                    <td>${model.size || 'N/A'}</td>
                    <td>
                        <span class="badge bg-${model.status === 'active' ? 'success' : 'warning'}">
                            ${model.status}
                        </span>
                    </td>
                    <td>${model.last_used || 'Never'}</td>
                    <td>
                        <button class="btn btn-sm btn-primary" onclick="testModel('${model.name}')">
                            Test
                        </button>
                        <button class="btn btn-sm btn-danger" onclick="removeModel('${model.name}')">
                            Remove
                        </button>
                    </td>
                `;
                tbody.appendChild(row);
            });
        })
        .catch(error => console.error('Error loading models:', error));
}

// Load containers
function loadContainers() {
    fetch('/api/containers')
        .then(response => response.json())
        .then(containers => {
            const tbody = document.getElementById('containers-table');
            tbody.innerHTML = '';
            
            if (containers.length === 0) {
                tbody.innerHTML = '<tr><td colspan="6" class="text-center">No containers running</td></tr>';
                return;
            }
            
            containers.forEach(container => {
                const row = document.createElement('tr');
                row.innerHTML = `
                    <td>${container.ID ? container.ID.substring(0, 12) : 'N/A'}</td>
                    <td>${container.Image || 'N/A'}</td>
                    <td>
                        <span class="badge bg-${container.State === 'running' ? 'success' : 'warning'}">
                            ${container.State || 'Unknown'}
                        </span>
                    </td>
                    <td>${container.Ports || 'N/A'}</td>
                    <td>${container.CreatedAt || 'N/A'}</td>
                    <td>
                        <button class="btn btn-sm btn-warning" onclick="restartContainer('${container.ID}')">
                            Restart
                        </button>
                        <button class="btn btn-sm btn-danger" onclick="stopContainer('${container.ID}')">
                            Stop
                        </button>
                    </td>
                `;
                tbody.appendChild(row);
            });
        })
        .catch(error => console.error('Error loading containers:', error));
}

// Load sessions
function loadSessions() {
    fetch('/api/sessions')
        .then(response => response.json())
        .then(sessions => {
            const tbody = document.getElementById('sessions-table');
            tbody.innerHTML = '';
            
            sessions.forEach(session => {
                const row = document.createElement('tr');
                row.innerHTML = `
                    <td>${session.id.substring(0, 8)}...</td>
                    <td>${session.user}</td>
                    <td>${session.ip}</td>
                    <td>${new Date(session.connected_at).toLocaleString()}</td>
                    <td>
                        <button class="btn btn-sm btn-danger" onclick="terminateSession('${session.id}')">
                            Terminate
                        </button>
                    </td>
                `;
                tbody.appendChild(row);
            });
        })
        .catch(error => console.error('Error loading sessions:', error));
}

// Load logs
function loadLogs() {
    const service = document.getElementById('log-service').value;
    
    fetch(`/api/logs/${service}`)
        .then(response => response.json())
        .then(data => {
            document.getElementById('log-content').textContent = data.logs || 'No logs available';
        })
        .catch(error => {
            document.getElementById('log-content').textContent = 'Error loading logs: ' + error;
        });
}

// Load configuration
function loadConfiguration() {
    fetch('/api/config')
        .then(response => response.json())
        .then(config => {
            if (config.api_keys) {
                if (config.api_keys.openrouter) {
                    document.getElementById('openrouter-key').placeholder = 'Key configured';
                }
                if (config.api_keys.huggingface) {
                    document.getElementById('huggingface-key').placeholder = 'Key configured';
                }
                if (config.api_keys.openai) {
                    document.getElementById('openai-key').placeholder = 'Key configured';
                }
            }
        })
        .catch(error => console.error('Error loading configuration:', error));
}

// Service control
function controlService(action, service) {
    fetch(`/api/service/${action}/${service}`, { method: 'POST' })
        .then(response => response.json())
        .then(data => {
            if (data.status === 'success') {
                showNotification(`Service ${service} ${action}ed successfully`, 'success');
                loadServices();
            } else {
                showNotification(`Failed to ${action} ${service}: ${data.error}`, 'danger');
            }
        })
        .catch(error => {
            showNotification(`Error: ${error}`, 'danger');
        });
}

// Event listeners
function initializeEventListeners() {
    // Log service selector
    const logService = document.getElementById('log-service');
    if (logService) {
        logService.addEventListener('change', loadLogs);
    }
    
    // API keys form
    const apiKeysForm = document.getElementById('api-keys-form');
    if (apiKeysForm) {
        apiKeysForm.addEventListener('submit', function(e) {
            e.preventDefault();
            saveApiKeys();
        });
    }
    
    // System settings form
    const settingsForm = document.getElementById('system-settings-form');
    if (settingsForm) {
        settingsForm.addEventListener('submit', function(e) {
            e.preventDefault();
            saveSystemSettings();
        });
    }
}

// Save API keys
function saveApiKeys() {
    const config = {
        api_keys: {
            openrouter: document.getElementById('openrouter-key').value,
            huggingface: document.getElementById('huggingface-key').value,
            openai: document.getElementById('openai-key').value
        }
    };
    
    fetch('/api/config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(config)
    })
    .then(response => response.json())
    .then(data => {
        if (data.status === 'success') {
            showNotification('API keys saved successfully', 'success');
        }
    })
    .catch(error => {
        showNotification('Error saving API keys: ' + error, 'danger');
    });
}

// Quick actions
function restartServices() {
    showNotification('Restarting all services...', 'info');
    // Implementation here
}

function updateModels() {
    showNotification('Updating AI models...', 'info');
    // Implementation here
}

function clearCache() {
    showNotification('Clearing cache...', 'info');
    // Implementation here
}

function runDiagnostics() {
    showNotification('Running system diagnostics...', 'info');
    // Implementation here
}

// Utility functions
function updateElement(id, value, property = 'textContent') {
    const element = document.getElementById(id);
    if (element) {
        if (property === 'width') {
            element.style.width = `${value}%`;
        } else {
            element[property] = value;
        }
    }
}

function formatBytes(bytes) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

function formatSpeed(bytesPerSec) {
    if (bytesPerSec < 1024) return bytesPerSec.toFixed(0) + ' B/s';
    if (bytesPerSec < 1024 * 1024) return (bytesPerSec / 1024).toFixed(1) + ' KB/s';
    return (bytesPerSec / (1024 * 1024)).toFixed(1) + ' MB/s';
}

function formatUptime(uptime) {
    if (!uptime) return 'N/A';
    // Parse uptime string like "2 days, 14:30:45"
    const parts = uptime.split(', ');
    if (parts.length === 2) {
        const days = parts[0].split(' ')[0];
        const time = parts[1].split(':');
        return `${days}d ${time[0]}h ${time[1]}m`;
    }
    return uptime;
}

function toggleVisibility(inputId) {
    const input = document.getElementById(inputId);
    if (input.type === 'password') {
        input.type = 'text';
    } else {
        input.type = 'password';
    }
}

function showNotification(message, type = 'info') {
    // Create toast notification
    const toast = document.createElement('div');
    toast.className = `alert alert-${type} position-fixed top-0 end-0 m-3`;
    toast.style.zIndex = '9999';
    toast.innerHTML = message;
    
    document.body.appendChild(toast);
    
    setTimeout(() => {
        toast.remove();
    }, 3000);
}

// Auto-refresh
setInterval(() => {
    socket.emit('request_metrics');
}, 5000);