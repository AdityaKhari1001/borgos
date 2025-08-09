"""
BorgOS Core API Server
Version 2.0 - MVP with Project Monitoring
"""

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager
from typing import List, Dict, Any, Optional
from pydantic import BaseModel
from datetime import datetime
import asyncio
import logging
import json
import os
import psutil
import docker
import asyncpg
import redis.asyncio as redis
import uvicorn

# Import BorgOS integrations
from zenith_integration import ZenithIntegration
from mcp_server import MCPServer
from vector_store import VectorStore
from agent_zero_integration import AgentZeroIntegration

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# ============= Models =============

class Project(BaseModel):
    id: Optional[int] = None
    name: str
    path: str
    zenith_id: Optional[str] = None
    project_type: Optional[str] = None
    tech_stack: List[str] = []
    health_score: int = 0
    vibe_score: int = 75
    eco_score: int = 80
    errors: List[Dict] = []
    metadata: Dict = {}
    is_active: bool = True

class Deployment(BaseModel):
    id: Optional[int] = None
    project_id: int
    name: str
    port: int
    status: str = "stopped"
    container_id: Optional[str] = None
    url: Optional[str] = None
    health_check_url: Optional[str] = None
    environment: Dict = {}
    cpu_limit: Optional[str] = None
    memory_limit: Optional[str] = None

class ErrorLog(BaseModel):
    project_id: Optional[int] = None
    deployment_id: Optional[int] = None
    error_type: str
    severity: str = "error"
    message: str
    stack_trace: Optional[str] = None
    context: Dict = {}

class AgentTask(BaseModel):
    project_id: Optional[int] = None
    agent_type: str  # 'agent-zero', 'zenith', 'gen-agent'
    task_type: str
    description: str
    priority: int = 1
    input_data: Dict = {}

class MCPQuery(BaseModel):
    project_id: Optional[int] = None
    query_type: str
    query: str
    context: Dict = {}

class SystemStatus(BaseModel):
    cpu_percent: float
    memory_percent: float
    disk_percent: float
    active_deployments: int
    total_projects: int
    recent_errors: int
    uptime_seconds: float

# ============= Application =============

