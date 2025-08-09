#!/usr/bin/env python3
"""
Unit tests for BorgOS WebUI
"""
import pytest
import json
import sys
import os
from unittest.mock import patch, MagicMock

# Add parent directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from webui.app import app, get_system_stats, check_services, get_uptime

@pytest.fixture
def client():
    """Create test client for Flask app."""
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

class TestWebUI:
    """Test suite for WebUI endpoints."""
    
    def test_home_page(self, client):
        """Test home page renders correctly."""
        response = client.get('/')
        assert response.status_code == 200
        assert b'BorgOS Control Center' in response.data
    
    def test_home_page_post(self, client):
        """Test POST request to home page."""
        with patch('subprocess.run') as mock_run:
            mock_run.return_value = MagicMock(
                stdout='Test output',
                stderr='',
                returncode=0
            )
            response = client.post('/', data={'q': 'test query'})
            assert response.status_code == 200
            assert b'Test output' in response.data
    
    def test_api_stats(self, client):
        """Test /api/stats endpoint."""
        response = client.get('/api/stats')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert 'stats' in data
        assert 'services' in data
        assert 'timestamp' in data
    
    def test_api_query(self, client):
        """Test /api/query endpoint."""
        with patch('subprocess.run') as mock_run:
            mock_run.return_value = MagicMock(
                stdout='API response',
                stderr='',
                returncode=0
            )
            
            response = client.post('/api/query', 
                                  json={'query': 'test query'},
                                  content_type='application/json')
            assert response.status_code == 200
            
            data = json.loads(response.data)
            assert data['query'] == 'test query'
            assert data['response'] == 'API response'
            assert data['error'] is None
    
    def test_api_query_no_input(self, client):
        """Test /api/query with no input."""
        response = client.post('/api/query', 
                              json={},
                              content_type='application/json')
        assert response.status_code == 400
        
        data = json.loads(response.data)
        assert 'error' in data
    
    def test_api_query_timeout(self, client):
        """Test /api/query timeout handling."""
        with patch('subprocess.run') as mock_run:
            import subprocess
            mock_run.side_effect = subprocess.TimeoutExpired('borg', 30)
            
            response = client.post('/api/query',
                                  json={'query': 'test'},
                                  content_type='application/json')
            assert response.status_code == 408
    
    def test_health_endpoint(self, client):
        """Test /health endpoint."""
        response = client.get('/health')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert data['status'] == 'healthy'
        assert 'version' in data
        assert 'timestamp' in data
    
    def test_manage_service(self, client):
        """Test service management endpoint."""
        with patch('subprocess.run') as mock_run:
            mock_run.return_value = MagicMock(
                stdout='active',
                stderr='',
                returncode=0
            )
            
            response = client.post('/api/services/nginx/status')
            assert response.status_code == 200
            
            data = json.loads(response.data)
            assert data['service'] == 'nginx'
            assert data['action'] == 'status'
            assert data['success'] is True
    
    def test_manage_service_invalid(self, client):
        """Test service management with invalid service."""
        response = client.post('/api/services/invalid_service/status')
        assert response.status_code == 403
        
        data = json.loads(response.data)
        assert 'error' in data
    
    def test_manage_service_invalid_action(self, client):
        """Test service management with invalid action."""
        response = client.post('/api/services/nginx/invalid_action')
        assert response.status_code == 403

class TestHelperFunctions:
    """Test helper functions."""
    
    def test_get_system_stats(self):
        """Test system stats collection."""
        stats = get_system_stats()
        
        assert 'cpu' in stats
        assert 'memory' in stats
        assert 'disk' in stats
        assert 'uptime' in stats
        assert 'network_status' in stats
        assert 'process_count' in stats
        
        assert isinstance(stats['cpu'], (int, float))
        assert isinstance(stats['memory'], (int, float))
        assert isinstance(stats['disk'], (int, float))
    
    def test_check_services(self):
        """Test service checking."""
        with patch('subprocess.run') as mock_run:
            mock_run.return_value = MagicMock(
                stdout='active',
                stderr='',
                returncode=0
            )
            
            services = check_services()
            assert isinstance(services, dict)
            assert 'Ollama' in services
            assert 'Nginx' in services
            assert 'WebUI' in services
            assert services['WebUI'] is True  # WebUI is always True when running
    
    @patch('builtins.open', create=True)
    def test_get_uptime(self, mock_open):
        """Test uptime calculation."""
        # Mock /proc/uptime content
        mock_open.return_value.__enter__.return_value.readline.return_value = "3661.5 1234.5"
        
        uptime = get_uptime()
        assert '1h 1m' in uptime
    
    @patch('builtins.open', side_effect=FileNotFoundError)
    def test_get_uptime_error(self, mock_open):
        """Test uptime with missing /proc/uptime."""
        uptime = get_uptime()
        assert uptime == "Unknown"