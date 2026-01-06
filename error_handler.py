#!/usr/bin/env python3
"""
Error handling yang robust untuk seluruh sistem
"""

import os
import sys
import time
import logging
import json
import traceback
import functools
import inspect
from typing import Dict, Any, List, Optional, Union, Callable, Type
from pathlib import Path
from datetime import datetime
from enum import Enum

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('error_handler.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class ErrorLevel(Enum):
    """Level error"""
    DEBUG = "DEBUG"
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"
    CRITICAL = "CRITICAL"

class ErrorCategory(Enum):
    """Kategori error"""
    NETWORK = "NETWORK"
    FILE_SYSTEM = "FILE_SYSTEM"
    DATABASE = "DATABASE"
    CONFIGURATION = "CONFIGURATION"
    AUTHENTICATION = "AUTHENTICATION"
    AUTHORIZATION = "AUTHORIZATION"
    VALIDATION = "VALIDATION"
    BUSINESS_LOGIC = "BUSINESS_LOGIC"
    EXTERNAL_SERVICE = "EXTERNAL_SERVICE"
    SYSTEM_RESOURCE = "SYSTEM_RESOURCE"
    UNKNOWN = "UNKNOWN"

class SystemError(Exception):
    """
    Base class untuk semua system error
    """
    
    def __init__(self, 
                 message: str, 
                 level: ErrorLevel = ErrorLevel.ERROR,
                 category: ErrorCategory = ErrorCategory.UNKNOWN,
                 details: Optional[Dict[str, Any]] = None,
                 cause: Optional[Exception] = None):
        """
        Inisialisasi SystemError
        
        Args:
            message: Pesan error
            level: Level error
            category: Kategori error
            details: Detail tambahan error
            cause: Penyebab error (exception lain)
        """
        super().__init__(message)
        self.message = message
        self.level = level
        self.category = category
        self.details = details or {}
        self.cause = cause
        self.timestamp = datetime.now()
        self.stack_trace = traceback.format_exc()
        
        # Extract module and function information
        frame = inspect.currentframe()
        try:
            while frame:
                if frame.f_code.co_name != '<module>':
                    self.module = frame.f_globals.get('__name__', 'unknown')
                    self.function = frame.f_code.co_name
                    self.line_no = frame.f_lineno
                    break
                frame = frame.f_back
        finally:
            del frame

class NetworkError(SystemError):
    """Error terkait jaringan"""
    
    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None, cause: Optional[Exception] = None):
        super().__init__(message, ErrorLevel.ERROR, ErrorCategory.NETWORK, details, cause)

class FileSystemError(SystemError):
    """Error terkait file system"""
    
    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None, cause: Optional[Exception] = None):
        super().__init__(message, ErrorLevel.ERROR, ErrorCategory.FILE_SYSTEM, details, cause)

class ConfigurationError(SystemError):
    """Error terkait konfigurasi"""
    
    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None, cause: Optional[Exception] = None):
        super().__init__(message, ErrorLevel.ERROR, ErrorCategory.CONFIGURATION, details, cause)

class ValidationError(SystemError):
    """Error terkait validasi"""
    
    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None, cause: Optional[Exception] = None):
        super().__init__(message, ErrorLevel.WARNING, ErrorCategory.VALIDATION, details, cause)

class ExternalServiceError(SystemError):
    """Error terkait external service"""
    
    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None, cause: Optional[Exception] = None):
        super().__init__(message, ErrorLevel.ERROR, ErrorCategory.EXTERNAL_SERVICE, details, cause)

class SystemResourceError(SystemError):
    """Error terkait sumber daya sistem"""
    
    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None, cause: Optional[Exception] = None):
        super().__init__(message, ErrorLevel.ERROR, ErrorCategory.SYSTEM_RESOURCE, details, cause)