class BorgOSAPI:
    def __init__(self):
        self.app = FastAPI(
            title="BorgOS Core API",
            description="AI-First Operating System with Project Monitoring",
            version="2.0.0"
        )
        self.db_pool: Optional[asyncpg.Pool] = None
        self.redis_client: Optional[redis.Redis] = None
        self.docker_client: Optional[docker.DockerClient] = None
        self.websocket_manager = WebSocketManager()
        self.zenith_integration: Optional[ZenithIntegration] = None
        self.mcp_server: Optional[MCPServer] = None
        self.vector_store: Optional[VectorStore] = None
        self.agent_zero: Optional[AgentZeroIntegration] = None
        self.setup_routes()
        self.setup_middleware()
        
    def setup_middleware(self):
        self.app.add_middleware(
            CORSMiddleware,
            allow_origins=["*"],
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )
    
    async def init_db(self):
        """Initialize database connection pool"""
        try:
            self.db_pool = await asyncpg.create_pool(
                host=os.getenv("DB_HOST", "postgres"),
                port=int(os.getenv("DB_PORT", 5432)),
                database=os.getenv("DB_NAME", "borgos"),
                user=os.getenv("DB_USER", "borgos"),
                password=os.getenv("DB_PASSWORD", "borgos123"),
                min_size=10,
                max_size=20
            )
            logger.info("Database connection pool created")
        except Exception as e:
            logger.error(f"Failed to create database pool: {e}")
            raise
    
    async def init_redis(self):
        """Initialize Redis connection"""
        try:
            self.redis_client = await redis.from_url(
                f"redis://{os.getenv('REDIS_HOST', 'redis')}:{os.getenv('REDIS_PORT', 6379)}"
            )
            await self.redis_client.ping()
            logger.info("Redis connection established")
        except Exception as e:
            logger.error(f"Failed to connect to Redis: {e}")
    
    def init_docker(self):
        """Initialize Docker client"""
        try:
            self.docker_client = docker.from_env()
            self.docker_client.ping()
            logger.info("Docker client initialized")
        except Exception as e:
            logger.error(f"Failed to initialize Docker client: {e}")
    
    def setup_routes(self):
        app = self.app
        
        # ============= Health & Status =============
        
        @app.get("/health")
        async def health_check():
            return {"status": "healthy", "timestamp": datetime.utcnow().isoformat()}
        
        @app.get("/api/v1/status", response_model=SystemStatus)
        async def get_system_status():
            """Get overall system status"""
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
            
            # Get counts from database
            async with self.db_pool.acquire() as conn:
                deployments = await conn.fetchval(
                    "SELECT COUNT(*) FROM deployments WHERE status = 'running'"
                )
                projects = await conn.fetchval(
                    "SELECT COUNT(*) FROM projects WHERE is_active = true"
                )
                errors = await conn.fetchval(
                    "SELECT COUNT(*) FROM error_logs WHERE occurred_at > NOW() - INTERVAL '1 hour'"
                )
            
            boot_time = psutil.boot_time()
            uptime = datetime.now().timestamp() - boot_time
            
            return SystemStatus(
                cpu_percent=cpu_percent,
                memory_percent=memory.percent,
                disk_percent=disk.percent,
                active_deployments=deployments or 0,
                total_projects=projects or 0,
                recent_errors=errors or 0,
                uptime_seconds=uptime
            )
        
        # ============= Projects =============
        
        @app.get("/api/v1/projects", response_model=List[Project])
        async def get_projects():
            """Get all projects"""
            async with self.db_pool.acquire() as conn:
                rows = await conn.fetch(
                    "SELECT * FROM projects WHERE is_active = true ORDER BY created_at DESC"
                )
                return [Project(**dict(row)) for row in rows]
        
        @app.post("/api/v1/projects", response_model=Project)
        async def create_project(project: Project):
            """Create a new project"""
            async with self.db_pool.acquire() as conn:
                row = await conn.fetchrow(
                    """
                    INSERT INTO projects (name, path, zenith_id, project_type, tech_stack, 
                                        health_score, vibe_score, eco_score, metadata)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                    RETURNING *
                    """,
                    project.name, project.path, project.zenith_id, project.project_type,
                    json.dumps(project.tech_stack), project.health_score, 
                    project.vibe_score, project.eco_score, json.dumps(project.metadata)
                )
                
                # Notify WebSocket clients
                await self.websocket_manager.broadcast({
                    "type": "project_created",
                    "data": dict(row)
                })
                
                return Project(**dict(row))
        
        @app.post("/api/v1/projects/{project_id}/scan")
        async def scan_project(project_id: int, background_tasks: BackgroundTasks):
            """Trigger project scan"""
            background_tasks.add_task(perform_project_scan, project_id, self.db_pool, self.zenith_integration, self.vector_store)
            return {"message": f"Scan initiated for project {project_id}"}
        
        @app.post("/api/v1/projects/scan-zenith")
        async def scan_zenith_projects():
            """Scan all Zenith Coder projects"""
            if not self.zenith_integration:
                raise HTTPException(status_code=503, detail="Zenith integration not initialized")
            
            projects = await self.zenith_integration.scan_zenith_projects()
            count = await self.zenith_integration.sync_to_database(projects)
            
            # Index in vector store
            if self.vector_store:
                for project in projects:
                    await self.vector_store.index_project(project)
            
            return {"message": f"Scanned and synced {count} Zenith projects", "count": count}
        
        @app.post("/api/v1/search/projects")
        async def search_projects(query: str, limit: int = 10):
            """Search projects using semantic search"""
            if not self.vector_store:
                # Fallback to basic search
                async with self.db_pool.acquire() as conn:
                    rows = await conn.fetch(
                        """
                        SELECT * FROM projects 
                        WHERE name ILIKE $1 OR path ILIKE $1
                        LIMIT $2
                        """,
                        f"%{query}%", limit
                    )
                    return [dict(row) for row in rows]
            
            results = await self.vector_store.search_projects(query, limit)
            return results
        
        # ============= Deployments =============
        
        @app.get("/api/v1/deployments", response_model=List[Deployment])
        async def get_deployments():
            """Get all deployments with their status"""
            async with self.db_pool.acquire() as conn:
                rows = await conn.fetch(
                    """
                    SELECT d.*, p.name as project_name 
                    FROM deployments d
                    JOIN projects p ON d.project_id = p.id
                    ORDER BY d.port
                    """
                )
                
                deployments = []
                for row in rows:
                    deployment = Deployment(**dict(row))
                    
                    # Check Docker container status if available
                    if self.docker_client and deployment.container_id:
                        try:
                            container = self.docker_client.containers.get(deployment.container_id)
                            deployment.status = container.status
                        except docker.errors.NotFound:
                            deployment.status = "not_found"
                    
                    deployments.append(deployment)
                
                return deployments
        
        @app.post("/api/v1/deploy")
        async def deploy_project(deployment: Deployment):
            """Deploy a project to a specific port"""
            # Check if port is available
            async with self.db_pool.acquire() as conn:
                existing = await conn.fetchval(
                    "SELECT id FROM deployments WHERE port = $1 AND status = 'running'",
                    deployment.port
                )
                if existing:
                    raise HTTPException(status_code=400, detail=f"Port {deployment.port} is already in use")
                
                # Create deployment record
                row = await conn.fetchrow(
                    """
                    INSERT INTO deployments (project_id, name, port, status, url, 
                                           health_check_url, environment, cpu_limit, memory_limit)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                    RETURNING *
                    """,
                    deployment.project_id, deployment.name, deployment.port, "pending",
                    deployment.url, deployment.health_check_url, 
                    json.dumps(deployment.environment), deployment.cpu_limit, deployment.memory_limit
                )
                
                deployment_id = row['id']
                
                # TODO: Actually deploy the container
                # This would integrate with Docker/K8s to deploy the project
                
                # Update status
                await conn.execute(
                    "UPDATE deployments SET status = 'running', started_at = NOW() WHERE id = $1",
                    deployment_id
                )
                
                # Notify WebSocket clients
                await self.websocket_manager.broadcast({
                    "type": "deployment_created",
                    "data": dict(row)
                })
                
                return {"message": f"Deployment created on port {deployment.port}", "id": deployment_id}
        
        @app.post("/api/v1/deployments/{deployment_id}/stop")
        async def stop_deployment(deployment_id: int):
            """Stop a deployment"""
            async with self.db_pool.acquire() as conn:
                deployment = await conn.fetchrow(
                    "SELECT * FROM deployments WHERE id = $1", deployment_id
                )
                if not deployment:
                    raise HTTPException(status_code=404, detail="Deployment not found")
                
                # Stop Docker container if available
                if self.docker_client and deployment['container_id']:
                    try:
                        container = self.docker_client.containers.get(deployment['container_id'])
                        container.stop()
                    except Exception as e:
                        logger.error(f"Failed to stop container: {e}")
                
                # Update status
                await conn.execute(
                    "UPDATE deployments SET status = 'stopped', stopped_at = NOW() WHERE id = $1",
                    deployment_id
                )
                
                return {"message": f"Deployment {deployment_id} stopped"}
        
        # ============= Errors & Logs =============
        
        @app.get("/api/v1/errors")
        async def get_errors(limit: int = 100):
            """Get recent error logs"""
            async with self.db_pool.acquire() as conn:
                rows = await conn.fetch(
                    """
                    SELECT e.*, p.name as project_name, d.name as deployment_name
                    FROM error_logs e
                    LEFT JOIN projects p ON e.project_id = p.id
                    LEFT JOIN deployments d ON e.deployment_id = d.id
                    ORDER BY e.occurred_at DESC
                    LIMIT $1
                    """,
                    limit
                )
                return [dict(row) for row in rows]
        
        @app.post("/api/v1/errors")
        async def log_error(error: ErrorLog):
            """Log an error"""
            async with self.db_pool.acquire() as conn:
                await conn.execute(
                    """
                    INSERT INTO error_logs (project_id, deployment_id, error_type, 
                                          severity, message, stack_trace, context)
                    VALUES ($1, $2, $3, $4, $5, $6, $7)
                    """,
                    error.project_id, error.deployment_id, error.error_type,
                    error.severity, error.message, error.stack_trace, json.dumps(error.context)
                )
                
                # Notify WebSocket clients for critical errors
                if error.severity in ['error', 'critical']:
                    await self.websocket_manager.broadcast({
                        "type": "error_logged",
                        "data": error.dict()
                    })
                
                return {"message": "Error logged successfully"}
        
        # ============= Agent Tasks =============
        
        @app.post("/api/v1/agent/task")
        async def create_agent_task(task: AgentTask):
            """Create a task for an AI agent"""
            async with self.db_pool.acquire() as conn:
                row = await conn.fetchrow(
                    """
                    INSERT INTO agent_tasks (project_id, agent_type, task_type, 
                                           description, priority, input_data)
                    VALUES ($1, $2, $3, $4, $5, $6)
                    RETURNING *
                    """,
                    task.project_id, task.agent_type, task.task_type,
                    task.description, task.priority, json.dumps(task.input_data)
                )
                
                # Trigger the appropriate agent
                if task.agent_type == "agent-zero" and self.agent_zero:
                    # Execute task with Agent Zero
                    background_tasks.add_task(
                        execute_agent_zero_task,
                        row['id'],
                        task.dict(),
                        self.agent_zero,
                        self.db_pool
                    )
                elif task.agent_type == "zenith" and self.zenith_integration:
                    # Execute with Zenith
                    pass  # Zenith task execution
                
                return {"message": "Task created and queued", "task_id": row['id']}
        
        @app.get("/api/v1/agent/tasks")
        async def get_agent_tasks(status: Optional[str] = None):
            """Get agent tasks"""
            query = "SELECT * FROM agent_tasks"
            params = []
            
            if status:
                query += " WHERE status = $1"
                params.append(status)
            
            query += " ORDER BY priority DESC, created_at DESC"
            
            async with self.db_pool.acquire() as conn:
                rows = await conn.fetch(query, *params)
                return [dict(row) for row in rows]
        
        # ============= Agent Zero Specific =============
        
        @app.get("/api/v1/agent-zero/status")
        async def get_agent_zero_status():
            """Get Agent Zero status"""
            if not self.agent_zero:
                return {"error": "Agent Zero not initialized"}
            return await self.agent_zero.get_agent_status()
        
        @app.post("/api/v1/agent-zero/start")
        async def start_agent_zero():
            """Start Agent Zero"""
            if not self.agent_zero:
                return {"error": "Agent Zero not initialized"}
            success = await self.agent_zero.start_agent()
            return {"success": success, "status": await self.agent_zero.get_agent_status()}
        
        @app.post("/api/v1/agent-zero/stop")
        async def stop_agent_zero():
            """Stop Agent Zero"""
            if not self.agent_zero:
                return {"error": "Agent Zero not initialized"}
            success = await self.agent_zero.stop_agent()
            return {"success": success}
        
        @app.post("/api/v1/agent-zero/restart")
        async def restart_agent_zero():
            """Restart Agent Zero"""
            if not self.agent_zero:
                return {"error": "Agent Zero not initialized"}
            success = await self.agent_zero.restart_agent()
            return {"success": success, "status": await self.agent_zero.get_agent_status()}
        
        @app.get("/api/v1/agent-zero/capabilities")
        async def get_agent_zero_capabilities():
            """Get Agent Zero capabilities"""
            if not self.agent_zero:
                return {"error": "Agent Zero not initialized"}
            return await self.agent_zero.get_agent_capabilities()
        
        @app.post("/api/v1/agent-zero/execute")
        async def execute_agent_zero_task(task: Dict[str, Any], background_tasks: BackgroundTasks):
            """Execute a task directly with Agent Zero"""
            if not self.agent_zero:
                return {"error": "Agent Zero not initialized"}
            
            # Create task record
            async with self.db_pool.acquire() as conn:
                row = await conn.fetchrow(
                    """
                    INSERT INTO agent_tasks (agent_type, task_type, description, input_data, status)
                    VALUES ('agent-zero', $1, $2, $3, 'processing')
                    RETURNING id
                    """,
                    task.get("type", "general"),
                    task.get("description", ""),
                    json.dumps(task)
                )
            
            task_id = row['id']
            task['id'] = task_id
            
            # Execute in background
            background_tasks.add_task(
                execute_agent_zero_task,
                task_id,
                task,
                self.agent_zero,
                self.db_pool
            )
            
            return {"message": "Task submitted", "task_id": task_id}
        
        # ============= MCP Queries =============
        
        @app.post("/api/v1/mcp/query")
        async def mcp_query(query: MCPQuery):
            """Execute an MCP query"""
            if not self.mcp_server:
                raise HTTPException(status_code=503, detail="MCP Server not initialized")
            
            result = await self.mcp_server.handle_query(query.dict())
            return result
        
        # ============= WebSocket =============
        
        @app.websocket("/ws")
        async def websocket_endpoint(websocket: WebSocket):
            await self.websocket_manager.connect(websocket)
            try:
                while True:
                    data = await websocket.receive_text()
                    # Echo back for now
                    await websocket.send_text(f"Echo: {data}")
            except WebSocketDisconnect:
                self.websocket_manager.disconnect(websocket)

