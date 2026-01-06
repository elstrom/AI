import logging
import time
import json
from typing import Dict, Any, Optional, List
from pathlib import Path
from threading import Lock
from datetime import datetime

from .memory_monitor import MemoryMonitor, MemoryStats, MemoryAlertLevel


class MemoryLogger:
    """
    Logger khusus untuk memory usage dan object pool statistics.
    """
    
    def __init__(self, 
                 memory_monitor: MemoryMonitor,
                 log_file: Optional[Path] = None,
                 log_interval: float = 60.0,
                 enable_file_logging: bool = True,
                 enable_console_logging: bool = True,
                 log_format: str = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"):
        """
        Initialize MemoryLogger.
        
        Args:
            memory_monitor: MemoryMonitor instance
            log_file: Path to log file
            log_interval: Interval for logging memory stats in seconds
            enable_file_logging: Enable logging to file
            enable_console_logging: Enable logging to console
            log_format: Format for log messages
        """
        self._memory_monitor = memory_monitor
        self._log_file = log_file
        self._log_interval = log_interval
        self._enable_file_logging = enable_file_logging
        self._enable_console_logging = enable_console_logging
        self._log_format = log_format
        
        # Logger instance
        self._logger = logging.getLogger("memory_logger")
        self._logger.setLevel(logging.INFO)
        self._logger.propagate = False
        
        # Clear existing handlers
        self._logger.handlers.clear()
        
        # Configure formatter
        formatter = logging.Formatter(log_format)
        
        # Add console handler if enabled
        if self._enable_console_logging:
            console_handler = logging.StreamHandler()
            console_handler.setFormatter(formatter)
            self._logger.addHandler(console_handler)
        
        # Add file handler if enabled
        if self._enable_file_logging and log_file:
            # Create log directory if it doesn't exist
            log_file.parent.mkdir(parents=True, exist_ok=True)
            
            file_handler = logging.FileHandler(log_file)
            file_handler.setFormatter(formatter)
            self._logger.addHandler(file_handler)
        
        # Thread for periodic logging
        self._log_thread = None
        self._stop_logging = False
        self._log_lock = Lock()
        
        # History for tracking
        self._history: List[Dict[str, Any]] = []
        self._max_history_size = 1000
        
        # Register alert callback with memory monitor
        self._memory_monitor.add_alert_callback(self._log_memory_alert)
        
        self._logger.info("MemoryLogger initialized")
    
    def start(self) -> None:
        """
        Start memory logging thread.
        """
        with self._log_lock:
            if self._log_thread and self._log_thread.is_alive():
                self._logger.warning("Memory logging thread is already running")
                return
            
            self._stop_logging = False
            self._log_thread = threading.Thread(target=self._log_loop, daemon=True)
            self._log_thread.start()
            self._logger.info("Memory logging thread started")
    
    def stop(self) -> None:
        """
        Stop memory logging thread.
        """
        with self._log_lock:
            if not self._log_thread or not self._log_thread.is_alive():
                self._logger.warning("Memory logging thread is not running")
                return
            
            self._stop_logging = True
            self._log_thread.join(timeout=2.0)
            self._logger.info("Memory logging thread stopped")
    
    def _log_loop(self) -> None:
        """
        Main logging loop.
        """
        while not self._stop_logging:
            try:
                # Log current memory stats
                self._log_memory_stats()
                
                # Sleep for the interval
                time.sleep(self._log_interval)
                
            except Exception as e:
                self._logger.error(f"Error in memory logging loop: {e}")
                time.sleep(self._log_interval)
    
    def _log_memory_stats(self) -> None:
        """
        Log current memory statistics.
        """
        try:
            # Get current memory stats
            stats = self._memory_monitor.get_current_stats()
            
            # Create log entry
            log_entry = {
                'timestamp': stats.timestamp,
                'datetime': datetime.fromtimestamp(stats.timestamp).isoformat(),
                'memory': {
                    'rss_mb': stats.rss / (1024 * 1024),
                    'vms_mb': stats.vms / (1024 * 1024),
                    'percent': stats.percent,
                    'available_mb': stats.available / (1024 * 1024)
                },
                'gc': {
                    'count0': stats.gc_count0,
                    'count1': stats.gc_count1,
                    'count2': stats.gc_count2,
                    'objects': stats.gc_objects
                }
            }
            
            # Add to history
            self._add_to_history(log_entry)
            
            # Log as JSON
            self._logger.info(f"Memory stats: {json.dumps(log_entry)}")
            
        except Exception as e:
            self._logger.error(f"Error logging memory stats: {e}")
    
    def _log_memory_alert(self, stats: MemoryStats, alert_level: MemoryAlertLevel) -> None:
        """
        Log memory alert.
        
        Args:
            stats: Current memory statistics
            alert_level: Alert level
        """
        try:
            # Create alert log entry
            alert_entry = {
                'timestamp': stats.timestamp,
                'datetime': datetime.fromtimestamp(stats.timestamp).isoformat(),
                'alert_level': alert_level.name,
                'memory': {
                    'rss_mb': stats.rss / (1024 * 1024),
                    'vms_mb': stats.vms / (1024 * 1024),
                    'percent': stats.percent,
                    'available_mb': stats.available / (1024 * 1024)
                },
                'gc': {
                    'count0': stats.gc_count0,
                    'count1': stats.gc_count1,
                    'count2': stats.gc_count2,
                    'objects': stats.gc_objects
                }
            }
            
            # Add to history
            self._add_to_history(alert_entry)
            
            # Log alert with appropriate level
            if alert_level == MemoryAlertLevel.CRITICAL:
                self._logger.critical(f"CRITICAL MEMORY ALERT: {json.dumps(alert_entry)}")
            elif alert_level == MemoryAlertLevel.WARNING:
                self._logger.warning(f"WARNING MEMORY ALERT: {json.dumps(alert_entry)}")
            
        except Exception as e:
            self._logger.error(f"Error logging memory alert: {e}")
    
    def _add_to_history(self, entry: Dict[str, Any]) -> None:
        """
        Add entry to history.
        
        Args:
            entry: Log entry to add to history
        """
        self._history.append(entry)
        
        # Limit history size
        if len(self._history) > self._max_history_size:
            self._history.pop(0)
    
    def log_object_pool_stats(self, pool_name: str, pool_stats: Dict[str, Any]) -> None:
        """
        Log object pool statistics.
        
        Args:
            pool_name: Name of the object pool
            pool_stats: Object pool statistics
        """
        try:
            # Create pool stats entry
            pool_entry = {
                'timestamp': time.time(),
                'datetime': datetime.fromtimestamp(time.time()).isoformat(),
                'pool_name': pool_name,
                'pool_stats': pool_stats
            }
            
            # Add to history
            self._add_to_history(pool_entry)
            
            # Log pool stats
            self._logger.info(f"Object pool stats [{pool_name}]: {json.dumps(pool_entry)}")
            
        except Exception as e:
            self._logger.error(f"Error logging object pool stats: {e}")
    
    def log_thread_pool_stats(self, thread_pool_stats: Dict[str, Any]) -> None:
        """
        Log thread pool statistics.
        
        Args:
            thread_pool_stats: Thread pool statistics
        """
        try:
            # Create thread pool stats entry
            thread_entry = {
                'timestamp': time.time(),
                'datetime': datetime.fromtimestamp(time.time()).isoformat(),
                'thread_pool_stats': thread_pool_stats
            }
            
            # Add to history
            self._add_to_history(thread_entry)
            
            # Log thread pool stats
            self._logger.info(f"Thread pool stats: {json.dumps(thread_entry)}")
            
        except Exception as e:
            self._logger.error(f"Error logging thread pool stats: {e}")
    
    def log_buffer_pool_stats(self, pool_name: str, buffer_pool_stats) -> None:
        """
        Log buffer pool statistics.
        
        Args:
            pool_name: Name of the buffer pool
            buffer_pool_stats: Buffer pool statistics
        """
        try:
            # Create buffer pool stats entry
            buffer_entry = {
                'timestamp': time.time(),
                'datetime': datetime.fromtimestamp(time.time()).isoformat(),
                'pool_name': pool_name,
                'buffer_pool_stats': {
                    'size': buffer_pool_stats.size,
                    'in_use': buffer_pool_stats.in_use,
                    'allocated': buffer_pool_stats.allocated,
                    'recycled': buffer_pool_stats.recycled,
                    'preallocated': buffer_pool_stats.preallocated,
                    'total_allocations': buffer_pool_stats.total_allocations,
                    'total_recycling': buffer_pool_stats.total_recycling,
                    'peak_usage': buffer_pool_stats.peak_usage,
                    'current_memory_usage': buffer_pool_stats.current_memory_usage
                }
            }
            
            # Add to history
            self._add_to_history(buffer_entry)
            
            # Log buffer pool stats
            self._logger.info(f"Buffer pool stats [{pool_name}]: {json.dumps(buffer_entry)}")
            
        except Exception as e:
            self._logger.error(f"Error logging buffer pool stats: {e}")
    
    def get_history(self, max_items: Optional[int] = None) -> List[Dict[str, Any]]:
        """
        Get logging history.
        
        Args:
            max_items: Maximum number of items to return (None for all)
            
        Returns:
            List of log entries
        """
        if max_items is None:
            return self._history.copy()
        else:
            return self._history[-max_items:]
    
    def clear_history(self) -> None:
        """
        Clear logging history.
        """
        self._history.clear()
        self._logger.info("Logging history cleared")
    
    def export_history_to_file(self, file_path: Path) -> None:
        """
        Export logging history to file.
        
        Args:
            file_path: Path to export file
        """
        try:
            # Create directory if it doesn't exist
            file_path.parent.mkdir(parents=True, exist_ok=True)
            
            # Write history to file
            with open(file_path, 'w') as f:
                json.dump(self._history, f, indent=2)
            
            self._logger.info(f"Logging history exported to {file_path}")
            
        except Exception as e:
            self._logger.error(f"Error exporting logging history: {e}")


# Import threading at the top of the file
import threading