import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:scanai_app/presentation/state/camera_state.dart';
import 'package:scanai_app/core/constants/app_constants.dart';
import 'dart:io';
import 'package:scanai_app/core/utils/ui_helper.dart';

/// Streaming monitor widget for detailed streaming metrics

class StreamingMonitor extends StatelessWidget {
  const StreamingMonitor({super.key, this.expanded = false, this.onTap});
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Return empty if not expanded to keep the UI clean
    if (!expanded) {
      return const SizedBox.shrink();
    }

    final containerWidth = context.scaleW(AppConstants.monitoringFixedWidth);
    final maxContainerHeight = MediaQuery.of(context).size.height * AppConstants.monitoringMaxHeightMultiplier;

    return Selector<CameraState, String>(
      selector: (_, state) => state.streamingStatus,
      builder: (context, streamingStatus, child) {
        return Container(
          width: containerWidth,
          constraints: BoxConstraints(
            maxHeight: maxContainerHeight,
            maxWidth: context.isTablet ? 450 : double.infinity,
          ),
          margin: EdgeInsets.all(context.scaleW(8)),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8), // Slightly darker for better readability
            borderRadius: BorderRadius.circular(context.scaleW(12)),
            border: Border.all(
              color: _getStatusColor(streamingStatus),
              width: context.scaleW(2),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(context.scaleW(12)),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.all(context.scaleW(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header with status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _getStatusIcon(streamingStatus),
                              color: _getStatusColor(streamingStatus),
                              size: context.scaleW(20),
                            ),
                            SizedBox(width: context.scaleW(8)),
                            Text(
                              'Streaming Monitor',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: context.scaleSP(16),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (onTap != null)
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              color: Colors.white,
                              size: context.scaleW(20),
                            ),
                            onPressed: onTap,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),

                    SizedBox(height: context.scaleH(8)),

                    // Status summary
                    const _ConnectionStatusWidget(),

                    SizedBox(height: context.scaleH(12)),

                    // Basic metrics
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _UploadMetricWidget(),
                        _DownloadMetricWidget(),
                        _FpsMetricWidget(),
                      ],
                    ),

                    // Detailed metrics (when expanded)
                    if (expanded) ...[
                      SizedBox(height: context.scaleH(16)),
                      const Divider(color: Colors.white30),
                      SizedBox(height: context.scaleH(8)),

                      // Connection metrics
                      const _ConnectionMetricsSection(),

                      SizedBox(height: context.scaleH(12)),

                      // Video metrics
                      const _VideoMetricsSection(),

                      SizedBox(height: context.scaleH(12)),

                      // System metrics
                      const _SystemMetricsSection(),
                      
                      // Debugging metrics (only in debug mode)
                      if (AppConstants.isDebugMode) ...[
                        SizedBox(height: context.scaleH(12)),
                        const Divider(color: Colors.white30),
                        SizedBox(height: context.scaleH(8)),
                        const _DebuggingMetricsSection(),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Get status color based on streaming status
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'streaming':
        return Colors.green;
      case 'connected':
        return Colors.blue;
      case 'connecting':
        return Colors.orange;
      case 'error':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// Get status icon based on streaming status
  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'streaming':
        return Icons.videocam;
      case 'connected':
        return Icons.wifi;
      case 'connecting':
        return Icons.wifi_tethering;
      case 'error':
        return Icons.error;
      default:
        return Icons.help_outline;
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<bool>('expanded', expanded));
    properties.add(
        DiagnosticsProperty<VoidCallback?>('onTap', onTap, defaultValue: null));
  }
}

/// Metric item widget
class _MetricItem extends StatelessWidget {
  const _MetricItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: context.scaleW(16)),
            SizedBox(width: context.scaleW(4)),
            Text(
              label,
              style: TextStyle(color: Colors.white70, fontSize: context.scaleSP(10)),
            ),
          ],
        ),
        SizedBox(height: context.scaleH(2)),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: context.scaleSP(12),
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('label', label));
    properties.add(StringProperty('value', value));
    properties.add(DiagnosticsProperty<IconData>('icon', icon));
    properties.add(ColorProperty('color', color));
  }
}