# ============= WebSocket Manager =============

class WebSocketManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []
    
    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)
        logger.info(f"WebSocket client connected. Total: {len(self.active_connections)}")
    
    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)
        logger.info(f"WebSocket client disconnected. Total: {len(self.active_connections)}")
    
    async def broadcast(self, message: dict):
        """Broadcast message to all connected clients"""
        if self.active_connections:
            message_text = json.dumps(message)
            for connection in self.active_connections:
                try:
                    await connection.send_text(message_text)
                except Exception as e:
                    logger.error(f"Error broadcasting to client: {e}")

# ============= Background Tasks =============

async def execute_agent_zero_task(task_id: int, task: Dict[str, Any],
                                 agent_zero: AgentZeroIntegration,
                                 db_pool: asyncpg.Pool):
    """Execute a task with Agent Zero in the background"""
    logger.info(f"Executing Agent Zero task {task_id}")
    
    try:
        # Execute the task
        result = await agent_zero.execute_task(task)
        
        # Update task status in database
        async with db_pool.acquire() as conn:
            await conn.execute(
                """
                UPDATE agent_tasks
                SET status = $1, result = $2, completed_at = NOW()
                WHERE id = $3
                """,
                "completed" if result.get("success") else "failed",
                json.dumps(result),
                task_id
            )
        
        logger.info(f"Agent Zero task {task_id} completed: {result.get('success')}")
        
    except Exception as e:
        logger.error(f"Error executing Agent Zero task {task_id}: {e}")
        
        # Update task as failed
        async with db_pool.acquire() as conn:
            await conn.execute(
                """
                UPDATE agent_tasks
                SET status = 'failed', result = $1, completed_at = NOW()
                WHERE id = $2
                """,
                json.dumps({"error": str(e)}),
                task_id
            )

