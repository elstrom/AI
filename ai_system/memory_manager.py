import logging
import time
from typing import Dict, Any, Optional, List
from pathlib import Path
from threading import Lock

from .config_manager import ConfigurationManager
from .memory_monitor import MemoryMonitor, MemoryAlertLevel
from .memory_logger import MemoryLogger
from .memory_alert_manager import MemoryAlertManager, AlertConfig, AlertAction
from .gc_monitor import GarbageCollectionMonitor
from .object_pool import ObjectPool
from .thread_pool import ThreadPool


class MemoryManager:
    """
    Manajer utama untuk mengintegrasikan semua komponen memory monitoring.
    """
    
    def __init__(self, 
                 config_manager: ConfigurationManager,
                 log_file: Optional[Path] = None):
        """
        Initialize MemoryManager.
        
        Args:
            config_manager: ConfigurationManager instance
            log_file: Path to log file
        """
        self._logger = logging.getLogger(__name__)
        self._config_manager = config_manager
        import os
        
        # Safe handling for log_file - use default if empty or invalid
        if log_file and str(log_file).strip():
            self._log_file = log_file if isinstance(log_file, Path) else Path(str(log_file))
        else:
            self._log_file = Path("logs/memory.log")
        
        # Ensure log directory exists - only if log_file has a parent directory
        try:
            if self._log_file.parent and str(self._log_file.parent) not in ("", "."):
                os.makedirs(self._log_file.parent, exist_ok=True)
        except (PermissionError, OSError) as e:
            self._logger.warning(f"Cannot create log directory {self._log_file.parent}: {e}. Using default.")
            self._log_file = Path("logs/memory.log")
            try:
                os.makedirs(self._log_file.parent, exist_ok=True)
            except (PermissionError, OSError):
                pass  # Continue without file logging
        
        # Get configuration values
        self._check_interval = config_manager.get('memory.check_interval', 5.0)
        self._warning_threshold = config_manager.get('memory.warning_threshold', 70.0)
        self._critical_threshold = config_manager.get('memory.critical_threshold', 85.0)
        self._enable_auto_gc = config_manager.get('memory.enable_auto_gc', True)
        self._gc_threshold = config_manager.get('memory.gc_threshold', 1000)
        self._enable_tracemalloc = config_manager.get('memory.enable_tracemalloc', True)
        self._enable_alerting = config_manager.get('memory.enable_alerting', True)
        self._enable_logging = config_manager.get('memory.enable_logging', True)
        
        # Initialize components
        self._memory_monitor = MemoryMonitor(
            check_interval=self._check_interval,
            warning_threshold=self._warning_threshold,
            critical_threshold=self._critical_threshold,
            enable_auto_gc=self._enable_auto_gc,
            gc_threshold=self._gc_threshold
        )
        
        self._memory_logger = MemoryLogger(
            memory_monitor=self._memory_monitor,
            log_file=self._log_file,
            enable_console_logging=self._enable_logging
        )
        
        self._gc_monitor = GarbageCollectionMonitor(
            enable_tracemalloc=self._enable_tracemalloc
        )
        
        self._alert_manager = None
        if self._enable_alerting:
            self._alert_manager = MemoryAlertManager(
                memory_monitor=self._memory_monitor,
                email_config=config_manager.get('memory.email_config', {})
            )
        
        # Object pools and thread pools for monitoring
        self._object_pools: Dict[str, ObjectPool] = {}
        self._thread_pools: Dict[str, ThreadPool] = {}
        self._pools_lock = Lock()
        
        # Statistics
        self._stats = {
            'start_time': time.time(),
            'uptime': 0.0,
            'total_gc_calls': 0,
            'total_alerts': 0,
            'max_memory_percent': 0.0,
            'current_memory_percent': 0.0
        }
        self._stats_lock = Lock()
        
        # Start monitoring
        self._memory_monitor.start()
        self._memory_logger.start()
        
        self._logger.info("MemoryManager initialized")
    
    def register_object_pool(self, name: str, object_pool: ObjectPool) -> None:
        """
        Register object pool for monitoring.
        
        Args:
            name: Name of the object pool
            object_pool: ObjectPool instance
        """
        with self._pools_lock:
            self._object_pools[name] = object_pool
        
        self._logger.info(f"Registered object pool: {name}")
    
    def unregister_object_pool(self, name: str) -> None:
        """
        Unregister object pool.
        
        Args:
            name: Name of the object pool
        """
        with self._pools_lock:
            if name in self._object_pools:
                del self._object_pools[name]
                self._logger.info(f"Unregistered object pool: {name}")
            else:
                self._logger.warning(f"Object pool not found: {name}")
    
    def register_thread_pool(self, name: str, thread_pool: ThreadPool) -> None:
        """
        Register thread pool for monitoring.
        
        Args:
            name: Name of the thread pool
            thread_pool: ThreadPool instance
        """
        with self._pools_lock:
            self._thread_pools[name] = thread_pool
        
        self._logger.info(f"Registered thread pool: {name}")
    
    def unregister_thread_pool(self, name: str) -> None:
        """
        Unregister thread pool.
        
        Args:
            name: Name of the thread pool
        """
        with self._pools_lock:
            if name in self._thread_pools:
                del self._thread_pools[name]
                self._logger.info(f"Unregistered thread pool: {name}")
            else:
                self._logger.warning(f"Thread pool not found: {name}")
    
    def log_pool_stats(self) -> None:
        """
        Log statistics for all registered pools.
        """
        # Log object pool stats
        with self._pools_lock:
            for name, pool in self._object_pools.items():
                pool_stats = {
                    'pool_size': pool.size(),
                    'in_use_count': pool.in_use_count()
                }
                self._memory_logger.log_object_pool_stats(name, pool_stats)
        
        # Log thread pool stats
        with self._pools_lock:
            for name, pool in self._thread_pools.items():
                thread_pool_stats = pool.get_stats()
                self._memory_logger.log_thread_pool_stats(thread_pool_stats)
    
    def add_email_alert(self, 
                       alert_level: MemoryAlertLevel,
                       recipients: List[str],
                       cooldown_period: float = 300.0) -> None:
        """
        Add email alert.
        
        Args:
            alert_level: Alert level
            recipients: List of email recipients
            cooldown_period: Cooldown period in seconds
        """
        if self._alert_manager:
            self._alert_manager.add_email_alert(alert_level, recipients, cooldown_period)
        else:
            self._logger.warning("Alert manager is not enabled")
    
    def add_webhook_alert(self, 
                         alert_level: MemoryAlertLevel,
                         webhook_url: str,
                         cooldown_period: float = 300.0) -> None:
        """
        Add webhook alert.
        
        Args:
            alert_level: Alert level
            webhook_url: Webhook URL
            cooldown_period: Cooldown period in seconds
        """
        if self._alert_manager:
            self._alert_manager.add_webhook_alert(alert_level, webhook_url, cooldown_period)
        else:
            self._logger.warning("Alert manager is not enabled")
    
    def force_gc(self, generation: int = 2) -> None:
        """
        Force garbage collection.
        
        Args:
            generation: Generation to collect (0, 1, or 2)
        """
        self._gc_monitor.force_gc(generation)
    
    def detect_memory_leaks(self, 
                           min_snapshots: int = 3,
                           growth_threshold: float = 1.1) -> List[Dict[str, Any]]:
        """
        Detect potential memory leaks.
        
        Args:
            min_snapshots: Minimum number of snapshots required for analysis
            growth_threshold: Threshold for memory growth
            
        Returns:
            List of potential memory leaks
        """
        return self._gc_monitor.detect_memory_leaks(min_snapshots, growth_threshold)
    
    def get_memory_stats(self) -> Dict[str, Any]:
        """
        Get comprehensive memory statistics.
        
        Returns:
            Dictionary containing memory statistics
        """
        # Get stats from all components
        memory_monitor_stats = self._memory_monitor.get_stats()
        gc_monitor_stats = self._gc_monitor.get_stats()
        
        # Update our own stats
        with self._stats_lock:
            self._stats['uptime'] = time.time() - self._stats['start_time']
            self._stats['total_gc_calls'] = gc_monitor_stats.get('total_gc_calls', 0)
            self._stats['total_alerts'] = memory_monitor_stats.get('alert_count', 0)
            self._stats['max_memory_percent'] = memory_monitor_stats.get('max_memory_percent', 0.0)
            self._stats['current_memory_percent'] = memory_monitor_stats.get('current_memory_percent', 0.0)
            
            # Return a copy of stats
            stats = self._stats.copy()
        
        # Add pool stats
        with self._pools_lock:
            pool_stats = {}
            
            # Object pool stats
            for name, pool in self._object_pools.items():
                pool_stats[f"object_pool_{name}"] = {
                    'pool_size': pool.size(),
                    'in_use_count': pool.in_use_count()
                }
            
            # Thread pool stats
            for name, pool in self._thread_pools.items():
                pool_stats[f"thread_pool_{name}"] = pool.get_stats()
            
            stats['pools'] = pool_stats
        
        # Add component stats
        stats['memory_monitor'] = memory_monitor_stats
        stats['gc_monitor'] = gc_monitor_stats
        
        # Add alert manager stats if enabled
        if self._alert_manager:
            stats['alert_manager'] = self._alert_manager.get_alert_configs()
        
        return stats
    
    def get_memory_history(self, max_items: Optional[int] = None) -> List[Dict[str, Any]]:
        """
        Get memory usage history.
        
        Args:
            max_items: Maximum number of items to return (None for all)
            
        Returns:
            List of memory history entries
        """
        return self._memory_logger.get_history(max_items)
    
    def get_gc_history(self, max_items: Optional[int] = None) -> List[Dict[str, Any]]:
        """
        Get garbage collection history.
        
        Args:
            max_items: Maximum number of items to return (None for all)
            
        Returns:
            List of GC history entries
        """
        gc_stats = self._gc_monitor.get_gc_stats(max_items)
        
        # Convert to list of dictionaries
        history = []
        for stat in gc_stats:
            history.append({
                'timestamp': stat.timestamp,
                'generation': stat.generation,
                'collected_objects': stat.collected_objects,
                'uncollectable_objects': stat.uncollectable_objects,
                'gc_duration': stat.gc_duration,
                'memory_before': stat.memory_before,
                'memory_after': stat.memory_after,
                'memory_freed': stat.memory_freed,
                'top_allocations': stat.top_allocations
            })
        
        return history
    
    def export_memory_report(self, file_path: Path) -> None:
        """
        Export comprehensive memory report to file.
        
        Args:
            file_path: Path to export file
        """
        try:
            # Create directory if it doesn't exist
            file_path.parent.mkdir(parents=True, exist_ok=True)
            
            # Create report
            report = {
                'timestamp': time.time(),
                'datetime': time.strftime('%Y-%m-%d %H:%M:%S'),
                'memory_stats': self.get_memory_stats(),
                'memory_history': self.get_memory_history(),
                'gc_history': self.get_gc_history()
            }
            
            # Write to file
            import json
            with open(file_path, 'w') as f:
                json.dump(report, f, indent=2)
            
            self._logger.info(f"Memory report exported to {file_path}")
            
        except Exception as e:
            self._logger.error(f"Error exporting memory report: {e}")
    
    def set_memory_thresholds(self, 
                            warning_threshold: Optional[float] = None,
                            critical_threshold: Optional[float] = None) -> None:
        """
        Set memory alert thresholds.
        
        Args:
            warning_threshold: Warning threshold in percentage (0-100)
            critical_threshold: Critical threshold in percentage (0-100)
        """
        self._memory_monitor.set_thresholds(warning_threshold, critical_threshold)
        
        # Update configuration
        if warning_threshold is not None:
            self._config_manager.set('memory.warning_threshold', warning_threshold)
        
        if critical_threshold is not None:
            self._config_manager.set('memory.critical_threshold', critical_threshold)
    
    def clear_history(self) -> None:
        """
        Clear all monitoring history.
        """
        self._memory_logger.clear_history()
        self._gc_monitor.clear_history()
        self._logger.info("All monitoring history cleared")
    
    def shutdown(self) -> None:
        """
        Shutdown the memory manager.
        """
        self._logger.info("Shutting down MemoryManager...")
        
        # Stop monitoring
        self._memory_monitor.stop()
        self._memory_logger.stop()
        self._gc_monitor.shutdown()
        
        self._logger.info("MemoryManager shutdown complete")