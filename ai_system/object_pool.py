import logging
import time
from typing import Generic, TypeVar, Optional, List, Callable
from threading import Lock, Condition

T = TypeVar('T')

class ObjectPool(Generic[T]):
    """
    Object Pool untuk mengelola objek yang sering digunakan dengan tujuan optimasi memori.
    Mendukung blocking acquisition untuk mencegah resource thrashing.
    """
    
    def __init__(self, 
                 create_object: Callable[[], T], 
                 max_size: int = 10,
                 reset_object: Optional[Callable[[T], None]] = None,
                 block: bool = True,
                 timeout: float = 30.0):
        """
        Inisialisasi Object Pool.
        
        Args:
            create_object: Fungsi untuk membuat objek baru
            max_size: Jumlah maksimum objek yang dapat disimpan dalam pool
            reset_object: Fungsi untuk mereset state objek sebelum digunakan kembali
            block: Jika True, acquire() akan menunggu sampai objek tersedia jika pool penuh
            timeout: Waktu maksimum menunggu objek tersedia (detik)
        """
        self._create_object = create_object
        self._max_size = max_size
        self._reset_object = reset_object
        self._block = block
        self._timeout = timeout
        
        self._pool: List[T] = []
        self._in_use_count = 0
        
        self._lock = Lock()
        self._cond = Condition(self._lock)
        self._logger = logging.getLogger(__name__)
        
    def acquire(self) -> T:
        """
        Mendapatkan objek dari pool.
        Jika pool kosong dan belum mencapai max_size, buat objek baru.
        Jika pool kosong dan sudah max_size:
           - Jika block=True, tunggu sampai ada objek kembali.
           - Jika block=False, buat objek baru sementara (burst mode, hati-hati memory leak).
        
        Returns:
            Objek yang siap digunakan
        """
        with self._cond:
            # Cek apakah ada objek nganggur di pool
            while not self._pool:
                # Pool kosong. Cek apakah kita bisa buat objek baru?
                if self._in_use_count < self._max_size:
                    # Masih ada slot, buat baru
                    try:
                        obj = self._create_object()
                        self._in_use_count += 1
                        self._logger.debug(f"New object created. In use: {self._in_use_count}/{self._max_size}")
                        return obj
                    except Exception as e:
                        self._logger.error(f"Failed to create object: {e}")
                        raise
                
                # Sudah mencapai limit max_size
                if not self._block:
                    # Non-blocking mode: Force create (Burst) - NOT RECOMMENDED for Heavy Objects
                    self._logger.warning(f"Pool limit reached ({self._max_size}), creating temporary burst object!")
                    return self._create_object()
                
                # Blocking mode: Tunggu ada yang balikin
                self._logger.debug(f"Pool exhausted ({self._max_size} in use). Waiting for object...")
                start_time = time.time()
                if not self._cond.wait(timeout=self._timeout):
                    raise TimeoutError(f"Timed out waiting for object from pool after {self._timeout}s")
                
                # Loop lagi untuk cek self._pool setelah bangun
            
            # Ada objek di pool
            obj = self._pool.pop()
            self._in_use_count += 1
            self._logger.debug(f"Object acquired from pool. In use: {self._in_use_count}/{self._max_size}")
            return obj
    
    def release(self, obj: T) -> None:
        """
        Mengembalikan objek ke pool.
        
        Args:
            obj: Objek yang akan dikembalikan ke pool
        """
        with self._cond:
            # Reset objek jika fungsi reset disediakan
            if self._reset_object:
                try:
                    self._reset_object(obj)
                except Exception as e:
                    self._logger.error(f"Error resetting object: {e}")
                    # Jangan kembalikan objek rusak ke pool
                    if self._in_use_count > 0:
                        self._in_use_count -= 1
                    self._cond.notify()
                    return

            # Cek apakah objek ini bagian dari tracked pool atau burst object
            if self._in_use_count > 0:
                self._in_use_count -= 1
                
                # Kembalikan ke pool
                self._pool.append(obj)
                self._logger.debug(f"Object returned. Pool size: {len(self._pool)}, In use: {self._in_use_count}")
                
                # Beritahu thread yang menunggu
                self._cond.notify()
            else:
                # Ini aneh, mungkin burst object atau logic error, discard saja
                self._logger.warning("Object released but tracking count is 0 (discarding)")

    def size(self) -> int:
        with self._lock:
            return len(self._pool)
    
    def in_use_count(self) -> int:
        with self._lock:
            return self._in_use_count
    
    def clear(self) -> None:
        with self._lock:
            self._pool.clear()
            self._in_use_count = 0
            self._logger.debug("Pool cleared")