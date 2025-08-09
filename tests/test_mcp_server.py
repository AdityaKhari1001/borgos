#!/usr/bin/env python3
"""
Unit tests for BorgOS MCP Server
"""
import pytest
import asyncio
import sys
import os
from pathlib import Path
from unittest.mock import patch, MagicMock, mock_open
import tempfile
import shutil

# Add parent directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from mcp_servers.fs_server import FileSystemServer

@pytest.fixture
def temp_dir():
    """Create a temporary directory for testing."""
    temp_path = tempfile.mkdtemp()
    yield temp_path
    shutil.rmtree(temp_path)

@pytest.fixture
def fs_server(temp_dir):
    """Create a FileSystemServer instance for testing."""
    return FileSystemServer(root_path=temp_dir, read_only=False)

@pytest.fixture
def read_only_server(temp_dir):
    """Create a read-only FileSystemServer instance."""
    return FileSystemServer(root_path=temp_dir, read_only=True)

class TestFileSystemServer:
    """Test suite for FileSystemServer."""
    
    def test_server_initialization(self, fs_server, temp_dir):
        """Test server initialization."""
        assert fs_server.root_path == Path(temp_dir)
        assert fs_server.read_only is False
        assert fs_server.server.name == "borgos-filesystem"
    
    def test_validate_path_valid(self, fs_server, temp_dir):
        """Test path validation with valid path."""
        valid_path = fs_server._validate_path("test.txt")
        assert str(valid_path).startswith(str(temp_dir))
    
    def test_validate_path_traversal(self, fs_server):
        """Test path validation prevents directory traversal."""
        with pytest.raises(ValueError, match="outside allowed directory"):
            fs_server._validate_path("../../../etc/passwd")
    
    def test_get_file_info(self, fs_server, temp_dir):
        """Test getting file information."""
        # Create a test file
        test_file = Path(temp_dir) / "test.txt"
        test_file.write_text("test content")
        
        info = fs_server._get_file_info(test_file)
        
        assert info["name"] == "test.txt"
        assert info["type"] == "file"
        assert info["size"] == 12
        assert "modified" in info
        assert "created" in info
        assert "permissions" in info
    
    def test_human_readable_size(self, fs_server):
        """Test human-readable size conversion."""
        assert fs_server._human_readable_size(100) == "100.00 B"
        assert fs_server._human_readable_size(1024) == "1.00 KB"
        assert fs_server._human_readable_size(1024 * 1024) == "1.00 MB"
        assert fs_server._human_readable_size(1024 * 1024 * 1024) == "1.00 GB"

