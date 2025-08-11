#!/usr/bin/env python3
"""
Example BorgOS Plugin
Demonstrates the plugin architecture and available APIs.
"""
import os
import platform
import psutil
from typing import Dict, Any, List, Optional
from datetime import datetime

class BorgPlugin:
    """Base class for BorgOS plugins."""
    
    def __init__(self):
        self.name = "example_plugin"
        self.version = "1.0.0"
        self.description = "Example plugin demonstrating BorgOS plugin capabilities"
        self.tools = []
        self._register_tools()
    
    def _register_tools(self):
        """Register all tools provided by this plugin."""
        self.tools = [
            {
                "name": "hello",
                "description": "Say hello with optional personalization",
                "handler": self.hello,
                "parameters": {
                    "name": {"type": "string", "default": "world", "description": "Name to greet"}
                }
            },
            {
                "name": "system_info",
                "description": "Get detailed system information",
                "handler": self.system_info,
                "parameters": {}
            },
            {
                "name": "disk_usage",
                "description": "Check disk usage for all mounted filesystems",
                "handler": self.disk_usage,
                "parameters": {
                    "threshold": {"type": "int", "default": 80, "description": "Alert threshold percentage"}
                }
            },
            {
                "name": "process_list",
                "description": "List running processes with resource usage",
                "handler": self.process_list,
                "parameters": {
                    "sort_by": {"type": "string", "default": "cpu", "description": "Sort by: cpu, memory, name"},
                    "limit": {"type": "int", "default": 10, "description": "Number of processes to return"}
                }
            },
            {
                "name": "network_status",
                "description": "Check network connectivity and interfaces",
                "handler": self.network_status,
                "parameters": {}
            }
        ]
    
    async def hello(self, name: str = "world") -> str:
        """Simple greeting function."""
        current_time = datetime.now().strftime("%H:%M:%S")
        return f"Hello {name}! Current time is {current_time}. This is the example BorgOS plugin."
    
    async def system_info(self) -> Dict[str, Any]:
        """Get comprehensive system information."""
        try:
            # CPU information
            cpu_info = {
                "physical_cores": psutil.cpu_count(logical=False),
                "logical_cores": psutil.cpu_count(logical=True),
                "current_frequency": psutil.cpu_freq().current if psutil.cpu_freq() else None,
                "cpu_percent": psutil.cpu_percent(interval=1),
                "per_cpu_percent": psutil.cpu_percent(interval=1, percpu=True)
            }
            
            # Memory information
            memory = psutil.virtual_memory()
            memory_info = {
                "total": self._format_bytes(memory.total),
                "available": self._format_bytes(memory.available),
                "used": self._format_bytes(memory.used),
                "percent": memory.percent
            }
            
            # System information
            boot_time = datetime.fromtimestamp(psutil.boot_time())
            system_info = {
                "platform": platform.platform(),
                "processor": platform.processor(),
                "architecture": platform.machine(),
                "hostname": platform.node(),
                "python_version": platform.python_version(),
                "boot_time": boot_time.isoformat(),
                "uptime": self._get_uptime()
            }
            
            return {
                "cpu": cpu_info,
                "memory": memory_info,
                "system": system_info
            }
        except Exception as e:
            return {"error": str(e)}
    
    async def disk_usage(self, threshold: int = 80) -> Dict[str, Any]:
        """Check disk usage and alert on high usage."""
        try:
            partitions = psutil.disk_partitions()
            disk_info = []
            alerts = []
            
            for partition in partitions:
                try:
                    usage = psutil.disk_usage(partition.mountpoint)
                    info = {
                        "device": partition.device,
                        "mountpoint": partition.mountpoint,
                        "filesystem": partition.fstype,
                        "total": self._format_bytes(usage.total),
                        "used": self._format_bytes(usage.used),
                        "free": self._format_bytes(usage.free),
                        "percent": usage.percent
                    }
                    disk_info.append(info)
                    
                    if usage.percent >= threshold:
                        alerts.append({
                            "device": partition.device,
                            "mountpoint": partition.mountpoint,
                            "usage": usage.percent,
                            "message": f"High disk usage: {usage.percent}% (threshold: {threshold}%)"
                        })
                except PermissionError:
                    continue
            
            return {
                "disks": disk_info,
                "alerts": alerts,
                "threshold": threshold
            }
        except Exception as e:
            return {"error": str(e)}
    
    async def process_list(self, sort_by: str = "cpu", limit: int = 10) -> List[Dict[str, Any]]:
        """List running processes sorted by resource usage."""
        try:
            processes = []
            for proc in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_percent', 'status']):
                try:
                    pinfo = proc.info
                    processes.append({
                        "pid": pinfo['pid'],
                        "name": pinfo['name'],
                        "cpu_percent": pinfo['cpu_percent'],
                        "memory_percent": round(pinfo['memory_percent'], 2),
                        "status": pinfo['status']
                    })
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue
            
            # Sort processes
            if sort_by == "cpu":
                processes.sort(key=lambda x: x['cpu_percent'], reverse=True)
            elif sort_by == "memory":
                processes.sort(key=lambda x: x['memory_percent'], reverse=True)
            elif sort_by == "name":
                processes.sort(key=lambda x: x['name'])
            
            return processes[:limit]
        except Exception as e:
            return [{"error": str(e)}]
    
    async def network_status(self) -> Dict[str, Any]:
        """Check network connectivity and interface status."""
        try:
            interfaces = {}
            for interface, addrs in psutil.net_if_addrs().items():
                interface_info = {
                    "addresses": []
                }
                for addr in addrs:
                    addr_info = {
                        "family": str(addr.family),
                        "address": addr.address,
                        "netmask": addr.netmask,
                        "broadcast": addr.broadcast
                    }
                    interface_info["addresses"].append(addr_info)
                interfaces[interface] = interface_info
            
            # Network statistics
            stats = psutil.net_io_counters()
            network_stats = {
                "bytes_sent": self._format_bytes(stats.bytes_sent),
                "bytes_received": self._format_bytes(stats.bytes_recv),
                "packets_sent": stats.packets_sent,
                "packets_received": stats.packets_recv,
                "errors_in": stats.errin,
                "errors_out": stats.errout
            }
            
            # Check internet connectivity
            import socket
            try:
                socket.create_connection(("1.1.1.1", 53), timeout=3)
                internet_connected = True
            except OSError:
                internet_connected = False
            
            return {
                "interfaces": interfaces,
                "statistics": network_stats,
                "internet_connected": internet_connected
            }
        except Exception as e:
            return {"error": str(e)}
    
    def _format_bytes(self, bytes: int) -> str:
        """Format bytes to human-readable string."""
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if bytes < 1024.0:
                return f"{bytes:.2f} {unit}"
            bytes /= 1024.0
        return f"{bytes:.2f} PB"
    
    def _get_uptime(self) -> str:
        """Get system uptime."""
        boot_time = datetime.fromtimestamp(psutil.boot_time())
        delta = datetime.now() - boot_time
        days = delta.days
        hours, remainder = divmod(delta.seconds, 3600)
        minutes, _ = divmod(remainder, 60)
        
        if days > 0:
            return f"{days}d {hours}h {minutes}m"
        elif hours > 0:
            return f"{hours}h {minutes}m"
        else:
            return f"{minutes}m"

# Plugin registration
def register():
    """Register this plugin with BorgOS."""
    return BorgPlugin()

# Allow running as standalone for testing
if __name__ == "__main__":
    import asyncio
    
    async def test():
        plugin = BorgPlugin()
        
        print("Testing plugin tools:")
        print("-" * 50)
        
        # Test hello
        result = await plugin.hello("BorgOS")
        print(f"Hello: {result}")
        print()
        
        # Test system info
        result = await plugin.system_info()
        print(f"System Info: {result}")
        print()
        
        # Test disk usage
        result = await plugin.disk_usage(threshold=50)
        print(f"Disk Usage: {result}")
        print()
        
        # Test process list
        result = await plugin.process_list(limit=5)
        print(f"Top 5 Processes: {result}")
        print()
        
        # Test network status
        result = await plugin.network_status()
        print(f"Network Status: {result}")
    
    asyncio.run(test())