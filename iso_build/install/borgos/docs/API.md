# API Reference

BorgOS provides a comprehensive REST API with WebSocket support for real-time updates.

## Base URL

```
http://localhost:8081/api/v1
```

## Authentication

Currently using basic authentication. JWT authentication coming in v2.1.

```bash
# Example with curl
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:8081/api/v1/projects
```

## Endpoints

### System

#### Health Check
```http
GET /health
```

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

#### System Status
```http
GET /api/v1/status
```

**Response:**
```json
{
  "cpu_percent": 45.2,
  "memory_percent": 62.5,
  "disk_percent": 38.9,
  "active_deployments": 5,
  "total_projects": 12,
  "recent_errors": 3,
  "uptime_seconds": 86400
}
```

### Projects

#### List Projects
```http
GET /api/v1/projects
```

**Query Parameters:**
- `active` (boolean): Filter by active status
- `limit` (integer): Maximum results
- `offset` (integer): Pagination offset

**Response:**
```json
[
  {
    "id": 1,
    "name": "MyProject",
    "path": "/projects/myproject",
    "zenith_id": "zen-123",
    "project_type": "web",
    "tech_stack": ["python", "react", "postgresql"],
    "health_score": 85,
    "vibe_score": 90,
    "eco_score": 75,
    "errors": [],
    "metadata": {},
    "is_active": true,
    "created_at": "2024-01-15T10:00:00Z",
    "updated_at": "2024-01-15T10:30:00Z"
  }
]
```

#### Create Project
```http
POST /api/v1/projects
```

**Request Body:**
```json
{
  "name": "NewProject",
  "path": "/projects/newproject",
  "project_type": "api",
  "tech_stack": ["fastapi", "postgresql"]
}
```

**Response:**
```json
{
  "id": 2,
  "name": "NewProject",
  "path": "/projects/newproject",
  "project_type": "api",
  "tech_stack": ["fastapi", "postgresql"],
  "health_score": 0,
  "vibe_score": 75,
  "eco_score": 80,
  "is_active": true,
  "created_at": "2024-01-15T11:00:00Z"
}
```

#### Get Project Details
```http
GET /api/v1/projects/{id}
```

**Response:**
```json
{
  "id": 1,
  "name": "MyProject",
  "path": "/projects/myproject",
  "zenith_id": "zen-123",
  "project_type": "web",
  "tech_stack": ["python", "react", "postgresql"],
  "health_score": 85,
  "vibe_score": 90,
  "eco_score": 75,
  "errors": [
    {
      "type": "syntax",
      "file": "main.py",
      "line": 42,
      "message": "Unexpected indent"
    }
  ],
  "metadata": {
    "lines_of_code": 5420,
    "test_coverage": 78.5,
    "dependencies": 32
  },
  "deployments": [
    {
      "id": 1,
      "port": 8090,
      "status": "running"
    }
  ]
}
```

#### Scan Project
```http
POST /api/v1/projects/{id}/scan
```

Triggers background scan of project for updates, errors, and metrics.

**Response:**
```json
{
  "message": "Scan initiated for project 1"
}
```

#### Scan Zenith Projects
```http
POST /api/v1/projects/scan-zenith
```

Scans all Zenith Coder projects and syncs to database.

**Response:**
```json
{
  "message": "Scanned and synced 5 Zenith projects",
  "count": 5
}
```

### Deployments

#### List Deployments
```http
GET /api/v1/deployments
```

**Response:**
```json
[
  {
    "id": 1,
    "project_id": 1,
    "name": "myproject-prod",
    "port": 8090,
    "status": "running",
    "container_id": "abc123def456",
    "url": "http://localhost:8090",
    "health_check_url": "http://localhost:8090/health",
    "environment": {
      "NODE_ENV": "production"
    },
    "cpu_limit": "1",
    "memory_limit": "512m",
    "started_at": "2024-01-15T09:00:00Z"
  }
]
```

#### Deploy Project
```http
POST /api/v1/deploy
```

**Request Body:**
```json
{
  "project_id": 1,
  "name": "myproject-staging",
  "port": 8091,
  "environment": {
    "NODE_ENV": "staging"
  },
  "cpu_limit": "0.5",
  "memory_limit": "256m"
}
```

**Response:**
```json
{
  "message": "Deployment created on port 8091",
  "id": 2
}
```

#### Stop Deployment
```http
POST /api/v1/deployments/{id}/stop
```

**Response:**
```json
{
  "message": "Deployment 2 stopped"
}
```

#### Restart Deployment
```http
POST /api/v1/deployments/{id}/restart
```

**Response:**
```json
{
  "message": "Deployment 2 restarted"
}
```

### Agent Zero

#### Get Status
```http
GET /api/v1/agent-zero/status
```

