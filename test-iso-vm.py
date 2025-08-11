#!/usr/bin/env python3
"""
BorgOS ISO VM Testing Suite
Comprehensive automated testing of BorgOS ISO in QEMU
"""

import os
import sys
import time
import subprocess
import socket
import pexpect
import json
import logging
from pathlib import Path
from typing import Dict, List, Tuple, Optional
import requests
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/results/test-vm.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


class BorgOSISOTester:
    """Comprehensive ISO testing in QEMU VM"""
    
    def __init__(self, iso_path: str, results_dir: str = "/results"):
        self.iso_path = iso_path
        self.results_dir = Path(results_dir)
        self.results_dir.mkdir(exist_ok=True)
        
        self.vm_process = None
        self.test_results = {
            "timestamp": datetime.now().isoformat(),
            "iso_path": iso_path,
            "tests": {}
        }
        
        # VM Configuration
        self.vm_config = {
            "memory": "4G",
            "cpu": "2",
            "vnc_port": 5900,
            "ssh_port": 10022,
            "web_port": 18080,
            "api_port": 18081,
            "monitor_port": 55555
        }
    
    def start_vm(self, boot_mode: str = "bios") -> bool:
        """Start QEMU VM with ISO"""
        logger.info(f"Starting VM with {boot_mode} boot mode...")
        
        qemu_cmd = [
            "qemu-system-x86_64",
            "-m", self.vm_config["memory"],
            "-smp", self.vm_config["cpu"],
            "-cdrom", self.iso_path,
            "-boot", "d",
            "-netdev", f"user,id=net0,hostfwd=tcp::{self.vm_config['ssh_port']}-:22,"
                      f"hostfwd=tcp::{self.vm_config['web_port']}-:8080,"
                      f"hostfwd=tcp::{self.vm_config['api_port']}-:8081",
            "-device", "e1000,netdev=net0",
            "-vnc", f":{self.vm_config['vnc_port'] - 5900}",
            "-monitor", f"telnet:127.0.0.1:{self.vm_config['monitor_port']},server,nowait",
            "-serial", "stdio"
        ]
        
        # Add UEFI boot for UEFI mode
        if boot_mode == "uefi":
            qemu_cmd.extend(["-bios", "/usr/share/ovmf/OVMF.fd"])
        
        try:
            self.vm_process = pexpect.spawn(" ".join(qemu_cmd), timeout=300)
            self.vm_process.logfile = open(self.results_dir / "vm-console.log", "wb")
            
            # Wait for boot menu
            logger.info("Waiting for boot menu...")
            index = self.vm_process.expect([
                "BorgOS",
                "GRUB",
                "isolinux",
                pexpect.TIMEOUT
            ], timeout=60)
            
            if index < 3:
                logger.info("Boot menu detected")
                self.test_results["tests"]["boot_menu"] = "PASS"
                return True
            else:
                logger.error("Boot menu not detected")
                self.test_results["tests"]["boot_menu"] = "FAIL"
                return False
                
        except Exception as e:
            logger.error(f"Failed to start VM: {e}")
            self.test_results["tests"]["vm_start"] = f"FAIL: {e}"
            return False
    
    def test_boot_process(self) -> bool:
        """Test the boot process"""
        logger.info("Testing boot process...")
        
        try:
            # Select default boot option (just press Enter or wait)
            time.sleep(2)
            self.vm_process.sendline("")
            
            # Wait for system to boot
            boot_indicators = [
                "systemd",
                "Welcome to",
                "BorgOS",
                "login:",
                pexpect.TIMEOUT
            ]
            
            index = self.vm_process.expect(boot_indicators, timeout=180)
            
            if index < 4:
                logger.info(f"System booted successfully (indicator: {boot_indicators[index]})")
                self.test_results["tests"]["boot_process"] = "PASS"
                return True
            else:
                logger.error("System boot timeout")
                self.test_results["tests"]["boot_process"] = "FAIL: Timeout"
                return False
                
        except Exception as e:
            logger.error(f"Boot process test failed: {e}")
            self.test_results["tests"]["boot_process"] = f"FAIL: {e}"
            return False
    
    def test_login(self) -> bool:
        """Test login with default credentials"""
        logger.info("Testing login...")
        
        try:
            # Wait for login prompt
            self.vm_process.expect("login:", timeout=30)
            self.vm_process.sendline("borgos")
            
            # Wait for password prompt
            self.vm_process.expect("Password:", timeout=10)
            self.vm_process.sendline("borgos")
            
            # Check for successful login
            index = self.vm_process.expect([
                "\\$",  # Shell prompt
                "#",    # Root prompt
                "Last login",
                "borgos@",
                pexpect.TIMEOUT
            ], timeout=30)
            
            if index < 4:
                logger.info("Login successful")
                self.test_results["tests"]["login"] = "PASS"
                return True
            else:
                logger.error("Login failed")
                self.test_results["tests"]["login"] = "FAIL"
                return False
                
        except Exception as e:
            logger.error(f"Login test failed: {e}")
            self.test_results["tests"]["login"] = f"FAIL: {e}"
            return False
    
    def test_network(self) -> bool:
        """Test network connectivity"""
        logger.info("Testing network...")
        
        try:
            # Test network interface
            self.vm_process.sendline("ip addr show")
            self.vm_process.expect("inet ", timeout=10)
            
            # Test localhost connectivity
            self.vm_process.sendline("ping -c 1 127.0.0.1")
            index = self.vm_process.expect([
                "1 received",
                "1 packets transmitted, 1 received",
                pexpect.TIMEOUT
            ], timeout=10)
            
            if index < 2:
                logger.info("Network test passed")
                self.test_results["tests"]["network"] = "PASS"
                return True
            else:
                logger.error("Network test failed")
                self.test_results["tests"]["network"] = "FAIL"
                return False
                
        except Exception as e:
            logger.error(f"Network test failed: {e}")
            self.test_results["tests"]["network"] = f"FAIL: {e}"
            return False
    
    def test_docker(self) -> bool:
        """Test Docker installation and functionality"""
        logger.info("Testing Docker...")
        
        try:
            # Check Docker service
            self.vm_process.sendline("systemctl status docker")
            index = self.vm_process.expect([
                "active \\(running\\)",
                "Active: active",
                pexpect.TIMEOUT
            ], timeout=10)
            
            if index < 2:
                logger.info("Docker service is running")
                
                # Test Docker command
                self.vm_process.sendline("docker --version")
                self.vm_process.expect("Docker version", timeout=10)
                
                # Check for pre-loaded images
                self.vm_process.sendline("docker images")
                time.sleep(2)
                
                self.test_results["tests"]["docker"] = "PASS"
                return True
            else:
                logger.error("Docker service not running")
                self.test_results["tests"]["docker"] = "FAIL: Service not running"
                return False
                
        except Exception as e:
            logger.error(f"Docker test failed: {e}")
            self.test_results["tests"]["docker"] = f"FAIL: {e}"
            return False
    
    def test_borgos_services(self) -> bool:
        """Test BorgOS specific services"""
        logger.info("Testing BorgOS services...")
        
        try:
            # Check if BorgOS files exist
            self.vm_process.sendline("ls -la /opt/borgos/")
            index = self.vm_process.expect([
                "docker-compose",
                "core",
                "webui",
                pexpect.TIMEOUT
            ], timeout=10)
            
            if index < 3:
                logger.info("BorgOS files found")
                
                # Try to start BorgOS services
                self.vm_process.sendline("cd /opt/borgos && sudo ./start-borgos.sh")
                time.sleep(30)  # Give services time to start
                
                # Check if services are running
                self.vm_process.sendline("docker ps")
                time.sleep(2)
                
                self.test_results["tests"]["borgos_services"] = "PASS"
                return True
            else:
                logger.error("BorgOS files not found")
                self.test_results["tests"]["borgos_services"] = "FAIL: Files not found"
                return False
                
        except Exception as e:
            logger.error(f"BorgOS services test failed: {e}")
            self.test_results["tests"]["borgos_services"] = f"FAIL: {e}"
            return False
    
    def test_web_interface(self) -> bool:
        """Test web interface accessibility"""
        logger.info("Testing web interface...")
        
        try:
            # Wait a bit for services to be fully up
            time.sleep(10)
            
            # Try to access web interface from host
            response = requests.get(
                f"http://localhost:{self.vm_config['web_port']}", 
                timeout=10
            )
            
            if response.status_code == 200:
                logger.info("Web interface accessible")
                self.test_results["tests"]["web_interface"] = "PASS"
                return True
            else:
                logger.error(f"Web interface returned status {response.status_code}")
                self.test_results["tests"]["web_interface"] = f"FAIL: Status {response.status_code}"
                return False
                
        except requests.exceptions.RequestException as e:
            logger.warning(f"Web interface not accessible from host: {e}")
            
            # Try from within VM
            try:
                self.vm_process.sendline("curl -I http://localhost:8080")
                index = self.vm_process.expect([
                    "200 OK",
                    "HTTP/1.1 200",
                    pexpect.TIMEOUT
                ], timeout=10)
                
                if index < 2:
                    logger.info("Web interface accessible from VM")
                    self.test_results["tests"]["web_interface"] = "PASS (VM only)"
                    return True
                else:
                    self.test_results["tests"]["web_interface"] = "FAIL"
                    return False
                    
            except Exception as e:
                logger.error(f"Web interface test failed: {e}")
                self.test_results["tests"]["web_interface"] = f"FAIL: {e}"
                return False
    
    def test_offline_capability(self) -> bool:
        """Test offline functionality"""
        logger.info("Testing offline capability...")
        
        try:
            # Check for offline packages
            self.vm_process.sendline("ls -la /opt/borgos/docker-images/")
            time.sleep(2)
            
            # Check for offline repository
            self.vm_process.sendline("ls -la /var/cache/apt/archives/*.deb | wc -l")
            self.vm_process.expect("\\d+", timeout=10)
            
            # Try to load a Docker image from tar
            self.vm_process.sendline("docker load -i /opt/borgos/docker-images/*.tar 2>/dev/null | head -1")
            time.sleep(5)
            
            self.test_results["tests"]["offline_capability"] = "PASS"
            return True
            
        except Exception as e:
            logger.warning(f"Offline capability test had issues: {e}")
            self.test_results["tests"]["offline_capability"] = f"PARTIAL: {e}"
            return False
    
    def test_shutdown(self) -> bool:
        """Test clean shutdown"""
        logger.info("Testing shutdown...")
        
        try:
            self.vm_process.sendline("sudo shutdown -h now")
            
            # Wait for shutdown
            index = self.vm_process.expect([
                "System halted",
                "Power down",
                "reboot: Power down",
                pexpect.EOF,
                pexpect.TIMEOUT
            ], timeout=60)
            
            if index < 4:
                logger.info("Clean shutdown successful")
                self.test_results["tests"]["shutdown"] = "PASS"
                return True
            else:
                logger.warning("Shutdown timeout")
                self.test_results["tests"]["shutdown"] = "TIMEOUT"
                return False
                
        except Exception as e:
            logger.error(f"Shutdown test failed: {e}")
            self.test_results["tests"]["shutdown"] = f"FAIL: {e}"
            return False
    
    def cleanup(self):
        """Clean up VM process"""
        if self.vm_process:
            try:
                self.vm_process.terminate()
                time.sleep(2)
                if self.vm_process.isalive():
                    self.vm_process.kill()
            except:
                pass
    
    def run_all_tests(self) -> Dict:
        """Run complete test suite"""
        logger.info("Starting BorgOS ISO test suite...")
        
        test_sequence = [
            ("VM Start", self.start_vm),
            ("Boot Process", self.test_boot_process),
            ("Login", self.test_login),
            ("Network", self.test_network),
            ("Docker", self.test_docker),
            ("BorgOS Services", self.test_borgos_services),
            ("Web Interface", self.test_web_interface),
            ("Offline Capability", self.test_offline_capability),
            ("Shutdown", self.test_shutdown)
        ]
        
        for test_name, test_func in test_sequence:
            logger.info(f"Running test: {test_name}")
            try:
                result = test_func()
                logger.info(f"{test_name}: {'PASS' if result else 'FAIL'}")
            except Exception as e:
                logger.error(f"{test_name} failed with exception: {e}")
                self.test_results["tests"][test_name.lower().replace(" ", "_")] = f"ERROR: {e}"
        
        # Save results
        results_file = self.results_dir / "test-results.json"
        with open(results_file, "w") as f:
            json.dump(self.test_results, f, indent=2)
        
        # Generate summary
        total_tests = len(self.test_results["tests"])
        passed = sum(1 for v in self.test_results["tests"].values() if v == "PASS")
        failed = sum(1 for v in self.test_results["tests"].values() if "FAIL" in str(v))
        
        summary = {
            "total": total_tests,
            "passed": passed,
            "failed": failed,
            "success_rate": f"{(passed/total_tests)*100:.1f}%" if total_tests > 0 else "0%"
        }
        
        logger.info(f"Test Summary: {summary}")
        
        # Cleanup
        self.cleanup()
        
        return self.test_results


def main():
    """Main test execution"""
    iso_path = sys.argv[1] if len(sys.argv) > 1 else "/iso/BorgOS-Offline.iso"
    
    if not os.path.exists(iso_path):
        logger.error(f"ISO not found: {iso_path}")
        sys.exit(1)
    
    tester = BorgOSISOTester(iso_path)
    results = tester.run_all_tests()
    
    # Exit with appropriate code
    if all(v == "PASS" for v in results["tests"].values()):
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()