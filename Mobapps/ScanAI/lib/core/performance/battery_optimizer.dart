import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';
import '../constants/app_constants.dart';

/// Optimizer untuk penggunaan baterai
///
/// BatteryOptimizer bertanggung jawab untuk:
/// - Memantau level baterai dan status charging
/// - Menyesuaikan pengaturan aplikasi berdasarkan status baterai
/// - Memberikan rekomendasi untuk penghematan baterai
/// - Mengoptimalkan penggunaan baterai saat aplikasi berjalan
class BatteryOptimizer extends ChangeNotifier {
  factory BatteryOptimizer() {
    return _instance;
  }

  BatteryOptimizer._internal() {
    _initialize();
  }
  static const String _tag = 'BatteryOptimizer';

  // Singleton pattern
  static final BatteryOptimizer _instance = BatteryOptimizer._internal();

  // Battery instance
  final Battery _battery = Battery();

  // Timer untuk monitoring baterai
  Timer? _monitoringTimer;
  StreamSubscription<BatteryState>? _batteryStateSubscription;

  // Status baterai
  int _batteryLevel = 100;
  bool _isCharging = false;
  BatteryOptimizationLevel _optimizationLevel =
      BatteryOptimizationLevel.balanced;

  // Pengaturan optimasi
  bool _autoOptimization = true;
  int _lowBatteryThreshold = 20;
  int _criticalBatteryThreshold = 5;

  // Getter
  int get batteryLevel => _batteryLevel;
  bool get isCharging => _isCharging;
  BatteryOptimizationLevel get optimizationLevel => _optimizationLevel;
  bool get autoOptimization => _autoOptimization;
  int get lowBatteryThreshold => _lowBatteryThreshold;
  int get criticalBatteryThreshold => _criticalBatteryThreshold;

  /// Inisialisasi BatteryOptimizer
  void _initialize() {
    if (AppConstants.isDebugMode) {
      developer.log('$_tag: Initializing BatteryOptimizer', name: _tag);
    }

    // Get initial battery level
    _updateBatteryStatus();

    // Listen to battery state changes
    _batteryStateSubscription = _battery.onBatteryStateChanged.listen((state) {
      _isCharging =
          state == BatteryState.charging || state == BatteryState.full;
      _updateBatteryStatus();
      _autoOptimize();
    });

    // Mulai monitoring baterai
    _startBatteryMonitoring();
  }