**Response:**
```json
{
  "running": true,
  "port": 8085,
  "process_id": 12345,
  "directory": "/Users/ai/agent-zero",
  "ui_url": "http://localhost:8085"
}
```

#### Start Agent Zero
```http
POST /api/v1/agent-zero/start
```

**Response:**
```json
{
  "success": true,
  "status": {
    "running": true,
    "port": 8085,
    "ui_url": "http://localhost:8085"
  }
}
```

#### Stop Agent Zero
```http
POST /api/v1/agent-zero/stop
```

**Response:**
```json
{
  "success": true
}
```

#### Execute Task
```http
POST /api/v1/agent-zero/execute
```

**Request Body:**
```json
{
  "type": "code_execution",
  "description": "Create a Python script to analyze logs",
  "prompt": "Write a script that parses error logs and generates a summary report",
  "context": {
    "project_id": 1,
    "log_path": "/logs/app.log"
  }
}
```

**Response:**
```json
{
  "message": "Task submitted",
  "task_id": 42
}
```

#### Get Capabilities
```http
GET /api/v1/agent-zero/capabilities
```

**Response:**
```json
[
  "code_execution",
  "web_browsing",
  "file_operations",
  "shell_commands",
  "memory_management",
  "task_scheduling",
  "multi_agent_coordination",
  "knowledge_retrieval",
  "image_analysis",
  "api_integration"
]
```

### Agent Tasks

#### Create Task
```http
POST /api/v1/agent/task
```

**Request Body:**
```json
{
  "project_id": 1,
  "agent_type": "agent-zero",
  "task_type": "automation",
  "description": "Monitor system logs and alert on errors",
  "priority": 1,
  "input_data": {
    "log_paths": ["/var/log/app.log"],
    "alert_threshold": 5
  }
}
```

**Response:**
```json
{
  "message": "Task created and queued",
  "task_id": 43
}
```

#### Get Tasks
```http
GET /api/v1/agent/tasks
```

**Query Parameters:**
- `status` (string): Filter by status (pending, running, completed, failed)
- `agent_type` (string): Filter by agent type
- `limit` (integer): Maximum results

**Response:**
```json
[
  {
    "id": 43,
    "project_id": 1,
    "agent_type": "agent-zero",
    "task_type": "automation",
    "description": "Monitor system logs",
    "status": "running",
    "priority": 1,
    "created_at": "2024-01-15T12:00:00Z"
  }
]
```

### Search

#### Search Projects
```http
POST /api/v1/search/projects?query=python+web+app
```

**Query Parameters:**
- `query` (string): Search query
- `limit` (integer): Maximum results (default: 10)

**Response:**
```json
[
  {
    "id": 1,
    "name": "MyWebApp",
    "path": "/projects/mywebapp",
    "relevance_score": 0.92,
    "tech_stack": ["python", "django", "react"]
  }
]
```

#### Search Code
```http
POST /api/v1/search/code?query=authentication
```

**Query Parameters:**
- `query` (string): Search query
- `project_id` (integer): Limit to specific project
- `limit` (integer): Maximum results

**Response:**
```json
[
  {
    "file": "/projects/myapp/auth.py",
    "line": 25,
    "content": "def authenticate_user(username, password):",
    "relevance_score": 0.88
  }
]
```

### MCP (Model Context Protocol)

#### Execute Query
```http
POST /api/v1/mcp/query
```

**Request Body:**
```json
{
  "query_type": "tool",
  "query": "List all Python files in the project",
  "context": {
    "project_id": 1,
    "path": "/projects/myproject"
  }
}
```

**Response:**
```json
{
  "result": [
    "main.py",
    "utils.py",
    "models.py",
    "tests/test_main.py"
  ],
  "tokens_used": 125,
  "model": "gpt-4o-mini"
}
```

#### List Tools
```http
GET /api/v1/mcp/tools
```

**Response:**
```json
{
  "tools": [
    {
      "name": "list_projects",
      "description": "List all projects in the system",
      "parameters": []
    },
    {
      "name": "deploy_project",
      "description": "Deploy a project to a specific port",
      "parameters": ["project_id", "port"]
    }
  ]
}
```

### Errors

#### Get Error Logs
```http
GET /api/v1/errors
```

**Query Parameters:**
- `limit` (integer): Maximum results (default: 100)
- `severity` (string): Filter by severity (debug, info, warning, error, critical)
- `project_id` (integer): Filter by project

**Response:**
```json
[
  {
    "id": 1,
    "project_id": 1,
    "project_name": "MyProject",
    "deployment_id": null,
    "error_type": "runtime",
    "severity": "error",
    "message": "Database connection failed",
    "stack_trace": "Traceback...",
    "context": {
      "file": "database.py",
      "function": "connect"
    },
    "occurred_at": "2024-01-15T11:45:00Z"
  }
]
```

