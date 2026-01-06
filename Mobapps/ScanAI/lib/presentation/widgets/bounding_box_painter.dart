import 'package:flutter/material.dart';
import 'package:scanai_app/data/models/detection_model.dart';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/core/constants/app_constants.dart';

class BoundingBoxPainter extends CustomPainter {
  /// Creates a new bounding box painter
  BoundingBoxPainter({
    required this.objects,
    required this.imageWidth,
    required this.imageHeight,
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
    this.enablePerformanceOptimization = true,
    this.maxObjectsToRender = 50,
    this.minBoxSize = 5.0,
    this.enableCaching = true,
    this.enableLogging = AppConstants.isDebugMode,
  });

  /// List of detected objects to draw
  final List<DetectionObject> objects;

  /// Image width in pixels
  final double imageWidth;

  /// Image height in pixels
  final double imageHeight;

  /// Preview width in pixels
  final double previewWidth;

  /// Preview height in pixels
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

  /// Performance optimization settings
  final bool enablePerformanceOptimization;
  final int maxObjectsToRender;
  final double minBoxSize;
  final bool enableCaching;

  /// Enable logging for debugging
  final bool enableLogging;

  @override
  void paint(Canvas canvas, Size size) {
    if (objects.isEmpty) {
      if (enableLogging) {
        AppLogger.d('BoundingBoxPainter: No objects to paint');
      }
      return;
    }

    // Apply performance optimizations
    final optimizedObjects = _optimizeObjects(objects);
    if (optimizedObjects.isEmpty) {
      if (enableLogging) {
        AppLogger.d('BoundingBoxPainter: No objects after optimization');
      }
      return;
    }

    if (enableLogging) {
      AppLogger.d(
          'BoundingBoxPainter: Painting ${optimizedObjects.length} objects');
    }

    // Create text painter for labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Calculate destination rect using BoxFit.cover to match CameraPreview
    // We determine the displayed image rect relative to the preview size
    var inputSize = Size(imageWidth, imageHeight);
    final outputSize = Size(previewWidth, previewHeight);

    // HEURISTIC: Handle orientation mismatch (e.g., Portrait Phone vs Landscape Server Buffer)
    // If we are in portrait mode but receiving landscape frames, the server frame is likely a
    // squashed version of the real world (or the preview is the un-squashed version).
    // We treat the "Visual Input Aspect Ratio" as swapped (9:16 instead of 16:9) to match the CameraPreview.
    // This forces non-uniform scaling which "un-squashes" the BBox.
    final isRotated = previewHeight > previewWidth && imageWidth > imageHeight;
    if (isRotated) {
      inputSize = Size(imageHeight, imageWidth);
    }

    final fittedSizes = applyBoxFit(BoxFit.cover, inputSize, outputSize);
    final destRect = Alignment.center.inscribe(
      fittedSizes.destination,
      Rect.fromLTWH(0, 0, previewWidth, previewHeight),
    );

    // Calculate scale factors based on the destination rect
    // This maps the image coordinate system to the displayed screen coordinate system
    final scaleX = destRect.width / imageWidth;
    final scaleY = destRect.height / imageHeight;

    // Draw each object
    for (final obj in optimizedObjects) {
      try {
        // Map bbox to destination rect with rotation handling
        // When rotated: flip both X and Y axes to match 90-degree rotation
        final mappedX = isRotated
            ? destRect.left +
                ((imageWidth - (obj.bbox.x + obj.bbox.width)) * scaleX)
            : destRect.left + (obj.bbox.x * scaleX);

        final mappedY = isRotated
            ? destRect.top +
                ((imageHeight - (obj.bbox.y + obj.bbox.height)) * scaleY)
            : destRect.top + (obj.bbox.y * scaleY);

        final scaledBox = BoundingBox(
          x: mappedX,
          y: mappedY,
          width: obj.bbox.width * scaleX,
          height: obj.bbox.height * scaleY,
        );

        // Logging removed to reduce noise

        // Skip boxes that are too small
        if (enablePerformanceOptimization &&
            (scaledBox.width < minBoxSize || scaledBox.height < minBoxSize)) {
          continue;
        }

        // Get color for this object
        final color = _getColorForObject(obj);

        // Draw bounding box
        _drawBoundingBox(canvas, scaledBox, color);

        // Draw label
        _drawLabel(canvas, textPainter, scaledBox, obj, color);
      } catch (e, stackTrace) {
        if (enableLogging) {
          AppLogger.e(
              'BoundingBoxPainter: Error drawing object ${obj.className}',
              error: e,
              stackTrace: stackTrace);
        }
      }
    }
  }