/// Metric section widget
class _MetricSection extends StatelessWidget {
  const _MetricSection({required this.title, required this.metrics});
  final String title;
  final List<_MetricItem> metrics;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: context.scaleSP(14),
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: context.scaleH(8)),
        Wrap(spacing: context.scaleW(16), runSpacing: context.scaleH(8), children: metrics),
      ],
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('title', title));
  }
}

/// Connection status widget with Selector
class _ConnectionStatusWidget extends StatelessWidget {
  const _ConnectionStatusWidget();

  @override
  Widget build(BuildContext context) {
    return Selector<CameraState, ({bool isConnected, bool isStreaming})>(
      selector: (_, state) => (
        isConnected: state.isConnected,
        isStreaming: state.isStreaming,
      ),
      builder: (context, data, child) {
        return Text(
          data.isConnected
              ? (data.isStreaming ? 'Streaming' : 'Connected')
              : 'Disconnected',
          style: TextStyle(
            color: data.isConnected
                ? (data.isStreaming ? Colors.green : Colors.blue)
                : Colors.red,
            fontSize: context.scaleSP(14),
            fontWeight: FontWeight.bold,
          ),
        );
      },
    );
  }
}

/// FPS metric widget with Selector - only rebuilds when FPS changes
class _FpsMetricWidget extends StatelessWidget {
  const _FpsMetricWidget();

  @override
  Widget build(BuildContext context) {
    return Selector<CameraState, double>(
      selector: (_, state) => state.fps,
      builder: (context, fps, child) {
        return _MetricItem(
          label: 'FPS',
          value: fps.toStringAsFixed(1),
          icon: Icons.speed,
          color: Colors.greenAccent,
        );
      },
    );
  }
}

/// Upload bandwidth metric widget with Selector
class _UploadMetricWidget extends StatelessWidget {
  const _UploadMetricWidget();

  @override
  Widget build(BuildContext context) {
    return Selector<CameraState, double>(
      selector: (_, state) => state.uploadBandwidthKBps,
      builder: (context, uploadKBps, child) {
        return _MetricItem(
          label: 'Upload',
          value: '${uploadKBps.toStringAsFixed(1)} KB/s',
          icon: Icons.upload,
          color: Colors.blueAccent,
        );
      },
    );
  }
}

/// Download bandwidth metric widget with Selector
class _DownloadMetricWidget extends StatelessWidget {
  const _DownloadMetricWidget();

  @override
  Widget build(BuildContext context) {
    return Selector<CameraState, double>(
      selector: (_, state) => state.downloadBandwidthKBps,
      builder: (context, downloadKBps, child) {
        return _MetricItem(
          label: 'Download',
          value: '${downloadKBps.toStringAsFixed(1)} KB/s',
          icon: Icons.download,
          color: Colors.green,
        );
      },
    );
  }
}

/// Connection metrics section with Selector
class _ConnectionMetricsSection extends StatelessWidget {
  const _ConnectionMetricsSection();

  @override
  Widget build(BuildContext context) {
    return Selector<CameraState,
        ({bool isConnected, String connectionStatus, String duration})>(
      selector: (_, state) => (
        isConnected: state.isConnected,
        connectionStatus: state.connectionStatus,
        duration: state.formattedStats['Duration'] ?? '0s',
      ),
      builder: (context, data, child) {
        return _MetricSection(
          title: 'Connection',
          metrics: [
            _MetricItem(
              label: 'Status',
              value: data.connectionStatus,
              icon: Icons.wifi,
              color: data.isConnected ? Colors.green : Colors.red,
            ),
            _MetricItem(
              label: 'Duration',
              value: data.duration,
              icon: Icons.timer,
              color: Colors.purple,
            ),
          ],
        );
      },
    );
  }
}

