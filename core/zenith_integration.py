"""
Zenith Coder Integration Module
Real integration with Zenith Coder projects
"""

import os
import json
import asyncio
import hashlib
from typing import List, Dict, Any, Optional
from pathlib import Path
import asyncpg
import logging

logger = logging.getLogger(__name__)

class ZenithIntegration:
    """Integrates with Zenith Coder projects for real-time monitoring"""
    
    def __init__(self, db_pool: asyncpg.Pool, zenith_path: str = None):
        self.db_pool = db_pool
        self.zenith_path = zenith_path or os.getenv('ZENITH_PATH', '/opt/zenith-coder')
        self.zenith_backend_path = Path(self.zenith_path) / 'backend'
        self.zenith_frontend_path = Path(self.zenith_path) / 'frontend'
        
    async def scan_zenith_projects(self) -> List[Dict[str, Any]]:
        """Scan Zenith Coder directory for projects"""
        projects = []
        
        # Check if Zenith Coder exists
        if not Path(self.zenith_path).exists():
            logger.warning(f"Zenith Coder path not found: {self.zenith_path}")
            return projects
        
        # Scan for Python projects
        for py_file in Path(self.zenith_path).rglob('*.py'):
            if 'venv' in str(py_file) or '__pycache__' in str(py_file):
                continue
                
            project_dir = py_file.parent
            project_name = project_dir.name
            
            # Check if it's a real project (has requirements.txt or setup.py)
            if (project_dir / 'requirements.txt').exists() or (project_dir / 'setup.py').exists():
                project_info = await self.analyze_project(project_dir)
                if project_info:
                    projects.append(project_info)
        
        # Check specific Zenith components
        if self.zenith_backend_path.exists():
            backend_info = await self.analyze_zenith_backend()
            if backend_info:
                projects.append(backend_info)
                
        if self.zenith_frontend_path.exists():
            frontend_info = await self.analyze_zenith_frontend()
            if frontend_info:
                projects.append(frontend_info)
        
        return projects
    
    async def analyze_project(self, project_path: Path) -> Optional[Dict[str, Any]]:
        """Analyze a single project directory"""
        try:
            project_info = {
                'name': project_path.name,
                'path': str(project_path),
                'zenith_id': hashlib.md5(str(project_path).encode()).hexdigest()[:10],
                'project_type': 'python',
                'tech_stack': [],
                'health_score': 100,
                'vibe_score': 85,
                'eco_score': 90,
                'errors': [],
                'metadata': {}
            }
            
            # Detect technologies
            tech_stack = set()
            
            # Check for common files
            if (project_path / 'requirements.txt').exists():
                tech_stack.add('python')
                requirements = (project_path / 'requirements.txt').read_text()
                if 'fastapi' in requirements.lower():
                    tech_stack.add('fastapi')
                if 'django' in requirements.lower():
                    tech_stack.add('django')
                if 'flask' in requirements.lower():
                    tech_stack.add('flask')
                if 'pytest' in requirements.lower():
                    tech_stack.add('pytest')
                    
            if (project_path / 'package.json').exists():
                tech_stack.add('nodejs')
                package_json = json.loads((project_path / 'package.json').read_text())
                deps = {**package_json.get('dependencies', {}), **package_json.get('devDependencies', {})}
                if 'react' in deps:
                    tech_stack.add('react')
                if 'vue' in deps:
                    tech_stack.add('vue')
                if '@angular/core' in deps:
                    tech_stack.add('angular')
                    
            if (project_path / 'Dockerfile').exists():
                tech_stack.add('docker')
                
            if (project_path / 'docker-compose.yml').exists():
                tech_stack.add('docker-compose')
                
            if (project_path / '.git').exists():
                tech_stack.add('git')
                
            project_info['tech_stack'] = list(tech_stack)
            
            # Calculate health score based on best practices
            health_score = 100
            if not (project_path / 'README.md').exists():
                health_score -= 10
                project_info['errors'].append({
                    'type': 'missing_readme',
                    'severity': 'warning',
                    'message': 'No README.md found'
                })
                
            if not (project_path / '.gitignore').exists() and (project_path / '.git').exists():
                health_score -= 15
                project_info['errors'].append({
                    'type': 'missing_gitignore',
                    'severity': 'warning',
                    'message': 'Git repository without .gitignore'
                })
                
            if not any((project_path / 'test').exists() or 
                      (project_path / 'tests').exists() or
                      list(project_path.glob('test_*.py'))):
                health_score -= 20
                project_info['errors'].append({
                    'type': 'no_tests',
                    'severity': 'warning',
                    'message': 'No test directory or test files found'
                })
                
            project_info['health_score'] = max(0, health_score)
            
            # Count files
            file_count = len(list(project_path.rglob('*')))
            project_info['metadata']['file_count'] = file_count
            
            # Calculate size
            total_size = sum(f.stat().st_size for f in project_path.rglob('*') if f.is_file())
            project_info['metadata']['size_mb'] = round(total_size / (1024 * 1024), 2)
            
            return project_info
            
        except Exception as e:
            logger.error(f"Error analyzing project {project_path}: {e}")
            return None
    
    async def analyze_zenith_backend(self) -> Dict[str, Any]:
        """Analyze Zenith Coder backend specifically"""
        backend_info = await self.analyze_project(self.zenith_backend_path)
        if backend_info:
            backend_info['name'] = 'Zenith Coder Backend'
            backend_info['project_type'] = 'zenith-backend'
            backend_info['metadata']['is_zenith_component'] = True
            
            # Check for specific Zenith features
            src_path = self.zenith_backend_path / 'src'
            if src_path.exists():
                # Check for agents
                agents_path = src_path / 'agents'
                if agents_path.exists():
                    agent_files = list(agents_path.glob('*.py'))
                    backend_info['metadata']['agent_count'] = len(agent_files)
                    backend_info['metadata']['agents'] = [f.stem for f in agent_files]
                    
                # Check for AI providers
                providers_path = src_path / 'ai' / 'providers'
                if providers_path.exists():
                    provider_files = list(providers_path.glob('*.py'))
                    backend_info['metadata']['ai_providers'] = [f.stem for f in provider_files]
                    
        return backend_info
    
    async def analyze_zenith_frontend(self) -> Dict[str, Any]:
        """Analyze Zenith Coder frontend specifically"""
        frontend_info = await self.analyze_project(self.zenith_frontend_path)
        if frontend_info:
            frontend_info['name'] = 'Zenith Coder Frontend'
            frontend_info['project_type'] = 'zenith-frontend'
            frontend_info['metadata']['is_zenith_component'] = True
            
            # Check for React components
            src_path = self.zenith_frontend_path / 'src'
            if src_path.exists():
                components_path = src_path / 'components'
                if components_path.exists():
                    component_files = list(components_path.rglob('*.tsx')) + list(components_path.rglob('*.jsx'))
                    frontend_info['metadata']['component_count'] = len(component_files)
                    
                pages_path = src_path / 'pages'
                if pages_path.exists():
                    page_files = list(pages_path.rglob('*.tsx')) + list(pages_path.rglob('*.jsx'))
                    frontend_info['metadata']['page_count'] = len(page_files)
                    frontend_info['metadata']['pages'] = [f.stem for f in page_files]
                    
        return frontend_info
    
    async def sync_to_database(self, projects: List[Dict[str, Any]]) -> int:
        """Sync discovered projects to database"""
        count = 0
        async with self.db_pool.acquire() as conn:
            for project in projects:
                try:
                    # Check if project exists
                    existing = await conn.fetchval(
                        "SELECT id FROM projects WHERE path = $1",
                        project['path']
                    )
                    
                    if existing:
                        # Update existing project
                        await conn.execute(
                            """
                            UPDATE projects 
                            SET name = $1, zenith_id = $2, project_type = $3,
                                tech_stack = $4, health_score = $5, vibe_score = $6,
                                eco_score = $7, errors = $8, metadata = $9,
                                last_scan = NOW()
                            WHERE path = $10
                            """,
                            project['name'], project['zenith_id'], project['project_type'],
                            json.dumps(project['tech_stack']), project['health_score'],
                            project['vibe_score'], project['eco_score'],
                            json.dumps(project['errors']), json.dumps(project['metadata']),
                            project['path']
                        )
                    else:
                        # Insert new project
                        await conn.execute(
                            """
                            INSERT INTO projects (name, path, zenith_id, project_type,
                                                tech_stack, health_score, vibe_score,
                                                eco_score, errors, metadata, last_scan)
                            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW())
                            """,
                            project['name'], project['path'], project['zenith_id'],
                            project['project_type'], json.dumps(project['tech_stack']),
                            project['health_score'], project['vibe_score'],
                            project['eco_score'], json.dumps(project['errors']),
                            json.dumps(project['metadata'])
                        )
                    count += 1
                    
                except Exception as e:
                    logger.error(f"Error syncing project {project['name']}: {e}")
                    
        return count
    
    async def get_project_deployments(self, project_id: int) -> List[Dict[str, Any]]:
        """Get all deployments for a project"""
        async with self.db_pool.acquire() as conn:
            rows = await conn.fetch(
                """
                SELECT d.*, 
                       COUNT(e.id) as error_count,
                       MAX(e.occurred_at) as last_error
                FROM deployments d
                LEFT JOIN error_logs e ON d.id = e.deployment_id
                WHERE d.project_id = $1
                GROUP BY d.id
                ORDER BY d.port
                """,
                project_id
            )
            return [dict(row) for row in rows]
    
    async def check_deployment_health(self, deployment_id: int) -> Dict[str, Any]:
        """Check health of a deployment"""
        async with self.db_pool.acquire() as conn:
            deployment = await conn.fetchrow(
                "SELECT * FROM deployments WHERE id = $1",
                deployment_id
            )
            
            if not deployment:
                return {'status': 'not_found'}
                
            health = {
                'deployment_id': deployment_id,
                'port': deployment['port'],
                'status': deployment['status'],
                'health': 'unknown'
            }
            
            # Check if port is actually listening
            import socket
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            result = sock.connect_ex(('localhost', deployment['port']))
            sock.close()
            
            if result == 0:
                health['health'] = 'healthy'
                health['port_open'] = True
            else:
                health['health'] = 'unhealthy'
                health['port_open'] = False
                
            # Check for recent errors
            error_count = await conn.fetchval(
                """
                SELECT COUNT(*) FROM error_logs 
                WHERE deployment_id = $1 
                AND occurred_at > NOW() - INTERVAL '1 hour'
                """,
                deployment_id
            )
            
            health['recent_errors'] = error_count
            if error_count > 10:
                health['health'] = 'degraded'
                
            return health