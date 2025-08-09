"""
BorgOS Plugin System
Provides extensibility through dynamically loaded Python modules.
"""
import os
import importlib.util
import logging
from pathlib import Path
from typing import Dict, List, Any, Optional

logger = logging.getLogger(__name__)

class PluginLoader:
    """Manages loading and registration of BorgOS plugins."""
    
    def __init__(self, plugin_dir: str = "/opt/borgos/plugins"):
        self.plugin_dir = Path(plugin_dir)
        self.plugins: Dict[str, Any] = {}
        self.tools: Dict[str, Any] = {}
        
    def load_plugins(self) -> Dict[str, Any]:
        """Load all plugins from the plugin directory."""
        if not self.plugin_dir.exists():
            logger.warning(f"Plugin directory {self.plugin_dir} does not exist")
            return {}
        
        for plugin_file in self.plugin_dir.glob("*.py"):
            if plugin_file.name.startswith("_"):
                continue
            
            try:
                self._load_plugin(plugin_file)
            except Exception as e:
                logger.error(f"Failed to load plugin {plugin_file.name}: {e}")
        
        return self.plugins
    
    def _load_plugin(self, plugin_file: Path):
        """Load a single plugin from a file."""
        plugin_name = plugin_file.stem
        
        # Load the module
        spec = importlib.util.spec_from_file_location(plugin_name, plugin_file)
        if spec is None or spec.loader is None:
            raise ValueError(f"Cannot load plugin from {plugin_file}")
        
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        
        # Register the plugin
        if hasattr(module, 'register'):
            plugin_instance = module.register()
            self.plugins[plugin_name] = plugin_instance
            
            # Register tools from the plugin
            if hasattr(plugin_instance, 'tools'):
                for tool in plugin_instance.tools:
                    tool_name = f"{plugin_name}.{tool['name']}"
                    self.tools[tool_name] = tool
                    logger.info(f"Registered tool: {tool_name}")
            
            logger.info(f"Loaded plugin: {plugin_name}")
        else:
            logger.warning(f"Plugin {plugin_name} has no register() function")
    
    def get_plugin(self, name: str) -> Optional[Any]:
        """Get a loaded plugin by name."""
        return self.plugins.get(name)
    
    def get_tool(self, name: str) -> Optional[Dict[str, Any]]:
        """Get a tool by name."""
        return self.tools.get(name)
    
    def list_plugins(self) -> List[str]:
        """List all loaded plugins."""
        return list(self.plugins.keys())
    
    def list_tools(self) -> List[str]:
        """List all available tools."""
        return list(self.tools.keys())
    
    async def execute_tool(self, tool_name: str, **kwargs) -> Any:
        """Execute a tool with given parameters."""
        tool = self.get_tool(tool_name)
        if not tool:
            raise ValueError(f"Tool {tool_name} not found")
        
        handler = tool.get('handler')
        if not handler:
            raise ValueError(f"Tool {tool_name} has no handler")
        
        # Validate parameters
        params = tool.get('parameters', {})
        for param_name, param_def in params.items():
            if param_name not in kwargs and 'default' in param_def:
                kwargs[param_name] = param_def['default']
        
        # Execute the handler
        if asyncio.iscoroutinefunction(handler):
            return await handler(**kwargs)
        else:
            return handler(**kwargs)

# Global plugin loader instance
_loader = None

def get_loader(plugin_dir: str = "/opt/borgos/plugins") -> PluginLoader:
    """Get or create the global plugin loader."""
    global _loader
    if _loader is None:
        _loader = PluginLoader(plugin_dir)
        _loader.load_plugins()
    return _loader

def reload_plugins(plugin_dir: str = "/opt/borgos/plugins"):
    """Reload all plugins."""
    global _loader
    _loader = PluginLoader(plugin_dir)
    _loader.load_plugins()
    return _loader

# Convenience exports
__all__ = ['PluginLoader', 'get_loader', 'reload_plugins']

# Auto-load plugins if running as main
if __name__ == "__main__":
    import asyncio
    
    # Test plugin loading
    loader = PluginLoader(".")
    loader.load_plugins()
    
    print(f"Loaded plugins: {loader.list_plugins()}")
    print(f"Available tools: {loader.list_tools()}")
    
    # Test tool execution if example plugin is loaded
    if "example_plugin.hello" in loader.list_tools():
        async def test():
            result = await loader.execute_tool("example_plugin.hello", name="Tester")
            print(f"Tool result: {result}")
        
        asyncio.run(test())