async def perform_project_scan(project_id: int, db_pool: asyncpg.Pool, 
                              zenith_integration: Optional[ZenithIntegration] = None,
                              vector_store: Optional[VectorStore] = None):
    """Background task to scan a project"""
    logger.info(f"Starting scan for project {project_id}")
    
    try:
        async with db_pool.acquire() as conn:
            # Get project details
            project = await conn.fetchrow(
                "SELECT * FROM projects WHERE id = $1", project_id
            )
            
            if not project:
                logger.error(f"Project {project_id} not found")
                return
            
            # If it's a Zenith project, use Zenith integration
            if zenith_integration and project['zenith_id']:
                from pathlib import Path
                project_path = Path(project['path'])
                if project_path.exists():
                    updated_info = await zenith_integration.analyze_project(project_path)
                    if updated_info:
                        # Update project with new info
                        await conn.execute(
                            """
                            UPDATE projects 
                            SET tech_stack = $1, health_score = $2, errors = $3, 
                                metadata = $4, last_scan = NOW()
                            WHERE id = $5
                            """,
                            json.dumps(updated_info['tech_stack']),
                            updated_info['health_score'],
                            json.dumps(updated_info['errors']),
                            json.dumps(updated_info['metadata']),
                            project_id
                        )
                        
                        # Update vector store
                        if vector_store:
                            updated_info['id'] = project_id
                            await vector_store.index_project(updated_info)
            else:
                # Basic scan - just update timestamp
                await conn.execute(
                    "UPDATE projects SET last_scan = NOW() WHERE id = $1",
                    project_id
                )
            
            logger.info(f"Scan completed for project {project_id}")
    except Exception as e:
        logger.error(f"Error scanning project {project_id}: {e}")

