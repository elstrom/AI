import 'dart:async';
import 'dart:collection';
import 'package:scanai_app/core/utils/logger.dart';

/// Performance metrics types
enum PerformanceMetric {
  frameRate,
  cpuUsage,
  memoryUsage,
  taskExecutionTime,
  threadUtilization,
  queueSize,
  latency,
  throughput,
}

/// Performance alert levels
enum PerformanceAlertLevel { info, warning, critical }

/// Performance alert
class PerformanceAlert {
  PerformanceAlert({
    required this.level,
    required this.message,
    required this.metric,
    required this.value,
    required this.threshold,
  }) : timestamp = DateTime.now();

  /// Alert level
  final PerformanceAlertLevel level;

  /// Alert message
  final String message;

  /// Metric that triggered the alert
  final PerformanceMetric metric;

  /// Alert timestamp
  final DateTime timestamp;

  /// Current value
  final double value;

  /// Threshold value
  final double threshold;

  @override
  String toString() {
    return 'PerformanceAlert(level: $level, metric: $metric, value: $value, threshold: $threshold, message: $message)';
  }
}

/// Performance metrics data
class PerformanceMetrics {
  PerformanceMetrics() : timestamp = DateTime.now();

  /// Frame rate (FPS)
  double frameRate = 0.0;

  /// CPU usage percentage
  double cpuUsage = 0.0;

  /// Memory usage in MB
  double memoryUsage = 0.0;

  /// Average task execution time in ms
  double avgTaskExecutionTime = 0.0;

  /// Thread utilization percentage
  double threadUtilization = 0.0;

  /// Average queue size
  double avgQueueSize = 0.0;

  /// Average latency in ms
  double avgLatency = 0.0;

  /// Throughput (tasks per second)
  double throughput = 0.0;

  /// Metrics timestamp
  final DateTime timestamp;

