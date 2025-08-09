#!/usr/bin/env python3
"""
BorgOS MCP Filesystem Server
Provides secure filesystem operations via MCP protocol.
"""
import os
import asyncio
import json
import logging
from pathlib import Path
from typing import Dict, List, Optional, Any
from datetime import datetime
import hashlib
import mimetypes

from mcp.server import Server, Resource, Tool
from mcp.server.models import InitializationOptions
from mcp.types import TextContent, ImageContent, EmbeddedResource

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class FileSystemServer:
    """Enhanced filesystem server with security and monitoring."""
    
    def __init__(self, root_path: str = "/", read_only: bool = False):
        self.root_path = Path(root_path).resolve()
        self.read_only = read_only
        self.server = Server(
            name="borgos-filesystem",
            version="1.0.0",
            description="Secure filesystem operations for BorgOS"
        )
        self._setup_tools()
        self._setup_resources()
        
    def _validate_path(self, path: str) -> Path:
        """Validate and sanitize file paths to prevent directory traversal."""
        try:
            # Resolve the path and ensure it's within root_path
            resolved = (self.root_path / path).resolve()
            if not str(resolved).startswith(str(self.root_path)):
                raise ValueError(f"Path '{path}' is outside allowed directory")
            return resolved
        except Exception as e:
            raise ValueError(f"Invalid path: {e}")
    
    def _get_file_info(self, path: Path) -> Dict[str, Any]:
        """Get detailed file information."""
        try:
            stat = path.stat()
            return {
                "name": path.name,
                "path": str(path.relative_to(self.root_path)),
                "type": "directory" if path.is_dir() else "file",
                "size": stat.st_size if not path.is_dir() else None,
                "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                "created": datetime.fromtimestamp(stat.st_ctime).isoformat(),
                "permissions": oct(stat.st_mode)[-3:],
                "mime_type": mimetypes.guess_type(str(path))[0] if path.is_file() else None
            }
        except Exception as e:
            logger.error(f"Error getting file info for {path}: {e}")
            return {"error": str(e)}
    
    def _setup_tools(self):
        """Register MCP tools."""
        
        @self.server.tool(
            name="list_directory",
            description="List contents of a directory with detailed information"
        )
        async def list_directory(
            path: str = ".",
            pattern: Optional[str] = None,
            recursive: bool = False
        ) -> Dict[str, Any]:
            """List directory contents with optional filtering."""
            try:
                dir_path = self._validate_path(path)
                if not dir_path.is_dir():
                    return {"error": f"'{path}' is not a directory"}
                
                files = []
                if recursive:
                    for item in dir_path.rglob(pattern or "*"):
                        files.append(self._get_file_info(item))
                else:
                    for item in dir_path.glob(pattern or "*"):
                        files.append(self._get_file_info(item))
                
                return {
                    "path": str(dir_path.relative_to(self.root_path)),
                    "count": len(files),
                    "files": files
                }
            except Exception as e:
                logger.error(f"Error listing directory {path}: {e}")
                return {"error": str(e)}
        
        @self.server.tool(
            name="read_file",
            description="Read contents of a file"
        )
        async def read_file(
            path: str,
            encoding: str = "utf-8",
            lines: Optional[int] = None
        ) -> Dict[str, Any]:
            """Read file contents with optional line limit."""
            try:
                file_path = self._validate_path(path)
                if not file_path.is_file():
                    return {"error": f"'{path}' is not a file"}
                
                # Check file size
                size = file_path.stat().st_size
                if size > 10 * 1024 * 1024:  # 10MB limit
                    return {"error": f"File too large ({size} bytes)"}
                
                with open(file_path, 'r', encoding=encoding) as f:
                    if lines:
                        content = "".join(f.readlines()[:lines])
                    else:
                        content = f.read()
                
                return {
                    "path": str(file_path.relative_to(self.root_path)),
                    "content": content,
                    "size": size,
                    "lines": content.count('\n') + 1
                }
            except Exception as e:
                logger.error(f"Error reading file {path}: {e}")
                return {"error": str(e)}
        
        @self.server.tool(
            name="write_file",
            description="Write content to a file"
        )
        async def write_file(
            path: str,
            content: str,
            mode: str = "w",
            encoding: str = "utf-8"
        ) -> Dict[str, Any]:
            """Write content to a file."""
            if self.read_only:
                return {"error": "Server is in read-only mode"}
            
            try:
                file_path = self._validate_path(path)
                
                # Create parent directories if needed
                file_path.parent.mkdir(parents=True, exist_ok=True)
                
                # Backup existing file
                backup_path = None
                if file_path.exists():
                    backup_path = file_path.with_suffix(file_path.suffix + '.bak')
                    backup_path.write_bytes(file_path.read_bytes())
                
                # Write new content
                with open(file_path, mode, encoding=encoding) as f:
                    f.write(content)
                
                # Calculate checksum
                with open(file_path, 'rb') as f:
                    checksum = hashlib.sha256(f.read()).hexdigest()
                
                return {
                    "path": str(file_path.relative_to(self.root_path)),
                    "size": file_path.stat().st_size,
                    "checksum": checksum,
                    "backup": str(backup_path.relative_to(self.root_path)) if backup_path else None
                }
            except Exception as e:
                logger.error(f"Error writing file {path}: {e}")
                return {"error": str(e)}
        
        @self.server.tool(
            name="delete_file",
            description="Delete a file or empty directory"
        )
        async def delete_file(path: str, recursive: bool = False) -> Dict[str, Any]:
            """Delete a file or directory."""
            if self.read_only:
                return {"error": "Server is in read-only mode"}
            
            try:
                file_path = self._validate_path(path)
                if not file_path.exists():
                    return {"error": f"'{path}' does not exist"}
                
                if file_path.is_dir():
                    if recursive:
                        import shutil
                        shutil.rmtree(file_path)
                    else:
                        file_path.rmdir()  # Only works for empty directories
                else:
                    file_path.unlink()
                
                return {
                    "path": str(file_path.relative_to(self.root_path)),
                    "deleted": True
                }
            except Exception as e:
                logger.error(f"Error deleting {path}: {e}")
                return {"error": str(e)}
        
        @self.server.tool(
            name="move_file",
            description="Move or rename a file or directory"
        )
        async def move_file(source: str, destination: str) -> Dict[str, Any]:
            """Move or rename a file or directory."""
            if self.read_only:
                return {"error": "Server is in read-only mode"}
            
            try:
                source_path = self._validate_path(source)
                dest_path = self._validate_path(destination)
                
                if not source_path.exists():
                    return {"error": f"Source '{source}' does not exist"}
                
                if dest_path.exists():
                    return {"error": f"Destination '{destination}' already exists"}
                
                # Create parent directories if needed
                dest_path.parent.mkdir(parents=True, exist_ok=True)
                
                source_path.rename(dest_path)
                
                return {
                    "source": str(source_path.relative_to(self.root_path)),
                    "destination": str(dest_path.relative_to(self.root_path)),
                    "moved": True
                }
            except Exception as e:
                logger.error(f"Error moving {source} to {destination}: {e}")
                return {"error": str(e)}
        
        @self.server.tool(
            name="search_files",
            description="Search for files by name or content"
        )
        async def search_files(
            pattern: str,
            path: str = ".",
            content: Optional[str] = None,
            max_results: int = 100
        ) -> Dict[str, Any]:
            """Search for files matching pattern and optionally containing content."""
            try:
                search_path = self._validate_path(path)
                if not search_path.is_dir():
                    return {"error": f"'{path}' is not a directory"}
                
                results = []
                count = 0
                
                for file_path in search_path.rglob(pattern):
                    if count >= max_results:
                        break
                    
                    if file_path.is_file():
                        # If content search is specified
                        if content:
                            try:
                                with open(file_path, 'r', encoding='utf-8') as f:
                                    if content not in f.read():
                                        continue
                            except:
                                continue  # Skip files that can't be read
                        
                        results.append(self._get_file_info(file_path))
                        count += 1
                
                return {
                    "pattern": pattern,
                    "path": str(search_path.relative_to(self.root_path)),
                    "content_filter": content,
                    "count": len(results),
                    "results": results
                }
            except Exception as e:
                logger.error(f"Error searching files: {e}")
                return {"error": str(e)}
        
        @self.server.tool(
            name="get_file_stats",
            description="Get detailed statistics about a file or directory"
        )
        async def get_file_stats(path: str) -> Dict[str, Any]:
            """Get detailed file or directory statistics."""
            try:
                file_path = self._validate_path(path)
                if not file_path.exists():
                    return {"error": f"'{path}' does not exist"}
                
                stat = file_path.stat()
                info = {
                    "path": str(file_path.relative_to(self.root_path)),
                    "type": "directory" if file_path.is_dir() else "file",
                    "size": stat.st_size,
                    "size_human": self._human_readable_size(stat.st_size),
                    "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                    "created": datetime.fromtimestamp(stat.st_ctime).isoformat(),
                    "accessed": datetime.fromtimestamp(stat.st_atime).isoformat(),
                    "permissions": {
                        "octal": oct(stat.st_mode)[-3:],
                        "owner": stat.st_uid,
                        "group": stat.st_gid
                    }
                }
                
                if file_path.is_dir():
                    # Count items in directory
                    items = list(file_path.iterdir())
                    info["items"] = len(items)
                    info["subdirectories"] = sum(1 for i in items if i.is_dir())
                    info["files"] = sum(1 for i in items if i.is_file())
                    
                    # Calculate total size
                    total_size = sum(
                        f.stat().st_size for f in file_path.rglob('*') if f.is_file()
                    )
                    info["total_size"] = total_size
                    info["total_size_human"] = self._human_readable_size(total_size)
                elif file_path.is_file():
                    # Calculate checksum for files
                    with open(file_path, 'rb') as f:
                        info["checksum"] = {
                            "sha256": hashlib.sha256(f.read()).hexdigest()
                        }
                    info["mime_type"] = mimetypes.guess_type(str(file_path))[0]
                
                return info
            except Exception as e:
                logger.error(f"Error getting stats for {path}: {e}")
                return {"error": str(e)}
    
    def _setup_resources(self):
        """Register MCP resources."""
        
        @self.server.resource(
            uri="file:///{path}",
            name="File System Resource",
            description="Access files through MCP resources"
        )
        async def file_resource(path: str) -> EmbeddedResource:
            """Provide file access as MCP resource."""
            try:
                file_path = self._validate_path(path)
                if not file_path.is_file():
                    raise ValueError(f"'{path}' is not a file")
                
                mime_type = mimetypes.guess_type(str(file_path))[0]
                
                # Handle text files
                if mime_type and mime_type.startswith('text/'):
                    with open(file_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                    return TextContent(
                        uri=f"file:///{path}",
                        mimeType=mime_type,
                        text=content
                    )
                # Handle images
                elif mime_type and mime_type.startswith('image/'):
                    with open(file_path, 'rb') as f:
                        data = f.read()
                    import base64
                    return ImageContent(
                        uri=f"file:///{path}",
                        mimeType=mime_type,
                        data=base64.b64encode(data).decode('utf-8')
                    )
                else:
                    # Return as text with base64 encoding for binary files
                    with open(file_path, 'rb') as f:
                        data = f.read()
                    import base64
                    return TextContent(
                        uri=f"file:///{path}",
                        mimeType="application/octet-stream",
                        text=base64.b64encode(data).decode('utf-8')
                    )
            except Exception as e:
                logger.error(f"Error accessing resource {path}: {e}")
                raise
    
    def _human_readable_size(self, size: int) -> str:
        """Convert bytes to human-readable format."""
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if size < 1024.0:
                return f"{size:.2f} {unit}"
            size /= 1024.0
        return f"{size:.2f} PB"
    
    async def run(self, host: str = "127.0.0.1", port: int = 7300):
        """Run the MCP server."""
        logger.info(f"Starting BorgOS MCP Filesystem Server on {host}:{port}")
        logger.info(f"Root path: {self.root_path}")
        logger.info(f"Read-only mode: {self.read_only}")
        
        try:
            await self.server.serve(host, port)
        except KeyboardInterrupt:
            logger.info("Server shutdown requested")
        except Exception as e:
            logger.error(f"Server error: {e}")
            raise

def main():
    """Main entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description="BorgOS MCP Filesystem Server")
    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="Host to bind to (default: 127.0.0.1)"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=7300,
        help="Port to bind to (default: 7300)"
    )
    parser.add_argument(
        "--root",
        default="/",
        help="Root directory for filesystem operations (default: /)"
    )
    parser.add_argument(
        "--read-only",
        action="store_true",
        help="Run in read-only mode"
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="Logging level (default: INFO)"
    )
    
    args = parser.parse_args()
    
    # Configure logging
    logging.getLogger().setLevel(getattr(logging, args.log_level))
    
    # Create and run server
    server = FileSystemServer(root_path=args.root, read_only=args.read_only)
    
    try:
        asyncio.run(server.run(args.host, args.port))
    except KeyboardInterrupt:
        print("\nShutdown complete")
    except Exception as e:
        logger.error(f"Failed to start server: {e}")
        exit(1)

if __name__ == "__main__":
    main()