  /// Draw bounding box
  void _drawBoundingBox(Canvas canvas, BoundingBox box, Color color) {
    final drawStartTime = DateTime.now();

    try {
      final paint = Paint()
        ..color = color.withValues(alpha: boxOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth;

      final rect = box.toRect();
      canvas.drawRect(rect, paint);

      // Draw corner indicators for better visibility
      _drawCornerIndicators(canvas, rect, paint);

      // Logging removed to reduce noise
    } catch (e, stackTrace) {
      if (enableLogging) {
        var errorType = 'unknown';
        if (e is FormatException) {
          errorType = 'FormatException';
        } else if (e is StateError) {
          errorType = 'StateError';
        }

        AppLogger.e(
          'BoundingBoxPainter: Error drawing bounding box',
          category: 'BoundingBoxPainter',
          error: e,
          stackTrace: stackTrace,
          context: {
            'error_type': errorType,
            'box_coordinates': box.toString(),
            'line_width': lineWidth,
            'box_opacity': boxOpacity,
            'color': color.toString(),
          },
        );
      }
    }
  }

  /// Draw corner indicators
  void _drawCornerIndicators(Canvas canvas, Rect rect, Paint paint) {
    final cornerLength = lineWidth * 3;

    // Top-left corner
    canvas.drawLine(
      rect.topLeft,
      Offset(rect.left + cornerLength, rect.top),
      paint,
    );
    canvas.drawLine(
      rect.topLeft,
      Offset(rect.left, rect.top + cornerLength),
      paint,
    );

    // Top-right corner
    canvas.drawLine(
      rect.topRight,
      Offset(rect.right - cornerLength, rect.top),
      paint,
    );
    canvas.drawLine(
      rect.topRight,
      Offset(rect.right, rect.top + cornerLength),
      paint,
    );

    // Bottom-left corner
    canvas.drawLine(
      rect.bottomLeft,
      Offset(rect.left + cornerLength, rect.bottom),
      paint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      Offset(rect.left, rect.bottom - cornerLength),
      paint,
    );

    // Bottom-right corner
    canvas.drawLine(
      rect.bottomRight,
      Offset(rect.right - cornerLength, rect.bottom),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      Offset(rect.right, rect.bottom - cornerLength),
      paint,
    );
  }

  /// Draw label
  void _drawLabel(
    Canvas canvas,
    TextPainter textPainter,
    BoundingBox box,
    DetectionObject obj,
    Color color,
  ) {
    final drawStartTime = DateTime.now();

    try {
      // Build label text
      final labelParts = <String>[];
      if (showClassNames) {
        labelParts.add(obj.className);
      }
      if (showConfidence) {
        labelParts.add('${(obj.confidence * 100).toStringAsFixed(0)}%');
      }
      if (showTrackingIds && obj.trackId != null) {
        labelParts.add('ID: ${obj.trackId}');
      }

      if (labelParts.isEmpty) {
        return;
      }

      final labelText = labelParts.join(' ');

      // Create text span
      final textSpan = TextSpan(
        text: labelText,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      );

      // Layout text
      textPainter.text = textSpan;
      textPainter.layout();

      // Calculate label position
      final textWidth = textPainter.width;
      final textHeight = textPainter.height;
      final padding = fontSize * 0.3;

      // Ensure label stays within bounds
      final labelX = box.x.clamp(0.0, previewWidth - textWidth - padding * 2);
      final labelY = box.y - textHeight - padding * 2;

      // Draw label background
      final labelRect = Rect.fromLTWH(
        labelX,
        labelY,
        textWidth + padding * 2,
        textHeight + padding * 2,
      );

      final backgroundPaint = Paint()
        ..color = color.withValues(alpha: labelOpacity)
        ..style = PaintingStyle.fill;

      // Draw rounded rectangle for background
      final radius = Radius.circular(fontSize * 0.3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, radius),
        backgroundPaint,
      );

      // Draw text
      final textOffset = Offset(labelX + padding, labelY + padding);
      textPainter.paint(canvas, textOffset);

      // Logging removed to reduce noise
    } catch (e, stackTrace) {
      if (enableLogging) {
        var errorType = 'unknown';
        if (e is FormatException) {
          errorType = 'FormatException';
        } else if (e is StateError) {
          errorType = 'StateError';
        }

        AppLogger.e(
          'BoundingBoxPainter: Error drawing label',
          category: 'BoundingBoxPainter',
          error: e,
          stackTrace: stackTrace,
          context: {
            'error_type': errorType,
            'class_name': obj.className,
            'confidence': obj.confidence,
            'box_coordinates': box.toString(),
            'font_size': fontSize,
            'label_opacity': labelOpacity,
            'color': color.toString(),
          },
        );
      }
    }
  }