/// Video metrics section with Selector
class _VideoMetricsSection extends StatelessWidget {
  const _VideoMetricsSection();

  String _getResolution(Map<String, dynamic> metrics) {
    if (metrics.isEmpty) {
      return '-';
    }

    final encoderMetrics = metrics['encoderMetrics'] as Map<String, dynamic>?;
    if (encoderMetrics == null) {
      return '-';
    }

    final resolution = encoderMetrics['resolution'] as String?;
    return resolution ?? '-';
  }

  String _getFormat(Map<String, dynamic> metrics) {
    if (metrics.isEmpty) {
      return '-';
    }

    final encoderMetrics = metrics['encoderMetrics'] as Map<String, dynamic>?;
    if (encoderMetrics == null) {
      return '-';
    }

    final format = encoderMetrics['format'] as String?;
    return format?.toUpperCase() ?? '-';
  }

  String _getQuality(Map<String, dynamic> metrics) {
    if (metrics.isEmpty) {
      return '-';
    }

    final encoderMetrics = metrics['encoderMetrics'] as Map<String, dynamic>?;
    if (encoderMetrics == null) {
      return '-';
    }

    final quality = encoderMetrics['quality'] as int?;
    return quality != null ? '$quality%' : '-';
  }

  @override
  Widget build(BuildContext context) {
    return Selector<CameraState, Map<String, dynamic>>(
      selector: (_, state) => state.streamingMetrics,
      builder: (context, metrics, child) {
        return _MetricSection(
          title: 'Video',
          metrics: [
            _MetricItem(
              label: 'Resolution',
              value: _getResolution(metrics),
              icon: Icons.aspect_ratio,
              color: Colors.orange,
            ),
            _MetricItem(
              label: 'Format',
              value: _getFormat(metrics),
              icon: Icons.image,
              color: Colors.teal,
            ),
            _MetricItem(
              label: 'Quality',
              value: _getQuality(metrics),
              icon: Icons.high_quality,
              color: Colors.amber,
            ),
          ],
        );
      },
    );
  }
}

/// System metrics section with Selector
class _SystemMetricsSection extends StatelessWidget {
  const _SystemMetricsSection();

  @override
  Widget build(BuildContext context) {
    return Selector<CameraState,
        ({double memory, int batteryLevel, bool isCharging, String perfMode})>(
      selector: (_, state) => (
        memory: state.memoryManagerLazy.currentMemoryUsage,
        batteryLevel: state.batteryOptimizerLazy.batteryLevel,
        isCharging: state.batteryOptimizerLazy.isCharging,
        perfMode: state.performanceOptimizerLazy.currentPerformanceLevel
            .toString()
            .split('.')
            .last,
      ),
      builder: (context, data, child) {
        return _MetricSection(
          title: 'System',
          metrics: [
            _MetricItem(
              label: 'Memory',
              value: '${data.memory.toStringAsFixed(1)} MB',
              icon: Icons.memory,
              color: Colors.cyan,
            ),
            _MetricItem(
              label: 'Battery',
              value: '${data.batteryLevel}%${data.isCharging ? ' ⚡' : ''}',
              icon: Icons.battery_std,
              color: Colors.amberAccent,
            ),
            _MetricItem(
              label: 'Mode',
              value: data.perfMode,
              icon: Icons.speed,
              color: Colors.indigoAccent,
            ),
          ],
        );
      },
    );
  }
}

/// Debugging metrics section with Selector (only in debug mode)
class _DebuggingMetricsSection extends StatelessWidget {
  const _DebuggingMetricsSection();

