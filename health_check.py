#!/usr/bin/env python3
"""
Health Check untuk monitoring kesehatan sistem
"""

import os
import sys
import time
import json
import logging
import argparse
import threading
import requests
import grpc
import psutil
from pathlib import Path
from typing import Dict, Any, List, Optional, Union, Tuple
from datetime import datetime, timedelta
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('health_check.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class HealthCheck:
    """
    Kelas untuk melakukan health check pada semua komponen sistem
    """
    
    def __init__(self, config_path: str = "health_config.json"):
        """
        Inisialisasi HealthCheck
        
        Args:
            config_path: Path ke file konfigurasi health check
        """
        self.config_path = config_path
        self.config = self._load_config()
        self.health_status = {
            "overall": "unknown",
            "components": {},
            "last_check": None,
            "uptime": 0
        }
        self.start_time = time.time()
        self.alert_history = []
        self.running = False
        
        logger.info("HealthCheck initialized")
    
    def _load_config(self) -> Dict[str, Any]:
        """
        Memuat konfigurasi health check dari file
        
        Returns:
            Dictionary konfigurasi
        """
        try:
            config_file = Path(self.config_path)
            if not config_file.exists():
                logger.warning(f"Health config file {self.config_path} not found, using defaults")
                return self._get_default_config()
            
            with open(config_file, 'r') as f:
                if config_file.suffix.lower() == '.json':
                    config = json.load(f)
                else:
                    logger.error(f"Unsupported config file format: {config_file.suffix}")
                    return self._get_default_config()
            
            logger.info(f"Loaded health config from {self.config_path}")
            return config
            
        except Exception as e:
            logger.error(f"Error loading health config: {e}")
            return self._get_default_config()
    
    def _get_default_config(self) -> Dict[str, Any]:
        """
        Mendapatkan konfigurasi default
        
        Returns:
            Dictionary konfigurasi default
        """
        return {
            "check_interval": 30,
            "timeout": 10,
            "components": {
                "python_ai": {
                    "enabled": True,
                    "type": "grpc",
                    "host": "localhost",
                    "port": 50051,
                    "critical": True
                },
                "go_server": {
                    "enabled": True,
                    "type": "http",
                    "host": "localhost",
                    "port": 8080,
                    "endpoint": "/health",
                    "critical": True
                },
                "websocket": {
                    "enabled": True,
                    "type": "websocket",
                    "host": "localhost",
                    "port": 8080,
                    "endpoint": "/ws",
                    "critical": False
                },
                "system_resources": {
                    "enabled": True,
                    "type": "system",
                    "critical": False,
                    "thresholds": {
                        "cpu_percent": 80,
                        "memory_percent": 85,
                        "disk_percent": 90
                    }
                }
            },
            "alerts": {
                "enabled": True,
                "email": {
                    "enabled": False,
                    "smtp_server": "smtp.example.com",
                    "smtp_port": 587,
                    "username": "user@example.com",
                    "password": "password",
                    "from": "healthcheck@example.com",
                    "to": ["admin@example.com"],
                    "subject": "System Health Alert"
                },
                "webhook": {
                    "enabled": False,
                    "url": "https://hooks.slack.com/services/...",
                    "method": "POST",
                    "headers": {
                        "Content-Type": "application/json"
                    }
                },
                "cooldown": 300  # 5 minutes
            },
            "logging": {
                "level": "INFO",
                "file": "health_check.log",
                "status_file": "health_status.json"
            }
        }
    
    def check_python_ai_grpc(self) -> Dict[str, Any]:
        """
        Memeriksa kesehatan Python AI Server via gRPC
        
        Returns:
            Dictionary status health check
        """
        status = {
            "component": "python_ai",
            "status": "unknown",
            "response_time": 0,
            "error": None,
            "details": {}
        }
        
        try:
            # Connect to gRPC server
            host = self.config["components"]["python_ai"]["host"]
            port = self.config["components"]["python_ai"]["port"]
            
            start_time = time.time()
            channel = grpc.insecure_channel(f"{host}:{port}")
            
            try:
                # Try to connect with a timeout
                grpc.channel_ready_future(channel).result(timeout=self.config["timeout"])
                response_time = time.time() - start_time
                
                # Get server stats
                sys.path.append(str(Path(__file__).parent / "ai_system"))
                from ai_system.proto import ai_service_pb2, ai_service_pb2_grpc
                
                stub = ai_service_pb2_grpc.AIServiceStub(channel)
                
                # Get server stats
                empty_request = ai_service_pb2.Empty()
                stats_response = stub.GetServerStats(empty_request, timeout=self.config["timeout"])
                
                if stats_response.success:
                    status["status"] = "healthy"
                    status["response_time"] = response_time
                    status["details"] = {
                        "pool_size": stats_response.pool_size,
                        "in_use": stats_response.in_use,
                        "status_message": stats_response.status
                    }
                else:
                    status["status"] = "unhealthy"
                    status["error"] = stats_response.status
                
            except grpc.FutureTimeoutError:
                status["status"] = "unhealthy"
                status["error"] = "Connection timeout"
            finally:
                channel.close()
                
        except Exception as e:
            status["status"] = "unhealthy"
            status["error"] = str(e)
        
        return status
    
    def check_go_server_http(self) -> Dict[str, Any]:
        """
        Memeriksa kesehatan Go Server via HTTP
        
        Returns:
            Dictionary status health check
        """
        status = {
            "component": "go_server",
            "status": "unknown",
            "response_time": 0,
            "error": None,
            "details": {}
        }
        
        try:
            # Make HTTP request
            host = self.config["components"]["go_server"]["host"]
            port = self.config["components"]["go_server"]["port"]
            endpoint = self.config["components"]["go_server"]["endpoint"]
            
            url = f"http://{host}:{port}{endpoint}"
            
            start_time = time.time()
            response = requests.get(url, timeout=self.config["timeout"])
            response_time = time.time() - start_time
            
            if response.status_code == 200:
                status["status"] = "healthy"
                status["response_time"] = response_time
                status["details"] = {
                    "status_code": response.status_code,
                    "response_text": response.text
                }
            else:
                status["status"] = "unhealthy"
                status["error"] = f"HTTP {response.status_code}"
                
        except Exception as e:
            status["status"] = "unhealthy"
            status["error"] = str(e)
        
        return status
    
    def check_websocket_connection(self) -> Dict[str, Any]:
        """
        Memeriksa koneksi WebSocket
        
        Returns:
            Dictionary status health check
        """
        status = {
            "component": "websocket",
            "status": "unknown",
            "response_time": 0,
            "error": None,
            "details": {}
        }
        
        try:
            import websocket
            
            # Connect to WebSocket
            host = self.config["components"]["websocket"]["host"]
            port = self.config["components"]["websocket"]["port"]
            endpoint = self.config["components"]["websocket"]["endpoint"]
            
            ws_url = f"ws://{host}:{port}{endpoint}"
            
            start_time = time.time()
            ws = websocket.create_connection(ws_url, timeout=self.config["timeout"])
            response_time = time.time() - start_time
            
            # Close connection
            ws.close()
            
            status["status"] = "healthy"
            status["response_time"] = response_time
            status["details"] = {
                "connection_successful": True
            }
            
        except Exception as e:
            status["status"] = "unhealthy"
            status["error"] = str(e)
        
        return status
    
    def check_system_resources(self) -> Dict[str, Any]:
        """
        Memeriksa sumber daya sistem
        
        Returns:
            Dictionary status health check
        """
        status = {
            "component": "system_resources",
            "status": "unknown",
            "response_time": 0,
            "error": None,
            "details": {}
        }
        
        try:
            start_time = time.time()
            
            # Get system metrics
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
            
            response_time = time.time() - start_time
            
            # Get thresholds
            thresholds = self.config["components"]["system_resources"]["thresholds"]
            
            # Check if any resource is above threshold
            unhealthy = False
            issues = []
            
            if cpu_percent > thresholds["cpu_percent"]:
                unhealthy = True
                issues.append(f"CPU usage is {cpu_percent}% (threshold: {thresholds['cpu_percent']}%)")
            
            if memory.percent > thresholds["memory_percent"]:
                unhealthy = True
                issues.append(f"Memory usage is {memory.percent}% (threshold: {thresholds['memory_percent']}%)")
            
            if disk.percent > thresholds["disk_percent"]:
                unhealthy = True
                issues.append(f"Disk usage is {disk.percent}% (threshold: {thresholds['disk_percent']}%)")
            
            status["status"] = "unhealthy" if unhealthy else "healthy"
            status["response_time"] = response_time
            status["details"] = {
                "cpu_percent": cpu_percent,
                "memory_percent": memory.percent,
                "disk_percent": disk.percent,
                "issues": issues
            }
            
            if issues:
                status["error"] = "; ".join(issues)
                
        except Exception as e:
            status["status"] = "unhealthy"
            status["error"] = str(e)
        
        return status
    
    def check_all_components(self) -> Dict[str, Any]:
        """
        Memeriksa semua komponen sistem
        
        Returns:
            Dictionary status health check untuk semua komponen
        """
        results = {
            "timestamp": time.time(),
            "datetime": datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            "components": {}
        }
        
        # Check each component
        components = self.config["components"]
        
        if components["python_ai"]["enabled"]:
            results["components"]["python_ai"] = self.check_python_ai_grpc()
        
        if components["go_server"]["enabled"]:
            results["components"]["go_server"] = self.check_go_server_http()
        
        if components["websocket"]["enabled"]:
            results["components"]["websocket"] = self.check_websocket_connection()
        
        if components["system_resources"]["enabled"]:
            results["components"]["system_resources"] = self.check_system_resources()
        
        # Determine overall status
        overall_status = "healthy"
        critical_failures = []
        
        for name, component in components.items():
            if component["enabled"] and component["critical"]:
                component_result = results["components"].get(name)
                if component_result and component_result["status"] != "healthy":
                    overall_status = "unhealthy"
                    critical_failures.append(name)
        
        # Update health status
        self.health_status["overall"] = overall_status
        self.health_status["components"] = results["components"]
        self.health_status["last_check"] = results["timestamp"]
        self.health_status["uptime"] = time.time() - self.start_time
        
        # Add critical failures to results
        if critical_failures:
            results["critical_failures"] = critical_failures
        
        return results
    
    def send_alert(self, status: Dict[str, Any]) -> bool:
        """
        Mengirim alert berdasarkan status health check
        
        Args:
            status: Status health check
            
        Returns:
            True jika alert berhasil dikirim, False jika gagal
        """
        if not self.config["alerts"]["enabled"]:
            logger.info("Alerts are disabled in config")
            return True
        
        # Check if we should send alert (only for unhealthy status)
        if status["overall"] == "healthy":
            return True
        
        # Check cooldown period
        now = time.time()
        cooldown = self.config["alerts"]["cooldown"]
        
        # Check if we've sent an alert recently
        for alert in self.alert_history:
            if now - alert["timestamp"] < cooldown:
                logger.info("Alert cooldown period active, not sending alert")
                return True
        
        # Send email alert
        email_success = True
        if self.config["alerts"]["email"]["enabled"]:
            email_success = self._send_email_alert(status)
        
        # Send webhook alert
        webhook_success = True
        if self.config["alerts"]["webhook"]["enabled"]:
            webhook_success = self._send_webhook_alert(status)
        
        # Record alert in history
        self.alert_history.append({
            "timestamp": now,
            "status": status["overall"],
            "email_sent": email_success,
            "webhook_sent": webhook_success
        })
        
        # Keep only recent alerts
        self.alert_history = [a for a in self.alert_history if now - a["timestamp"] < 86400]  # 24 hours
        
        return email_success and webhook_success
    
    def _send_email_alert(self, status: Dict[str, Any]) -> bool:
        """
        Mengirim alert via email
        
        Args:
            status: Status health check
            
        Returns:
            True jika email berhasil dikirim, False jika gagal
        """
        try:
            email_config = self.config["alerts"]["email"]
            
            # Create message
            msg = MIMEMultipart()
            msg['From'] = email_config["from"]
            msg['To'] = ", ".join(email_config["to"])
            msg['Subject'] = email_config["subject"]
            
            # Create body
            body = f"""
System Health Alert

Overall Status: {status['overall'].upper()}
Time: {status['datetime']}

Component Status:
"""
            
            for name, component in status["components"].items():
                body += f"\n{name}: {component['status'].upper()}"
                if component.get("error"):
                    body += f" - {component['error']}"
            
            if "critical_failures" in status:
                body += f"\n\nCritical Failures: {', '.join(status['critical_failures'])}"
            
            msg.attach(MIMEText(body, 'plain'))
            
            # Send email
            server = smtplib.SMTP(email_config["smtp_server"], email_config["smtp_port"])
            server.starttls()
            server.login(email_config["username"], email_config["password"])
            text = msg.as_string()
            server.sendmail(email_config["from"], email_config["to"], text)
            server.quit()
            
            logger.info("Email alert sent successfully")
            return True
            
        except Exception as e:
            logger.error(f"Error sending email alert: {e}")
            return False
    
    def _send_webhook_alert(self, status: Dict[str, Any]) -> bool:
        """
        Mengirim alert via webhook
        
        Args:
            status: Status health check
            
        Returns:
            True jika webhook berhasil dikirim, False jika gagal
        """
        try:
            webhook_config = self.config["alerts"]["webhook"]
            
            # Create payload
            payload = {
                "text": f"System Health Alert: {status['overall'].upper()}",
                "attachments": [
                    {
                        "color": "danger" if status["overall"] == "unhealthy" else "good",
                        "title": "System Health Status",
                        "fields": [
                            {
                                "title": "Overall Status",
                                "value": status["overall"].upper(),
                                "short": True
                            },
                            {
                                "title": "Time",
                                "value": status["datetime"],
                                "short": True
                            }
                        ]
                    }
                ]
            }
            
            # Add component status
            fields = []
            for name, component in status["components"].items():
                fields.append({
                    "title": name.replace("_", " ").title(),
                    "value": component["status"].upper(),
                    "short": True
                })
            
            payload["attachments"][0]["fields"].extend(fields)
            
            # Send webhook
            response = requests.post(
                webhook_config["url"],
                json=payload,
                headers=webhook_config.get("headers", {}),
                timeout=10
            )
            
            if response.status_code == 200:
                logger.info("Webhook alert sent successfully")
                return True
            else:
                logger.error(f"Webhook returned status code {response.status_code}")
                return False
                
        except Exception as e:
            logger.error(f"Error sending webhook alert: {e}")
            return False
    
    def save_status(self, status: Dict[str, Any]) -> bool:
        """
        Menyimpan status health check ke file
        
        Args:
            status: Status health check
            
        Returns:
            True jika berhasil, False jika gagal
        """
        try:
            status_file = self.config["logging"]["status_file"]
            
            with open(status_file, 'w') as f:
                json.dump(status, f, indent=2)
            
            logger.debug(f"Health status saved to {status_file}")
            return True
            
        except Exception as e:
            logger.error(f"Error saving health status: {e}")
            return False
    
    def run_health_check_loop(self):
        """
        Loop untuk menjalankan health check secara berkala
        """
        logger.info("Starting health check loop...")
        
        self.running = True
        
        while self.running:
            try:
                # Run health check
                status = self.check_all_components()
                
                # Log status
                logger.info(f"Overall health status: {status['overall']}")
                for name, component in status["components"].items():
                    logger.debug(f"{name}: {component['status']}")
                
                # Save status
                self.save_status(status)
                
                # Send alert if needed
                self.send_alert(status)
                
                # Sleep until next check
                time.sleep(self.config["check_interval"])
                
            except Exception as e:
                logger.error(f"Error in health check loop: {e}")
                time.sleep(5)  # Wait before retrying
        
        logger.info("Health check loop stopped")
    
    def start(self):
        """
        Memulai health check
        """
        logger.info("Starting health check...")
        
        # Run initial health check
        status = self.check_all_components()
        logger.info(f"Initial health status: {status['overall']}")
        
        # Save status
        self.save_status(status)
        
        # Start health check loop in a separate thread
        self.health_check_thread = threading.Thread(
            target=self.run_health_check_loop,
            daemon=True
        )
        self.health_check_thread.start()
    
    def stop(self):
        """
        Menghentikan health check
        """
        logger.info("Stopping health check...")
        
        self.running = False
        
        # Wait for thread to finish
        if hasattr(self, 'health_check_thread') and self.health_check_thread.is_alive():
            self.health_check_thread.join(timeout=5)
        
        logger.info("Health check stopped")

def main():
    """
    Fungsi utama untuk menjalankan script
    """
    parser = argparse.ArgumentParser(description="Monitor system health")
    parser.add_argument("--config", default="health_config.json", 
                       help="Path to health configuration file")
    parser.add_argument("--create-config", action="store_true",
                       help="Create default health configuration file")
    parser.add_argument("--once", action="store_true",
                       help="Run health check once and exit")
    parser.add_argument("--status", action="store_true",
                       help="Show current health status and exit")
    
    args = parser.parse_args()
    
    # Create default config if requested
    if args.create_config:
        config_path = Path(args.config)
        if config_path.exists():
            logger.warning(f"Health config file {config_path} already exists")
        else:
            health_check = HealthCheck(args.config)
            default_config = health_check._get_default_config()
            
            with open(config_path, 'w') as f:
                json.dump(default_config, f, indent=2)
            
            logger.info(f"Created default health config file: {config_path}")
            return 0
    
    # Initialize health check
    health_check = HealthCheck(args.config)
    
    try:
        if args.status:
            # Just show current status
            status = health_check.check_all_components()
            print(f"Overall health status: {status['overall']}")
            for name, component in status["components"].items():
                print(f"{name}: {component['status']}")
            return 0
        
        if args.once:
            # Run health check once
            status = health_check.check_all_components()
            health_check.save_status(status)
            
            if status["overall"] == "healthy":
                logger.info("All components are healthy")
                return 0
            else:
                logger.warning("Some components are unhealthy")
                return 1
        
        # Start continuous health monitoring
        health_check.start()
        
        # Keep script running
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            logger.info("Received keyboard interrupt, stopping health check...")
            health_check.stop()
        
        return 0
        
    except Exception as e:
        logger.error(f"Error running health check: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())