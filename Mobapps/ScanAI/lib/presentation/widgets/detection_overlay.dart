import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:scanai_app/data/models/detection_model.dart';
import 'package:scanai_app/presentation/widgets/bounding_box_painter.dart';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/core/constants/app_constants.dart';
import 'package:scanai_app/core/utils/ui_helper.dart';

/// Detection overlay widget for displaying object detection results
///
/// This widget overlays bounding boxes and labels on top of the camera preview
/// to show the detected objects in real-time.
///
/// Example usage:
/// ```dart
/// DetectionOverlay(
///   detectionResult: detection,
///   previewWidth: 320.0,
///   previewHeight: 240.0,
///   showConfidence: true,
///   showClassNames: true,
///   lineWidth: 2.0,
///   fontSize: 12.0,
///   defaultColor: Colors.red,
/// )
/// ```
class DetectionOverlay extends StatelessWidget {
  const DetectionOverlay({
    super.key,
    required this.detectionResult,
    required this.previewWidth,
    required this.previewHeight,
    this.lineWidth = 2.0,
    this.fontSize = 12.0,
    this.showConfidence = true,
    this.showClassNames = true,
    this.showTrackingIds = false,
    this.colorMap,
    this.defaultColor = Colors.red,
    this.boxOpacity = 1.0,
    this.labelOpacity = 0.8,
    this.enableLogging = AppConstants.isDebugMode,
  });

  /// Detection results to display
  final DetectionModel? detectionResult;

  /// Width of the preview area
  final double previewWidth;

  /// Height of the preview area
  final double previewHeight;

  /// Line width for bounding boxes
  final double lineWidth;

  /// Font size for labels
  final double fontSize;

  /// Whether to show confidence scores
  final bool showConfidence;

  /// Whether to show class names
  final bool showClassNames;

  /// Whether to show tracking IDs
  final bool showTrackingIds;

  /// Color map for different classes
  final Map<String, Color>? colorMap;

  /// Default color for bounding boxes
  final Color defaultColor;

  /// Opacity for bounding boxes
  final double boxOpacity;

  /// Opacity for label backgrounds
  final double labelOpacity;

  /// Enable logging for debugging
  final bool enableLogging;

  @override
  Widget build(BuildContext context) {
    final buildTime = DateTime.now();

    if (detectionResult == null || detectionResult!.objects.isEmpty) {
      if (enableLogging) {
        AppLogger.d(
          'DetectionOverlay: No detection results to display',
          category: 'DetectionOverlay',
          context: {
            'has_detection_result': detectionResult != null,
            'objects_count': detectionResult?.objects.length ?? 0,
            'build_timestamp': buildTime.millisecondsSinceEpoch,
          },
        );
      }
      return const SizedBox.shrink();
    }

    if (enableLogging) {
      AppLogger.d(
        'DetectionOverlay: Rendering detection results',
        category: 'DetectionOverlay',
        context: {
          'objects_count': detectionResult!.objects.length,
          'preview_size': '${previewWidth}x$previewHeight',
          'image_size':
              '${detectionResult!.imageWidth}x${detectionResult!.imageHeight}',
          'build_timestamp': buildTime.millisecondsSinceEpoch,
          'show_confidence': showConfidence,
          'show_class_names': showClassNames,
          'show_tracking_ids': showTrackingIds,
          'line_width': lineWidth,
          'font_size': fontSize,
          'box_opacity': boxOpacity,
          'label_opacity': labelOpacity,
        },
      );
    }

    try {
      return SizedBox(
        width: previewWidth,
        height: previewHeight,
        child: CustomPaint(
          painter: BoundingBoxPainter(
            objects: detectionResult!.objects,
            imageWidth: detectionResult!.imageWidth.toDouble(),
            imageHeight: detectionResult!.imageHeight.toDouble(),
            previewWidth: previewWidth,
            previewHeight: previewHeight,
            lineWidth: lineWidth,
            fontSize: fontSize,
            showConfidence: showConfidence,
            showClassNames: showClassNames,
            showTrackingIds: showTrackingIds,
            colorMap: colorMap,
            defaultColor: defaultColor,
            boxOpacity: boxOpacity,
            labelOpacity: labelOpacity,
            enableLogging: enableLogging,
          ),
        ),
      );
    } catch (e, stackTrace) {
      if (enableLogging) {
        AppLogger.e(
          'DetectionOverlay: Error building widget',
          category: 'DetectionOverlay',
          error: e,
          stackTrace: stackTrace,
          context: {
            'objects_count': detectionResult?.objects.length ?? 0,
            'preview_size': '${previewWidth}x$previewHeight',
            'image_size':
                '${detectionResult?.imageWidth}x${detectionResult?.imageHeight}',
            'build_timestamp': buildTime.millisecondsSinceEpoch,
            'error_type': e.runtimeType.toString(),
          },
        );
      }
      rethrow;
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<DetectionModel?>(
        'detectionResult', detectionResult));
    properties.add(DoubleProperty('previewWidth', previewWidth));
    properties.add(DoubleProperty('previewHeight', previewHeight));
    properties.add(DoubleProperty('lineWidth', lineWidth));
    properties.add(DoubleProperty('fontSize', fontSize));
    properties.add(DiagnosticsProperty<bool>('showConfidence', showConfidence));
    properties.add(DiagnosticsProperty<bool>('showClassNames', showClassNames));
    properties
        .add(DiagnosticsProperty<bool>('showTrackingIds', showTrackingIds));
    properties
        .add(DiagnosticsProperty<Map<String, Color>?>('colorMap', colorMap));
    properties.add(ColorProperty('defaultColor', defaultColor));
    properties.add(DoubleProperty('boxOpacity', boxOpacity));
    properties.add(DoubleProperty('labelOpacity', labelOpacity));
    properties.add(DiagnosticsProperty<bool>('enableLogging', enableLogging));
  }
}

