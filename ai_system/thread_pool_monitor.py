import logging
import time
import threading
from typing import Dict, Any, Optional, Callable
from .thread_pool import ThreadPool


class ThreadPoolMonitor:
    """
    Monitor untuk ThreadPool yang menyediakan logging dan statistik secara periodik.
    """
    
    def __init__(self, 
                 thread_pool: ThreadPool, 
                 log_interval: float = 10.0,
                 logger_name: str = __name__):
        """
        Inisialisasi ThreadPoolMonitor.
        
        Args:
            thread_pool: Instance ThreadPool yang akan dimonitor
            log_interval: Interval logging dalam detik (default: 10.0)
            logger_name: Nama logger (default: __name__)
        """
        self._thread_pool = thread_pool
        self._log_interval = log_interval
        self._logger = logging.getLogger(logger_name)
        
        # Flag untuk mengontrol monitoring
        self._running = False
        self._monitor_thread: Optional[threading.Thread] = None
        
        # Callback untuk custom logging
        self._custom_log_callback: Optional[Callable[[Dict[str, Any]], None]] = None
        
        self._logger.info("ThreadPoolMonitor initialized")
    
    def set_custom_log_callback(self, callback: Callable[[Dict[str, Any]], None]):
        """
        Set custom callback untuk logging.
        
        Args:
            callback: Fungsi callback yang menerima stats dictionary
        """
        self._custom_log_callback = callback
        self._logger.info("Custom log callback set")
    
    def _log_stats(self):
        """Log statistik thread pool."""
        try:
            # Dapatkan statistik dari thread pool
            stats = self._thread_pool.get_stats()
            
            # Format log message
            log_message = (
                f"ThreadPool Stats: "
                f"Active={stats['active_tasks']}, "
                f"Queue={stats['queue_size']}/{stats['max_queue_size']}, "
                f"Completed={stats['completed_tasks']}, "
                f"Failed={stats['failed_tasks']}, "
                f"Workers={stats['max_workers']}, "
                f"Shutdown={stats['is_shutdown']}"
            )
            
            # Log dengan level INFO
            self._logger.info(log_message)
            
            # Log warning jika queue hampir penuh
            if stats['queue_size'] > stats['max_queue_size'] * 0.8:
                self._logger.warning(
                    f"ThreadPool queue is almost full: {stats['queue_size']}/{stats['max_queue_size']}"
                )
            
            # Log warning jika terlalu banyak task yang gagal
            if stats['failed_tasks'] > 0 and stats['total_tasks'] > 0:
                failure_rate = stats['failed_tasks'] / stats['total_tasks']
                if failure_rate > 0.1:  # Lebih dari 10% failure rate
                    self._logger.warning(
                        f"High task failure rate: {failure_rate:.2%} "
                        f"({stats['failed_tasks']}/{stats['total_tasks']})"
                    )
            
            # Panggil custom callback jika diset
            if self._custom_log_callback:
                self._custom_log_callback(stats)
                
        except Exception as e:
            self._logger.error(f"Error logging thread pool stats: {e}")
    
    def _monitor_loop(self):
        """Loop monitoring yang berjalan di thread terpisah."""
        while self._running:
            try:
                self._log_stats()
                
                # Tunggu interval atau sampai dihentikan
                for _ in range(int(self._log_interval)):
                    if not self._running:
                        break
                    time.sleep(1)
                    
            except Exception as e:
                self._logger.error(f"Error in monitor loop: {e}")
                time.sleep(1)  # Prevent rapid error loops
    
    def start(self):
        """Mulai monitoring thread pool."""
        if self._running:
            self._logger.warning("ThreadPoolMonitor is already running")
            return
        
        self._running = True
        self._monitor_thread = threading.Thread(
            target=self._monitor_loop,
            daemon=True
        )
        self._monitor_thread.start()
        
        self._logger.info(f"ThreadPoolMonitor started with {self._log_interval}s interval")
    
    def stop(self):
        """Hentikan monitoring thread pool."""
        if not self._running:
            self._logger.warning("ThreadPoolMonitor is not running")
            return
        
        self._running = False
        
        # Tunggu monitor thread selesai
        if self._monitor_thread:
            self._monitor_thread.join(timeout=2.0)
        
        self._logger.info("ThreadPoolMonitor stopped")
    
    def __enter__(self):
        """Context manager entry."""
        self.start()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.stop()


def create_thread_pool_monitor(thread_pool: ThreadPool, 
                              log_interval: float = 10.0,
                              auto_start: bool = True) -> ThreadPoolMonitor:
    """
    Factory function untuk membuat ThreadPoolMonitor.
    
    Args:
        thread_pool: Instance ThreadPool yang akan dimonitor
        log_interval: Interval logging dalam detik (default: 10.0)
        auto_start: Apakah monitor harus langsung dimulai (default: True)
        
    Returns:
        Instance ThreadPoolMonitor
    """
    monitor = ThreadPoolMonitor(
        thread_pool=thread_pool,
        log_interval=log_interval
    )
    
    if auto_start:
        monitor.start()
    
    return monitor