import 'dart:developer' as developer;
import 'dart:collection';
import '../constants/app_constants.dart';

/// Cache yang lebih efisien dengan algoritma LRU (Least Recently Used)
///
/// MemoryCache mengimplementasikan cache dengan:
/// - Batasan ukuran maksimum
/// - Kebijakan eviksi LRU
/// - Timer untuk kedaluwarsa otomatis
/// - Statistik cache untuk monitoring
class MemoryCache<K, V> {
  /// Constructor
  MemoryCache({
    required int maxSize,
    Duration defaultExpiration = const Duration(minutes: 30),
  })  : _maxSize = maxSize,
        _defaultExpiration = defaultExpiration;
  static const String _tag = 'MemoryCache';

  final int _maxSize;
  final Duration _defaultExpiration;
  final Map<K, _CacheEntry<V>> _storage = {};
  final LinkedHashMap<K, _CacheEntry<V>> _lruCache = LinkedHashMap();

  /// Statistik cache
  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;

  /// Mendapatkan ukuran cache saat ini
  int get size => _storage.length;

  /// Mendapatkan ukuran maksimum cache
  int get maxSize => _maxSize;

  /// Mendapatkan rasio hit cache
  double get hitRatio => _hits + _misses > 0 ? _hits / (_hits + _misses) : 0.0;

  /// Mendapatkan jumlah hit
  int get hits => _hits;

  /// Mendapatkan jumlah miss
  int get misses => _misses;

  /// Mendapatkan jumlah eviksi
  int get evictions => _evictions;

  /// Menyimpan nilai ke cache
  void put(K key, V value, {Duration? expiration}) {
    if (AppConstants.isDebugMode) {
      developer.log('$_tag: Putting value to cache with key: $key', name: _tag);
    }

    // Hapus entri lama jika ada
    _removeEntry(key);

    // Buat entri baru
    final exp = expiration ?? _defaultExpiration;
    final entry = _CacheEntry<V>(
      value: value,
      expiration: exp.inMilliseconds > 0 ? DateTime.now().add(exp) : null,
    );

    // Simpan ke storage
    _storage[key] = entry;
    _lruCache[key] = entry;

    // Periksa ukuran cache
    _checkSize();
  }

  /// Mendapatkan nilai dari cache
  V? get(K key) {
    final entry = _storage[key];
    if (entry == null) {
      _misses++;
      return null;
    }

    // Periksa kedaluwarsa
    if (entry.expiration != null && DateTime.now().isAfter(entry.expiration!)) {
      _removeEntry(key);
      _misses++;
      return null;
    }

    // Update posisi di LRU
    _lruCache.remove(key);
    _lruCache[key] = entry;

    _hits++;
    return entry.value;
  }

  /// Memeriksa apakah key ada di cache
  bool containsKey(K key) {
    return _storage.containsKey(key) && get(key) != null;
  }

  /// Menghapus nilai dari cache
  void remove(K key) {
    _removeEntry(key);
  }

  /// Menghapus semua nilai dari cache
  void clear() {
    if (AppConstants.isDebugMode) {
      developer.log('$_tag: Clearing cache', name: _tag);
    }

    _storage.clear();
    _lruCache.clear();
    _hits = 0;
    _misses = 0;
    _evictions = 0;
  }

  /// Membersihkan entri yang sudah kedaluwarsa
  void cleanExpired() {
    if (AppConstants.isDebugMode) {
      developer.log('$_tag: Cleaning expired entries', name: _tag);
    }

    final now = DateTime.now();
    final expiredKeys = <K>[];

    for (final entry in _storage.entries) {
      if (entry.value.expiration != null &&
          now.isAfter(entry.value.expiration!)) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _removeEntry(key);
    }
  }

  /// Mendapatkan statistik cache
  Map<String, dynamic> getStats() {
    return {
      'size': size,
      'max_size': maxSize,
      'hits': _hits,
      'misses': _misses,
      'evictions': _evictions,
      'hit_ratio': hitRatio,
    };
  }

  /// Menghapus entri dari cache
  void _removeEntry(K key) {
    _storage.remove(key);
    _lruCache.remove(key);
  }

  /// Memeriksa ukuran cache dan eviksi jika perlu
  void _checkSize() {
    if (_storage.length <= _maxSize) {
      return;
    }

    if (AppConstants.isDebugMode) {
      developer.log('$_tag: Cache size exceeded, evicting entries', name: _tag);
    }

    final overflow = _storage.length - _maxSize;
    final keysToRemove = _lruCache.keys.take(overflow).toList();

    for (final key in keysToRemove) {
      _removeEntry(key);
      _evictions++;
    }
  }
}

/// Entri cache dengan nilai dan waktu kedaluwarsa
class _CacheEntry<V> {
  _CacheEntry({
    required this.value,
    this.expiration,
  });
  final V value;
  final DateTime? expiration;
}