  /// Memulai monitoring status baterai
  void _startBatteryMonitoring() {
    if (AppConstants.isDebugMode) {
      developer.log('$_tag: Starting battery monitoring', name: _tag);
    }

    _monitoringTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _updateBatteryStatus();
      _autoOptimize();
    });
  }

  /// Memperbarui status baterai
  ///
  /// Menggunakan battery_plus untuk mendapatkan informasi baterai yang akurat
  Future<void> _updateBatteryStatus() async {
    try {
      // Get actual battery level from device
      final level = await _battery.batteryLevel;
      _batteryLevel = level;

      // Get charging state
      final state = await _battery.batteryState;
      _isCharging =
          state == BatteryState.charging || state == BatteryState.full;

      notifyListeners();
    } catch (e) {
      if (AppConstants.isDebugMode) {
        developer.log('$_tag: Error getting battery status: $e', name: _tag);
      }
      // Keep previous values on error
    }
  }

  /// Optimasi otomatis berdasarkan status baterai
  void _autoOptimize() {
    if (!_autoOptimization) {
      return;
    }

    if (_batteryLevel <= _criticalBatteryThreshold) {
      // Mode hemat baterai maksimal
      _setOptimizationLevel(BatteryOptimizationLevel.maxBatterySaver);
    } else if (_batteryLevel <= _lowBatteryThreshold) {
      // Mode hemat baterai
      _setOptimizationLevel(BatteryOptimizationLevel.batterySaver);
    } else if (_isCharging) {
      // Mode performa saat charging
      _setOptimizationLevel(BatteryOptimizationLevel.performance);
    } else {
      // Mode seimbang untuk kondisi normal
      _setOptimizationLevel(BatteryOptimizationLevel.balanced);
    }
  }

  /// Mengatur level optimasi baterai
  void _setOptimizationLevel(BatteryOptimizationLevel level) {
    if (_optimizationLevel == level) {
      return;
    }

    if (AppConstants.isDebugMode) {
      developer.log(
        '$_tag: Setting battery optimization level to: $level',
        name: _tag,
      );
    }

    _optimizationLevel = level;

    // Terapkan pengaturan berdasarkan level optimasi
    _applyOptimizationSettings();

    notifyListeners();
  }

  /// Menerapkan pengaturan berdasarkan level optimasi
  void _applyOptimizationSettings() {
    switch (_optimizationLevel) {
      case BatteryOptimizationLevel.performance:
        if (AppConstants.isDebugMode) {
          developer.log('$_tag: Applying performance settings', name: _tag);
        }
        // Pengaturan untuk performa maksimal
        // - Frame rate tinggi
        // - Kualitas video tinggi
        // - Efek visual aktif
        break;

      case BatteryOptimizationLevel.balanced:
        if (AppConstants.isDebugMode) {
          developer.log('$_tag: Applying balanced settings', name: _tag);
        }
        // Pengaturan seimbang
        // - Frame rate sedang
        // - Kualitas video sedang
        // - Efek visual terbatas
        break;

      case BatteryOptimizationLevel.batterySaver:
        if (AppConstants.isDebugMode) {
          developer.log('$_tag: Applying battery saver settings', name: _tag);
        }
        // Pengaturan hemat baterai
        // - Frame rate rendah
        // - Kualitas video rendah
        // - Efek visual minimal
        break;

      case BatteryOptimizationLevel.maxBatterySaver:
        if (AppConstants.isDebugMode) {
          developer.log('$_tag: Applying max battery saver settings', name: _tag);
        }
        // Pengaturan hemat baterai maksimal
        // - Frame rate minimal
        // - Kualitas video minimal
        // - Tidak ada efek visual
        // - Background process dimatikan
        break;
    }
  }

  /// Mengatur level optimasi baterai
  void setOptimizationLevel(BatteryOptimizationLevel level) {
    _setOptimizationLevel(level);
  }

  /// Mengatur status auto optimasi
  void setAutoOptimization(bool enabled) {
    if (AppConstants.isDebugMode) {
      developer.log('$_tag: Setting auto optimization to: $enabled', name: _tag);
    }

    _autoOptimization = enabled;

    if (enabled) {
      _autoOptimize();
    }

    notifyListeners();
  }

  /// Mengatur threshold baterai rendah
  void setLowBatteryThreshold(int threshold) {
    if (AppConstants.isDebugMode) {
      developer.log(
        '$_tag: Setting low battery threshold to: $threshold%',
        name: _tag,
      );
    }

    _lowBatteryThreshold = threshold.clamp(1, 99);

    if (_autoOptimization) {
      _autoOptimize();
    }

    notifyListeners();
  }

  /// Mengatur threshold baterai kritis
  void setCriticalBatteryThreshold(int threshold) {
    if (AppConstants.isDebugMode) {
      developer.log(
        '$_tag: Setting critical battery threshold to: $threshold%',
        name: _tag,
      );
    }

    _criticalBatteryThreshold = threshold.clamp(1, _lowBatteryThreshold - 1);

    if (_autoOptimization) {
      _autoOptimize();
    }

    notifyListeners();
  }

  /// Simulasi perubahan level baterai (untuk testing)
  void simulateBatteryLevel(int level) {
    if (AppConstants.isDebugMode) {
      developer.log('$_tag: Simulating battery level to: $level%', name: _tag);
    }

    _batteryLevel = level.clamp(0, 100);

    if (_autoOptimization) {
      _autoOptimize();
    }

    notifyListeners();
  }

  /// Simulasi perubahan status charging (untuk testing)
  void simulateChargingStatus(bool charging) {
    if (AppConstants.isDebugMode) {
      developer.log(
        '$_tag: Simulating charging status to: $charging',
        name: _tag,
      );
    }

    _isCharging = charging;

    if (_autoOptimization) {
      _autoOptimize();
    }

    notifyListeners();
  }

  /// Mendapatkan estimasi waktu tersisa baterai
  ///
  /// Di implementasi nyata, kita bisa menggunakan algoritma yang lebih kompleks
  /// berdasarkan pola penggunaan dan konsumsi daya
  String getEstimatedTimeRemaining() {
    if (_isCharging) {
      return 'Mengisi daya...';
    }

    if (_batteryLevel <= 0) {
      return 'Baterai habis';
    }

    // Simulasi estimasi waktu (dalam jam)
    // Di implementasi nyata, gunakan data konsumsi daya yang sebenarnya
    final estimatedHours = _batteryLevel / 20; // Asumsi 20% per jam

    if (estimatedHours >= 1) {
      return '${estimatedHours.toStringAsFixed(1)} jam tersisa';
    } else {
      final estimatedMinutes = estimatedHours * 60;
      return '${estimatedMinutes.round()} menit tersisa';
    }
  }

  /// Mendapatkan rekomendasi penghematan baterai
  List<String> getBatteryRecommendations() {
    final recommendations = <String>[];

    if (_batteryLevel <= _criticalBatteryThreshold) {
      recommendations.add(
        'Baterai sangat rendah. Segera hubungkan ke charger.',
      );
      recommendations.add('Matikan aplikasi yang tidak digunakan.');
      recommendations.add('Kurangi kecerahan layar.');
    } else if (_batteryLevel <= _lowBatteryThreshold) {
      recommendations.add(
        'Baterai rendah. Pertimbangkan untuk menghubungkan ke charger.',
      );
      recommendations.add('Aktifkan mode hemat baterai.');
    }

    if (!_isCharging && _batteryLevel < 50) {
      recommendations.add(
        'Pertimbangkan untuk mengurangi kualitas video untuk menghemat baterai.',
      );
    }

    return recommendations;
  }

  /// Mendapatkan status baterai sebagai string
  String getBatteryStatusText() {
    if (_isCharging) {
      return 'Mengisi daya ($_batteryLevel%)';
    } else if (_batteryLevel <= _criticalBatteryThreshold) {
      return 'Baterai kritis ($_batteryLevel%)';
    } else if (_batteryLevel <= _lowBatteryThreshold) {
      return 'Baterai rendah ($_batteryLevel%)';
    } else {
      return 'Baterai normal ($_batteryLevel%)';
    }
  }

  /// Mendapatkan warna indikator berdasarkan level baterai
  Color getBatteryColor() {
    if (_batteryLevel <= _criticalBatteryThreshold) {
      return Colors.red;
    } else if (_batteryLevel <= _lowBatteryThreshold) {
      return Colors.orange;
    } else if (_batteryLevel <= 50) {
      return Colors.yellow;
    } else {
      return Colors.green;
    }
  }

  /// Membersihkan sumber daya
  @override
  void dispose() {
    _monitoringTimer?.cancel();
    _batteryStateSubscription?.cancel();
    super.dispose();
  }
}

