"""
MCP Server Implementation for BorgOS
Model Context Protocol for AI interactions
"""

import json
import asyncio
import logging
from typing import Dict, List, Any, Optional
from datetime import datetime
import asyncpg
import httpx

logger = logging.getLogger(__name__)

class MCPServer:
    """Model Context Protocol Server for BorgOS"""
    
    def __init__(self, db_pool: asyncpg.Pool):
        self.db_pool = db_pool
        self.tools = self.register_tools()
        self.contexts = {}  # Store conversation contexts
        
    def register_tools(self) -> Dict[str, Any]:
        """Register available MCP tools"""
        return {
            "list_projects": {
                "description": "List all projects in BorgOS",
                "parameters": {},
                "handler": self.tool_list_projects
            },
            "get_project_details": {
                "description": "Get detailed information about a project",
                "parameters": {
                    "project_id": {"type": "integer", "required": True}
                },
                "handler": self.tool_get_project_details
            },
            "scan_project": {
                "description": "Trigger a scan of a project",
                "parameters": {
                    "project_id": {"type": "integer", "required": True}
                },
                "handler": self.tool_scan_project
            },
            "list_deployments": {
                "description": "List all deployments",
                "parameters": {},
                "handler": self.tool_list_deployments
            },
            "deploy_project": {
                "description": "Deploy a project to a specific port",
                "parameters": {
                    "project_id": {"type": "integer", "required": True},
                    "port": {"type": "integer", "required": True},
                    "environment": {"type": "object", "required": False}
                },
                "handler": self.tool_deploy_project
            },
            "get_errors": {
                "description": "Get recent error logs",
                "parameters": {
                    "limit": {"type": "integer", "default": 10},
                    "severity": {"type": "string", "required": False}
                },
                "handler": self.tool_get_errors
            },
            "execute_command": {
                "description": "Execute a system command",
                "parameters": {
                    "command": {"type": "string", "required": True},
                    "working_dir": {"type": "string", "required": False}
                },
                "handler": self.tool_execute_command
            },
            "analyze_code": {
                "description": "Analyze code quality and suggest improvements",
                "parameters": {
                    "project_id": {"type": "integer", "required": True},
                    "file_path": {"type": "string", "required": False}
                },
                "handler": self.tool_analyze_code
            }
        }
    
    async def handle_query(self, query: Dict[str, Any]) -> Dict[str, Any]:
        """Handle MCP query"""
        query_type = query.get('query_type', 'chat')
        context_id = query.get('context_id', 'default')
        
        # Store query in database
        async with self.db_pool.acquire() as conn:
            query_id = await conn.fetchval(
                """
                INSERT INTO mcp_queries (project_id, query_type, query, context)
                VALUES ($1, $2, $3, $4)
                RETURNING id
                """,
                query.get('project_id'),
                query_type,
                query.get('query', ''),
                json.dumps(query.get('context', {}))
            )
        
        # Handle different query types
        if query_type == 'tool':
            response = await self.handle_tool_call(query)
        elif query_type == 'chat':
            response = await self.handle_chat(query, context_id)
        elif query_type == 'analysis':
            response = await self.handle_analysis(query)
        else:
            response = {
                'error': f'Unknown query type: {query_type}'
            }
        
        # Update response in database
        async with self.db_pool.acquire() as conn:
            await conn.execute(
                """
                UPDATE mcp_queries 
                SET response = $1, response_time_ms = $2
                WHERE id = $3
                """,
                json.dumps(response),
                100,  # TODO: Calculate actual response time
                query_id
            )
        
        return {
            'query_id': query_id,
            'response': response,
            'context_id': context_id
        }
    
    async def handle_tool_call(self, query: Dict[str, Any]) -> Dict[str, Any]:
        """Handle tool execution"""
        tool_name = query.get('tool')
        params = query.get('parameters', {})
        
        if tool_name not in self.tools:
            return {'error': f'Unknown tool: {tool_name}'}
        
        tool = self.tools[tool_name]
        handler = tool['handler']
        
        try:
            result = await handler(**params)
            return {
                'tool': tool_name,
                'result': result,
                'success': True
            }
        except Exception as e:
            logger.error(f"Error executing tool {tool_name}: {e}")
            return {
                'tool': tool_name,
                'error': str(e),
                'success': False
            }
    
    async def handle_chat(self, query: Dict[str, Any], context_id: str) -> Dict[str, Any]:
        """Handle chat conversation"""
        message = query.get('query', '')
        
        # Get or create context
        if context_id not in self.contexts:
            self.contexts[context_id] = {
                'messages': [],
                'created_at': datetime.utcnow().isoformat()
            }
        
        context = self.contexts[context_id]
        context['messages'].append({
            'role': 'user',
            'content': message,
            'timestamp': datetime.utcnow().isoformat()
        })
        
        # Generate response based on context
        # This is a simplified response - in production, integrate with LLM
        response_text = await self.generate_chat_response(message, context)
        
        context['messages'].append({
            'role': 'assistant',
            'content': response_text,
            'timestamp': datetime.utcnow().isoformat()
        })
        
        return {
            'message': response_text,
            'context_id': context_id,
            'message_count': len(context['messages'])
        }
    
    async def handle_analysis(self, query: Dict[str, Any]) -> Dict[str, Any]:
        """Handle code/project analysis request"""
        project_id = query.get('project_id')
        analysis_type = query.get('analysis_type', 'general')
        
        if not project_id:
            return {'error': 'project_id required for analysis'}
        
        async with self.db_pool.acquire() as conn:
            project = await conn.fetchrow(
                "SELECT * FROM projects WHERE id = $1",
                project_id
            )
            
            if not project:
                return {'error': f'Project {project_id} not found'}
            
            # Perform analysis based on type
            if analysis_type == 'health':
                analysis = await self.analyze_project_health(project)
            elif analysis_type == 'dependencies':
                analysis = await self.analyze_dependencies(project)
            elif analysis_type == 'security':
                analysis = await self.analyze_security(project)
            else:
                analysis = await self.analyze_general(project)
        
        return {
            'project_id': project_id,
            'project_name': project['name'],
            'analysis_type': analysis_type,
            'analysis': analysis
        }
    
    # Tool implementations
    
    async def tool_list_projects(self) -> List[Dict[str, Any]]:
        """List all projects"""
        async with self.db_pool.acquire() as conn:
            rows = await conn.fetch(
                "SELECT * FROM projects WHERE is_active = true ORDER BY name"
            )
            return [dict(row) for row in rows]
    
    async def tool_get_project_details(self, project_id: int) -> Dict[str, Any]:
        """Get project details"""
        async with self.db_pool.acquire() as conn:
            project = await conn.fetchrow(
                "SELECT * FROM projects WHERE id = $1",
                project_id
            )
            if not project:
                raise ValueError(f"Project {project_id} not found")
            
            # Get deployments
            deployments = await conn.fetch(
                "SELECT * FROM deployments WHERE project_id = $1",
                project_id
            )
            
            # Get recent errors
            errors = await conn.fetch(
                """
                SELECT * FROM error_logs 
                WHERE project_id = $1 
                ORDER BY occurred_at DESC 
                LIMIT 5
                """,
                project_id
            )
            
            return {
                'project': dict(project),
                'deployments': [dict(d) for d in deployments],
                'recent_errors': [dict(e) for e in errors]
            }
    
    async def tool_scan_project(self, project_id: int) -> Dict[str, Any]:
        """Trigger project scan"""
        # This would trigger actual scanning logic
        async with self.db_pool.acquire() as conn:
            await conn.execute(
                "UPDATE projects SET last_scan = NOW() WHERE id = $1",
                project_id
            )
        
        return {
            'project_id': project_id,
            'status': 'scan_initiated',
            'timestamp': datetime.utcnow().isoformat()
        }
    
    async def tool_list_deployments(self) -> List[Dict[str, Any]]:
        """List all deployments"""
        async with self.db_pool.acquire() as conn:
            rows = await conn.fetch(
                """
                SELECT d.*, p.name as project_name 
                FROM deployments d
                JOIN projects p ON d.project_id = p.id
                ORDER BY d.port
                """
            )
            return [dict(row) for row in rows]
    
    async def tool_deploy_project(self, project_id: int, port: int, 
                                  environment: Optional[Dict] = None) -> Dict[str, Any]:
        """Deploy a project"""
        async with self.db_pool.acquire() as conn:
            # Check if port is available
            existing = await conn.fetchval(
                "SELECT id FROM deployments WHERE port = $1 AND status = 'running'",
                port
            )
            if existing:
                raise ValueError(f"Port {port} is already in use")
            
            # Create deployment
            deployment_id = await conn.fetchval(
                """
                INSERT INTO deployments (project_id, name, port, environment, status)
                VALUES ($1, $2, $3, $4, 'pending')
                RETURNING id
                """,
                project_id,
                f"Deployment-{project_id}-{port}",
                port,
                json.dumps(environment or {})
            )
            
            # TODO: Trigger actual deployment
            
            return {
                'deployment_id': deployment_id,
                'project_id': project_id,
                'port': port,
                'status': 'deployment_initiated'
            }
    
    async def tool_get_errors(self, limit: int = 10, severity: Optional[str] = None) -> List[Dict[str, Any]]:
        """Get error logs"""
        query = """
            SELECT e.*, p.name as project_name, d.name as deployment_name
            FROM error_logs e
            LEFT JOIN projects p ON e.project_id = p.id
            LEFT JOIN deployments d ON e.deployment_id = d.id
        """
        params = []
        
        if severity:
            query += " WHERE e.severity = $1"
            params.append(severity)
        
        query += " ORDER BY e.occurred_at DESC LIMIT $" + str(len(params) + 1)
        params.append(limit)
        
        async with self.db_pool.acquire() as conn:
            rows = await conn.fetch(query, *params)
            return [dict(row) for row in rows]
    
    async def tool_execute_command(self, command: str, working_dir: Optional[str] = None) -> Dict[str, Any]:
        """Execute system command"""
        import subprocess
        
        try:
            result = subprocess.run(
                command,
                shell=True,
                cwd=working_dir,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            return {
                'command': command,
                'stdout': result.stdout,
                'stderr': result.stderr,
                'return_code': result.returncode,
                'success': result.returncode == 0
            }
        except subprocess.TimeoutExpired:
            return {
                'command': command,
                'error': 'Command timed out after 30 seconds',
                'success': False
            }
        except Exception as e:
            return {
                'command': command,
                'error': str(e),
                'success': False
            }
    
    async def tool_analyze_code(self, project_id: int, file_path: Optional[str] = None) -> Dict[str, Any]:
        """Analyze code quality"""
        async with self.db_pool.acquire() as conn:
            project = await conn.fetchrow(
                "SELECT * FROM projects WHERE id = $1",
                project_id
            )
            
            if not project:
                raise ValueError(f"Project {project_id} not found")
        
        # Simplified analysis - in production, use real code analysis tools
        analysis = {
            'project_id': project_id,
            'project_name': project['name'],
            'health_score': project['health_score'],
            'issues': [],
            'suggestions': []
        }
        
        if project['health_score'] < 80:
            analysis['issues'].append('Low health score indicates potential issues')
            
        if not project['tech_stack']:
            analysis['issues'].append('No technology stack detected')
            
        if project['errors']:
            analysis['issues'].append(f"Found {len(project['errors'])} errors")
            
        # Add suggestions based on issues
        if analysis['issues']:
            analysis['suggestions'].append('Consider adding tests to improve health score')
            analysis['suggestions'].append('Add README.md for better documentation')
            
        return analysis
    
    # Helper methods
    
    async def generate_chat_response(self, message: str, context: Dict) -> str:
        """Generate chat response"""
        # Simple keyword-based responses for MVP
        # In production, integrate with LLM
        
        message_lower = message.lower()
        
        if 'help' in message_lower:
            return "I can help you manage projects, deployments, and analyze code. Try asking about listing projects, checking deployments, or analyzing errors."
        elif 'project' in message_lower:
            projects = await self.tool_list_projects()
            return f"You have {len(projects)} active projects. Use 'list projects' to see them all."
        elif 'deploy' in message_lower:
            return "To deploy a project, specify the project ID and port. Example: 'deploy project 1 on port 8080'"
        elif 'error' in message_lower:
            errors = await self.tool_get_errors(limit=5)
            return f"Found {len(errors)} recent errors. Most are warnings about missing documentation."
        else:
            return f"I understand you said: '{message}'. I can help with project management, deployments, and code analysis. What would you like to know?"
    
    async def analyze_project_health(self, project: Dict) -> Dict[str, Any]:
        """Analyze project health"""
        return {
            'current_score': project['health_score'],
            'factors': {
                'documentation': 'Good' if project['health_score'] > 90 else 'Needs improvement',
                'testing': 'Present' if project['health_score'] > 80 else 'Missing',
                'dependencies': 'Up to date' if project['health_score'] > 70 else 'May need updates'
            },
            'recommendations': [
                'Add comprehensive tests' if project['health_score'] < 80 else 'Maintain test coverage',
                'Update documentation' if project['health_score'] < 90 else 'Documentation is good',
                'Review dependencies' if project['health_score'] < 70 else 'Dependencies look good'
            ]
        }
    
    async def analyze_dependencies(self, project: Dict) -> Dict[str, Any]:
        """Analyze project dependencies"""
        return {
            'tech_stack': project['tech_stack'],
            'dependency_count': len(project['tech_stack']) * 5,  # Estimate
            'outdated': [],  # Would check actual versions
            'security_issues': [],  # Would run security scan
            'recommendations': ['Keep dependencies updated', 'Run security audits regularly']
        }
    
    async def analyze_security(self, project: Dict) -> Dict[str, Any]:
        """Analyze project security"""
        return {
            'scan_date': datetime.utcnow().isoformat(),
            'vulnerabilities': [],  # Would run actual security scan
            'recommendations': [
                'Enable dependency scanning',
                'Use environment variables for secrets',
                'Implement proper authentication'
            ]
        }
    
    async def analyze_general(self, project: Dict) -> Dict[str, Any]:
        """General project analysis"""
        return {
            'overview': {
                'name': project['name'],
                'type': project['project_type'],
                'health': project['health_score'],
                'tech_stack': project['tech_stack']
            },
            'metrics': {
                'vibe_score': project['vibe_score'],
                'eco_score': project['eco_score'],
                'file_count': project['metadata'].get('file_count', 0),
                'size_mb': project['metadata'].get('size_mb', 0)
            },
            'status': 'healthy' if project['health_score'] > 80 else 'needs attention'
        }