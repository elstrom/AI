#!/usr/bin/env python3
"""
Script untuk menjalankan semua komponen sistem (Python AI dan Go server)
"""

import os
import sys
import subprocess
import time
import signal
import logging
import json
import yaml
import argparse
import platform
import socket
from pathlib import Path
from typing import Dict, Any, Optional, List
import threading
import atexit

# Detect OS
IS_WINDOWS = platform.system() == 'Windows'

# Setup logging
os.makedirs('logs', exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/system_integration.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class SystemIntegration:
    """
    Kelas untuk mengelola integrasi semua komponen sistem
    """
    
    def __init__(self, config_path: str = "config.json"):
        self.config_path = config_path
        self.processes: Dict[str, subprocess.Popen] = {}
        self.config = self._load_config()
        self.shutdown_flag = False
        self._cleanup_done = False  # Prevent double cleanup
        
        signal.signal(signal.SIGINT, self._signal_handler)
        if not IS_WINDOWS:
            signal.signal(signal.SIGTERM, self._signal_handler)
        
        atexit.register(self.cleanup)
        logger.info("SystemIntegration initialized")
    
    def _load_config(self) -> Dict[str, Any]:
        try:
            config_file = Path(self.config_path)
            if not config_file.exists():
                logger.warning(f"Config file {self.config_path} not found, using defaults")
                return self._get_default_config()
            
            with open(config_file, 'r') as f:
                if config_file.suffix.lower() == '.json':
                    config = json.load(f)
                elif config_file.suffix.lower() in ['.yaml', '.yml']:
                    config = yaml.safe_load(f)
                else:
                    return self._get_default_config()
            return config
        except Exception as e:
            logger.error(f"Error loading config: {e}")
            return self._get_default_config()
    
    def _get_default_config(self) -> Dict[str, Any]:
        return {
            "python_ai": {
                "enabled": True,
                "command": "python",
                "args": ["main.py"],
                "host": "[::]",
                "port": 50051,
                "wait_for_startup": True,
                "startup_timeout": 30
            },
            "go_server": {
                "enabled": True,
                "command": "go",
                "args": ["run", "cmd/server/main.go"],
                "host": "0.0.0.0",
                "port": 8080,
                "wait_for_startup": True,
                "startup_timeout": 30
            },
            "health_check": {
                "enabled": True,
                "interval": 10,
                "endpoints": ["http://localhost:8080/health"]
            }
        }
    
    def _signal_handler(self, signum, frame):
        logger.info(f"Received signal {signum}, shutting down...")
        self.shutdown_flag = True
        self.cleanup()
        sys.exit(0)

    def _check_port_open(self, host: str, port: int, timeout: float = 1.0) -> bool:
        """
        Simple TCP port check to verify if a service is listening.
        Handles both IPv4 and IPv6.
        """
        port = int(port)
        # Clean host for IPv6 if needed
        if host == "[::]":
            host = "::1" # Try localhost ipv6
        elif host == "0.0.0.0":
            host = "127.0.0.1" # Try localhost ipv4

        try:
            # Try connecting
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            result = sock.connect_ex((host, port))
            sock.close()
            return result == 0
        except:
            # Fallback for IPv6
            try:
                sock = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
                sock.settimeout(timeout)
                result = sock.connect_ex((host, port))
                sock.close()
                return result == 0
            except:
                return False

    def start_python_ai(self) -> bool:
        if not self.config["python_ai"]["enabled"]:
            return True
        
        logger.info("Starting Python AI System...")
        cmd = [self.config["python_ai"]["command"]]
        cmd.extend(self.config["python_ai"]["args"])
        
        # Add config/host/port args if they exist in config
        if "config" in self.config["python_ai"]:
            cmd.extend(["--config", self.config["python_ai"]["config"]])
        if "host" in self.config["python_ai"]:
            cmd.extend(["--host", self.config["python_ai"]["host"]])
        if "port" in self.config["python_ai"]:
            cmd.extend(["--port", str(self.config["python_ai"]["port"])])
        
        try:
            # Use PIPE for stdout/stderr to capture output if it fails
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1
            )
            self.processes["python_ai"] = process
            logger.info(f"Python AI System started with PID {process.pid}")
            
            # Intelligently log output from the process
            def log_pipe(pipe, level, prefix):
                for line in iter(pipe.readline, ''):
                    if self.shutdown_flag:
                        break
                    
                    line = line.strip()
                    if not line:
                        continue
                    
                    lower_line = line.lower()
                    
                    # Skip common gRPC warnings that are not actual errors
                    skip_patterns = [
                        "warning:",
                        "all log messages before absl",
                        "initializelog",
                        "addresses added out of total",
                        "failed to prepare server socket",
                        "bind: wsa error",
                        "only one usage of each socket address",
                        "grpc_status",
                        "chttp2_server.cc",
                        "i0000 00:00:",
                        "stderr",
                        "unknown:only",
                        "unavailable:bind",
                        "-- 10048",
                        "{children:",
                    ]
                    
                    if any(pattern in lower_line for pattern in skip_patterns):
                        continue  # Skip these warnings completely
                    
                    # Filter INFO level messages to DEBUG
                    if "info" in lower_line or any(msg in lower_line for msg in ["started", "initialized", "ready", "loading"]):
                        logger.debug(f"[{prefix}] {line}")
                    else:
                        # Only log actual errors
                        logger.log(level, f"[{prefix}] {line}")
                pipe.close()

            threading.Thread(target=log_pipe, args=(process.stdout, logging.DEBUG, "Python AI"), daemon=True).start()
            threading.Thread(target=log_pipe, args=(process.stderr, logging.ERROR, "Python AI"), daemon=True).start()
            
            if self.config["python_ai"].get("wait_for_startup", False):
                timeout = self.config["python_ai"].get("startup_timeout", 30)
                start_time = time.time()
                while time.time() - start_time < timeout:
                    if process.poll() is not None:
                        logger.error(f"Python AI process exited early with code {process.returncode}")
                        return False
                    
                    # Use TCP Port Check instead of complex GRPC check
                    port = self.config["python_ai"]["port"]
                    if self._check_port_open("localhost", port):
                        logger.info("Python AI System port is open and ready")
                        return True
                    time.sleep(1)
                
                logger.error("Python AI System start timed out")
                return False
            return True
        except Exception as e:
            logger.error(f"Failed to start Python AI: {e}")
            return False

    def start_go_server(self) -> bool:
        if not self.config["go_server"]["enabled"]:
            return True
        
        logger.info("Starting Go Server...")
        cmd = [self.config["go_server"]["command"]]
        cmd.extend(self.config["go_server"]["args"])
        
        if "config" in self.config["go_server"]:
            cmd.extend(["--config", self.config["go_server"]["config"]])
        
        try:
            cwd = "go_server"

            env = os.environ.copy()
            env["CGO_ENABLED"] = "0"

            kwargs = {
                "cwd": cwd,
                "stdout": subprocess.PIPE,
                "stderr": subprocess.PIPE,
                "text": True,
                "env": env,
                "bufsize": 1
            }
            if IS_WINDOWS:
                kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP

            process = subprocess.Popen(cmd, **kwargs)
            self.processes["go_server"] = process
            logger.info(f"Go Server started with PID {process.pid}")

            # Intelligently log output from the process
            def log_pipe(pipe, level, prefix):
                for line in iter(pipe.readline, ''):
                    if self.shutdown_flag:
                        break
                    
                    line = line.strip()
                    if not line:
                        continue
                    
                    lower_line = line.lower()
                    
                    # Skip common warnings and verbose logs
                    skip_patterns = [
                        "downloading",
                        "go: finding",
                        "go: extracting",
                        "using",
                        "websocket: discarding reader close error",
                        "io: read/write on closed pipe",
                    ]
                    
                    if any(pattern in lower_line for pattern in skip_patterns):
                        continue  # Skip these verbose logs
                    
                    # Filter INFO level messages to DEBUG
                    if "info" in lower_line or any(msg in lower_line for msg in ["started", "listening", "ready", "server"]):
                        logger.debug(f"[{prefix}] {line}")
                    else:
                        # Only log actual errors
                        logger.log(level, f"[{prefix}] {line}")
                pipe.close()

            threading.Thread(target=log_pipe, args=(process.stdout, logging.DEBUG, "Go Server"), daemon=True).start()
            threading.Thread(target=log_pipe, args=(process.stderr, logging.ERROR, "Go Server"), daemon=True).start()
            
            if self.config["go_server"].get("wait_for_startup", False):
                timeout = self.config["go_server"].get("startup_timeout", 30)
                start_time = time.time()
                while time.time() - start_time < timeout:
                    if process.poll() is not None:
                        logger.error(f"Go Server exited early with code {process.returncode}")
                        return False
                    
                    # Check HTTP port
                    if self._check_port_open("localhost", self.config["go_server"]["port"]):
                        logger.info("Go Server port is open and ready")
                        return True
                    time.sleep(1)

                logger.error("Go Server start timed out")
                return False
            return True
        except Exception as e:
            logger.error(f"Failed to start Go Server: {e}")
            return False

    def start_all(self) -> bool:
        logger.info("Starting all system components...")
        
        if not self.start_python_ai():
            return False
            
        if not self.start_go_server():
            return False
            
        if not self.start_ngrok():
            # We don't return False here because ngrok is usually optional
            logger.warning("Ngrok failed to start, systems will still be accessible locally")
            
        # Optional: Start health monitoring thread here if needed
        
        logger.info("=" * 60)
        logger.info("[OK] All systems started successfully")
        logger.info(f"  - Python AI System: localhost:{self.config['python_ai']['port']}")
        logger.info(f"  - Go Server: localhost:{self.config['go_server']['port']}")
        if "ngrok" in self.processes:
             logger.info(f"  - Ngrok Tunnel: Active (check your ngrok dashboard for URL)")
        logger.info("=" * 60)
        return True

    def start_ngrok(self) -> bool:
        if "ngrok" not in self.config or not self.config["ngrok"].get("enabled", False):
            return True
        
        logger.info("Starting Ngrok tunnel...")
        port = self.config["ngrok"].get("port", "8080")
        region = self.config["ngrok"].get("region", "ap")
        ngrok_exe = self.config["ngrok"].get("path", "ngrok")
        
        cmd = [ngrok_exe, "http", str(port), "--region", region]
        
        try:
            # Start ngrok in background
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if IS_WINDOWS else 0
            )
            self.processes["ngrok"] = process
            logger.info(f"Ngrok started with PID {process.pid} on port {port}")
            
            # Give it a second to initialize
            time.sleep(1)
            if process.poll() is not None:
                _, err = process.communicate()
                logger.error(f"Ngrok exited immediately: {err}")
                return False
                
            return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            logger.warning("Ngrok not found in PATH. Skipping ngrok tunnel.")
            return False
        except Exception as e:
            logger.error(f"Failed to start Ngrok: {e}")
            return False

    def cleanup(self):
        """Clean up all running processes"""
        if self._cleanup_done:
            return  # Already cleaned up
        
        self._cleanup_done = True
        logger.info("Cleaning up all processes...")
        
        # First, kill processes we started directly
        for name, process in list(self.processes.items()):
            if process.poll() is None:  # Process still running
                logger.info(f"Stopping {name} (PID: {process.pid})...")
                try:
                    if IS_WINDOWS:
                        subprocess.run(
                            ["taskkill", "/F", "/T", "/PID", str(process.pid)],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                            timeout=5
                        )
                        logger.info(f"[OK] {name} killed (Windows taskkill)")
                    else:
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                            logger.info(f"[OK] {name} terminated gracefully")
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait(timeout=2)
                            logger.info(f"[OK] {name} killed forcefully")
                except Exception as e:
                    logger.error(f"[ERROR] Error stopping {name}: {e}")
                    try:
                        process.kill()
                    except:
                        pass
        
        self.processes.clear()
        
        # Also find and kill any orphaned processes from previous runs
        try:
            import psutil
            
            current_pid = os.getpid()
            base_dir = os.path.dirname(os.path.abspath(__file__)).lower()
            
            # Kill Python AI processes (python main.py in our directory)
            for proc in psutil.process_iter(['pid', 'name', 'cmdline', 'cwd', 'exe']):
                try:
                    if proc.pid == current_pid:
                        continue
                    
                    name = (proc.info.get('name', '') or '').lower()
                    cmdline = ' '.join(proc.info.get('cmdline', []) or []).lower()
                    exe = (proc.info.get('exe', '') or '').lower()
                    
                    # Match Python processes running main.py in our directory
                    is_our_python = False
                    if 'python' in name:
                        # Check if it's running main.py from our directory
                        if 'main.py' in cmdline:
                            # Try to check if cwd or cmdline contains our path
                            try:
                                cwd = proc.cwd().lower() if hasattr(proc, 'cwd') else ''
                                # Check for ScanAI_server or just main.py in current structure
                                if 'scanai_server' in cwd or 'scanai_server' in cmdline:
                                    is_our_python = True
                                # Also check for ai_system in cmdline (common in args)
                                elif 'ai_system' in cwd or 'ai_system' in cmdline:
                                    is_our_python = True
                            except:
                                # If we can't get cwd, assume it's ours if it has AI system components in cmdline
                                if 'ai_system' in cmdline:
                                    is_our_python = True
                                elif 'main.py' in cmdline and 'grpc' not in cmdline:
                                    # Generic main.py - heuristic check
                                    is_our_python = True
                    
                    if is_our_python:
                        logger.info(f"Killing orphaned Python AI process {proc.pid}")
                        if IS_WINDOWS:
                            subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)],
                                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                         timeout=5)
                        else:
                            proc.kill()
                            
                except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                    pass
                except Exception:
                    pass
            
            # Kill Go server processes  
            for proc in psutil.process_iter(['pid', 'name', 'exe', 'cmdline']):
                try:
                    name = (proc.info.get('name', '') or '').lower()
                    exe = (proc.info.get('exe', '') or '').lower()
                    cmdline = ' '.join(proc.info.get('cmdline', []) or []).lower()
                    
                    is_our_go = False
                    # Match Go server executable or go run command
                    if 'go_server' in exe or 'go_server' in cmdline:
                        is_our_go = True
                    elif ('server.exe' in name or 'main.exe' in name) and 'go' in exe:
                        is_our_go = True
                    elif 'go.exe' in name and 'cmd/server' in cmdline:
                        is_our_go = True
                        
                    if is_our_go:
                        logger.info(f"Killing orphaned Go Server process {proc.pid}")
                        if IS_WINDOWS:
                            subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)],
                                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                         timeout=5)
                        else:
                            proc.kill()
                            
                except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                    pass
                except Exception:
                    pass
                    
        except ImportError:
            pass  # psutil not available, skip orphan cleanup
        except Exception as e:
            logger.warning(f"Error cleaning up orphaned processes: {e}")
        
        logger.info("[OK] All processes cleaned up")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="config.json")
    args = parser.parse_args()
    
    system = SystemIntegration(args.config)
    
    if system.start_all():
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            logger.info("Keyboard interrupt received")
    else:
        logger.error("System startup failed")
        sys.exit(1)

if __name__ == "__main__":
    main()