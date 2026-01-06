import logging
import threading
import time
import queue
from typing import Callable, Any, Dict, List, Optional, Union
from enum import Enum
from dataclasses import dataclass
from concurrent.futures import ThreadPoolExecutor, Future
import uuid


class TaskPriority(Enum):
    """Enum untuk prioritas tugas."""
    LOW = 0
    MEDIUM = 1
    HIGH = 2
    CRITICAL = 3


@dataclass
class Task:
    """Data class untuk merepresentasikan tugas."""
    id: str
    func: Callable
    args: tuple
    kwargs: dict
    priority: TaskPriority
    future: Future
    created_at: float
    
    def __lt__(self, other):
        """Membandingkan prioritas tugas untuk priority queue."""
        if self.priority.value == other.priority.value:
            # Jika prioritas sama, gunakan urutan kedatangan (FIFO)
            return self.created_at < other.created_at
        return self.priority.value > other.priority.value


class ThreadPool:
    """
    Thread Pool untuk mengelola eksekusi tugas-tugas secara paralel dengan dukungan prioritas.
    """
    
    def __init__(self, 
                 max_workers: int = 10, 
                 task_queue_size: int = 100,
                 graceful_shutdown_timeout: float = 5.0):
        """
        Inisialisasi ThreadPool.
        
        Args:
            max_workers: Jumlah maksimum worker threads
            task_queue_size: Queue unlimited
            graceful_shutdown_timeout: Timeout shutdown (detik)
        """
        self._max_workers = max_workers
        self._graceful_shutdown_timeout = graceful_shutdown_timeout
        self._logger = logging.getLogger(__name__)
        
        # Flag untuk mengontrol thread pool
        self._shutdown = False
        self._shutdown_lock = threading.Lock()
        
        # Antrian tugas dengan prioritas (UNLIMITED - no maxsize)
        self._task_queue = queue.PriorityQueue()
        
        # Thread pool executor untuk eksekusi tugas
        self._executor = ThreadPoolExecutor(max_workers=max_workers)
        
        # Thread untuk memproses antrian tugas
        self._dispatcher_thread = threading.Thread(target=self._dispatch_tasks, daemon=True)
        self._dispatcher_thread.start()
        
        # Statistik thread pool
        self._stats = {
            'total_tasks': 0,
            'completed_tasks': 0,
            'failed_tasks': 0,
            'active_tasks': 0
        }
        self._stats_lock = threading.Lock()
        
        self._logger.info(f"ThreadPool initialized with {max_workers} workers")
    
    def _dispatch_tasks(self):
        """Thread dispatcher untuk mengambil tugas dari antrian dan mengeksekusinya."""
        while not self._is_shutdown():
            try:
                # Ambil tugas dari antrian dengan timeout untuk memeriksa shutdown
                task = self._task_queue.get(timeout=0.1)
                
                # Increment active tasks count BEFORE submitting to executor
                # This ensures active_tasks = (currently running + waiting in executor queue)
                with self._stats_lock:
                    self._stats['active_tasks'] += 1
                
                # Eksekusi tugas menggunakan executor
                self._executor.submit(self._execute_task, task)
                
            except queue.Empty:
                # Antrian kosong, lanjutkan loop
                continue
            except Exception as e:
                self._logger.error(f"[DISPATCH ERROR] Error in task dispatcher: {e}", exc_info=True)
    
    def _execute_task(self, task: Task):
        """Eksekusi tugas."""
        try:
            # Eksekusi fungsi tugas
            result = task.func(*task.args, **task.kwargs)
            
            # Set result pada future
            if not task.future.done():
                task.future.set_result(result)
            
            with self._stats_lock:
                self._stats['completed_tasks'] += 1
                completed = self._stats['completed_tasks']
                total = self._stats['total_tasks']
            self._logger.info(f"[TASK DONE] {completed}/{total}")
            
        except Exception as e:
            # Set exception pada future
            if not task.future.done():
                task.future.set_exception(e)
            
            with self._stats_lock:
                self._stats['failed_tasks'] += 1
                failed = self._stats['failed_tasks']
            
            self._logger.error(f"[TASK FAILED] Task {task.id} failed: {e}, Total Failed: {failed}", exc_info=True)
        
        finally:
            # Decrement active tasks count in finally block to ensure it always happens
            with self._stats_lock:
                self._stats['active_tasks'] -= 1
                
            # Tandai tugas selesai di antrian
            self._task_queue.task_done()
    
    def submit(self, 
               func: Callable, 
               *args, 
               priority: TaskPriority = TaskPriority.MEDIUM, 
               **kwargs) -> Future:
        """
        Submit tugas untuk dieksekusi.
        
        Args:
            func: Fungsi yang akan dieksekusi
            *args: Argumen posisi untuk fungsi
            priority: Prioritas tugas (default: MEDIUM)
            **kwargs: Argumen kata kunci untuk fungsi
            
        Returns:
            Future object untuk tracking hasil eksekusi
            
        Raises:
            RuntimeError: Jika thread pool sudah shutdown
            queue.Full: Jika antrian tugas penuh
        """
        if self._is_shutdown():
            raise RuntimeError("ThreadPool is shutdown")
        
        # Buat ID unik untuk tugas
        task_id = str(uuid.uuid4())
        
        # Buat Future object
        future = Future()
        
        # Buat objek Task
        task = Task(
            id=task_id,
            func=func,
            args=args,
            kwargs=kwargs,
            priority=priority,
            future=future,
            created_at=time.time()
        )
        
        # Tambahkan ke antrian (blocking, unlimited)
        self._task_queue.put(task)
        
        with self._stats_lock:
            self._stats['total_tasks'] += 1
        
        return future
    
    def submit_batch(self, 
                     tasks: List[Dict[str, Any]]) -> List[Future]:
        """
        Submit multiple tasks at once.
        
        Args:
            tasks: List of task dictionaries, each containing:
                - 'func': Function to execute
                - 'args': Positional arguments (optional)
                - 'kwargs': Keyword arguments (optional)
                - 'priority': Task priority (optional, default: MEDIUM)
                
        Returns:
            List of Future objects for tracking execution results
            
        Raises:
            RuntimeError: If thread pool is shutdown
            queue.Full: If task queue is full
        """
        if self._is_shutdown():
            raise RuntimeError("ThreadPool is shutdown")
        
        futures = []
        
        for task_dict in tasks:
            func = task_dict['func']
            args = task_dict.get('args', ())
            kwargs = task_dict.get('kwargs', {})
            priority = task_dict.get('priority', TaskPriority.MEDIUM)
            
            future = self.submit(func, *args, priority=priority, **kwargs)
            futures.append(future)
        
        return futures
    
    def shutdown(self, wait: bool = True, timeout: Optional[float] = None):
        """
        Shutdown thread pool dengan graceful.
        
        Args:
            wait: Jika True, tunggu semua tugas selesai
            timeout: Maximum time to wait for tasks to complete (None for no timeout)
        """
        if self._is_shutdown():
            return
        
        # Set shutdown flag
        with self._shutdown_lock:
            self._shutdown = True
        
        self._logger.info("ThreadPool shutting down...")
        
        # Shutdown executor
        if timeout is None:
            timeout = self._graceful_shutdown_timeout
            
        # ThreadPoolExecutor.shutdown() doesn't accept timeout parameter in some Python versions
        try:
            self._executor.shutdown(wait=wait, timeout=timeout)
        except TypeError:
            # Fallback for Python versions that don't support timeout parameter
            self._executor.shutdown(wait=wait)
        
        # Tunggu dispatcher thread selesai
        if wait:
            self._dispatcher_thread.join(timeout=timeout)
        
        self._logger.info("ThreadPool shutdown complete")
    
    def _is_shutdown(self) -> bool:
        """Check if thread pool is shutdown."""
        with self._shutdown_lock:
            return self._shutdown
    
    def get_stats(self) -> Dict[str, Any]:
        """
        Get thread pool statistics.
        
        Returns:
            Dictionary containing thread pool statistics
        """
        with self._stats_lock:
            stats = self._stats.copy()
        
        stats.update({
            'queue_size': self._task_queue.qsize(),
            'max_workers': self._max_workers,
            'is_shutdown': self._is_shutdown()
        })
        
        return stats
    
    def resize(self, new_max_workers: int):
        """
        Resize thread pool.
        
        Args:
            new_max_workers: New maximum number of workers
            
        Note:
            This will create a new ThreadPoolExecutor with the new size.
            Existing tasks will continue to run on the old executor.
        """
        if new_max_workers <= 0:
            raise ValueError("max_workers must be positive")
        
        if self._is_shutdown():
            raise RuntimeError("Cannot resize shutdown ThreadPool")
        
        self._logger.info(f"Resizing ThreadPool from {self._max_workers} to {new_max_workers} workers")
        
        # Shutdown old executor
        self._executor.shutdown(wait=False)
        
        # Create new executor with new size
        self._max_workers = new_max_workers
        self._executor = ThreadPoolExecutor(max_workers=new_max_workers)
        
        # Start new dispatcher thread
        self._dispatcher_thread = threading.Thread(target=self._dispatch_tasks, daemon=True)
        self._dispatcher_thread.start()
        
        self._logger.info(f"ThreadPool resized to {new_max_workers} workers")
    
    def purge_queue(self):
        """
        Remove all pending tasks from the queue.
        
        Note:
            This only removes pending tasks, not currently executing tasks.
        """
        if self._is_shutdown():
            return
        
        # Clear the queue
        with self._task_queue.mutex:
            self._task_queue.queue.clear()
            self._task_queue.not_full.notify()
        
        self._logger.info("Task queue purged")
    
    def __enter__(self):
        """Context manager entry."""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit with graceful shutdown."""
        self.shutdown(wait=True)