/// Level optimasi baterai
enum BatteryOptimizationLevel {
  performance,
  balanced,
  batterySaver,
  maxBatterySaver,
}

/// Ekstensi untuk BatteryOptimizationLevel
extension BatteryOptimizationLevelExtension on BatteryOptimizationLevel {
  String get name {
    switch (this) {
      case BatteryOptimizationLevel.performance:
        return 'Performa';
      case BatteryOptimizationLevel.balanced:
        return 'Seimbang';
      case BatteryOptimizationLevel.batterySaver:
        return 'Hemat Baterai';
      case BatteryOptimizationLevel.maxBatterySaver:
        return 'Hemat Maksimal';
    }
  }

  String get description {
    switch (this) {
      case BatteryOptimizationLevel.performance:
        return 'Performa maksimal, konsumsi baterai tinggi';
      case BatteryOptimizationLevel.balanced:
        return 'Keseimbangan antara performa dan penghematan baterai';
      case BatteryOptimizationLevel.batterySaver:
        return 'Penghematan baterai dengan performa yang masih baik';
      case BatteryOptimizationLevel.maxBatterySaver:
        return 'Penghematan baterai maksimal, performa minimal';
    }
  }

  IconData get icon {
    switch (this) {
      case BatteryOptimizationLevel.performance:
        return Icons.speed;
      case BatteryOptimizationLevel.balanced:
        return Icons.balance;
      case BatteryOptimizationLevel.batterySaver:
        return Icons.battery_saver;
      case BatteryOptimizationLevel.maxBatterySaver:
        return Icons.battery_alert;
    }
  }
}
