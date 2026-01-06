import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import 'memory_cache.dart';

/// Manajer memori untuk mengoptimalkan penggunaan memori aplikasi
///
/// MemoryManager bertanggung jawab untuk:
/// - Memantau penggunaan memori
/// - Membersihkan cache yang tidak digunakan
/// - Mengelola alokasi memori untuk operasi berat
/// - Mendeteksi dan mencegah memory leak
class MemoryManager extends ChangeNotifier {
  factory MemoryManager() {
    return _instance;
  }

  MemoryManager._internal() {
    _initialize();
  }
  static const String _tag = 'MemoryManager';

  // Singleton pattern
  static final MemoryManager _instance = MemoryManager._internal();

  // Timer untuk monitoring memori
  Timer? _monitoringTimer;

  // Cache untuk menyimpan data sementara
  late MemoryCache<String, dynamic> _cache;

  // Pengaturan
  bool _aggressiveMode = false;
  int _maxCacheSize = 50; // Jumlah maksimum item dalam cache
  Duration _cacheExpiration = const Duration(minutes: 30);

  // Status memori
  double _currentMemoryUsage = 0;
  double _peakMemoryUsage = 0;
  int _cacheHits = 0;
  int _cacheMisses = 0;

  // Getter
  bool get aggressiveMode => _aggressiveMode;
  double get currentMemoryUsage => _currentMemoryUsage;
  double get peakMemoryUsage => _peakMemoryUsage;
  int get cacheSize => _cache.size;
  int get maxCacheSize => _maxCacheSize;
  double get cacheHitRatio => _cacheHits + _cacheMisses > 0
      ? _cacheHits / (_cacheHits + _cacheMisses)
      : 0.0;

  /// Inisialisasi MemoryManager
  void _initialize() {
    if (AppConstants.isDebugMode) {
      developer.log('$_tag: Initializing MemoryManager', name: _tag);
    }

    // Inisialisasi cache
    _cache = MemoryCache<String, dynamic>(
      maxSize: _maxCacheSize,
      defaultExpiration: _cacheExpiration,
    );

    // Mulai monitoring memori
    _startMemoryMonitoring();
  }

