import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/logger.dart';
import './memory_manager.dart';
import './battery_optimizer.dart';

/// Kelas utama untuk mengoptimalkan performa aplikasi
///
/// PerformanceOptimizer bertanggung jawab untuk:
/// - Memantau performa aplikasi secara real-time
/// - Menyesuaikan pengaturan berdasarkan kemampuan device
/// - Memberikan rekomendasi optimasi
/// - Mendeteksi dan mengatasi masalah performa
class PerformanceOptimizer extends ChangeNotifier {
  factory PerformanceOptimizer() {
    return _instance;
  }

  PerformanceOptimizer._internal() {
    _initialize();
  }
  static const String _tag = 'PerformanceOptimizer';

  // Singleton pattern
  static final PerformanceOptimizer _instance =
      PerformanceOptimizer._internal();

  // Komponen optimasi
  late MemoryManager _memoryManager;
  late BatteryOptimizer _batteryOptimizer;

  // Timer untuk monitoring
  Timer? _monitoringTimer;

  // Status performa
  bool _isOptimized = false;
  PerformanceLevel _currentPerformanceLevel = PerformanceLevel.balanced;
  Map<String, dynamic> _performanceMetrics = {};

  // Getter
  bool get isOptimized => _isOptimized;
  PerformanceLevel get currentPerformanceLevel => _currentPerformanceLevel;
  Map<String, dynamic> get performanceMetrics => _performanceMetrics;
  MemoryManager get memoryManager => _memoryManager;
  BatteryOptimizer get batteryOptimizer => _batteryOptimizer;

  /// Inisialisasi komponen-komponen optimasi
  void _initialize() {
    AppLogger.d('Initializing PerformanceOptimizer', category: 'performance');

    _memoryManager = MemoryManager();
    _batteryOptimizer = BatteryOptimizer();

    // Mulai monitoring performa
    _startMonitoring();
  }

  /// Initialize performance optimizer (public method)
  Future<void> initialize() async {
    _initialize();
  }

  /// Memulai monitoring performa aplikasi
  void _startMonitoring() {
    AppLogger.d('Starting performance monitoring', category: 'performance');

    _monitoringTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _collectPerformanceMetrics();
      _autoOptimize();
    });
  }

  /// Mengumpulkan metrik performa
  void _collectPerformanceMetrics() {
    final memoryUsage = _memoryManager.getCurrentMemoryUsage();
    final batteryLevel = _batteryOptimizer.batteryLevel;
    final isCharging = _batteryOptimizer.isCharging;

    _performanceMetrics = {
      'memory_usage': memoryUsage,
      'cpu_usage': 0.0,
      'frame_rate': 0.0,
      'battery_level': batteryLevel,
      'is_charging': isCharging,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    // Log metrik untuk debugging
    AppLogger.d(
      'Performance metrics update',
      category: 'performance',
      context: _performanceMetrics,
      throttleKey: 'perf_metrics_log',
      throttleInterval: const Duration(minutes: 1),
    );
  }

  /// Optimasi otomatis berdasarkan metrik performa
  void _autoOptimize() {
    final memoryUsage = _performanceMetrics['memory_usage'] ?? 0;
    final batteryLevel = _performanceMetrics['battery_level'] ?? 100;
    final isCharging = _performanceMetrics['is_charging'] ?? false;

    // Tentukan level performa yang sesuai
    var newLevel = _currentPerformanceLevel;

    if (!isCharging && batteryLevel < 20) {
      // Mode hemat baterai jika baterai rendah dan tidak sedang di-charge
      newLevel = PerformanceLevel.batterySaver;
    } else if (memoryUsage > 80) {
      // Mode rendah jika penggunaan sumber daya tinggi
      newLevel = PerformanceLevel.low;
    } else {
      // Mode seimbang untuk kondisi normal
      newLevel = PerformanceLevel.balanced;
    }

    // Terapkan level performa baru jika berubah
    if (newLevel != _currentPerformanceLevel) {
      _setPerformanceLevel(newLevel);
    }
  }

  /// Mengatur level performa
  void _setPerformanceLevel(PerformanceLevel level) {
    AppLogger.i('Setting performance level to: $level', category: 'performance');

    _currentPerformanceLevel = level;

    // Terapkan pengaturan berdasarkan level performa
    switch (level) {
      case PerformanceLevel.high:
        _memoryManager.setAggressiveMode(false);
        _batteryOptimizer.setOptimizationLevel(
          BatteryOptimizationLevel.performance,
        );
        break;
      case PerformanceLevel.balanced:
        _memoryManager.setAggressiveMode(false);
        _batteryOptimizer.setOptimizationLevel(
          BatteryOptimizationLevel.balanced,
        );
        break;
      case PerformanceLevel.low:
        _memoryManager.setAggressiveMode(true);
        _batteryOptimizer.setOptimizationLevel(
          BatteryOptimizationLevel.balanced,
        );
        break;
      case PerformanceLevel.batterySaver:
        _memoryManager.setAggressiveMode(true);
        _batteryOptimizer.setOptimizationLevel(
          BatteryOptimizationLevel.batterySaver,
        );
        break;
    }

    _isOptimized = true;
    notifyListeners();
  }

  /// Mengoptimalkan untuk operasi berat (misalnya streaming video)
  void optimizeForHeavyOperation() {
    AppLogger.d('Optimizing for heavy operation', category: 'performance');

    // Bersihkan memori sebelum operasi berat
    _memoryManager.clearCache();

    // Pastikan CPU dalam performa tinggi
    _setPerformanceLevel(PerformanceLevel.high);
  }

  /// Mengoptimalkan untuk operasi ringan (misalnya idle)
  void optimizeForLightOperation() {
    AppLogger.d('Optimizing for light operation', category: 'performance');

    // Kurangi penggunaan sumber daya
    _setPerformanceLevel(PerformanceLevel.low);
  }

  /// Mendapatkan rekomendasi optimasi
  List<String> getOptimizationRecommendations() {
    final recommendations = <String>[];

    final memoryUsage = _performanceMetrics['memory_usage'] ?? 0;
    final batteryLevel = _performanceMetrics['battery_level'] ?? 100;

    if (memoryUsage > 80) {
      recommendations.add(
        'Penggunaan memori tinggi. Pertimbangkan untuk membersihkan cache atau menutup aplikasi lain.',
      );
    }

    if (batteryLevel < 20) {
      recommendations.add(
        'Baterai rendah. Pertimbangkan untuk mengaktifkan mode hemat baterai atau menghubungkan charger.',
      );
    }

    return recommendations;
  }

  /// Membersihkan sumber daya
  @override
  void dispose() {
    _monitoringTimer?.cancel();
    super.dispose();
  }
}

/// Level performa aplikasi
enum PerformanceLevel { high, balanced, low, batterySaver }

/// Ekstensi untuk PerformanceLevel
extension PerformanceLevelExtension on PerformanceLevel {
  String get name {
    switch (this) {
      case PerformanceLevel.high:
        return 'Tinggi';
      case PerformanceLevel.balanced:
        return 'Seimbang';
      case PerformanceLevel.low:
        return 'Rendah';
      case PerformanceLevel.batterySaver:
        return 'Hemat Baterai';
    }
  }

  String get description {
    switch (this) {
      case PerformanceLevel.high:
        return 'Performa maksimum untuk kualitas terbaik';
      case PerformanceLevel.balanced:
        return 'Keseimbangan antara performa dan efisiensi';
      case PerformanceLevel.low:
        return 'Penggunaan sumber daya minimal';
      case PerformanceLevel.batterySaver:
        return 'Menghemat baterai sebanyak mungkin';
    }
  }
}