  /// Optimize objects list for performance
  List<DetectionObject> _optimizeObjects(List<DetectionObject> objects) {
    if (!enablePerformanceOptimization) {
      return objects;
    }

    // Limit number of objects to render
    if (objects.length > maxObjectsToRender) {
      // Sort by confidence and take top objects
      final sortedObjects = List<DetectionObject>.from(objects)
        ..sort((a, b) => b.confidence.compareTo(a.confidence));

      return sortedObjects.take(maxObjectsToRender).toList();
    }

    return objects;
  }

  /// Get color for an object
  Color _getColorForObject(DetectionObject obj) {
    // Use color from object if available
    if (obj.colorHex != null) {
      try {
        return Color(int.parse(obj.colorHex!.replaceFirst('#', '0xFF')));
      } catch (e) {
        // Fall back to default color
      }
    }

    // Use color from color map if available
    if (colorMap != null && colorMap!.containsKey(obj.className)) {
      return colorMap![obj.className]!;
    }

    // Use default color
    return defaultColor;
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    // If caching is enabled and objects are the same, don't repaint
    if (enableCaching &&
        oldDelegate.objects == objects &&
        oldDelegate.enableCaching == enableCaching) {
      return false;
    }

    // Repaint if any of the following changes:
    return oldDelegate.objects != objects ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight ||
        oldDelegate.previewWidth != previewWidth ||
        oldDelegate.previewHeight != previewHeight ||
        oldDelegate.lineWidth != lineWidth ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.showConfidence != showConfidence ||
        oldDelegate.showClassNames != showClassNames ||
        oldDelegate.showTrackingIds != showTrackingIds ||
        oldDelegate.colorMap != colorMap ||
        oldDelegate.defaultColor != defaultColor ||
        oldDelegate.boxOpacity != boxOpacity ||
        oldDelegate.labelOpacity != labelOpacity ||
        oldDelegate.enablePerformanceOptimization !=
            enablePerformanceOptimization ||
        oldDelegate.maxObjectsToRender != maxObjectsToRender ||
        oldDelegate.minBoxSize != minBoxSize ||
        oldDelegate.enableCaching != enableCaching;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is BoundingBoxPainter &&
        other.objects == objects &&
        other.imageWidth == imageWidth &&
        other.imageHeight == imageHeight &&
        other.previewWidth == previewWidth &&
        other.previewHeight == previewHeight &&
        other.lineWidth == lineWidth &&
        other.fontSize == fontSize &&
        other.showConfidence == showConfidence &&
        other.showClassNames == showClassNames &&
        other.showTrackingIds == showTrackingIds &&
        other.colorMap == colorMap &&
        other.defaultColor == defaultColor &&
        other.boxOpacity == boxOpacity &&
        other.labelOpacity == labelOpacity &&
        other.enablePerformanceOptimization == enablePerformanceOptimization &&
        other.maxObjectsToRender == maxObjectsToRender &&
        other.minBoxSize == minBoxSize &&
        other.enableCaching == enableCaching &&
        other.enableLogging == enableLogging;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      objects,
      imageWidth,
      imageHeight,
      previewWidth,
      previewHeight,
      lineWidth,
      fontSize,
      showConfidence,
      showClassNames,
      showTrackingIds,
      colorMap,
      defaultColor,
      boxOpacity,
      labelOpacity,
      enablePerformanceOptimization,
      maxObjectsToRender,
      minBoxSize,
      enableCaching,
      enableLogging,
    ]);
  }
}

/// Extension for double clamping
extension DoubleClamp on double {
  double clamp(double min, double max) {
    if (this < min) {
      return min;
    }
    if (this > max) {
      return max;
    }
    return this;
  }
}