  /// Memulai monitoring penggunaan memori
  void _startMemoryMonitoring() {
    if (AppConstants.isDebugMode) {
      developer.log('$_tag: Starting memory monitoring', name: _tag);
    }

    _monitoringTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _updateMemoryUsage();
      _checkMemoryPressure();
    });
  }

  /// Memperbarui informasi penggunaan memori
  void _updateMemoryUsage() {
    // Di platform native, kita bisa menggunakan package seperti device_info_plus
    // atau platform channel untuk mendapatkan informasi memori yang lebih akurat
    // Untuk sekarang, kita gunakan nilai dummy

    // Simulasi penggunaan memori (dalam MB)
    final simulatedUsage =
        50 + (_cache.size * 0.5) + (DateTime.now().millisecondsSinceEpoch % 30);

    _currentMemoryUsage = simulatedUsage;
    if (_currentMemoryUsage > _peakMemoryUsage) {
      _peakMemoryUsage = _currentMemoryUsage;
    }

    notifyListeners();
  }

  /// Memeriksa tekanan memori dan membersihkan jika diperlukan
  void _checkMemoryPressure() {
    // Jika penggunaan memori tinggi atau mode agresif aktif, bersihkan cache
    if (_currentMemoryUsage > 80 || _aggressiveMode) {
      _cleanCache();
    }

    // Jika cache terlalu besar, hapus item tertua
    if (_cache.size > _maxCacheSize) {
      _evictOldestItems();
    }
  }

  /// Mengatur mode agresif untuk pembersihan memori
  void setAggressiveMode(bool aggressive) {
    if (AppConstants.isDebugMode) {
      developer.log('$_tag: Setting aggressive mode to: $aggressive', name: _tag);
    }

    _aggressiveMode = aggressive;

    if (aggressive) {
      _cleanCache();
    }

    notifyListeners();
  }

  /// Mengatur ukuran maksimum cache
  void setMaxCacheSize(int size) {
    if (AppConstants.isDebugMode) {
      developer.log('$_tag: Setting max cache size to: $size', name: _tag);
    }

    _maxCacheSize = size;

    // Jika cache saat ini lebih besar dari ukuran baru, hapus item tertua
    if (_cache.size > _maxCacheSize) {
      _evictOldestItems();
    }

    notifyListeners();
  }

  /// Mengatur waktu kedaluwarsa cache
  void setCacheExpiration(Duration duration) {
    if (AppConstants.isDebugMode) {
      developer.log('$_tag: Setting cache expiration to: $duration', name: _tag);
    }

    _cacheExpiration = duration;

    // Bersihkan cache yang sudah kedaluwarsa
    _cleanExpiredCache();

    notifyListeners();
  }

  /// Menyimpan data ke cache
  void putCache<T>(String key, T data, {Duration? expiration}) {
    if (AppConstants.isDebugMode) {
      developer.log('$_tag: Putting data to cache with key: $key', name: _tag);
    }

    // Simpan data
    _cache.put(key, data, expiration: expiration);

    // Periksa ukuran cache
    if (_cache.size > _maxCacheSize) {
      _evictOldestItems();
    }

    notifyListeners();
  }

  /// Mendapatkan data dari cache
  T? getCache<T>(String key) {
    final value = _cache.get(key);
    if (value != null) {
      if (AppConstants.isDebugMode) {
        developer.log('$_tag: Cache hit for key: $key', name: _tag);
      }
      _cacheHits++;
    } else {
      if (AppConstants.isDebugMode) {
        developer.log('$_tag: Cache miss for key: $key', name: _tag);
      }
      _cacheMisses++;
    }
    return value as T?;
  }

  /// Menghapus data dari cache
  void removeCache(String key) {
    if (AppConstants.isDebugMode) {
      developer.log('$_tag: Removing cache with key: $key', name: _tag);
    }

    // Hapus data dari cache
    _cache.remove(key);

    notifyListeners();
  }

  /// Membersihkan semua cache
  void clearCache() {
    if (AppConstants.isDebugMode) {
      developer.log('$_tag: Clearing all cache', name: _tag);
    }

    // Hapus semua data dari cache
    _cache.clear();

    notifyListeners();
  }

  /// Membersihkan cache yang tidak digunakan
  void _cleanCache() {
    if (AppConstants.isDebugMode) {
      developer.log('$_tag: Cleaning cache', name: _tag);
    }

    // MemoryCache sudah menggunakan algoritma LRU otomatis
    // Kita hanya perlu membersihkan cache yang sudah kedaluwarsa
    _cache.cleanExpired();
  }

  /// Menghapus item cache yang sudah kedaluwarsa
  void _cleanExpiredCache() {
    // MemoryCache sudah menangani kedaluwarsa otomatis
  }

  /// Menghapus item cache tertua
  void _evictOldestItems() {
    if (AppConstants.isDebugMode) {
      developer.log('$_tag: Evicting oldest cache items', name: _tag);
    }

    // MemoryCache sudah menggunakan algoritma LRU otomatis
    // Kita tidak perlu melakukan apa-apa lagi di sini
  }

  /// Mengalokasikan memori untuk operasi berat
  ///
  /// Metode ini akan memeriksa penggunaan memori saat ini dan membersihkan cache
  /// jika diperlukan sebelum melakukan operasi berat
  bool allocateMemoryForHeavyOperation(int requiredMb) {
    if (AppConstants.isDebugMode) {
      developer.log(
        '$_tag: Allocating $requiredMb MB for heavy operation',
        name: _tag,
      );
    }

    // Jika penggunaan memori sudah tinggi, bersihkan cache
    if (_currentMemoryUsage > 70) {
      _cleanCache();
    }

    // Periksa apakah ada cukup memori yang tersedia
    // Di implementasi nyata, kita bisa menggunakan package seperti device_info_plus
    // untuk mendapatkan informasi memori yang lebih akurat
    final availableMemory = 100 - _currentMemoryUsage; // Simulasi

    if (availableMemory >= requiredMb) {
      if (AppConstants.isDebugMode) {
        developer.log('$_tag: Memory allocated successfully', name: _tag);
      }
      return true;
    } else {
      if (AppConstants.isDebugMode) {
        developer.log('$_tag: Not enough memory available', name: _tag);
      }
      return false;
    }
  }

  /// Mendapatkan penggunaan memori saat ini
  double getCurrentMemoryUsage() {
    return _currentMemoryUsage;
  }

  /// Mendapatkan statistik cache
  Map<String, dynamic> getCacheStats() {
    final cacheStats = _cache.getStats();
    return {
      'size': _cache.size,
      'max_size': _cache.maxSize,
      'hits': _cacheHits,
      'misses': _cacheMisses,
      'hit_ratio': cacheHitRatio,
      'evictions': cacheStats['evictions'] ?? 0,
    };
  }

  /// Membersihkan sumber daya
  @override
  void dispose() {
    // Hapus timer monitoring
    _monitoringTimer?.cancel();

    // Bersihkan cache
    _cache.clear();

    super.dispose();
  }
}
