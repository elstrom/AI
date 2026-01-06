import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:scanai_app/core/constants/app_constants.dart';

/// System Monitor Service
/// Android and iOS implementation for monitoring system metrics (CPU, Memory, Threads, Thermal)
/// Used for debugging performance and stability issues
class SystemMonitorService {
  static const _channel = MethodChannel('com.scanai/system_monitor');
  
  Timer? _updateTimer;
  double _currentCpuUsage = 0.0;
  int _currentThreadCount = 0;
  String _currentThermalStatus = 'Unknown';
  Map<String, dynamic> _currentMemoryInfo = {};
  Map<String, dynamic> _currentStorageInfo = {};
  
  /// Stream controller for all system metrics
  final _metricsController = StreamController<Map<String, dynamic>>.broadcast();
  
  /// Stream of all system metrics
  Stream<Map<String, dynamic>> get metricsStream => _metricsController.stream;
  
  /// Shortcut streams for individual metrics
  Stream<double> get cpuUsageStream => metricsStream.map((m) => m['cpuUsage'] as double);
  
  /// Getters for current values
  double get currentCpuUsage => _currentCpuUsage;
  int get currentThreadCount => _currentThreadCount;
  String get currentThermalStatus => _currentThermalStatus;
  Map<String, dynamic> get currentMemoryInfo => _currentMemoryInfo;
  Map<String, dynamic> get currentStorageInfo => _currentStorageInfo;
  
  /// Start monitoring system metrics
  /// Uses [AppConstants.cpuMonitorIntervalMs] by default
  /// Now supports both Android and iOS (Native SystemMonitor added to iOS)
  void startMonitoring({int? intervalMs}) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (!AppConstants.isDebugMode) return;
    
    stopMonitoring();
    
    final interval = intervalMs ?? AppConstants.cpuMonitorIntervalMs;
    _updateTimer = Timer.periodic(Duration(milliseconds: interval), (_) {
      _updateMetrics();
    });
    
    _updateMetrics();
  }
  
  /// Stop monitoring
  void stopMonitoring() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }
  
  /// Update all metrics from native
  Future<void> _updateMetrics() async {
    try {
      final cpuUsage = await _channel.invokeMethod<double>('getCpuUsage') ?? 0.0;
      final threadCount = await _channel.invokeMethod<int>('getThreadCount') ?? 0;
      final thermalStatusValue = await _channel.invokeMethod<int>('getThermalStatus') ?? -1;
      final memInfo = await _channel.invokeMapMethod<String, dynamic>('getMemoryInfo') ?? {};
      final storageInfo = await _channel.invokeMapMethod<String, dynamic>('getStorageInfo') ?? {};
      
      _currentCpuUsage = cpuUsage;
      _currentThreadCount = threadCount;
      _currentThermalStatus = _parseThermalStatus(thermalStatusValue);
      _currentMemoryInfo = memInfo;
      _currentStorageInfo = storageInfo;
      
      _metricsController.add({
        'cpuUsage': _currentCpuUsage,
        'threadCount': _currentThreadCount,
        'thermalStatus': _currentThermalStatus,
        'memoryInfo': _currentMemoryInfo,
        'storageInfo': _currentStorageInfo,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      // Silently fail in debug monitor
    }
  }
  
  /// Parse thermal status value to human-readable string
  /// Android PowerManager thermal status: 0-6
  /// iOS ProcessInfo.thermalState: 0-3 (Nominal, Fair, Serious, Critical)
  String _parseThermalStatus(int value) {
    if (Platform.isIOS) {
      // iOS thermal states (ProcessInfo.ThermalState)
      switch (value) {
        case 0: return 'Nominal (Cool)';    // .nominal
        case 1: return 'Fair (Warm)';       // .fair
        case 2: return 'Serious (Hot)';     // .serious
        case 3: return 'Critical';          // .critical
        case -1: return 'Not Supported';
        default: return 'Unknown ($value)';
      }
    } else {
      // Android thermal status (PowerManager.THERMAL_STATUS_*)
      switch (value) {
        case 0: return 'Normal (Ideal)';    // THERMAL_STATUS_NONE
        case 1: return 'Light (Warm)';      // THERMAL_STATUS_LIGHT
        case 2: return 'Moderate';          // THERMAL_STATUS_MODERATE
        case 3: return 'Severe (Hot)';      // THERMAL_STATUS_SEVERE
        case 4: return 'Critical';          // THERMAL_STATUS_CRITICAL
        case 5: return 'Emergency';         // THERMAL_STATUS_EMERGENCY
        case 6: return 'Shutdown';          // THERMAL_STATUS_SHUTDOWN
        case -1: return 'Not Supported';
        default: return 'Unknown ($value)';
      }
    }
  }
  
  /// Dispose resources
  void dispose() {
    stopMonitoring();
    _metricsController.close();
  }
}