class TestMCPTools:
    """Test MCP tool implementations."""
    
    @pytest.mark.asyncio
    async def test_list_directory(self, fs_server, temp_dir):
        """Test list_directory tool."""
        # Create test files
        (Path(temp_dir) / "file1.txt").write_text("content1")
        (Path(temp_dir) / "file2.txt").write_text("content2")
        (Path(temp_dir) / "subdir").mkdir()
        
        # Get the tool
        tools = fs_server.server._tools
        list_dir_tool = next(t for t in tools if t.name == "list_directory")
        
        # Test listing
        result = await list_dir_tool.handler(path=".")
        
        assert result["count"] == 3
        assert len(result["files"]) == 3
        names = [f["name"] for f in result["files"]]
        assert "file1.txt" in names
        assert "file2.txt" in names
        assert "subdir" in names
    
    @pytest.mark.asyncio
    async def test_read_file(self, fs_server, temp_dir):
        """Test read_file tool."""
        # Create test file
        test_content = "Hello, BorgOS!"
        (Path(temp_dir) / "test.txt").write_text(test_content)
        
        # Get the tool
        tools = fs_server.server._tools
        read_tool = next(t for t in tools if t.name == "read_file")
        
        # Test reading
        result = await read_tool.handler(path="test.txt")
        
        assert result["content"] == test_content
        assert result["size"] == len(test_content)
        assert result["lines"] == 1
    
    @pytest.mark.asyncio
    async def test_read_file_not_found(self, fs_server):
        """Test read_file with non-existent file."""
        tools = fs_server.server._tools
        read_tool = next(t for t in tools if t.name == "read_file")
        
        result = await read_tool.handler(path="nonexistent.txt")
        assert "error" in result
    
    @pytest.mark.asyncio
    async def test_write_file(self, fs_server, temp_dir):
        """Test write_file tool."""
        tools = fs_server.server._tools
        write_tool = next(t for t in tools if t.name == "write_file")
        
        # Write a file
        content = "New content"
        result = await write_tool.handler(path="new.txt", content=content)
        
        assert result["size"] == len(content)
        assert "checksum" in result
        
        # Verify file was written
        written_content = (Path(temp_dir) / "new.txt").read_text()
        assert written_content == content
    
    @pytest.mark.asyncio
    async def test_write_file_read_only(self, read_only_server):
        """Test write_file in read-only mode."""
        tools = read_only_server.server._tools
        write_tool = next(t for t in tools if t.name == "write_file")
        
        result = await write_tool.handler(path="test.txt", content="content")
        assert result["error"] == "Server is in read-only mode"
    
    @pytest.mark.asyncio
    async def test_delete_file(self, fs_server, temp_dir):
        """Test delete_file tool."""
        # Create test file
        test_file = Path(temp_dir) / "delete_me.txt"
        test_file.write_text("delete this")
        
        tools = fs_server.server._tools
        delete_tool = next(t for t in tools if t.name == "delete_file")
        
        # Delete the file
        result = await delete_tool.handler(path="delete_me.txt")
        
        assert result["deleted"] is True
        assert not test_file.exists()
    
    @pytest.mark.asyncio
    async def test_delete_directory(self, fs_server, temp_dir):
        """Test deleting a directory."""
        # Create test directory with content
        test_dir = Path(temp_dir) / "delete_dir"
        test_dir.mkdir()
        (test_dir / "file.txt").write_text("content")
        
        tools = fs_server.server._tools
        delete_tool = next(t for t in tools if t.name == "delete_file")
        
        # Try without recursive (should fail)
        result = await delete_tool.handler(path="delete_dir", recursive=False)
        assert "error" in result
        
        # Try with recursive
        result = await delete_tool.handler(path="delete_dir", recursive=True)
        assert result["deleted"] is True
        assert not test_dir.exists()
    
    @pytest.mark.asyncio
    async def test_move_file(self, fs_server, temp_dir):
        """Test move_file tool."""
        # Create source file
        source = Path(temp_dir) / "source.txt"
        source.write_text("move me")
        
        tools = fs_server.server._tools
        move_tool = next(t for t in tools if t.name == "move_file")
        
        # Move the file
        result = await move_tool.handler(source="source.txt", destination="dest.txt")
        
        assert result["moved"] is True
        assert not source.exists()
        assert (Path(temp_dir) / "dest.txt").exists()
        assert (Path(temp_dir) / "dest.txt").read_text() == "move me"
    
    @pytest.mark.asyncio
    async def test_search_files(self, fs_server, temp_dir):
        """Test search_files tool."""
        # Create test files
        (Path(temp_dir) / "test1.txt").write_text("content one")
        (Path(temp_dir) / "test2.txt").write_text("content two")
        (Path(temp_dir) / "other.md").write_text("different")
        
        subdir = Path(temp_dir) / "subdir"
        subdir.mkdir()
        (subdir / "test3.txt").write_text("content three")
        
        tools = fs_server.server._tools
        search_tool = next(t for t in tools if t.name == "search_files")
        
        # Search by pattern
        result = await search_tool.handler(pattern="*.txt")
        assert result["count"] == 3
        
        # Search with content filter
        result = await search_tool.handler(pattern="*.txt", content="two")
        assert result["count"] == 1
        assert result["results"][0]["name"] == "test2.txt"
    
    @pytest.mark.asyncio
    async def test_get_file_stats(self, fs_server, temp_dir):
        """Test get_file_stats tool."""
        # Create test file
        test_file = Path(temp_dir) / "stats.txt"
        test_file.write_text("test content for stats")
        
        tools = fs_server.server._tools
        stats_tool = next(t for t in tools if t.name == "get_file_stats")
        
        # Get file stats
        result = await stats_tool.handler(path="stats.txt")
        
        assert result["type"] == "file"
        assert result["size"] == 22
        assert "checksum" in result
        assert result["checksum"]["sha256"] is not None
        assert "modified" in result
        assert "created" in result
        assert "permissions" in result
    
    @pytest.mark.asyncio
    async def test_get_directory_stats(self, fs_server, temp_dir):
        """Test get_file_stats for directories."""
        # Create test directory with files
        test_dir = Path(temp_dir) / "dir_stats"
        test_dir.mkdir()
        (test_dir / "file1.txt").write_text("content1")
        (test_dir / "file2.txt").write_text("content2")
        
        subdir = test_dir / "subdir"
        subdir.mkdir()
        (subdir / "file3.txt").write_text("content3")
        
        tools = fs_server.server._tools
        stats_tool = next(t for t in tools if t.name == "get_file_stats")
        
        # Get directory stats
        result = await stats_tool.handler(path="dir_stats")
        
        assert result["type"] == "directory"
        assert result["items"] == 3
        assert result["files"] == 2
        assert result["subdirectories"] == 1
        assert "total_size" in result
        assert "total_size_human" in result