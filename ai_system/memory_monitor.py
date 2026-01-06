import logging
import time
import threading
import gc
import psutil
import os
from typing import Dict, Any, Optional, Callable, List
from dataclasses import dataclass
from enum import Enum


class MemoryAlertLevel(Enum):
    """Enum untuk level alert memory."""
    NORMAL = 0
    WARNING = 1
    CRITICAL = 2


@dataclass
class MemoryStats:
    """Data class untuk menyimpan statistik memory."""
    timestamp: float
    rss: int  # Resident Set Size (bytes)
    vms: int  # Virtual Memory Size (bytes)
    percent: float  # Memory usage percentage
    available: int  # Available memory (bytes)
    gc_count0: int  # Generation 0 garbage collection count
    gc_count1: int  # Generation 1 garbage collection count
    gc_count2: int  # Generation 2 garbage collection count
    gc_objects: int  # Number of objects tracked by garbage collector


class MemoryMonitor:
    """
    Memory Monitor untuk memantau penggunaan memori dan mencegah kebocoran memori.
    """
    
    def __init__(self, 
                 check_interval: float = 5.0,
                 warning_threshold: float = 70.0,
                 critical_threshold: float = 85.0,
                 enable_auto_gc: bool = True,
                 gc_threshold: int = 1000):
        """
        Initialize MemoryMonitor.
        
        Args:
            check_interval: Interval pengecekan memory dalam detik
            warning_threshold: Threshold warning dalam persentase (0-100)
            critical_threshold: Threshold critical dalam persentase (0-100)
            enable_auto_gc: Enable automatic garbage collection
            gc_threshold: Threshold untuk automatic garbage collection
        """
        self._logger = logging.getLogger(__name__)
        self._check_interval = check_interval
        self._warning_threshold = warning_threshold
        self._critical_threshold = critical_threshold
        self._enable_auto_gc = enable_auto_gc
        self._gc_threshold = gc_threshold
        
        # Process information
        self._process = psutil.Process(os.getpid())
        
        # Thread untuk monitoring
        self._monitor_thread: Optional[threading.Thread] = None
        self._stop_monitoring = False
        self._monitor_lock = threading.Lock()
        
        # History untuk tracking memory usage
        self._history: List[MemoryStats] = []
        self._max_history_size = 100
        
        # Alert callbacks
        self._alert_callbacks: List[Callable[[MemoryStats, MemoryAlertLevel], None]] = []
        
        # Statistics
        self._stats = {
            'max_memory_percent': 0.0,
            'max_memory_rss': 0,
            'gc_count': 0,
            'alert_count': 0
        }
        self._stats_lock = threading.Lock()
        
        self._logger.info("MemoryMonitor initialized")
    
    def start(self) -> None:
        """
        Start memory monitoring thread.
        """
        with self._monitor_lock:
            if self._monitor_thread and self._monitor_thread.is_alive():
                self._logger.warning("Memory monitoring thread is already running")
                return
            
            self._stop_monitoring = False
            self._monitor_thread = threading.Thread(target=self._monitor_loop, daemon=True)
            self._monitor_thread.start()
            self._logger.info("Memory monitoring thread started")
    
    def stop(self) -> None:
        """
        Stop memory monitoring thread.
        """
        with self._monitor_lock:
            if not self._monitor_thread or not self._monitor_thread.is_alive():
                self._logger.warning("Memory monitoring thread is not running")
                return
            
            self._stop_monitoring = True
            self._monitor_thread.join(timeout=2.0)
            self._logger.info("Memory monitoring thread stopped")
    
    def _monitor_loop(self) -> None:
        """
        Main monitoring loop.
        """
        while not self._stop_monitoring:
            try:
                # Get current memory stats
                stats = self._get_memory_stats()
                
                # Add to history
                self._add_to_history(stats)
                
                # Check for alerts
                alert_level = self._check_alert_level(stats)
                if alert_level != MemoryAlertLevel.NORMAL:
                    self._trigger_alert(stats, alert_level)
                
                # Update statistics
                self._update_stats(stats)
                
                # Check if automatic garbage collection is needed
                if self._enable_auto_gc and self._should_trigger_gc(stats):
                    self._trigger_gc()
                
                # Sleep for the interval
                time.sleep(self._check_interval)
                
            except Exception as e:
                self._logger.error(f"Error in memory monitoring loop: {e}")
                time.sleep(self._check_interval)
    
    def _get_memory_stats(self) -> MemoryStats:
        """
        Get current memory statistics.
        
        Returns:
            MemoryStats object with current memory information
        """
        # Get memory info
        memory_info = self._process.memory_info()
        memory_percent = self._process.memory_percent()
        
        # Get virtual memory info
        vm = psutil.virtual_memory()
        
        # Get garbage collection stats
        gc_counts = gc.get_count()
        gc_objects = len(gc.get_objects())
        
        return MemoryStats(
            timestamp=time.time(),
            rss=memory_info.rss,
            vms=memory_info.vms,
            percent=memory_percent,
            available=vm.available,
            gc_count0=gc_counts[0],
            gc_count1=gc_counts[1],
            gc_count2=gc_counts[2],
            gc_objects=gc_objects
        )
    
    def _add_to_history(self, stats: MemoryStats) -> None:
        """
        Add memory stats to history.
        
        Args:
            stats: MemoryStats to add to history
        """
        self._history.append(stats)
        
        # Limit history size
        if len(self._history) > self._max_history_size:
            self._history.pop(0)
    
    def _check_alert_level(self, stats: MemoryStats) -> MemoryAlertLevel:
        """
        Check alert level based on memory usage.
        
        Args:
            stats: Current memory statistics
            
        Returns:
            MemoryAlertLevel based on memory usage
        """
        if stats.percent >= self._critical_threshold:
            return MemoryAlertLevel.CRITICAL
        elif stats.percent >= self._warning_threshold:
            return MemoryAlertLevel.WARNING
        
        return MemoryAlertLevel.NORMAL
    
    def _trigger_alert(self, stats: MemoryStats, alert_level: MemoryAlertLevel) -> None:
        """
        Trigger memory alert.
        
        Args:
            stats: Current memory statistics
            alert_level: Alert level
        """
        # Log alert
        if alert_level == MemoryAlertLevel.CRITICAL:
            self._logger.critical(
                f"CRITICAL MEMORY USAGE: {stats.percent:.1f}% "
                f"(RSS: {self._format_bytes(stats.rss)})"
            )
        elif alert_level == MemoryAlertLevel.WARNING:
            self._logger.warning(
                f"WARNING MEMORY USAGE: {stats.percent:.1f}% "
                f"(RSS: {self._format_bytes(stats.rss)})"
            )
        
        # Update alert count
        with self._stats_lock:
            self._stats['alert_count'] += 1
        
        # Call alert callbacks
        for callback in self._alert_callbacks:
            try:
                callback(stats, alert_level)
            except Exception as e:
                self._logger.error(f"Error in memory alert callback: {e}")
    
    def _update_stats(self, stats: MemoryStats) -> None:
        """
        Update memory statistics.
        
        Args:
            stats: Current memory statistics
        """
        with self._stats_lock:
            if stats.percent > self._stats['max_memory_percent']:
                self._stats['max_memory_percent'] = stats.percent
            
            if stats.rss > self._stats['max_memory_rss']:
                self._stats['max_memory_rss'] = stats.rss
    
    def _should_trigger_gc(self, stats: MemoryStats) -> bool:
        """
        Check if garbage collection should be triggered.
        
        Args:
            stats: Current memory statistics
            
        Returns:
            True if garbage collection should be triggered
        """
        # Trigger GC if memory usage is high and object count is above threshold
        return (stats.percent > self._warning_threshold and 
                stats.gc_objects > self._gc_threshold)
    
    def _trigger_gc(self) -> None:
        """
        Trigger garbage collection.
        """
        self._logger.info("Triggering garbage collection")
        
        # Get GC counts before collection
        before_counts = gc.get_count()
        
        # Trigger garbage collection for all generations
        gc.collect()
        
        # Get GC counts after collection
        after_counts = gc.get_count()
        
        # Calculate collected objects
        collected = sum(after_counts[i] - before_counts[i] for i in range(3))
        
        # Update statistics
        with self._stats_lock:
            self._stats['gc_count'] += 1
        
        self._logger.info(f"Garbage collection completed: {collected} objects collected")
    
    def _format_bytes(self, bytes_value: int) -> str:
        """
        Format bytes to human-readable string.
        
        Args:
            bytes_value: Bytes value to format
            
        Returns:
            Formatted string (e.g., "100.0 MB")
        """
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if bytes_value < 1024.0:
                return f"{bytes_value:.1f} {unit}"
            bytes_value /= 1024.0
        return f"{bytes_value:.1f} PB"
    
    def add_alert_callback(self, callback: Callable[[MemoryStats, MemoryAlertLevel], None]) -> None:
        """
        Add callback for memory alerts.
        
        Args:
            callback: Callback function that takes MemoryStats and MemoryAlertLevel
        """
        self._alert_callbacks.append(callback)
        self._logger.info("Memory alert callback added")
    
    def remove_alert_callback(self, callback: Callable[[MemoryStats, MemoryAlertLevel], None]) -> None:
        """
        Remove memory alert callback.
        
        Args:
            callback: Callback function to remove
        """
        if callback in self._alert_callbacks:
            self._alert_callbacks.remove(callback)
            self._logger.info("Memory alert callback removed")
    
    def get_current_stats(self) -> MemoryStats:
        """
        Get current memory statistics.
        
        Returns:
            Current MemoryStats
        """
        return self._get_memory_stats()
    
    def get_history(self, max_items: Optional[int] = None) -> List[MemoryStats]:
        """
        Get memory usage history.
        
        Args:
            max_items: Maximum number of items to return (None for all)
            
        Returns:
            List of MemoryStats
        """
        if max_items is None:
            return self._history.copy()
        else:
            return self._history[-max_items:]
    
    def get_stats(self) -> Dict[str, Any]:
        """
        Get memory monitor statistics.
        
        Returns:
            Dictionary containing memory monitor statistics
        """
        with self._stats_lock:
            stats = self._stats.copy()
        
        # Add current memory info
        current_stats = self._get_memory_stats()
        stats.update({
            'current_memory_percent': current_stats.percent,
            'current_memory_rss': current_stats.rss,
            'current_memory_vms': current_stats.vms,
            'current_memory_available': current_stats.available,
            'current_gc_objects': current_stats.gc_objects,
            'is_monitoring': self._monitor_thread and self._monitor_thread.is_alive()
        })
        
        return stats
    
    def set_thresholds(self, 
                      warning_threshold: Optional[float] = None,
                      critical_threshold: Optional[float] = None) -> None:
        """
        Set memory alert thresholds.
        
        Args:
            warning_threshold: Warning threshold in percentage (0-100)
            critical_threshold: Critical threshold in percentage (0-100)
        """
        if warning_threshold is not None:
            if 0 <= warning_threshold <= 100:
                self._warning_threshold = warning_threshold
                self._logger.info(f"Warning threshold set to {warning_threshold}%")
            else:
                raise ValueError("Warning threshold must be between 0 and 100")
        
        if critical_threshold is not None:
            if 0 <= critical_threshold <= 100:
                self._critical_threshold = critical_threshold
                self._logger.info(f"Critical threshold set to {critical_threshold}%")
            else:
                raise ValueError("Critical threshold must be between 0 and 100")
        
        # Validate that critical is higher than warning
        if self._critical_threshold <= self._warning_threshold:
            raise ValueError("Critical threshold must be higher than warning threshold")
    
    def clear_history(self) -> None:
        """
        Clear memory usage history.
        """
        self._history.clear()
        self._logger.info("Memory usage history cleared")
    
    def force_gc(self) -> None:
        """
        Force garbage collection.
        """
        self._trigger_gc()