# ============= Application Lifecycle =============

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    borgos_api = app.state.borgos_api
    await borgos_api.init_db()
    await borgos_api.init_redis()
    borgos_api.init_docker()
    
    # Initialize integrations
    if borgos_api.db_pool:
        # Zenith Integration
        borgos_api.zenith_integration = ZenithIntegration(borgos_api.db_pool)
        
        # MCP Server
        borgos_api.mcp_server = MCPServer(borgos_api.db_pool)
        
        # Vector Store
        borgos_api.vector_store = VectorStore(borgos_api.db_pool)
        if await borgos_api.vector_store.initialize():
            logger.info("ChromaDB vector store initialized")
            # Reindex existing projects
            asyncio.create_task(borgos_api.vector_store.reindex_all_projects())
        
        # Agent Zero Integration
        borgos_api.agent_zero = AgentZeroIntegration(borgos_api.db_pool)
        if await borgos_api.agent_zero.initialize():
            logger.info("Agent Zero integration initialized")
            # Optionally start Agent Zero automatically
            if os.getenv('AGENT_ZERO_AUTOSTART', 'false').lower() == 'true':
                asyncio.create_task(borgos_api.agent_zero.start_agent())
        
        # Initial Zenith scan
        if os.getenv('ZENITH_ENABLED', 'true') == 'true':
            logger.info("Starting initial Zenith Coder scan...")
            projects = await borgos_api.zenith_integration.scan_zenith_projects()
            count = await borgos_api.zenith_integration.sync_to_database(projects)
            logger.info(f"Synced {count} Zenith projects")
    
    logger.info("BorgOS API started successfully with all integrations")
    
    yield
    
    # Shutdown
    if borgos_api.db_pool:
        await borgos_api.db_pool.close()
    if borgos_api.redis_client:
        await borgos_api.redis_client.close()
    logger.info("BorgOS API shutdown complete")

# ============= Main =============

def create_app():
    borgos_api = BorgOSAPI()
    borgos_api.app.state.borgos_api = borgos_api
    borgos_api.app.router.lifespan_context = lifespan
    return borgos_api.app

app = create_app()

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8081,
        reload=True,
        log_level="info"
    )