#### Log Error
```http
POST /api/v1/errors
```

**Request Body:**
```json
{
  "project_id": 1,
  "error_type": "validation",
  "severity": "warning",
  "message": "Invalid input format",
  "stack_trace": null,
  "context": {
    "endpoint": "/api/users",
    "input": {"email": "invalid"}
  }
}
```

**Response:**
```json
{
  "message": "Error logged successfully"
}
```

## WebSocket API

Connect to WebSocket for real-time updates:

```javascript
const ws = new WebSocket('ws://localhost:8081/ws');

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Received:', data);
};

ws.send(JSON.stringify({
  type: 'subscribe',
  channels: ['projects', 'deployments', 'errors']
}));
```

### Event Types

#### project_created
```json
{
  "type": "project_created",
  "data": {
    "id": 3,
    "name": "NewProject"
  }
}
```

#### deployment_status
```json
{
  "type": "deployment_status",
  "data": {
    "id": 1,
    "status": "running",
    "port": 8090
  }
}
```

#### error_logged
```json
{
  "type": "error_logged",
  "data": {
    "severity": "critical",
    "message": "System failure",
    "project_id": 1
  }
}
```

## Rate Limiting

API endpoints are rate-limited to prevent abuse:
- Default: 60 requests per minute
- Burst: 100 requests
- WebSocket: 10 messages per second

Rate limit headers:
```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 45
X-RateLimit-Reset: 1642248000
```

## Error Responses

### 400 Bad Request
```json
{
  "error": "Invalid request",
  "message": "Port 8080 is already in use",
  "code": "PORT_IN_USE"
}
```

### 401 Unauthorized
```json
{
  "error": "Unauthorized",
  "message": "Invalid or missing authentication token"
}
```

### 404 Not Found
```json
{
  "error": "Not found",
  "message": "Project with id 99 not found"
}
```

### 500 Internal Server Error
```json
{
  "error": "Internal server error",
  "message": "An unexpected error occurred",
  "request_id": "req_abc123"
}
```

## SDK Examples

### Python
```python
import requests

class BorgOSClient:
    def __init__(self, base_url="http://localhost:8081"):
        self.base_url = base_url
        self.session = requests.Session()
    
    def get_projects(self):
        response = self.session.get(f"{self.base_url}/api/v1/projects")
        return response.json()
    
    def deploy_project(self, project_id, port):
        data = {
            "project_id": project_id,
            "port": port,
            "name": f"deployment-{port}"
        }
        response = self.session.post(f"{self.base_url}/api/v1/deploy", json=data)
        return response.json()

# Usage
client = BorgOSClient()
projects = client.get_projects()
deployment = client.deploy_project(1, 8090)
```

### JavaScript/TypeScript
```typescript
class BorgOSClient {
  private baseUrl: string;

  constructor(baseUrl = "http://localhost:8081") {
    this.baseUrl = baseUrl;
  }

  async getProjects(): Promise<Project[]> {
    const response = await fetch(`${this.baseUrl}/api/v1/projects`);
    return response.json();
  }

  async deployProject(projectId: number, port: number): Promise<Deployment> {
    const response = await fetch(`${this.baseUrl}/api/v1/deploy`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        project_id: projectId,
        port: port,
        name: `deployment-${port}`
      })
    });
    return response.json();
  }
}

// Usage
const client = new BorgOSClient();
const projects = await client.getProjects();
const deployment = await client.deployProject(1, 8090);
```

### cURL
```bash
# Get projects
curl http://localhost:8081/api/v1/projects

# Deploy project
curl -X POST http://localhost:8081/api/v1/deploy \
  -H "Content-Type: application/json" \
  -d '{"project_id": 1, "port": 8090, "name": "my-deployment"}'

# Execute Agent Zero task
curl -X POST http://localhost:8081/api/v1/agent-zero/execute \
  -H "Content-Type: application/json" \
  -d '{
    "type": "code_execution",
    "description": "Analyze code quality",
    "prompt": "Review the Python code and suggest improvements"
  }'
```

## Pagination

List endpoints support pagination:

```http
GET /api/v1/projects?limit=10&offset=20
```

Response includes pagination metadata:
```json
{
  "data": [...],
  "pagination": {
    "total": 150,
    "limit": 10,
    "offset": 20,
    "has_more": true
  }
}
```

## Filtering

Most list endpoints support filtering:

```http
GET /api/v1/projects?active=true&tech_stack=python
GET /api/v1/deployments?status=running&project_id=1
GET /api/v1/errors?severity=error&limit=50
```

## Webhooks (Coming Soon)

Configure webhooks to receive notifications:

```json
{
  "url": "https://your-app.com/webhook",
  "events": ["project.created", "deployment.failed", "error.critical"],
  "secret": "your-webhook-secret"
}
```