  @override
  Widget build(BuildContext context) {
    // Only show on Android or iOS in debug mode (Native SystemMonitor available on both)
    if ((!Platform.isAndroid && !Platform.isIOS) || !AppConstants.isDebugMode) {
      return const SizedBox.shrink();
    }

    return Selector<CameraState,
        ({
          double cpuUsage,
          int threadCount,
          String thermalStatus,
          double availableStorageGB,
          double totalMemGB,
          double availMemGB,
          int framesSent,
          int framesReceived,
          int streamingDurationMs,
        })>(
      selector: (_, state) => (
        cpuUsage: state.systemMonitorLazy.currentCpuUsage,
        threadCount: state.systemMonitorLazy.currentThreadCount,
        thermalStatus: state.systemMonitorLazy.currentThermalStatus,
        availableStorageGB: (state.systemMonitorLazy.currentStorageInfo['availableStorage'] as int? ?? 0) / (1024 * 1024 * 1024),
        totalMemGB: (state.systemMonitorLazy.currentMemoryInfo['totalMemory'] as int? ?? 0) / (1024 * 1024 * 1024),
        availMemGB: (state.systemMonitorLazy.currentMemoryInfo['availableMemory'] as int? ?? 0) / (1024 * 1024 * 1024),
        framesSent: state.framesSent,
        framesReceived: state.framesReceived,
        streamingDurationMs: state.streamingMetrics['streamingDurationMs'] as int? ?? 0,
      ),
      builder: (context, data, child) {
        // Calculate drop rate
        final dropRate = data.framesSent > 0
            ? ((data.framesSent - data.framesReceived) / data.framesSent * 100).clamp(0.0, 100.0)
            : 0.0;

        // Calculate average latency
        final avgLatencyMs = data.framesReceived > 0 && data.streamingDurationMs > 0
            ? (data.streamingDurationMs / data.framesReceived).round()
            : 0;

        return _MetricSection(
          title: 'Debugging',
          metrics: [
            // CPU Usage
            _MetricItem(
              label: 'CPU',
              value: '${data.cpuUsage.toStringAsFixed(1)}%',
              icon: Icons.memory,
              color: Colors.blueAccent,
            ),
            // Thread Count
            _MetricItem(
              label: 'Threads',
              value: '${data.threadCount}',
              icon: Icons.account_tree_outlined,
              color: Colors.deepPurpleAccent,
            ),
            // System Memory
            _MetricItem(
              label: 'Sys RAM',
              value: '${data.availMemGB.toStringAsFixed(1)}/${data.totalMemGB.toStringAsFixed(1)} GB',
              icon: Icons.memory_outlined,
              color: Colors.cyanAccent,
            ),
            // Storage
            _MetricItem(
              label: 'Disk Free',
              value: '${data.availableStorageGB.toStringAsFixed(1)} GB',
              icon: Icons.storage_outlined,
              color: Colors.blueGrey,
            ),
            // Thermal Status
            if (data.thermalStatus != 'Not Supported' && data.thermalStatus != 'Unknown')
              _MetricItem(
                label: 'Thermal',
                value: data.thermalStatus,
                icon: Icons.thermostat_outlined,
                color: Colors.orangeAccent,
              ),
            // Frames Sent
            _MetricItem(
              label: 'Sent',
              value: '${data.framesSent}',
              icon: Icons.upload_outlined,
              color: Colors.blue,
            ),
            // Frames Received (ACKs)
            _MetricItem(
              label: 'ACK',
              value: '${data.framesReceived}',
              icon: Icons.download_outlined,
              color: Colors.teal,
            ),
            // Drop Rate
            _MetricItem(
              label: 'Drop',
              value: '${dropRate.toStringAsFixed(1)}%',
              icon: Icons.warning_amber_outlined,
              color: Colors.amber,
            ),
            // Average Latency
            _MetricItem(
              label: 'Latency',
              value: '${avgLatencyMs}ms',
              icon: Icons.timer_outlined,
              color: Colors.green,
            ),
          ],
        );
      },
    );
  }
}