class ErrorHandler:
    """
    Handler untuk mengelola error di seluruh sistem
    """
    
    def __init__(self, config_path: str = "error_handler_config.json"):
        """
        Inisialisasi ErrorHandler
        
        Args:
            config_path: Path ke file konfigurasi error handler
        """
        self.config_path = config_path
        self.config = self._load_config()
        self.error_history = []
        self.error_stats = {
            "total_errors": 0,
            "by_level": {},
            "by_category": {},
            "by_module": {}
        }
        
        logger.info("ErrorHandler initialized")
    
    def _load_config(self) -> Dict[str, Any]:
        """
        Memuat konfigurasi error handler dari file
        
        Returns:
            Dictionary konfigurasi
        """
        try:
            config_file = Path(self.config_path)
            if not config_file.exists():
                logger.warning(f"Error handler config file {self.config_path} not found, using defaults")
                return self._get_default_config()
            
            with open(config_file, 'r') as f:
                if config_file.suffix.lower() == '.json':
                    config = json.load(f)
                else:
                    logger.error(f"Unsupported config file format: {config_file.suffix}")
                    return self._get_default_config()
            
            logger.info(f"Loaded error handler config from {self.config_path}")
            return config
            
        except Exception as e:
            logger.error(f"Error loading error handler config: {e}")
            return self._get_default_config()
    
    def _get_default_config(self) -> Dict[str, Any]:
        """
        Mendapatkan konfigurasi default
        
        Returns:
            Dictionary konfigurasi default
        """
        return {
            "logging": {
                "level": "INFO",
                "file": "error_handler.log",
                "max_history": 1000
            },
            "handling": {
                "retry_attempts": 3,
                "retry_delay": 1.0,
                "circuit_breaker_threshold": 5,
                "circuit_breaker_timeout": 60.0
            },
            "notification": {
                "enabled": True,
                "levels": ["ERROR", "CRITICAL"],
                "channels": ["console", "file"],
                "webhook": {
                    "enabled": False,
                    "url": "https://hooks.slack.com/services/...",
                    "method": "POST",
                    "headers": {
                        "Content-Type": "application/json"
                    }
                }
            },
            "recovery": {
                "enabled": True,
                "actions": ["restart_service", "clear_cache", "free_memory"]
            }
        }
    
    def handle_error(self, error: Exception, context: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """
        Menangani error
        
        Args:
            error: Error yang akan ditangani
            context: Konteks tambahan
            
        Returns:
            Dictionary hasil penanganan error
        """
        # Convert to SystemError if not already
        if not isinstance(error, SystemError):
            if isinstance(error, ConnectionError) or isinstance(error, TimeoutError):
                system_error = NetworkError(str(error), cause=error)
            elif isinstance(error, FileNotFoundError) or isinstance(error, PermissionError):
                system_error = FileSystemError(str(error), cause=error)
            elif isinstance(error, ValueError) or isinstance(error, TypeError):
                system_error = ValidationError(str(error), cause=error)
            elif isinstance(error, MemoryError) or isinstance(error, OSError):
                system_error = SystemResourceError(str(error), cause=error)
            else:
                system_error = SystemError(str(error), cause=error)
        else:
            system_error = error
        
        # Add context to details
        if context:
            system_error.details.update(context)
        
        # Log error
        self._log_error(system_error)
        
        # Update stats
        self._update_stats(system_error)
        
        # Add to history
        self._add_to_history(system_error)
        
        # Send notification if needed
        self._send_notification(system_error)
        
        # Attempt recovery if needed
        recovery_result = self._attempt_recovery(system_error)
        
        # Return handling result
        result = {
            "error": {
                "message": system_error.message,
                "level": system_error.level.value,
                "category": system_error.category.value,
                "module": getattr(system_error, 'module', 'unknown'),
                "function": getattr(system_error, 'function', 'unknown'),
                "line_no": getattr(system_error, 'line_no', 0),
                "timestamp": system_error.timestamp.isoformat(),
                "details": system_error.details,
                "stack_trace": system_error.stack_trace
            },
            "recovery": recovery_result
        }
        
        return result
    
    def _log_error(self, error: SystemError):
        """
        Mencatat error ke log
        
        Args:
            error: Error yang akan dicatat
        """
        # Map error level to logging level
        level_map = {
            ErrorLevel.DEBUG: logging.DEBUG,
            ErrorLevel.INFO: logging.INFO,
            ErrorLevel.WARNING: logging.WARNING,
            ErrorLevel.ERROR: logging.ERROR,
            ErrorLevel.CRITICAL: logging.CRITICAL
        }
        
        log_level = level_map.get(error.level, logging.ERROR)
        
        # Create logger for module
        module_logger = logging.getLogger(error.module)
        
        # Log error
        module_logger.log(
            log_level,
            f"{error.category.value}: {error.message}",
            extra={
                "error_category": error.category.value,
                "error_level": error.level.value,
                "error_details": error.details,
                "error_stack_trace": error.stack_trace
            }
        )
    
    def _update_stats(self, error: SystemError):
        """
        Update statistik error
        
        Args:
            error: Error yang akan diupdate ke statistik
        """
        # Increment total errors
        self.error_stats["total_errors"] += 1
        
        # Update by level
        level = error.level.value
        if level not in self.error_stats["by_level"]:
            self.error_stats["by_level"][level] = 0
        self.error_stats["by_level"][level] += 1
        
        # Update by category
        category = error.category.value
        if category not in self.error_stats["by_category"]:
            self.error_stats["by_category"][category] = 0
        self.error_stats["by_category"][category] += 1
        
        # Update by module
        module = getattr(error, 'module', 'unknown')
        if module not in self.error_stats["by_module"]:
            self.error_stats["by_module"][module] = 0
        self.error_stats["by_module"][module] += 1
    
    def _add_to_history(self, error: SystemError):
        """
        Menambahkan error ke history
        
        Args:
            error: Error yang akan ditambahkan
        """
        # Create error record
        error_record = {
            "timestamp": error.timestamp.isoformat(),
            "level": error.level.value,
            "category": error.category.value,
            "module": getattr(error, 'module', 'unknown'),
            "function": getattr(error, 'function', 'unknown'),
            "line_no": getattr(error, 'line_no', 0),
            "message": error.message,
            "details": error.details,
            "stack_trace": error.stack_trace
        }
        
        # Add to history
        self.error_history.append(error_record)
        
        # Limit history size
        max_history = self.config["logging"]["max_history"]
        if len(self.error_history) > max_history:
            self.error_history = self.error_history[-max_history:]
    
    def _send_notification(self, error: SystemError):
        """
        Mengirim notifikasi error
        
        Args:
            error: Error yang akan dikirim notifikasinya
        """
        if not self.config["notification"]["enabled"]:
            return
        
        # Check if error level is in notification levels
        if error.level.value not in self.config["notification"]["levels"]:
            return
        
        # Send webhook notification
        if self.config["notification"]["webhook"]["enabled"]:
            self._send_webhook_notification(error)
    
    def _send_webhook_notification(self, error: SystemError):
        """
        Mengirim notifikasi error via webhook
        
        Args:
            error: Error yang akan dikirim notifikasinya
        """
        try:
            import requests
            
            webhook_config = self.config["notification"]["webhook"]
            
            # Create payload
            payload = {
                "text": f"Error Alert: {error.level.value} - {error.category.value}",
                "attachments": [
                    {
                        "color": "danger" if error.level == ErrorLevel.CRITICAL else "warning",
                        "title": "Error Details",
                        "fields": [
                            {
                                "title": "Level",
                                "value": error.level.value,
                                "short": True
                            },
                            {
                                "title": "Category",
                                "value": error.category.value,
                                "short": True
                            },
                            {
                                "title": "Module",
                                "value": getattr(error, 'module', 'unknown'),
                                "short": True
                            },
                            {
                                "title": "Function",
                                "value": getattr(error, 'function', 'unknown'),
                                "short": True
                            },
                            {
                                "title": "Message",
                                "value": error.message,
                                "short": False
                            }
                        ]
                    }
                ]
            }
            
            # Send webhook
            response = requests.post(
                webhook_config["url"],
                json=payload,
                headers=webhook_config.get("headers", {}),
                timeout=10
            )
            
            if response.status_code == 200:
                logger.info("Error notification sent successfully")
            else:
                logger.error(f"Failed to send error notification: {response.status_code}")
                
        except Exception as e:
            logger.error(f"Error sending error notification: {e}")
    
    def _attempt_recovery(self, error: SystemError) -> Dict[str, Any]:
        """
        Mencoba recovery dari error
        
        Args:
            error: Error yang akan di-recover
            
        Returns:
            Dictionary hasil recovery
        """
        if not self.config["recovery"]["enabled"]:
            return {"attempted": False, "actions": []}
        
        recovery_actions = []
        successful_actions = []
        
        # Determine recovery actions based on error category
        if error.category == ErrorCategory.SYSTEM_RESOURCE:
            if "free_memory" in self.config["recovery"]["actions"]:
                # Try to free memory
                try:
                    import gc
                    gc.collect()
                    successful_actions.append("free_memory")
                except:
                    pass
        
        if error.category == ErrorCategory.NETWORK:
            if "restart_service" in self.config["recovery"]["actions"]:
                # Try to restart service (placeholder)
                successful_actions.append("restart_service")
        
        if error.category == ErrorCategory.FILE_SYSTEM:
            if "clear_cache" in self.config["recovery"]["actions"]:
                # Try to clear cache (placeholder)
                successful_actions.append("clear_cache")
        
        return {
            "attempted": True,
            "actions": recovery_actions,
            "successful_actions": successful_actions
        }
    
    def get_error_stats(self) -> Dict[str, Any]:
        """
        Mendapatkan statistik error
        
        Returns:
            Dictionary statistik error
        """
        return self.error_stats.copy()
    
    def get_error_history(self, limit: Optional[int] = None) -> List[Dict[str, Any]]:
        """
        Mendapatkan history error
        
        Args:
            limit: Batasan jumlah history yang dikembalikan
            
        Returns:
            List history error
        """
        if limit is None:
            return self.error_history.copy()
        else:
            return self.error_history[-limit:]
    
    def export_error_report(self, file_path: str) -> bool:
        """
        Mengekspor laporan error ke file
        
        Args:
            file_path: Path file laporan
            
        Returns:
            True jika berhasil, False jika gagal
        """
        try:
            report = {
                "timestamp": datetime.now().isoformat(),
                "stats": self.error_stats,
                "history": self.error_history
            }
            
            with open(file_path, 'w') as f:
                json.dump(report, f, indent=2)
            
            logger.info(f"Error report exported to {file_path}")
            return True
            
        except Exception as e:
            logger.error(f"Error exporting error report: {e}")
            return False
    
    def clear_error_history(self):
        """
        Membersihkan history error
        """
        self.error_history.clear()
        logger.info("Error history cleared")

# Global error handler instance
_error_handler = None

def get_error_handler(config_path: str = "error_handler_config.json") -> ErrorHandler:
    """
    Mendapatkan global error handler instance
    
    Args:
        config_path: Path ke file konfigurasi error handler
        
    Returns:
        ErrorHandler instance
    """
    global _error_handler
    if _error_handler is None:
        _error_handler = ErrorHandler(config_path)
    return _error_handler

def handle_errors(error_level: ErrorLevel = ErrorLevel.ERROR, 
                error_category: ErrorCategory = ErrorCategory.UNKNOWN,
                retry: bool = False,
                retry_attempts: Optional[int] = None,
                retry_delay: Optional[float] = None):
    """
    Decorator untuk menangani error pada fungsi
    
    Args:
        error_level: Level error default
        error_category: Kategori error default
        retry: Apakah akan mencoba retry jika error
        retry_attempts: Jumlah maksimum retry
        retry_delay: Delay antara retry dalam detik
        
    Returns:
        Decorator function
    """
    def decorator(func):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            # Get error handler
            error_handler = get_error_handler()
            
            # Get retry configuration
            config = error_handler.config["handling"]
            should_retry = retry
            attempts = retry_attempts or config["retry_attempts"]
            delay = retry_delay or config["retry_delay"]
            
            # Try to execute function
            last_error = None
            for attempt in range(attempts + 1):  # +1 for initial attempt
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    last_error = e
                    
                    # Handle error
                    context = {
                        "function": func.__name__,
                        "attempt": attempt + 1,
                        "max_attempts": attempts + 1
                    }
                    
                    result = error_handler.handle_error(e, context)
                    
                    # If not retrying or last attempt, re-raise
                    if not should_retry or attempt == attempts:
                        raise e
                    
                    # Wait before retry
                    if delay > 0:
                        time.sleep(delay)
            
            # If we get here, all retries failed
            raise last_error
        
        return wrapper
    return decorator

def safe_execute(func: Callable, 
                *args, 
                error_level: ErrorLevel = ErrorLevel.ERROR,
                error_category: ErrorCategory = ErrorCategory.UNKNOWN,
                default_return: Any = None,
                **kwargs) -> Any:
    """
    Menjalankan fungsi dengan aman (menangani error)
    
    Args:
        func: Fungsi yang akan dijalankan
        *args: Argumen posisi fungsi
        error_level: Level error default
        error_category: Kategori error default
        default_return: Nilai default yang dikembalikan jika error
        **kwargs: Argumen kata kunci fungsi
        
    Returns:
        Hasil fungsi atau default_return jika error
    """
    try:
        return func(*args, **kwargs)
    except Exception as e:
        # Get error handler
        error_handler = get_error_handler()
        
        # Handle error
        context = {
            "function": func.__name__
        }
        
        error_handler.handle_error(e, context)
        
        # Return default value
        return default_return

def main():
    """
    Fungsi utama untuk testing error handler
    """
    parser = argparse.ArgumentParser(description="Error Handler")
    parser.add_argument("--config", default="error_handler_config.json", 
                       help="Path to error handler configuration file")
    parser.add_argument("--create-config", action="store_true",
                       help="Create default error handler configuration file")
    parser.add_argument("--stats", action="store_true",
                       help="Show error statistics")
    parser.add_argument("--history", action="store_true",
                       help="Show error history")
    parser.add_argument("--export", metavar="FILE",
                       help="Export error report to file")
    parser.add_argument("--clear", action="store_true",
                       help="Clear error history")
    
    args = parser.parse_args()
    
    # Create default config if requested
    if args.create_config:
        config_path = Path(args.config)
        if config_path.exists():
            logger.warning(f"Error handler config file {config_path} already exists")
        else:
            error_handler = ErrorHandler(args.config)
            default_config = error_handler._get_default_config()
            
            with open(config_path, 'w') as f:
                json.dump(default_config, f, indent=2)
            
            logger.info(f"Created default error handler config file: {config_path}")
            return 0
    
    # Initialize error handler
    error_handler = ErrorHandler(args.config)
    
    try:
        if args.stats:
            # Show error statistics
            stats = error_handler.get_error_stats()
            print(f"Total errors: {stats['total_errors']}")
            print("By level:")
            for level, count in stats['by_level'].items():
                print(f"  {level}: {count}")
            print("By category:")
            for category, count in stats['by_category'].items():
                print(f"  {category}: {count}")
            print("By module:")
            for module, count in stats['by_module'].items():
                print(f"  {module}: {count}")
            return 0
        
        if args.history:
            # Show error history
            history = error_handler.get_error_history()
            print(f"Error history ({len(history)} entries):")
            for error in history[-10:]:  # Show last 10 errors
                print(f"{error['timestamp']} - {error['level']} - {error['category']} - {error['module']}.{error['function']} - {error['message']}")
            return 0
        
        if args.export:
            # Export error report
            if error_handler.export_error_report(args.export):
                logger.info(f"Error report exported to {args.export}")
                return 0
            else:
                logger.error(f"Failed to export error report to {args.export}")
                return 1
        
        if args.clear:
            # Clear error history
            error_handler.clear_error_history()
            logger.info("Error history cleared")
            return 0
        
        # Test error handling
        try:
            # Test with different error types
            raise NetworkError("Test network error", {"test": True})
        except Exception as e:
            error_handler.handle_error(e)
        
        try:
            # Test with file system error
            raise FileSystemError("Test file system error", {"test": True})
        except Exception as e:
            error_handler.handle_error(e)
        
        try:
            # Test with validation error
            raise ValidationError("Test validation error", {"test": True})
        except Exception as e:
            error_handler.handle_error(e)
        
        logger.info("Error handler test completed")
        return 0
        
    except Exception as e:
        logger.error(f"Error testing error handler: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())