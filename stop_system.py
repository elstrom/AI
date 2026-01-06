#!/usr/bin/env python3
"""
Script untuk menghentikan semua komponen sistem dengan graceful shutdown
"""

import os
import sys
import signal
import subprocess
import time
import logging
import argparse
import platform
from pathlib import Path
from typing import Dict, Any, List, Optional, Set
import psutil
import requests

# Detect OS
IS_WINDOWS = platform.system() == 'Windows'

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class SystemShutdown:
    """
    Kelas untuk mengelola shutdown semua komponen sistem
    """
    
    def __init__(self, config_path: str = "config.json"):
        """
        Inisialisasi SystemShutdown
        
        Args:
            config_path: Path ke file konfigurasi integrasi
        """
        self.base_dir = Path(__file__).parent.absolute()
        self.config_path = config_path
        self.config = self._load_config()
        self.processes_found: List[Dict[str, Any]] = []
        
        logger.info(f"SystemShutdown initialized. Base dir: {self.base_dir}")
    
    def _load_config(self) -> Dict[str, Any]:
        """
        Memuat konfigurasi integrasi dari file
        
        Returns:
            Dictionary konfigurasi
        """
        try:
            import json
            import yaml
            
            config_file = Path(self.config_path)
            if not config_file.exists():
                # Try from base_dir
                config_file = self.base_dir / self.config_path
                
            if not config_file.exists():
                logger.warning(f"Config file {self.config_path} not found in CWD or base dir, using defaults")
                return self._get_default_config()
            
            with open(config_file, 'r') as f:
                if config_file.suffix.lower() == '.json':
                    config = json.load(f)
                elif config_file.suffix.lower() in ['.yaml', '.yml']:
                    config = yaml.safe_load(f)
                else:
                    logger.error(f"Unsupported config file format: {config_file.suffix}")
                    return self._get_default_config()
            
            logger.info(f"Loaded config from {self.config_path}")
            return config
            
        except Exception as e:
            logger.error(f"Error loading config: {e}")
            return self._get_default_config()
    
    def _get_default_config(self) -> Dict[str, Any]:
        """
        Mendapatkan konfigurasi default sesuai aturan user (semua parameter di config)
        """
        return {
            "python_ai": {
                "process_names": ["python", "main.py"],
                "port": 50051,
                "graceful_shutdown_timeout": 30
            },
            "go_server": {
                "process_names": ["go", "main"],
                "port": 8080,
                "graceful_shutdown_timeout": 30
            },
            "shutdown": {
                "force_kill_after": 60,
                "cleanup_temp_files": True,
                "verify_shutdown": True
            }
        }
    
    def _find_processes_by_port(self, port: int) -> Set[int]:
        """
        Mencari PID proses yang menggunakan port tertentu
        """
        pids = set()
        try:
            for conn in psutil.net_connections(kind='inet'):
                if conn.laddr.port == port and conn.status == 'LISTEN':
                    if conn.pid:
                        pids.add(conn.pid)
        except (psutil.AccessDenied, psutil.NoSuchProcess):
            pass
        return pids

    def _find_processes_by_config(self, config_section: str) -> List[Dict[str, Any]]:
        """
        Mencari proses berdasarkan konfigurasi section (Generic)
        """
        if config_section not in self.config:
            logger.warning(f"Config section {config_section} not found")
            return []

        section_config = self.config[config_section]
        target_port = int(section_config.get("port", 0))
        # Support various formats: string or list
        process_names = section_config.get("process_names", [])
        if isinstance(process_names, str):
            process_names = [process_names]
            
        # Also check command args to match if available
        target_args = section_config.get("args", [])
        if isinstance(target_args, str):
            target_args = [target_args]

        found_processes = []
        found_pids = set()

        # 1. Strategy: Find by Port (Most Accurate)
        if target_port > 0:
            port_pids = self._find_processes_by_port(target_port)
            for pid in port_pids:
                if pid not in found_pids:
                    try:
                        proc = psutil.Process(pid)
                        found_processes.append(proc.as_dict(attrs=['pid', 'name', 'cmdline', 'create_time']))
                        found_pids.add(pid)
                    except (psutil.NoSuchProcess, psutil.AccessDenied):
                        continue

        # 2. Strategy: Find by Name/Cmdline patterns
        current_pid = os.getpid()
        for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
            try:
                if proc.info['pid'] == current_pid or proc.info['pid'] in found_pids:
                    continue

                name = (proc.info.get('name', '') or '').lower()
                cmdline = ' '.join(proc.info.get('cmdline', []) or []).lower()
                
                # Check if any of the process names match
                name_match = False
                for p_name in process_names:
                    if p_name.lower() in name or p_name.lower() in cmdline:
                        name_match = True
                        break
                
                # If name matches, ALSO check if args match (to avoid false positives)
                # If no args defined in config, name match is enough (but risky)
                args_match = False
                if target_args:
                    for arg in target_args:
                        if arg.lower() in cmdline:
                            args_match = True
                            break
                else:
                    # If no args specified, rely on name match
                    args_match = True 

                if name_match and args_match:
                    found_processes.append(proc.info)
                    found_pids.add(proc.info['pid'])

            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                pass
        
        # Remove duplicates
        unique_processes = []
        seen_pids = set()
        for p in found_processes:
            if p['pid'] not in seen_pids:
                unique_processes.append(p)
                seen_pids.add(p['pid'])

        logger.info(f"Found {len(unique_processes)} processes for {config_section}")
        return unique_processes

    def find_python_ai_processes(self) -> List[Dict[str, Any]]:
        return self._find_processes_by_config("python_ai")
    
    def find_go_server_processes(self) -> List[Dict[str, Any]]:
        return self._find_processes_by_config("go_server")
    
    def graceful_shutdown_python_ai(self) -> bool:
        """
        Melakukan graceful shutdown pada Python AI System
        """
        processes = self.find_python_ai_processes()
        if not processes:
            logger.info("No Python AI processes found")
            return True
        
        logger.info("Attempting graceful shutdown of Python AI processes...")
        
        success_count = 0
        timeout = self.config.get("python_ai", {}).get("graceful_shutdown_timeout", 30)
        
        for proc_info in processes:
            try:
                proc = psutil.Process(proc_info['pid'])
                logger.info(f"Terminating Python AI process {proc.pid}")
                proc.terminate()
                
                try:
                    proc.wait(timeout=timeout)
                    logger.info(f"Python AI process {proc.pid} stopped gracefully")
                    success_count += 1
                except psutil.TimeoutExpired:
                    logger.warning(f"Python AI process {proc.pid} did not stop within {timeout} seconds")
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                logger.warning(f"Could not terminate Python AI process {proc_info['pid']}")
        
        success = success_count == len(processes)
        return success
    
    def graceful_shutdown_go_server(self) -> bool:
        """
        Melakukan graceful shutdown pada Go Server
        """
        processes = self.find_go_server_processes()
        if not processes:
            logger.info("No Go Server processes found")
            return True
        
        logger.info("Attempting graceful shutdown of Go Server processes...")
        
        # Try HTTP shutdown first
        port = self.config.get("go_server", {}).get("port", 8080)
        host = "localhost"
        
        try:
            response = requests.post(f"http://{host}:{port}/shutdown", timeout=2)
            if response.status_code == 200:
                logger.info("Graceful shutdown request sent to Go Server")
                time.sleep(2)
        except:
            pass
        
        # Force kill/terminate logic
        success_count = 0
        for proc_info in processes:
            pid = proc_info['pid']
            try:
                if IS_WINDOWS:
                    subprocess.run(
                        ["taskkill", "/F", "/T", "/PID", str(pid)],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        timeout=5
                    )
                    time.sleep(0.5)
                    if not psutil.pid_exists(pid):
                        success_count += 1
                else:
                    proc = psutil.Process(pid)
                    proc.terminate()
                    try:
                        proc.wait(timeout=5)
                        success_count += 1
                    except psutil.TimeoutExpired:
                        proc.kill()
                        proc.wait(timeout=2)
                        success_count += 1
                        
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                success_count += 1
            except Exception as e:
                logger.warning(f"Error stopping Go Server process {pid}: {e}")
        
        success = success_count == len(processes)
        return success
    
    def force_kill_processes(self) -> bool:
        """
        Memaksa menghentikan proses yang masih berjalan
        """
        logger.info("Force killing remaining processes...")
        
        python_processes = self.find_python_ai_processes()
        go_processes = self.find_go_server_processes()
        
        all_processes = python_processes + go_processes
        if not all_processes:
            logger.info("No remaining processes to kill")
            return True
        
        success_count = 0
        for proc_info in all_processes:
            pid = proc_info['pid']
            try:
                if IS_WINDOWS:
                    logger.info(f"Force killing process {pid} (taskkill)")
                    subprocess.run(f"taskkill /F /T /PID {pid}", shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                else:
                    proc = psutil.Process(pid)
                    logger.info(f"Force killing process {pid} (kill)")
                    proc.kill()
                
                # Check outcome
                try:
                    if psutil.pid_exists(pid):
                        p = psutil.Process(pid)
                        p.wait(timeout=2)
                except:
                    pass
                
                if not psutil.pid_exists(pid):
                    success_count += 1
                    
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                success_count += 1
        
        return success_count == len(all_processes)
    
    def verify_shutdown(self) -> bool:
        """
        Memverifikasi bahwa semua proses telah dihentikan
        """
        if not self.config.get("shutdown", {}).get("verify_shutdown", True):
            return True
        
        logger.info("Verifying shutdown...")
        
        python_processes = self.find_python_ai_processes()
        go_processes = self.find_go_server_processes()
        
        all_processes = python_processes + go_processes
        
        if all_processes:
            logger.warning(f"Found {len(all_processes)} still running processes:")
            for proc_info in all_processes:
                logger.warning(f"  PID: {proc_info['pid']}, Name: {proc_info.get('name', 'unknown')}")
            return False
        
        logger.info("All processes have been successfully stopped")
        return True
    
    def cleanup_temp_files(self) -> bool:
        """
        Membersihkan file temporary
        """
        if not self.config.get("shutdown", {}).get("cleanup_temp_files", False):
            return True
        
        logger.info("Cleaning up temporary files...")
        
        # Define temp files relative to base_dir or absolute
        temp_files = ["tmp", "logs/app.log"] # Example, should be in config preferably but kept simple
        
        for file_path in temp_files:
            try:
                path = self.base_dir / file_path
                if path.exists():
                    if path.is_file():
                        path.unlink()
                    elif path.is_dir():
                        import shutil
                        shutil.rmtree(path)
            except Exception:
                pass
        
        return True
    
    def shutdown_all(self) -> bool:
        """
        Menghentikan semua komponen sistem
        """
        logger.info("Starting system shutdown...")
        
        self.graceful_shutdown_python_ai()
        self.graceful_shutdown_go_server()
        
        time.sleep(2)
        
        self.force_kill_processes()
        
        verify_success = self.verify_shutdown()
        
        self.cleanup_temp_files()
        
        if verify_success:
            logger.info("System shutdown completed successfully")
        else:
            logger.warning("System shutdown completed but some processes may still be running")
        
        return verify_success

def main():
    """
    Fungsi utama untuk menjalankan script
    """
    parser = argparse.ArgumentParser(description="Stop all system components")
    parser.add_argument("--config", default="config.json", 
                       help="Path to integration configuration file")
    parser.add_argument("--force", action="store_true",
                       help="Force kill processes without graceful shutdown")
    parser.add_argument("--verify", action="store_true",
                       help="Verify that all processes have been stopped")
    
    args = parser.parse_args()
    
    # Initialize and shutdown system
    shutdown = SystemShutdown(args.config)
    
    try:
        if args.force:
            logger.info("Force shutdown requested")
            success = shutdown.force_kill_processes()
            if args.verify:
                success = success and shutdown.verify_shutdown()
        else:
            success = shutdown.shutdown_all()
        
        if success:
            logger.info("System shutdown completed successfully")
            return 0
        else:
            logger.error("System shutdown failed")
            return 1
            
    except Exception as e:
        logger.error(f"Error during system shutdown: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())