/// Detection overlay with statistics widget
///
/// This widget extends the basic DetectionOverlay to include
/// detection statistics and performance metrics.
///
/// Example usage:
/// ```dart
/// DetectionOverlayWithStats(
///   detectionResult: detection,
///   previewWidth: 320.0,
///   previewHeight: 240.0,
///   fps: 30.0,
///   showStats: true,
///   statsAlignment: Alignment.topLeft,
///   statsBackgroundColor: Colors.black54,
///   statsTextColor: Colors.white,
/// )
/// ```
class DetectionOverlayWithStats extends StatelessWidget {
  const DetectionOverlayWithStats({
    super.key,
    required this.detectionResult,
    required this.previewWidth,
    required this.previewHeight,
    this.fps,
    this.showStats = true,
    this.statsAlignment = Alignment.topLeft,
    this.statsBackgroundColor = const Color(0x80000000),
    this.statsTextColor = Colors.white,
    this.lineWidth = 2.0,
    this.fontSize = 12.0,
    this.showConfidence = true,
    this.showClassNames = true,
    this.showTrackingIds = false,
    this.colorMap,
    this.defaultColor = Colors.red,
    this.boxOpacity = 1.0,
    this.labelOpacity = 0.8,
    this.enableLogging = AppConstants.isDebugMode, // PERFORMANCE: Disabled by default for production
  });

  /// Detection results to display
  final DetectionModel? detectionResult;

  /// Width of the preview area
  final double previewWidth;

  /// Height of the preview area
  final double previewHeight;

  /// Current FPS
  final double? fps;

  /// Whether to show statistics
  final bool showStats;

  /// Statistics position
  final AlignmentGeometry statsAlignment;

  /// Statistics background color
  final Color statsBackgroundColor;

  /// Statistics text color
  final Color statsTextColor;

  /// Line width for bounding boxes
  final double lineWidth;

  /// Font size for labels
  final double fontSize;

  /// Whether to show confidence scores
  final bool showConfidence;

  /// Whether to show class names
  final bool showClassNames;

  /// Whether to show tracking IDs
  final bool showTrackingIds;

  /// Color map for different classes
  final Map<String, Color>? colorMap;

  /// Default color for bounding boxes
  final Color defaultColor;

  /// Opacity for bounding boxes
  final double boxOpacity;

  /// Opacity for label backgrounds
  final double labelOpacity;

