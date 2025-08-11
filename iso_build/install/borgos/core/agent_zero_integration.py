"""
Agent Zero Integration for BorgOS
Connects Agent Zero autonomous agent to the BorgOS ecosystem
"""

import os
import sys
import json
import asyncio
import subprocess
from pathlib import Path
from typing import Optional, Dict, Any, List
import logging
from datetime import datetime

# Add Agent Zero to path
AGENT_ZERO_PATH = Path("/Users/wojciechwiesner/ai/agent-zero")
if AGENT_ZERO_PATH.exists():
    sys.path.insert(0, str(AGENT_ZERO_PATH))

logger = logging.getLogger(__name__)

class AgentZeroIntegration:
    """Integration layer for Agent Zero in BorgOS"""
    
    def __init__(self, db_pool=None):
        self.db_pool = db_pool
        self.agent_zero_dir = AGENT_ZERO_PATH
        self.agent_process = None
        self.agent_port = 8085  # Default port for Agent Zero
        self.is_running = False
        
    async def initialize(self) -> bool:
        """Initialize Agent Zero integration"""
        try:
            if not self.agent_zero_dir.exists():
                logger.error(f"Agent Zero directory not found at {self.agent_zero_dir}")
                return False
            
            # Check if Agent Zero is properly configured
            env_file = self.agent_zero_dir / ".env"
            if not env_file.exists():
                logger.info("Creating Agent Zero .env file...")
                self.create_default_env()
            
            # Check requirements
            requirements_file = self.agent_zero_dir / "requirements.txt"
            if requirements_file.exists():
                logger.info("Checking Agent Zero dependencies...")
                # Note: In production, this would be done during installation
                # subprocess.run([sys.executable, "-m", "pip", "install", "-r", str(requirements_file)], check=False)
            
            logger.info("Agent Zero integration initialized")
            return True
            
        except Exception as e:
            logger.error(f"Failed to initialize Agent Zero: {e}")
            return False
    
    def create_default_env(self):
        """Create default .env file for Agent Zero"""
        env_content = """
# Agent Zero Configuration for BorgOS

# API Keys (will be managed by BorgOS)
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
GROQ_API_KEY=
OPENROUTER_API_KEY=
GOOGLE_API_KEY=
OLLAMA_API_BASE_URL=http://localhost:11434

# Agent Configuration
CHAT_MODEL=gpt-4o-mini
UTILITY_MODEL=gpt-4o-mini
EMBEDDING_MODEL=text-embedding-3-small
BROWSER_MODEL=gpt-4o-mini

# System Settings
AGENT_NAME=Agent Zero
AGENT_ROLE=Autonomous AI Assistant
MAX_CONTEXT_LENGTH=128000
MAX_TOKENS=4000
TEMPERATURE=0.5

# Docker Configuration
DOCKER_CONTAINER_NAME=agent-zero-exe
DOCKER_IMAGE=frdel/agent-zero-exe:latest
DOCKER_INTERNAL_PORT=50000
DOCKER_EXTERNAL_PORT=50001

# Security
RUN_IN_DOCKER=true
SSH_ENABLED=false

# BorgOS Integration
BORGOS_ENABLED=true
BORGOS_API_URL=http://localhost:8081
BORGOS_WEBHOOK_URL=http://localhost:8081/api/v1/agent/callback
"""
        
        env_file = self.agent_zero_dir / ".env"
        env_file.write_text(env_content.strip())
        logger.info("Created default Agent Zero .env file")
    
    async def start_agent(self, config: Optional[Dict[str, Any]] = None) -> bool:
        """Start Agent Zero process"""
        try:
            if self.is_running:
                logger.warning("Agent Zero is already running")
                return True
            
            # Update configuration if provided
            if config:
                self.update_config(config)
            
            # Start Agent Zero UI
            cmd = [
                sys.executable,
                str(self.agent_zero_dir / "run_ui.py"),
                "--port", str(self.agent_port)
            ]
            
            logger.info(f"Starting Agent Zero on port {self.agent_port}...")
            self.agent_process = subprocess.Popen(
                cmd,
                cwd=str(self.agent_zero_dir),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            
            # Wait for Agent Zero to start
            await asyncio.sleep(5)
            
            # Check if process is running
            if self.agent_process.poll() is None:
                self.is_running = True
                logger.info(f"Agent Zero started successfully on port {self.agent_port}")
                
                # Log to database if available
                if self.db_pool:
                    await self.log_agent_status("started")
                
                return True
            else:
                logger.error("Agent Zero process terminated unexpectedly")
                return False
                
        except Exception as e:
            logger.error(f"Failed to start Agent Zero: {e}")
            return False
    
    async def stop_agent(self) -> bool:
        """Stop Agent Zero process"""
        try:
            if not self.is_running or not self.agent_process:
                logger.warning("Agent Zero is not running")
                return True
            
            logger.info("Stopping Agent Zero...")
            self.agent_process.terminate()
            
            # Wait for process to terminate
            try:
                self.agent_process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                logger.warning("Agent Zero did not terminate, forcing kill")
                self.agent_process.kill()
            
            self.is_running = False
            self.agent_process = None
            
            # Log to database
            if self.db_pool:
                await self.log_agent_status("stopped")
            
            logger.info("Agent Zero stopped")
            return True
            
        except Exception as e:
            logger.error(f"Failed to stop Agent Zero: {e}")
            return False
    
    async def restart_agent(self) -> bool:
        """Restart Agent Zero"""
        await self.stop_agent()
        await asyncio.sleep(2)
        return await self.start_agent()
    
    async def execute_task(self, task: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a task using Agent Zero"""
        try:
            if not self.is_running:
                logger.warning("Agent Zero is not running, starting it...")
                if not await self.start_agent():
                    return {"success": False, "error": "Failed to start Agent Zero"}
            
            # Import Agent Zero modules
            from agent import Agent
            from python.helpers.print_style import PrintStyle
            
            # Create agent instance
            agent_config = {
                "chat_model": os.getenv("CHAT_MODEL", "gpt-4o-mini"),
                "utility_model": os.getenv("UTILITY_MODEL", "gpt-4o-mini"),
                "max_context_length": int(os.getenv("MAX_CONTEXT_LENGTH", 128000)),
                "max_tokens": int(os.getenv("MAX_TOKENS", 4000)),
                "temperature": float(os.getenv("TEMPERATURE", 0.5))
            }
            
            agent = Agent(**agent_config)
            
            # Execute task
            task_type = task.get("type", "general")
            prompt = task.get("prompt", "")
            context = task.get("context", {})
            
            logger.info(f"Executing Agent Zero task: {task_type}")
            
            # Add context to prompt
            if context:
                context_str = json.dumps(context, indent=2)
                prompt = f"Context:\n{context_str}\n\nTask: {prompt}"
            
            # Run agent
            response = agent.message_loop(prompt)
            
            # Process response
            result = {
                "success": True,
                "task_id": task.get("id"),
                "task_type": task_type,
                "response": response,
                "timestamp": datetime.utcnow().isoformat()
            }
            
            # Log to database
            if self.db_pool:
                await self.log_task_execution(task, result)
            
            return result
            
        except Exception as e:
            logger.error(f"Failed to execute Agent Zero task: {e}")
            return {
                "success": False,
                "error": str(e),
                "task_id": task.get("id")
            }
    
    async def get_agent_status(self) -> Dict[str, Any]:
        """Get Agent Zero status"""
        return {
            "running": self.is_running,
            "port": self.agent_port,
            "process_id": self.agent_process.pid if self.agent_process else None,
            "directory": str(self.agent_zero_dir),
            "ui_url": f"http://localhost:{self.agent_port}" if self.is_running else None
        }
    
    async def get_agent_capabilities(self) -> List[str]:
        """Get list of Agent Zero capabilities"""
        return [
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
    
    def update_config(self, config: Dict[str, Any]):
        """Update Agent Zero configuration"""
        env_file = self.agent_zero_dir / ".env"
        
        if env_file.exists():
            # Read existing config
            lines = env_file.read_text().split('\n')
            
            # Update with new values
            for key, value in config.items():
                key_upper = key.upper()
                found = False
                
                for i, line in enumerate(lines):
                    if line.startswith(f"{key_upper}="):
                        lines[i] = f"{key_upper}={value}"
                        found = True
                        break
                
                if not found:
                    lines.append(f"{key_upper}={value}")
            
            # Write back
            env_file.write_text('\n'.join(lines))
            logger.info(f"Updated Agent Zero config: {config}")
    
    async def log_agent_status(self, status: str):
        """Log agent status to database"""
        if not self.db_pool:
            return
        
        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute(
                    """
                    INSERT INTO agent_logs (agent_type, status, timestamp, metadata)
                    VALUES ('agent-zero', $1, NOW(), $2)
                    """,
                    status,
                    json.dumps({
                        "port": self.agent_port,
                        "directory": str(self.agent_zero_dir)
                    })
                )
        except Exception as e:
            logger.error(f"Failed to log agent status: {e}")
    
    async def log_task_execution(self, task: Dict[str, Any], result: Dict[str, Any]):
        """Log task execution to database"""
        if not self.db_pool:
            return
        
        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute(
                    """
                    UPDATE agent_tasks
                    SET status = $1, result = $2, completed_at = NOW()
                    WHERE id = $3
                    """,
                    "completed" if result.get("success") else "failed",
                    json.dumps(result),
                    task.get("id")
                )
        except Exception as e:
            logger.error(f"Failed to log task execution: {e}")
    
    async def create_subordinate_agent(self, name: str, role: str) -> Dict[str, Any]:
        """Create a subordinate agent for specific tasks"""
        try:
            # This would create a specialized instance of Agent Zero
            subordinate_config = {
                "name": name,
                "role": role,
                "parent": "main",
                "capabilities": self.get_specialized_capabilities(role)
            }
            
            # In a full implementation, this would spawn a new agent instance
            logger.info(f"Created subordinate agent: {name} with role: {role}")
            
            return {
                "success": True,
                "agent_name": name,
                "agent_role": role,
                "status": "ready"
            }
            
        except Exception as e:
            logger.error(f"Failed to create subordinate agent: {e}")
            return {"success": False, "error": str(e)}
    
    def get_specialized_capabilities(self, role: str) -> List[str]:
        """Get capabilities based on agent role"""
        role_capabilities = {
            "researcher": ["web_browsing", "knowledge_retrieval", "api_integration"],
            "developer": ["code_execution", "file_operations", "shell_commands"],
            "analyst": ["data_processing", "visualization", "reporting"],
            "automation": ["task_scheduling", "workflow_management", "monitoring"]
        }
        return role_capabilities.get(role, ["general_assistance"])

# Singleton instance
_agent_zero_instance = None

def get_agent_zero_integration(db_pool=None) -> AgentZeroIntegration:
    """Get or create Agent Zero integration instance"""
    global _agent_zero_instance
    if _agent_zero_instance is None:
        _agent_zero_instance = AgentZeroIntegration(db_pool)
    return _agent_zero_instance