  /// Convert to map
  Map<String, dynamic> toMap() {
    return {
      'frameRate': frameRate,
      'cpuUsage': cpuUsage,
      'memoryUsage': memoryUsage,
      'avgTaskExecutionTime': avgTaskExecutionTime,
      'threadUtilization': threadUtilization,
      'avgQueueSize': avgQueueSize,
      'avgLatency': avgLatency,
      'throughput': throughput,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  @override
  String toString() {
    return 'PerformanceMetrics('
        'FPS: ${frameRate.toStringAsFixed(1)}, '
        'CPU: ${cpuUsage.toStringAsFixed(1)}%, '
        'Memory: ${memoryUsage.toStringAsFixed(1)}MB, '
        'TaskTime: ${avgTaskExecutionTime.toStringAsFixed(1)}ms, '
        'Threads: ${threadUtilization.toStringAsFixed(1)}%, '
        'Queue: ${avgQueueSize.toStringAsFixed(1)}, '
        'Latency: ${avgLatency.toStringAsFixed(1)}ms, '
        'Throughput: ${throughput.toStringAsFixed(1)}/s)';
  }
}

/// Performance thresholds configuration
class PerformanceThresholds {
  const PerformanceThresholds({
    this.minFrameRate = 15.0,
    this.maxCpuUsage = 80.0,
    this.maxMemoryUsage = 500.0,
    this.maxTaskExecutionTime = 100.0,
    this.minThreadUtilization = 30.0,
    this.maxQueueSize = 20.0,
    this.maxLatency = 200.0,
    this.minThroughput = 10.0,
  });

  /// Minimum acceptable frame rate (FPS)
  final double minFrameRate;

  /// Maximum acceptable CPU usage percentage
  final double maxCpuUsage;

  /// Maximum acceptable memory usage in MB
  final double maxMemoryUsage;

  /// Maximum acceptable task execution time in ms
  final double maxTaskExecutionTime;

  /// Minimum acceptable thread utilization percentage
  final double minThreadUtilization;

  /// Maximum acceptable queue size
  final double maxQueueSize;

  /// Maximum acceptable latency in ms
  final double maxLatency;

  /// Minimum acceptable throughput (tasks per second)
  final double minThroughput;

  /// Check if a metric value is within threshold
  bool isWithinThreshold(PerformanceMetric metric, double value) {
    switch (metric) {
      case PerformanceMetric.frameRate:
        return value >= minFrameRate;
      case PerformanceMetric.cpuUsage:
        return value <= maxCpuUsage;
      case PerformanceMetric.memoryUsage:
        return value <= maxMemoryUsage;
      case PerformanceMetric.taskExecutionTime:
        return value <= maxTaskExecutionTime;
      case PerformanceMetric.threadUtilization:
        return value >= minThreadUtilization;
      case PerformanceMetric.queueSize:
        return value <= maxQueueSize;
      case PerformanceMetric.latency:
        return value <= maxLatency;
      case PerformanceMetric.throughput:
        return value >= minThroughput;
    }
  }

  /// Get threshold value for a metric
  double getThreshold(PerformanceMetric metric) {
    switch (metric) {
      case PerformanceMetric.frameRate:
        return minFrameRate;
      case PerformanceMetric.cpuUsage:
        return maxCpuUsage;
      case PerformanceMetric.memoryUsage:
        return maxMemoryUsage;
      case PerformanceMetric.taskExecutionTime:
        return maxTaskExecutionTime;
      case PerformanceMetric.threadUtilization:
        return minThreadUtilization;
      case PerformanceMetric.queueSize:
        return maxQueueSize;
      case PerformanceMetric.latency:
        return maxLatency;
      case PerformanceMetric.throughput:
        return minThroughput;
    }
  }

  /// Check metrics and generate alerts
  List<PerformanceAlert> checkMetrics(PerformanceMetrics metrics) {
    final alerts = <PerformanceAlert>[];

    // Check frame rate
    if (!isWithinThreshold(PerformanceMetric.frameRate, metrics.frameRate)) {
      alerts.add(
        PerformanceAlert(
          level: PerformanceAlertLevel.warning,
          message:
              'Frame rate is too low: ${metrics.frameRate.toStringAsFixed(1)} FPS',
          metric: PerformanceMetric.frameRate,
          value: metrics.frameRate,
          threshold: minFrameRate,
        ),
      );
    }

    // Check CPU usage
    if (!isWithinThreshold(PerformanceMetric.cpuUsage, metrics.cpuUsage)) {
      alerts.add(
        PerformanceAlert(
          level: PerformanceAlertLevel.critical,
          message:
              'CPU usage is too high: ${metrics.cpuUsage.toStringAsFixed(1)}%',
          metric: PerformanceMetric.cpuUsage,
          value: metrics.cpuUsage,
          threshold: maxCpuUsage,
        ),
      );
    }

    // Check memory usage
    if (!isWithinThreshold(
      PerformanceMetric.memoryUsage,
      metrics.memoryUsage,
    )) {
      alerts.add(
        PerformanceAlert(
          level: PerformanceAlertLevel.warning,
          message:
              'Memory usage is too high: ${metrics.memoryUsage.toStringAsFixed(1)} MB',
          metric: PerformanceMetric.memoryUsage,
          value: metrics.memoryUsage,
          threshold: maxMemoryUsage,
        ),
      );
    }

    // Check task execution time
    if (!isWithinThreshold(
      PerformanceMetric.taskExecutionTime,
      metrics.avgTaskExecutionTime,
    )) {
      alerts.add(
        PerformanceAlert(
          level: PerformanceAlertLevel.warning,
          message:
              'Task execution time is too high: ${metrics.avgTaskExecutionTime.toStringAsFixed(1)} ms',
          metric: PerformanceMetric.taskExecutionTime,
          value: metrics.avgTaskExecutionTime,
          threshold: maxTaskExecutionTime,
        ),
      );
    }

    // Check thread utilization
    if (!isWithinThreshold(
      PerformanceMetric.threadUtilization,
      metrics.threadUtilization,
    )) {
      alerts.add(
        PerformanceAlert(
          level: PerformanceAlertLevel.info,
          message:
              'Thread utilization is too low: ${metrics.threadUtilization.toStringAsFixed(1)}%',
          metric: PerformanceMetric.threadUtilization,
          value: metrics.threadUtilization,
          threshold: minThreadUtilization,
        ),
      );
    }

    // Check queue size
    if (!isWithinThreshold(PerformanceMetric.queueSize, metrics.avgQueueSize)) {
      alerts.add(
        PerformanceAlert(
          level: PerformanceAlertLevel.warning,
          message:
              'Queue size is too large: ${metrics.avgQueueSize.toStringAsFixed(1)}',
          metric: PerformanceMetric.queueSize,
          value: metrics.avgQueueSize,
          threshold: maxQueueSize,
        ),
      );
    }

    // Check latency
    if (!isWithinThreshold(PerformanceMetric.latency, metrics.avgLatency)) {
      alerts.add(
        PerformanceAlert(
          level: PerformanceAlertLevel.warning,
          message:
              'Latency is too high: ${metrics.avgLatency.toStringAsFixed(1)} ms',
          metric: PerformanceMetric.latency,
          value: metrics.avgLatency,
          threshold: maxLatency,
        ),
      );
    }

    // Check throughput
    if (!isWithinThreshold(PerformanceMetric.throughput, metrics.throughput)) {
      alerts.add(
        PerformanceAlert(
          level: PerformanceAlertLevel.warning,
          message:
              'Throughput is too low: ${metrics.throughput.toStringAsFixed(1)}/s',
          metric: PerformanceMetric.throughput,
          value: metrics.throughput,
          threshold: minThroughput,
        ),
      );
    }

    return alerts;
  }
}

/// Performance monitor that tracks and analyzes system performance
///
/// This class monitors various performance metrics including:
/// - Frame rate (FPS)
/// - CPU usage
/// - Memory usage
/// - Task execution time
/// - Thread utilization
/// - Queue size
/// - Latency
/// - Throughput
///
/// It provides real-time monitoring, alerts, and performance analysis.
class PerformanceMonitor {
  /// Create a new performance monitor
  PerformanceMonitor({
    PerformanceThresholds? thresholds,
    int maxHistorySize = 100,
    Duration monitoringInterval = const Duration(seconds: 1),
  })  : thresholds = thresholds ?? const PerformanceThresholds(),
        _maxHistorySize = maxHistorySize,
        _monitoringInterval = monitoringInterval {
    AppLogger.i('Performance monitor created');
  }

  /// Whether the monitor is initialized
  bool _isInitialized = false;

  /// Get whether the monitor is initialized
  bool get isInitialized => _isInitialized;

  /// Performance thresholds
  final PerformanceThresholds thresholds;

  /// Current metrics
  PerformanceMetrics _currentMetrics = PerformanceMetrics();

  /// Metrics history
  final ListQueue<PerformanceMetrics> _metricsHistory = ListQueue();

  /// Maximum history size
  final int _maxHistorySize;

  /// Performance alerts
  final StreamController<PerformanceAlert> _alertController =
      StreamController<PerformanceAlert>.broadcast();

  /// Metrics stream
  final StreamController<PerformanceMetrics> _metricsController =
      StreamController<PerformanceMetrics>.broadcast();

  /// Monitoring timer
  Timer? _monitoringTimer;

  /// Whether to monitor performance
  bool _isMonitoring = false;

  /// Monitoring interval
  final Duration _monitoringInterval;

  /// Frame rate calculation
  int _frameCount = 0;
  DateTime? _lastFrameTime;

  /// Task execution times
  final List<double> _taskExecutionTimes = [];

  /// Queue sizes
  final List<double> _queueSizes = [];

  /// Latencies
  final List<double> _latencies = [];

  /// Throughput calculation
  int _taskCount = 0;
  DateTime? _lastTaskTime;

  /// Get current metrics
  PerformanceMetrics get currentMetrics => _currentMetrics;

  /// Get metrics history
  List<PerformanceMetrics> get metricsHistory => _metricsHistory.toList();

  /// Get performance alerts stream
  Stream<PerformanceAlert> get alertStream => _alertController.stream;

  /// Get metrics stream
  Stream<PerformanceMetrics> get metricsStream => _metricsController.stream;

  /// Get whether to monitor performance
  bool get isMonitoring => _isMonitoring;

  /// Initialize the performance monitor
  Future<void> initialize() async {
    AppLogger.i('Initializing performance monitor');
    // Initialize any resources needed for the performance monitor
    // This is a placeholder for any initialization that might be needed
    _isInitialized = true;
    AppLogger.i('Performance monitor initialized successfully', context: {
      'is_initialized': _isInitialized,
    });
  }

  /// Start monitoring
  Future<void> start() async {
    if (_isMonitoring) {
      AppLogger.w('Performance monitor is already running');
      return;
    }

    try {
      // Start monitoring timer
      _monitoringTimer = Timer.periodic(_monitoringInterval, (_) {
        _updateMetrics();
      });

      _isMonitoring = true;
      AppLogger.i('Performance monitor started');
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to start performance monitor: $e',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Stop monitoring
  Future<void> stop() async {
    if (!_isMonitoring) {
      AppLogger.w('Performance monitor is not running');
      return;
    }

    try {
      // Stop monitoring timer
      _monitoringTimer?.cancel();
      _monitoringTimer = null;

      _isMonitoring = false;
      AppLogger.i('Performance monitor stopped');
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to stop performance monitor: $e',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Update metrics
  void _updateMetrics() {
    try {
      // Create new metrics
      final metrics = PerformanceMetrics();

      // Update frame rate
      metrics.frameRate = _calculateFrameRate();

      // Update CPU usage (simulated)
      metrics.cpuUsage = _simulateCpuUsage();

      // Update memory usage (simulated)
      metrics.memoryUsage = _simulateMemoryUsage();

      // Update task execution time
      metrics.avgTaskExecutionTime = _calculateAvgTaskExecutionTime();

      // Update thread utilization (simulated)
      metrics.threadUtilization = _simulateThreadUtilization();

      // Update queue size
      metrics.avgQueueSize = _calculateAvgQueueSize();

      // Update latency
      metrics.avgLatency = _calculateAvgLatency();

      // Update throughput
      metrics.throughput = _calculateThroughput();

      // Set current metrics
      _currentMetrics = metrics;

      // Add to history
      _metricsHistory.add(metrics);
      if (_metricsHistory.length > _maxHistorySize) {
        _metricsHistory.removeFirst();
      }

      // Check for alerts
      _checkForAlerts(metrics);

      // Notify metrics stream
      _metricsController.add(metrics);
    } catch (e, stackTrace) {
      AppLogger.e(
        'Error updating metrics: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Calculate frame rate
  double _calculateFrameRate() {
    if (_lastFrameTime == null) {
      return 0.0;
    }

    final now = DateTime.now();
    final timeDiff = now.difference(_lastFrameTime!).inMilliseconds;

    if (timeDiff <= 0) {
      return 0.0;
    }

    final fps = (_frameCount * 1000) / timeDiff;

    // Reset frame count
    _frameCount = 0;
    _lastFrameTime = now;

    return fps;
  }

  /// Simulate CPU usage
  double _simulateCpuUsage() {
    // In a real implementation, you would use platform-specific APIs
    // to get actual CPU usage

    // For now, return a simulated value
    return 30.0 + (DateTime.now().millisecondsSinceEpoch % 40);
  }

  /// Simulate memory usage
  double _simulateMemoryUsage() {
    // In a real implementation, you would use platform-specific APIs
    // to get actual memory usage

    // For now, return a simulated value
    return 100.0 + (DateTime.now().millisecondsSinceEpoch % 100);
  }

  /// Calculate average task execution time
  double _calculateAvgTaskExecutionTime() {
    if (_taskExecutionTimes.isEmpty) {
      return 0.0;
    }

    final totalTime = _taskExecutionTimes.reduce((a, b) => a + b);
    return totalTime / _taskExecutionTimes.length;
  }

  /// Simulate thread utilization
  double _simulateThreadUtilization() {
    // In a real implementation, you would calculate actual thread utilization

    // For now, return a simulated value
    return 50.0 + (DateTime.now().millisecondsSinceEpoch % 30);
  }

  /// Calculate average queue size
  double _calculateAvgQueueSize() {
    if (_queueSizes.isEmpty) {
      return 0.0;
    }

    final totalSize = _queueSizes.reduce((a, b) => a + b);
    return totalSize / _queueSizes.length;
  }

  /// Calculate average latency
  double _calculateAvgLatency() {
    if (_latencies.isEmpty) {
      return 0.0;
    }

    final totalLatency = _latencies.reduce((a, b) => a + b);
    return totalLatency / _latencies.length;
  }

  /// Calculate throughput
  double _calculateThroughput() {
    if (_lastTaskTime == null) {
      return 0.0;
    }

    final now = DateTime.now();
    final timeDiff = now.difference(_lastTaskTime!).inSeconds;

    if (timeDiff <= 0) {
      return 0.0;
    }

    final throughput = _taskCount / timeDiff;

    // Reset task count
    _taskCount = 0;
    _lastTaskTime = now;

    return throughput;
  }

  /// Check for performance alerts
  int _alertDebounceCounter = 0;

  void _checkForAlerts(PerformanceMetrics metrics) {
    try {
      final alerts = thresholds.checkMetrics(metrics);

      for (final alert in alerts) {
        _alertController.add(alert);

        // PERFORMANCE: Only log alerts every 10 seconds (10 * 1 second interval)
        // to reduce log spam while still notifying via stream
        _alertDebounceCounter++;
        if (_alertDebounceCounter >= 10) {
          _alertDebounceCounter = 0;
          switch (alert.level) {
            case PerformanceAlertLevel.info:
              // Skip info level logging entirely - too verbose
              break;
            case PerformanceAlertLevel.warning:
              AppLogger.w('Performance alert: ${alert.message}');
              break;
            case PerformanceAlertLevel.critical:
              AppLogger.e('Performance alert: ${alert.message}');
              break;
          }
        }
      }
    } catch (e, stackTrace) {
      AppLogger.e(
        'Error checking for alerts: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Record a frame
  void recordFrame() {
    _frameCount++;

    _lastFrameTime ??= DateTime.now();
  }

  /// Record a task execution time
  void recordTaskExecutionTime(double timeMs) {
    _taskExecutionTimes.add(timeMs);

    // Keep only the last 100 execution times
    if (_taskExecutionTimes.length > 100) {
      _taskExecutionTimes.removeAt(0);
    }

    _taskCount++;

    _lastTaskTime ??= DateTime.now();
  }

  /// Record a queue size
  void recordQueueSize(double size) {
    _queueSizes.add(size);

    // Keep only the last 100 queue sizes
    if (_queueSizes.length > 100) {
      _queueSizes.removeAt(0);
    }
  }

  /// Record a latency
  void recordLatency(double latencyMs) {
    _latencies.add(latencyMs);

    // Keep only the last 100 latencies
    if (_latencies.length > 100) {
      _latencies.removeAt(0);
    }
  }

  /// Get performance statistics
  Map<String, dynamic> get statistics {
    final history = _metricsHistory.toList();

    if (history.isEmpty) {
      return {
        'currentMetrics': _currentMetrics.toMap(),
        'historySize': 0,
        'isMonitoring': _isMonitoring,
      };
    }

    // Calculate statistics from history
    final avgFrameRate =
        history.fold<double>(0.0, (sum, m) => sum + m.frameRate) /
            history.length;
    final maxFrameRate =
        history.map((m) => m.frameRate).reduce((a, b) => a > b ? a : b);
    final minFrameRate =
        history.map((m) => m.frameRate).reduce((a, b) => a < b ? a : b);

    final avgCpuUsage =
        history.fold<double>(0.0, (sum, m) => sum + m.cpuUsage) /
            history.length;
    final maxCpuUsage =
        history.map((m) => m.cpuUsage).reduce((a, b) => a > b ? a : b);

    final avgMemoryUsage =
        history.fold<double>(0.0, (sum, m) => sum + m.memoryUsage) /
            history.length;
    final maxMemoryUsage =
        history.map((m) => m.memoryUsage).reduce((a, b) => a > b ? a : b);

    final avgTaskExecutionTime =
        history.fold<double>(0.0, (sum, m) => sum + m.avgTaskExecutionTime) /
            history.length;
    final maxTaskExecutionTime = history
        .map((m) => m.avgTaskExecutionTime)
        .reduce((a, b) => a > b ? a : b);

    final avgThreadUtilization =
        history.fold<double>(0.0, (sum, m) => sum + m.threadUtilization) /
            history.length;
    final minThreadUtilization =
        history.map((m) => m.threadUtilization).reduce((a, b) => a < b ? a : b);

    final avgQueueSize =
        history.fold<double>(0.0, (sum, m) => sum + m.avgQueueSize) /
            history.length;
    final maxQueueSize =
        history.map((m) => m.avgQueueSize).reduce((a, b) => a > b ? a : b);

    final avgLatency =
        history.fold<double>(0.0, (sum, m) => sum + m.avgLatency) /
            history.length;
    final maxLatency =
        history.map((m) => m.avgLatency).reduce((a, b) => a > b ? a : b);

    final avgThroughput =
        history.fold<double>(0.0, (sum, m) => sum + m.throughput) /
            history.length;
    final minThroughput =
        history.map((m) => m.throughput).reduce((a, b) => a < b ? a : b);

    return {
      'currentMetrics': _currentMetrics.toMap(),
      'historySize': history.length,
      'isMonitoring': _isMonitoring,
      'frameRate': {
        'avg': avgFrameRate,
        'max': maxFrameRate,
        'min': minFrameRate,
      },
      'cpuUsage': {'avg': avgCpuUsage, 'max': maxCpuUsage},
      'memoryUsage': {'avg': avgMemoryUsage, 'max': maxMemoryUsage},
      'taskExecutionTime': {
        'avg': avgTaskExecutionTime,
        'max': maxTaskExecutionTime,
      },
      'threadUtilization': {
        'avg': avgThreadUtilization,
        'min': minThreadUtilization,
      },
      'queueSize': {'avg': avgQueueSize, 'max': maxQueueSize},
      'latency': {'avg': avgLatency, 'max': maxLatency},
      'throughput': {'avg': avgThroughput, 'min': minThroughput},
    };
  }

  /// Clear metrics history
  void clearHistory() {
    _metricsHistory.clear();
    AppLogger.i('Performance metrics history cleared');
  }

  /// Reset all metrics
  void reset() {
    _currentMetrics = PerformanceMetrics();
    _metricsHistory.clear();
    _frameCount = 0;
    _lastFrameTime = null;
    _taskExecutionTimes.clear();
    _queueSizes.clear();
    _latencies.clear();
    _taskCount = 0;
    _lastTaskTime = null;
    AppLogger.i('Performance metrics reset');
  }

  /// Get current CPU usage
  double getCpuUsage() {
    return _currentMetrics.cpuUsage;
  }

  /// Get current frame rate
  double getFrameRate() {
    return _currentMetrics.frameRate;
  }

  /// Dispose performance monitor
  void dispose() {
    if (_isMonitoring) {
      stop();
    }

    _alertController.close();
    _metricsController.close();
    AppLogger.i('Performance monitor disposed');
  }
}