  /// Enable logging for debugging
  final bool enableLogging;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: previewWidth,
      height: previewHeight,
      child: Stack(
        children: [
          // Detection overlay
          DetectionOverlay(
            detectionResult: detectionResult,
            previewWidth: previewWidth,
            previewHeight: previewHeight,
            lineWidth: lineWidth,
            fontSize: fontSize,
            showConfidence: showConfidence,
            showClassNames: showClassNames,
            showTrackingIds: showTrackingIds,
            colorMap: colorMap,
            defaultColor: defaultColor,
            boxOpacity: boxOpacity,
            labelOpacity: labelOpacity,
            enableLogging: enableLogging,
          ),
          // Detection stats
          if (showStats)
            _DetectionStats(
              detectionResult: detectionResult,
              fps: fps,
              alignment: statsAlignment,
              backgroundColor: statsBackgroundColor,
              textColor: statsTextColor,
            ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<DetectionModel?>(
        'detectionResult', detectionResult));
    properties.add(DoubleProperty('previewWidth', previewWidth));
    properties.add(DoubleProperty('previewHeight', previewHeight));
    properties.add(DoubleProperty('fps', fps));
    properties.add(DiagnosticsProperty<bool>('showStats', showStats));
    properties.add(DiagnosticsProperty<AlignmentGeometry>(
        'statsAlignment', statsAlignment));
    properties.add(ColorProperty('statsBackgroundColor', statsBackgroundColor));
    properties.add(ColorProperty('statsTextColor', statsTextColor));
    properties.add(DoubleProperty('lineWidth', lineWidth));
    properties.add(DoubleProperty('fontSize', fontSize));
    properties.add(DiagnosticsProperty<bool>('showConfidence', showConfidence));
    properties.add(DiagnosticsProperty<bool>('showClassNames', showClassNames));
    properties
        .add(DiagnosticsProperty<bool>('showTrackingIds', showTrackingIds));
    properties
        .add(DiagnosticsProperty<Map<String, Color>?>('colorMap', colorMap));
    properties.add(ColorProperty('defaultColor', defaultColor));
    properties.add(DoubleProperty('boxOpacity', boxOpacity));
    properties.add(DoubleProperty('labelOpacity', labelOpacity));
    properties.add(DiagnosticsProperty<bool>('enableLogging', enableLogging));
  }
}

/// Detection statistics widget
class _DetectionStats extends StatelessWidget {
  const _DetectionStats({
    required this.detectionResult,
    this.fps,
    this.alignment = Alignment.topLeft,
    this.backgroundColor = const Color(0x80000000),
    this.textColor = Colors.white,
  });

  /// Detection results
  final DetectionModel? detectionResult;

  /// Current FPS
  final double? fps;

  /// Alignment of the stats
  final AlignmentGeometry alignment;

  /// Background color
  final Color backgroundColor;

  /// Text color
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    if (detectionResult == null) {
      return const SizedBox.shrink();
    }
  
    final objectCount = detectionResult!.objects.length;
    final avgConfidence = detectionResult!.averageConfidence;
    final processingTime = detectionResult!.processingTimeMs;

    return Align(
      alignment: alignment,
      child: Container(
        margin: EdgeInsets.only(
            left: context.scaleW(8), 
            top: context.scaleH(90), 
            right: context.scaleW(8), 
            bottom: context.scaleH(8)),
        padding: EdgeInsets.symmetric(horizontal: context.scaleW(8), vertical: context.scaleH(4)),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(context.scaleW(4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Object count
            buildStatText(context, 'Objects: $objectCount'),
 
            // Average confidence
            buildStatText(
              context,
              'Avg. Conf: ${(avgConfidence * 100).toStringAsFixed(1)}%',
            ),
 
            // Processing time
            if (processingTime != null)
              buildStatText(context, 'Proc. Time: ${processingTime}ms'),
 
            // Object counts by class
            ...buildObjectCountsByClass(context),
          ],
        ),
      ),
    );
  }

  /// Build stat text widget
  Widget buildStatText(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        color: textColor,
        fontSize: context.scaleSP(12),
        fontWeight: FontWeight.bold,
      ),
    );
  }
 
  /// Build object counts by class widgets
  List<Widget> buildObjectCountsByClass(BuildContext context) {
    final objectCounts = detectionResult!.objectCountsByClass;
    if (objectCounts.isEmpty) {
      return [];
    }
 
    return objectCounts.entries.map((entry) {
      return buildStatText(context, '${entry.key}: ${entry.value}');
    }).toList();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<DetectionModel?>(
        'detectionResult', detectionResult));
    properties.add(DoubleProperty('fps', fps));
    properties
        .add(DiagnosticsProperty<AlignmentGeometry>('alignment', alignment));
    properties.add(ColorProperty('backgroundColor', backgroundColor));
    properties.add(ColorProperty('textColor', textColor));
  }
}
