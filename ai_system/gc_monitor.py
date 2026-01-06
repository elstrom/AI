import logging
import time
import threading
import gc
import tracemalloc
from typing import Dict, Any, Optional, List, Callable
from dataclasses import dataclass
from collections import defaultdict


@dataclass
class GCStats:
    """Data class untuk menyimpan statistik garbage collection."""
    timestamp: float
    generation: int
    collected_objects: int
    uncollectable_objects: int
    gc_duration: float
    memory_before: int
    memory_after: int
    memory_freed: int
    top_allocations: List[Dict[str, Any]]


class GarbageCollectionMonitor:
    """
    Monitor untuk garbage collection dan memory leak detection.
    """
    
    def __init__(self, 
                 enable_tracemalloc: bool = True,
                 snapshot_interval: float = 60.0,
                 max_snapshots: int = 10,
                 enable_gc_callbacks: bool = True):
        """
        Initialize GarbageCollectionMonitor.
        
        Args:
            enable_tracemalloc: Enable tracemalloc for memory allocation tracking
            snapshot_interval: Interval for taking memory snapshots in seconds
            max_snapshots: Maximum number of snapshots to keep
            enable_gc_callbacks: Enable callbacks for garbage collection events
        """
        self._logger = logging.getLogger(__name__)
        self._enable_tracemalloc = enable_tracemalloc
        self._snapshot_interval = snapshot_interval
        self._max_snapshots = max_snapshots
        self._enable_gc_callbacks = enable_gc_callbacks
        
        # GC statistics
        self._gc_stats: List[GCStats] = []
        self._gc_stats_lock = threading.Lock()
        
        # Memory snapshots
        self._snapshots: List[Dict[str, Any]] = []
        self._snapshots_lock = threading.Lock()
        
        # Thread for taking snapshots
        self._snapshot_thread: Optional[threading.Thread] = None
        self._stop_snapshot_thread = False
        self._snapshot_lock = threading.Lock()
        
        # Original GC callbacks
        self._original_gc_callbacks: List[Callable] = []
        
        # Logging limiter
        self._last_log_time = 0.0
        self._log_interval = 2.0  # seconds

        # Statistics
        self._stats = {
            'total_gc_calls': 0,
            'total_objects_collected': 0,
            'total_memory_freed': 0,
            'avg_gc_duration': 0.0,
            'last_gc_time': 0.0
        }
        self._stats_lock = threading.Lock()
        
        # Start monitoring
        if self._enable_tracemalloc:
            tracemalloc.start()
        
        if self._enable_gc_callbacks:
            self._register_gc_callbacks()
        
        # Start snapshot thread
        self._start_snapshot_thread()
        
        self._logger.info("GarbageCollectionMonitor initialized")
    
    def _start_snapshot_thread(self) -> None:
        """
        Start thread for taking memory snapshots.
        """
        with self._snapshot_lock:
            if self._snapshot_thread and self._snapshot_thread.is_alive():
                self._logger.warning("Snapshot thread is already running")
                return
            
            self._stop_snapshot_thread = False
            self._snapshot_thread = threading.Thread(target=self._snapshot_loop, daemon=True)
            self._snapshot_thread.start()
            self._logger.info("Snapshot thread started")
    
    def _stop_snapshot_thread(self) -> None:
        """
        Stop thread for taking memory snapshots.
        """
        with self._snapshot_lock:
            if not self._snapshot_thread or not self._snapshot_thread.is_alive():
                self._logger.warning("Snapshot thread is not running")
                return
            
            self._stop_snapshot_thread = True
            self._snapshot_thread.join(timeout=2.0)
            self._logger.info("Snapshot thread stopped")
    
    def _snapshot_loop(self) -> None:
        """
        Main snapshot loop.
        """
        while not self._stop_snapshot_thread:
            try:
                # Take memory snapshot
                self._take_snapshot()
                
                # Sleep for the interval
                time.sleep(self._snapshot_interval)
                
            except Exception as e:
                self._logger.error(f"Error in snapshot loop: {e}")
                time.sleep(self._snapshot_interval)
    
    def _take_snapshot(self) -> None:
        """
        Take memory snapshot using tracemalloc.
        """
        if not self._enable_tracemalloc:
            return
        
        try:
            # Take snapshot
            snapshot = tracemalloc.take_snapshot()
            
            # Get top allocations
            top_stats = snapshot.statistics('lineno')
            
            # Create snapshot data
            snapshot_data = {
                'timestamp': time.time(),
                'total_size': sum(stat.size for stat in top_stats),
                'total_count': sum(stat.count for stat in top_stats),
                'top_allocations': [
                    {
                        'file': str(stat.traceback.format()[-1]) if stat.traceback else 'unknown',
                        'size': stat.size,
                        'count': stat.count
                    }
                    for stat in top_stats[:10]  # Top 10 allocations
                ]
            }
            
            # Add to snapshots
            with self._snapshots_lock:
                self._snapshots.append(snapshot_data)
                
                # Limit snapshots
                if len(self._snapshots) > self._max_snapshots:
                    self._snapshots.pop(0)
            
            self._logger.debug(f"Memory snapshot taken: {snapshot_data['total_size']} bytes")
            
        except Exception as e:
            self._logger.error(f"Error taking memory snapshot: {e}")
    
    def _register_gc_callbacks(self) -> None:
        """
        Register callbacks for garbage collection events.
        """
        # Store original callbacks
        self._original_gc_callbacks = gc.callbacks.copy()
        
        # Add our callback
        gc.callbacks.append(self._gc_callback)
        
        self._logger.info("GC callbacks registered")
    
    def _unregister_gc_callbacks(self) -> None:
        """
        Unregister callbacks for garbage collection events.
        """
        # Remove our callback
        if self._gc_callback in gc.callbacks:
            gc.callbacks.remove(self._gc_callback)
        
        # Restore original callbacks
        gc.callbacks = self._original_gc_callbacks.copy()
        
        self._logger.info("GC callbacks unregistered")
    
    def _gc_callback(self, phase: str, info: Dict[str, Any]) -> None:
        """
        Callback for garbage collection events.
        
        Args:
            phase: GC phase ('start', 'stop', etc.)
            info: GC information dictionary
        """
        if phase == 'start':
            # Record start time and memory
            info['start_time'] = time.time()
            
            if self._enable_tracemalloc:
                info['memory_before'] = tracemalloc.get_traced_memory()[0]
            else:
                import psutil
                process = psutil.Process()
                info['memory_before'] = process.memory_info().rss
        
        elif phase == 'stop':
            # Calculate duration and memory freed
            duration = time.time() - info.get('start_time', 0)
            
            if self._enable_tracemalloc:
                memory_after = tracemalloc.get_traced_memory()[0]
            else:
                import psutil
                process = psutil.Process()
                memory_after = process.memory_info().rss
            
            memory_before = info.get('memory_before', memory_after)
            memory_freed = max(0, memory_before - memory_after)
            
            # Get generation
            generation = info.get('generation', 0)
            
            # Create GC stats
            gc_stats = GCStats(
                timestamp=time.time(),
                generation=generation,
                collected_objects=info.get('collected', 0),
                uncollectable_objects=info.get('uncollectable', 0),
                gc_duration=duration,
                memory_before=memory_before,
                memory_after=memory_after,
                memory_freed=memory_freed,
                top_allocations=[]  # Will be filled if tracemalloc is enabled
            )
            
            # Get top allocations if tracemalloc is enabled
            if self._enable_tracemalloc:
                try:
                    snapshot = tracemalloc.take_snapshot()
                    top_stats = snapshot.statistics('lineno')
                    
                    gc_stats.top_allocations = [
                        {
                            'file': str(stat.traceback.format()[-1]) if stat.traceback else 'unknown',
                            'size': stat.size,
                            'count': stat.count
                        }
                        for stat in top_stats[:5]  # Top 5 allocations
                    ]
                except Exception as e:
                    self._logger.error(f"Error getting top allocations: {e}")
            
            # Add to GC stats
            with self._gc_stats_lock:
                self._gc_stats.append(gc_stats)
                
                # Limit GC stats
                if len(self._gc_stats) > 100:  # Keep last 100 GC stats
                    self._gc_stats.pop(0)
            
            # Update statistics
            with self._stats_lock:
                self._stats['total_gc_calls'] += 1
                self._stats['total_objects_collected'] += gc_stats.collected_objects
                self._stats['total_memory_freed'] += gc_stats.memory_freed
                
                # Update average duration
                if self._stats['total_gc_calls'] > 0:
                    total_duration = (self._stats['avg_gc_duration'] * 
                                     (self._stats['total_gc_calls'] - 1) + 
                                     gc_stats.gc_duration)
                    self._stats['avg_gc_duration'] = total_duration / self._stats['total_gc_calls']
                
                self._stats['last_gc_time'] = gc_stats.timestamp
            
            # Log GC event
            # Log GC event (rate limited)
            current_time = time.time()
            if generation == 2 or (current_time - self._last_log_time) >= self._log_interval:
                self._logger.info(
                    f"GC Gen {generation} completed: {gc_stats.collected_objects} objects, "
                    f"{self._format_bytes(gc_stats.memory_freed)} freed, "
                    f"{gc_stats.gc_duration:.4f}s"
                )
                self._last_log_time = current_time
    
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
    
    def get_gc_stats(self, max_items: Optional[int] = None) -> List[GCStats]:
        """
        Get garbage collection statistics.
        
        Args:
            max_items: Maximum number of items to return (None for all)
            
        Returns:
            List of GCStats
        """
        with self._gc_stats_lock:
            if max_items is None:
                return self._gc_stats.copy()
            else:
                return self._gc_stats[-max_items:]
    
    def get_snapshots(self, max_items: Optional[int] = None) -> List[Dict[str, Any]]:
        """
        Get memory snapshots.
        
        Args:
            max_items: Maximum number of items to return (None for all)
            
        Returns:
            List of memory snapshots
        """
        with self._snapshots_lock:
            if max_items is None:
                return self._snapshots.copy()
            else:
                return self._snapshots[-max_items:]
    
    def get_stats(self) -> Dict[str, Any]:
        """
        Get garbage collection monitor statistics.
        
        Returns:
            Dictionary containing GC monitor statistics
        """
        with self._stats_lock:
            stats = self._stats.copy()
        
        # Add current GC counts
        stats['current_gc_counts'] = gc.get_count()
        
        # Add current object count
        stats['current_object_count'] = len(gc.get_objects())
        
        # Add current memory usage
        if self._enable_tracemalloc:
            current, peak = tracemalloc.get_traced_memory()
            stats['current_traced_memory'] = current
            stats['peak_traced_memory'] = peak
        else:
            import psutil
            process = psutil.Process()
            memory_info = process.memory_info()
            stats['current_rss'] = memory_info.rss
            stats['current_vms'] = memory_info.vms
        
        return stats
    
    def compare_snapshots(self, 
                         snapshot1: Dict[str, Any], 
                         snapshot2: Dict[str, Any]) -> Dict[str, Any]:
        """
        Compare two memory snapshots.
        
        Args:
            snapshot1: First snapshot
            snapshot2: Second snapshot
            
        Returns:
            Dictionary containing comparison results
        """
        try:
            # Create comparison result
            result = {
                'time_diff': snapshot2['timestamp'] - snapshot1['timestamp'],
                'size_diff': snapshot2['total_size'] - snapshot1['total_size'],
                'count_diff': snapshot2['total_count'] - snapshot1['total_count'],
                'new_allocations': [],
                'increased_allocations': [],
                'decreased_allocations': []
            }
            
            # Compare top allocations
            alloc1 = {alloc['file']: alloc for alloc in snapshot1['top_allocations']}
            alloc2 = {alloc['file']: alloc for alloc in snapshot2['top_allocations']}
            
            # Find new allocations
            for file, alloc in alloc2.items():
                if file not in alloc1:
                    result['new_allocations'].append(alloc)
            
            # Find increased allocations
            for file, alloc in alloc2.items():
                if file in alloc1 and alloc['size'] > alloc1[file]['size']:
                    result['increased_allocations'].append({
                        'file': file,
                        'size_diff': alloc['size'] - alloc1[file]['size'],
                        'old_size': alloc1[file]['size'],
                        'new_size': alloc['size']
                    })
            
            # Find decreased allocations
            for file, alloc in alloc2.items():
                if file in alloc1 and alloc['size'] < alloc1[file]['size']:
                    result['decreased_allocations'].append({
                        'file': file,
                        'size_diff': alloc1[file]['size'] - alloc['size'],
                        'old_size': alloc1[file]['size'],
                        'new_size': alloc['size']
                    })
            
            return result
            
        except Exception as e:
            self._logger.error(f"Error comparing snapshots: {e}")
            return {}
    
    def detect_memory_leaks(self, 
                           min_snapshots: int = 3,
                           growth_threshold: float = 1.1) -> List[Dict[str, Any]]:
        """
        Detect potential memory leaks by analyzing memory growth.
        
        Args:
            min_snapshots: Minimum number of snapshots required for analysis
            growth_threshold: Threshold for memory growth (1.1 = 10% growth)
            
        Returns:
            List of potential memory leaks
        """
        if len(self._snapshots) < min_snapshots:
            return []
        
        try:
            # Get recent snapshots
            recent_snapshots = self._snapshots[-min_snapshots:]
            
            # Check for consistent growth
            potential_leaks = []
            
            for i in range(1, len(recent_snapshots)):
                prev = recent_snapshots[i-1]
                curr = recent_snapshots[i]
                
                # Calculate growth rate
                if prev['total_size'] > 0:
                    growth_rate = curr['total_size'] / prev['total_size']
                    
                    if growth_rate > growth_threshold:
                        # Check for consistent growth patterns
                        consistent_growth = True
                        
                        for j in range(2, len(recent_snapshots)):
                            if i-j >= 0:
                                earlier = recent_snapshots[i-j]
                                if earlier['total_size'] > 0:
                                    earlier_growth = curr['total_size'] / earlier['total_size']
                                    if earlier_growth <= growth_threshold:
                                        consistent_growth = False
                                        break
                        
                        if consistent_growth:
                            # Get comparison details
                            comparison = self.compare_snapshots(prev, curr)
                            
                            potential_leaks.append({
                                'start_time': prev['timestamp'],
                                'end_time': curr['timestamp'],
                                'start_size': prev['total_size'],
                                'end_size': curr['total_size'],
                                'growth_rate': growth_rate,
                                'size_diff': comparison['size_diff'],
                                'new_allocations': comparison['new_allocations'],
                                'increased_allocations': comparison['increased_allocations']
                            })
            
            return potential_leaks
            
        except Exception as e:
            self._logger.error(f"Error detecting memory leaks: {e}")
            return []
    
    def force_gc(self, generation: int = 2) -> None:
        """
        Force garbage collection.
        
        Args:
            generation: Generation to collect (0, 1, or 2)
        """
        self._logger.info(f"Force garbage collection for generation {generation}")
        
        # Get GC counts before collection
        before_counts = gc.get_count()
        
        # Trigger garbage collection
        collected = gc.collect(generation)
        
        # Get GC counts after collection
        after_counts = gc.get_count()
        
        # Calculate collected objects
        gen_collected = after_counts[generation] - before_counts[generation]
        
        self._logger.info(
            f"Force GC Gen {generation} completed: {gen_collected} objects collected"
        )
    
    def clear_history(self) -> None:
        """
        Clear GC stats and snapshots history.
        """
        with self._gc_stats_lock:
            self._gc_stats.clear()
        
        with self._snapshots_lock:
            self._snapshots.clear()
        
        self._logger.info("GC stats and snapshots history cleared")
    
    def shutdown(self) -> None:
        """
        Shutdown the garbage collection monitor.
        """
        # Stop snapshot thread
        self._stop_snapshot_thread()
        
        # Unregister GC callbacks
        if self._enable_gc_callbacks:
            self._unregister_gc_callbacks()
        
        # Stop tracemalloc if enabled
        if self._enable_tracemalloc:
            tracemalloc.stop()
        
        self._logger.info("GarbageCollectionMonitor shutdown")