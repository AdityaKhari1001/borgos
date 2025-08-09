"""
ChromaDB Vector Store Integration
For semantic search and AI-powered project discovery
"""

import os
import json
import hashlib
from typing import List, Dict, Any, Optional
import logging
import chromadb
from chromadb.config import Settings
import asyncpg

logger = logging.getLogger(__name__)

class VectorStore:
    """Vector store for semantic search using ChromaDB"""
    
    def __init__(self, db_pool: asyncpg.Pool, chroma_host: str = None):
        self.db_pool = db_pool
        self.chroma_host = chroma_host or os.getenv('CHROMADB_HOST', 'chromadb')
        self.chroma_port = int(os.getenv('CHROMADB_PORT', 8000))
        self.client = None
        self.collection = None
        
    async def initialize(self):
        """Initialize ChromaDB connection"""
        try:
            # Connect to ChromaDB
            self.client = chromadb.HttpClient(
                host=self.chroma_host,
                port=self.chroma_port,
                settings=Settings(
                    anonymized_telemetry=False,
                    allow_reset=True
                )
            )
            
            # Create or get collection for projects
            self.collection = self.client.get_or_create_collection(
                name="borgos_projects",
                metadata={"description": "BorgOS project embeddings"}
            )
            
            logger.info(f"ChromaDB connected: {self.chroma_host}:{self.chroma_port}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to connect to ChromaDB: {e}")
            return False
    
    async def index_project(self, project: Dict[str, Any]) -> bool:
        """Index a project in the vector store"""
        try:
            if not self.collection:
                logger.warning("ChromaDB not initialized")
                return False
            
            # Create document content
            document = self.create_project_document(project)
            
            # Generate unique ID
            doc_id = f"project_{project['id']}"
            
            # Create metadata
            metadata = {
                'project_id': project['id'],
                'name': project['name'],
                'path': project['path'],
                'project_type': project.get('project_type', 'unknown'),
                'health_score': project.get('health_score', 0),
                'tech_stack': ','.join(project.get('tech_stack', [])),
                'last_scan': str(project.get('last_scan', ''))
            }
            
            # Upsert to ChromaDB
            self.collection.upsert(
                documents=[document],
                metadatas=[metadata],
                ids=[doc_id]
            )
            
            # Store reference in PostgreSQL
            async with self.db_pool.acquire() as conn:
                await conn.execute(
                    """
                    INSERT INTO vector_embeddings (project_id, document_id, content, embedding_model, metadata)
                    VALUES ($1, $2, $3, $4, $5)
                    ON CONFLICT (document_id) DO UPDATE
                    SET content = $3, metadata = $5
                    """,
                    project['id'],
                    doc_id,
                    document,
                    'default',
                    json.dumps(metadata)
                )
            
            logger.info(f"Indexed project {project['name']} in vector store")
            return True
            
        except Exception as e:
            logger.error(f"Error indexing project {project.get('name', 'unknown')}: {e}")
            return False
    
    async def search_projects(self, query: str, limit: int = 10, 
                             filters: Optional[Dict] = None) -> List[Dict[str, Any]]:
        """Search for projects using semantic search"""
        try:
            if not self.collection:
                logger.warning("ChromaDB not initialized")
                return []
            
            # Build where clause for filters
            where_clause = {}
            if filters:
                if 'project_type' in filters:
                    where_clause['project_type'] = filters['project_type']
                if 'min_health_score' in filters:
                    where_clause['health_score'] = {"$gte": filters['min_health_score']}
            
            # Perform semantic search
            results = self.collection.query(
                query_texts=[query],
                n_results=limit,
                where=where_clause if where_clause else None
            )
            
            # Process results
            projects = []
            if results and results['ids'] and len(results['ids'][0]) > 0:
                for i, doc_id in enumerate(results['ids'][0]):
                    metadata = results['metadatas'][0][i]
                    distance = results['distances'][0][i] if results.get('distances') else 0
                    
                    # Get full project data from PostgreSQL
                    async with self.db_pool.acquire() as conn:
                        project = await conn.fetchrow(
                            "SELECT * FROM projects WHERE id = $1",
                            metadata['project_id']
                        )
                        
                        if project:
                            project_dict = dict(project)
                            project_dict['relevance_score'] = 1 - distance  # Convert distance to relevance
                            projects.append(project_dict)
            
            return projects
            
        except Exception as e:
            logger.error(f"Error searching projects: {e}")
            return []
    
    async def find_similar_projects(self, project_id: int, limit: int = 5) -> List[Dict[str, Any]]:
        """Find projects similar to a given project"""
        try:
            if not self.collection:
                return []
            
            # Get the project's embedding
            doc_id = f"project_{project_id}"
            
            # Get similar documents
            results = self.collection.query(
                query_embeddings=None,
                query_texts=None,
                where={"project_id": {"$ne": project_id}},  # Exclude the same project
                n_results=limit + 1  # Get extra in case we need to filter
            )
            
            # Process results
            similar_projects = []
            if results and results['ids']:
                for i, result_id in enumerate(results['ids'][0]):
                    if result_id != doc_id:  # Skip if it's the same project
                        metadata = results['metadatas'][0][i]
                        
                        async with self.db_pool.acquire() as conn:
                            project = await conn.fetchrow(
                                "SELECT * FROM projects WHERE id = $1",
                                metadata['project_id']
                            )
                            
                            if project:
                                similar_projects.append(dict(project))
                    
                    if len(similar_projects) >= limit:
                        break
            
            return similar_projects
            
        except Exception as e:
            logger.error(f"Error finding similar projects: {e}")
            return []
    
    async def index_code_snippet(self, project_id: int, file_path: str, 
                                 code: str, language: str) -> bool:
        """Index a code snippet for semantic code search"""
        try:
            if not self.collection:
                return False
            
            # Create document
            doc_id = f"code_{project_id}_{hashlib.md5(file_path.encode()).hexdigest()}"
            document = f"File: {file_path}\nLanguage: {language}\n\n{code}"
            
            metadata = {
                'project_id': project_id,
                'file_path': file_path,
                'language': language,
                'type': 'code'
            }
            
            # Index in ChromaDB
            self.collection.upsert(
                documents=[document],
                metadatas=[metadata],
                ids=[doc_id]
            )
            
            return True
            
        except Exception as e:
            logger.error(f"Error indexing code snippet: {e}")
            return False
    
    async def search_code(self, query: str, project_id: Optional[int] = None, 
                         language: Optional[str] = None, limit: int = 10) -> List[Dict[str, Any]]:
        """Search for code snippets"""
        try:
            if not self.collection:
                return []
            
            # Build filters
            where_clause = {'type': 'code'}
            if project_id:
                where_clause['project_id'] = project_id
            if language:
                where_clause['language'] = language
            
            # Search
            results = self.collection.query(
                query_texts=[query],
                n_results=limit,
                where=where_clause
            )
            
            # Process results
            code_results = []
            if results and results['ids'] and len(results['ids'][0]) > 0:
                for i, doc_id in enumerate(results['ids'][0]):
                    metadata = results['metadatas'][0][i]
                    document = results['documents'][0][i]
                    distance = results['distances'][0][i] if results.get('distances') else 0
                    
                    code_results.append({
                        'file_path': metadata['file_path'],
                        'language': metadata['language'],
                        'project_id': metadata['project_id'],
                        'snippet': document,
                        'relevance_score': 1 - distance
                    })
            
            return code_results
            
        except Exception as e:
            logger.error(f"Error searching code: {e}")
            return []
    
    async def index_error(self, error: Dict[str, Any]) -> bool:
        """Index an error for similarity search"""
        try:
            if not self.collection:
                return False
            
            # Create document from error
            doc_id = f"error_{error['id']}"
            document = f"Error: {error['error_type']}\nMessage: {error['message']}\nStack: {error.get('stack_trace', '')}"
            
            metadata = {
                'error_id': error['id'],
                'project_id': error.get('project_id'),
                'deployment_id': error.get('deployment_id'),
                'severity': error['severity'],
                'type': 'error'
            }
            
            # Index
            self.collection.upsert(
                documents=[document],
                metadatas=[metadata],
                ids=[doc_id]
            )
            
            return True
            
        except Exception as e:
            logger.error(f"Error indexing error log: {e}")
            return False
    
    async def find_similar_errors(self, error_message: str, limit: int = 5) -> List[Dict[str, Any]]:
        """Find similar errors to help with debugging"""
        try:
            if not self.collection:
                return []
            
            # Search for similar errors
            results = self.collection.query(
                query_texts=[error_message],
                n_results=limit,
                where={'type': 'error'}
            )
            
            # Process results
            similar_errors = []
            if results and results['ids'] and len(results['ids'][0]) > 0:
                for i, doc_id in enumerate(results['ids'][0]):
                    metadata = results['metadatas'][0][i]
                    
                    async with self.db_pool.acquire() as conn:
                        error = await conn.fetchrow(
                            "SELECT * FROM error_logs WHERE id = $1",
                            metadata['error_id']
                        )
                        
                        if error:
                            error_dict = dict(error)
                            error_dict['similarity_score'] = 1 - results['distances'][0][i]
                            similar_errors.append(error_dict)
            
            return similar_errors
            
        except Exception as e:
            logger.error(f"Error finding similar errors: {e}")
            return []
    
    def create_project_document(self, project: Dict[str, Any]) -> str:
        """Create a searchable document from project data"""
        parts = [
            f"Project: {project['name']}",
            f"Type: {project.get('project_type', 'unknown')}",
            f"Path: {project['path']}",
            f"Technologies: {', '.join(project.get('tech_stack', []))}",
            f"Health Score: {project.get('health_score', 0)}",
            f"Description: {project.get('metadata', {}).get('description', '')}",
        ]
        
        # Add errors if present
        if project.get('errors'):
            error_msgs = [e.get('message', '') for e in project['errors']]
            parts.append(f"Errors: {'; '.join(error_msgs)}")
        
        # Add metadata
        metadata = project.get('metadata', {})
        if metadata.get('agents'):
            parts.append(f"Agents: {', '.join(metadata['agents'])}")
        if metadata.get('pages'):
            parts.append(f"Pages: {', '.join(metadata['pages'])}")
        
        return '\n'.join(parts)
    
    async def reindex_all_projects(self) -> int:
        """Reindex all projects in the vector store"""
        count = 0
        try:
            async with self.db_pool.acquire() as conn:
                projects = await conn.fetch("SELECT * FROM projects WHERE is_active = true")
                
                for project in projects:
                    if await self.index_project(dict(project)):
                        count += 1
            
            logger.info(f"Reindexed {count} projects")
            return count
            
        except Exception as e:
            logger.error(f"Error reindexing projects: {e}")
            return count