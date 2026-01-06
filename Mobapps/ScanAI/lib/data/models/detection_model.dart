import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/core/constants/app_constants.dart';

part 'detection_model.g.dart';

/// Model for server response
///
/// This class represents the response structure from the server
/// with success flag and AI results.
@JsonSerializable(fieldRename: FieldRename.snake, checked: true)
class ServerResponse {
  ServerResponse({
    required this.success,
    AIResults? aiResults,
  }) : aiResults = aiResults ?? AIResults();

  /// Creates a ServerResponse from JSON
  factory ServerResponse.fromJson(Map<String, dynamic> json) =>
      _$ServerResponseFromJson(json);

  /// Whether the request was successful
  final bool success;

  /// AI detection results (defaults to empty AIResults if not provided)
  @JsonKey()
  final AIResults aiResults;

  /// Converts ServerResponse to JSON
  Map<String, dynamic> toJson() => _$ServerResponseToJson(this);

  /// Creates a copy of this ServerResponse with the given fields replaced
  ServerResponse copyWith({
    bool? success,
    AIResults? aiResults,
  }) {
    return ServerResponse(
      success: success ?? this.success,
      aiResults: aiResults ?? this.aiResults,
    );
  }

  @override
  String toString() {
    return 'ServerResponse(success: $success, aiResults: $aiResults)';
  }
}

/// Model for AI results
///
/// This class represents the AI detection results
/// containing a list of detections.
@JsonSerializable(fieldRename: FieldRename.snake, checked: true)
class AIResults {
  AIResults({
    List<ServerDetectionObject>? detections,
  }) : detections = detections ?? [];

  /// Creates an AIResults from JSON
  factory AIResults.fromJson(Map<String, dynamic> json) =>
      _$AIResultsFromJson(json);

  /// List of detections (defaults to empty list if not provided)
  @JsonKey(defaultValue: [])
  final List<ServerDetectionObject> detections;

  /// Converts AIResults to JSON
  Map<String, dynamic> toJson() => _$AIResultsToJson(this);

  /// Creates a copy of this AIResults with the given fields replaced
  AIResults copyWith({
    List<ServerDetectionObject>? detections,
  }) {
    return AIResults(
      detections: detections ?? this.detections,
    );
  }

  @override
  String toString() {
    return 'AIResults(detections: ${detections.length})';
  }
}

/// Model for server detection object
///
/// This class represents a detection object as returned by the server
/// with class name as ID and normalized bounding box.
@JsonSerializable(fieldRename: FieldRename.snake, checked: true)
class ServerDetectionObject {
  ServerDetectionObject({
    required this.className,
    required this.confidence,
    required this.bbox,
  });

  /// Creates a ServerDetectionObject from JSON
  factory ServerDetectionObject.fromJson(Map<String, dynamic> json) =>
      _$ServerDetectionObjectFromJson(json);

  /// Object class name (as ID, e.g., "0", "1", etc.)
  final String className;

  /// Confidence score (0.0 to 1.0)
  final double confidence;

  /// Normalized bounding box coordinates
  final NormalizedBoundingBox bbox;

  /// Converts ServerDetectionObject to JSON
  Map<String, dynamic> toJson() => _$ServerDetectionObjectToJson(this);

  /// Creates a copy of this ServerDetectionObject with the given fields replaced
  ServerDetectionObject copyWith({
    String? className,
    double? confidence,
    NormalizedBoundingBox? bbox,
  }) {
    return ServerDetectionObject(
      className: className ?? this.className,
      confidence: confidence ?? this.confidence,
      bbox: bbox ?? this.bbox,
    );
  }

  @override
  String toString() {
    return 'ServerDetectionObject(className: $className, confidence: ${confidence.toStringAsFixed(2)}, '
        'bbox: $bbox)';
  }
}

/// Model for normalized bounding box coordinates
///
/// This class represents the normalized bounding box coordinates
/// as returned by the server (x_min, y_min, width, height).
@JsonSerializable(fieldRename: FieldRename.snake, checked: true)
class NormalizedBoundingBox {
  NormalizedBoundingBox({
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
  });

  /// Creates a NormalizedBoundingBox from JSON
  factory NormalizedBoundingBox.fromJson(Map<String, dynamic> json) =>
      _$NormalizedBoundingBoxFromJson(json);

  /// Minimum X coordinate (normalized, 0.0 to 1.0)
  @JsonKey(defaultValue: 0.0)
  final double xMin;

  /// Minimum Y coordinate (normalized, 0.0 to 1.0)
  @JsonKey(defaultValue: 0.0)
  final double yMin;

  /// Maximum X coordinate (normalized, 0.0 to 1.0)
  @JsonKey(defaultValue: 0.0)
  final double xMax;

  /// Maximum Y coordinate (normalized, 0.0 to 1.0)
  @JsonKey(defaultValue: 0.0)
  final double yMax;

  /// Width of the bounding box (normalized, 0.0 to 1.0)
  double get width => xMax - xMin;

  /// Height of the bounding box (normalized, 0.0 to 1.0)
  double get height => yMax - yMin;

  /// Get object name from class ID using AppConstants
  static String getObjectNameFromId(String classId) {
    // Direct key lookup
    if (AppConstants.objectClasses.containsKey(classId)) {
      return AppConstants.objectClasses[classId]!;
    }
    // Reverse lookup: check if the "ID" is actually the name itself
    if (AppConstants.objectClasses.containsValue(classId)) {
      return classId;
    }
    return 'unknown';
  }

  /// Get all supported class names from AppConstants
  static List<String> get supportedClassNames {
    return AppConstants.objectClasses.values.toList();
  }

  /// Get class ID from object name using AppConstants
  static String? getClassIdFromName(String objectName) {
    for (final entry in AppConstants.objectClasses.entries) {
      if (entry.value.toLowerCase() == objectName.toLowerCase()) {
        return entry.key;
      }
    }
    return null;
  }

  /// Converts NormalizedBoundingBox to JSON
  Map<String, dynamic> toJson() => _$NormalizedBoundingBoxToJson(this);

  /// Creates a copy of this NormalizedBoundingBox with the given fields replaced
  NormalizedBoundingBox copyWith({
    double? xMin,
    double? yMin,
    double? xMax,
    double? yMax,
  }) {
    return NormalizedBoundingBox(
      xMin: xMin ?? this.xMin,
      yMin: yMin ?? this.yMin,
      xMax: xMax ?? this.xMax,
      yMax: yMax ?? this.yMax,
    );
  }

  /// Get center point of the bounding box (normalized)
  Offset get center => Offset(xMin + width / 2, yMin + height / 2);

  /// Calculate area of the bounding box (normalized)
  double get area => width * height;

  /// Convert to absolute coordinates
  BoundingBox toAbsolute(int imageWidth, int imageHeight) {
    return BoundingBox(
      x: xMin * imageWidth,
      y: yMin * imageHeight,
      width: width * imageWidth,
      height: height * imageHeight,
    );
  }

  /// Convert to absolute coordinates with preview scaling
  BoundingBox toAbsoluteWithPreview({
    required int imageWidth,
    required int imageHeight,
    required double previewWidth,
    required double previewHeight,
  }) {
    // First convert to absolute coordinates
    final absoluteBox = toAbsolute(imageWidth, imageHeight);

    // Then scale to preview size
    final scaleX = previewWidth / imageWidth;
    final scaleY = previewHeight / imageHeight;

    return absoluteBox.scale(scaleX, scaleY);
  }

  /// Convert to absolute coordinates and ensure it's within preview bounds
  BoundingBox toAbsoluteClamped({
    required int imageWidth,
    required int imageHeight,
    required double previewWidth,
    required double previewHeight,
  }) {
    final box = toAbsoluteWithPreview(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      previewWidth: previewWidth,
      previewHeight: previewHeight,
    );

    // Clamp coordinates to ensure they're within preview bounds
    final clampedX = box.x.clamp(0.0, previewWidth - box.width);
    final clampedY = box.y.clamp(0.0, previewHeight - box.height);

    // Adjust width and height if they exceed bounds
    final clampedWidth = (box.x + box.width > previewWidth)
        ? previewWidth - clampedX
        : box.width;
    final clampedHeight = (box.y + box.height > previewHeight)
        ? previewHeight - clampedY
        : box.height;

    return BoundingBox(
      x: clampedX,
      y: clampedY,
      width: clampedWidth,
      height: clampedHeight,
    );
  }

  /// Validate the normalized bounding box data
  bool get isValid {
    if (width <= 0 || height <= 0) {
      AppLogger.w(
          'Invalid normalized bounding box dimensions: ${width}x$height');
      return false;
    }

    if (xMin < 0 || yMin < 0 || xMin > 1 || yMin > 1) {
      AppLogger.w(
          'Invalid normalized bounding box coordinates: ($xMin, $yMin)');
      return false;
    }

    if (xMax > 1 || yMax > 1) {
      AppLogger.w(
          'Normalized bounding box exceeds image bounds: xMax=$xMax, yMax=$yMax');
      return false;
    }

    return true;
  }

  @override
  String toString() {
    return 'NormalizedBoundingBox(xMin: ${xMin.toStringAsFixed(3)}, yMin: ${yMin.toStringAsFixed(3)}, '
        'xMax: ${xMax.toStringAsFixed(3)}, yMax: ${yMax.toStringAsFixed(3)})';
  }
}

/// Parser for server response
///
/// This class provides utilities to convert server response
/// to DetectionModel format.
class ServerResponseParser {
  /// Convert server response to DetectionModel
  static DetectionModel fromServerResponse(
    ServerResponse serverResponse, {
    required int imageWidth,
    required int imageHeight,
    DateTime? timestamp,
    String? frameId,
    int? frameSequence,
    int? processingTimeMs,
    DateTime? serverTimestamp,
  }) {
    if (!serverResponse.success) {
      AppLogger.w('Server response indicates failure');
      return DetectionModel(
        objects: [],
        timestamp: timestamp ?? DateTime.now(),
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        frameId: frameId,
        frameSequence: frameSequence,
        processingTimeMs: processingTimeMs,
        serverTimestamp: serverTimestamp,
      );
    }

    final objects = <DetectionObject>[];
    for (final detection in serverResponse.aiResults.detections) {
      final className = _mapClassIdToName(detection.className);
      final bbox = detection.bbox.toAbsolute(imageWidth, imageHeight);

      objects.add(DetectionObject(
        className: className,
        confidence: detection.confidence,
        bbox: bbox,
        classId: int.tryParse(detection.className),
      ));
    }

    return DetectionModel(
      objects: objects,
      timestamp: timestamp ?? DateTime.now(),
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      frameId: frameId,
      frameSequence: frameSequence,
      processingTimeMs: processingTimeMs,
      serverTimestamp: serverTimestamp,
    );
  }

  /// Map class ID to object name
  static String _mapClassIdToName(String classId) {
    return NormalizedBoundingBox.getObjectNameFromId(classId);
  }

  /// Get all supported class names
  static List<String> get supportedClassNames =>
      NormalizedBoundingBox.supportedClassNames;

  /// Get class ID from object name
  static String? getClassIdFromName(String objectName) {
    return NormalizedBoundingBox.getClassIdFromName(objectName);
  }
}

/// Model for object detection results
///
/// This class represents the data structure for object detection
/// results returned from the server.
///
/// Example usage:
/// ```dart
/// final detection = DetectionModel.fromJson(jsonData);
/// if (detection.isValid) {
///   final filtered = detection.filterByConfidence(0.5);
///   print('Detected ${filtered.objects.length} objects');
/// }
/// ```
@JsonSerializable()
class DetectionModel {
  DetectionModel({
    required this.objects,
    required this.timestamp,
    required this.imageWidth,
    required this.imageHeight,
    this.frameId,
    this.frameSequence,
    this.processingTimeMs,
    this.serverTimestamp,
    this.totalDetectionsBeforeFilter,
    this.confidenceThreshold,
  });

  /// Creates a DetectionModel from JSON
  factory DetectionModel.fromJson(Map<String, dynamic> json) =>
      _$DetectionModelFromJson(json);

  /// List of detected objects
  final List<DetectionObject> objects;

  /// Timestamp of the detection
  final DateTime timestamp;

  /// Image width in pixels
  final int imageWidth;

  /// Image height in pixels
  final int imageHeight;

  /// Frame ID for synchronization with video stream (string format)
  final String? frameId;

  /// Frame sequence number for synchronization (numeric, more reliable)
  final int? frameSequence;

  /// Processing time in milliseconds
  final int? processingTimeMs;

  /// Server timestamp when detection was processed
  final DateTime? serverTimestamp;

  /// Number of objects before filtering
  final int? totalDetectionsBeforeFilter;

  /// Confidence threshold used for filtering
  final double? confidenceThreshold;

  /// Converts DetectionModel to JSON
  Map<String, dynamic> toJson() => _$DetectionModelToJson(this);

  /// Creates a copy of this DetectionModel with the given fields replaced
  DetectionModel copyWith({
    List<DetectionObject>? objects,
    DateTime? timestamp,
    int? imageWidth,
    int? imageHeight,
    String? frameId,
    int? frameSequence,
    int? processingTimeMs,
    DateTime? serverTimestamp,
    int? totalDetectionsBeforeFilter,
    double? confidenceThreshold,
  }) {
    return DetectionModel(
      objects: objects ?? this.objects,
      timestamp: timestamp ?? this.timestamp,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      frameId: frameId ?? this.frameId,
      frameSequence: frameSequence ?? this.frameSequence,
      processingTimeMs: processingTimeMs ?? this.processingTimeMs,
      serverTimestamp: serverTimestamp ?? this.serverTimestamp,
      totalDetectionsBeforeFilter:
          totalDetectionsBeforeFilter ?? this.totalDetectionsBeforeFilter,
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
    );
  }

  /// Filter objects by confidence threshold
  DetectionModel filterByConfidence(double threshold) {
    final filteredObjects =
        objects.where((obj) => obj.confidence >= threshold).toList();
    return copyWith(
      objects: filteredObjects,
      totalDetectionsBeforeFilter: objects.length,
      confidenceThreshold: threshold,
    );
  }

  /// Get objects sorted by confidence (highest first)
  List<DetectionObject> get sortedObjects {
    final sorted = List<DetectionObject>.from(objects);
    sorted.sort((a, b) => b.confidence.compareTo(a.confidence));
    return sorted;
  }

  /// Get objects grouped by class name
  Map<String, List<DetectionObject>> get objectsByClass {
    final result = <String, List<DetectionObject>>{};
    for (final obj in objects) {
      if (!result.containsKey(obj.className)) {
        result[obj.className] = [];
      }
      result[obj.className]!.add(obj);
    }
    return result;
  }

  /// Get count of objects by class name
  Map<String, int> get objectCountsByClass {
    final result = <String, int>{};
    for (final obj in objects) {
      result[obj.className] = (result[obj.className] ?? 0) + 1;
    }
    return result;
  }

  /// Calculate average confidence of all detections
  double get averageConfidence {
    if (objects.isEmpty) {
      return 0.0;
    }
    final total = objects.fold(0.0, (sum, obj) => sum + obj.confidence);
    return total / objects.length;
  }

  /// Get the object with highest confidence
  DetectionObject? get highestConfidenceObject {
    if (objects.isEmpty) {
      return null;
    }
    return objects.reduce((a, b) => a.confidence > b.confidence ? a : b);
  }

  /// Validate the detection model data
  bool get isValid {
    if (imageWidth <= 0 || imageHeight <= 0) {
      AppLogger.w('Invalid image dimensions: $imageWidth x $imageHeight');
      return false;
    }

    if (objects.isEmpty) {
      return true; // Empty detection is valid
    }

    for (final obj in objects) {
      if (!obj.isValid) {
        return false;
      }
    }

    return true;
  }

  @override
  String toString() {
    return 'DetectionModel(objects: ${objects.length}, timestamp: $timestamp, '
        'dimensions: ${imageWidth}x$imageHeight, frameId: $frameId)';
  }
}

/// Model for a single detected object
///
/// This class represents a single object that has been detected
/// by the object detection model.
///
/// Example usage:
/// ```dart
/// final obj = DetectionObject.fromJson(jsonData);
/// if (obj.isValid) {
///   print('Detected ${obj.className} with ${obj.confidence} confidence');
///   print('Bounding box: ${obj.bbox}');
/// }
/// ```
@JsonSerializable()
class DetectionObject {
  DetectionObject({
    required this.className,
    required this.confidence,
    required this.bbox,
    this.id,
    this.classId,
    this.colorHex,
    this.trackId,
  });

  /// Creates a DetectionObject from JSON
  factory DetectionObject.fromJson(Map<String, dynamic> json) =>
      _$DetectionObjectFromJson(json);

  /// Object class name (e.g., "person", "car", etc.)
  final String className;

  /// Confidence score (0.0 to 1.0)
  final double confidence;

  /// Bounding box coordinates
  final BoundingBox bbox;

  /// Unique ID for this detection (if provided by server)
  final String? id;

  /// Object class ID (numeric)
  final int? classId;

  /// Color information for rendering (hex code)
  final String? colorHex;

  /// Object tracking ID (if tracking is enabled)
  final String? trackId;

  /// Converts DetectionObject to JSON
  Map<String, dynamic> toJson() => _$DetectionObjectToJson(this);

  /// Creates a copy of this DetectionObject with the given fields replaced
  DetectionObject copyWith({
    String? className,
    double? confidence,
    BoundingBox? bbox,
    String? id,
    int? classId,
    String? colorHex,
    String? trackId,
  }) {
    return DetectionObject(
      className: className ?? this.className,
      confidence: confidence ?? this.confidence,
      bbox: bbox ?? this.bbox,
      id: id ?? this.id,
      classId: classId ?? this.classId,
      colorHex: colorHex ?? this.colorHex,
      trackId: trackId ?? this.trackId,
    );
  }

  /// Get color for this object
  Color get color {
    if (colorHex != null) {
      try {
        return Color(int.parse(colorHex!.replaceFirst('#', '0xFF')));
      } catch (e) {
        AppLogger.w('Invalid color hex: $colorHex', error: e);
      }
    }
    return _getDefaultColorForClass(className);
  }

  /// Get display label with confidence percentage
  String get displayLabel {
    return '$className ${(confidence * 100).toStringAsFixed(0)}%';
  }

  /// Calculate center point of the bounding box
  Offset get center {
    return Offset(bbox.x + bbox.width / 2, bbox.y + bbox.height / 2);
  }

  /// Calculate area of the bounding box
  double get area => bbox.width * bbox.height;

  /// Validate the detection object data
  bool get isValid {
    if (className.isEmpty) {
      AppLogger.w('Empty class name in detection object');
      return false;
    }

    if (confidence < 0.0 || confidence > 1.0) {
      AppLogger.w('Invalid confidence value: $confidence');
      return false;
    }

    if (!bbox.isValid) {
      return false;
    }

    return true;
  }

  /// Get default color for a class name
  Color _getDefaultColorForClass(String className) {
    // Simple hash function to generate consistent colors
    var hash = 0;
    for (var i = 0; i < className.length; i++) {
      hash = className.codeUnitAt(i) + ((hash << 5) - hash);
    }

    // Convert hash to RGB values
    final r = (hash & 0xFF0000) >> 16;
    final g = (hash & 0x00FF00) >> 8;
    final b = hash & 0x0000FF;

    return Color.fromARGB(255, r, g, b).withValues(alpha: 0.8);
  }

  @override
  String toString() {
    return 'DetectionObject(className: $className, confidence: ${confidence.toStringAsFixed(2)}, '
        'bbox: $bbox, id: $id, trackId: $trackId)';
  }
}

/// Model for bounding box coordinates
///
/// This class represents the coordinates of a bounding box that
/// surrounds a detected object.
///
/// Example usage:
/// ```dart
/// final bbox = BoundingBox.fromJson(jsonData);
/// if (bbox.isValid) {
///   print('Box area: ${bbox.area}');
///   print('Box center: ${bbox.center}');
///
///   // Scale the box for display
///   final scaled = bbox.scale(0.5, 0.5);
/// }
/// ```
@JsonSerializable()
class BoundingBox {
  BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// Creates a BoundingBox from JSON
  factory BoundingBox.fromJson(Map<String, dynamic> json) =>
      _$BoundingBoxFromJson(json);

  /// X coordinate of the top-left corner
  final double x;

  /// Y coordinate of the top-left corner
  final double y;

  /// Width of the bounding box
  final double width;

  /// Height of the bounding box
  final double height;

  /// Converts BoundingBox to JSON
  Map<String, dynamic> toJson() => _$BoundingBoxToJson(this);

  /// Creates a copy of this BoundingBox with the given fields replaced
  BoundingBox copyWith({double? x, double? y, double? width, double? height}) {
    return BoundingBox(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  /// Get right edge coordinate
  double get right => x + width;

  /// Get bottom edge coordinate
  double get bottom => y + height;

  /// Get center point of the bounding box
  Offset get center => Offset(x + width / 2, y + height / 2);

  /// Calculate area of the bounding box
  double get area => width * height;

  /// Scale the bounding box by the given factors
  BoundingBox scale(double scaleX, double scaleY) {
    return BoundingBox(
      x: x * scaleX,
      y: y * scaleY,
      width: width * scaleX,
      height: height * scaleY,
    );
  }

  /// Create a BoundingBox from NormalizedBoundingBox
  static BoundingBox fromNormalized(
    NormalizedBoundingBox normalizedBox, {
    required int imageWidth,
    required int imageHeight,
  }) {
    return normalizedBox.toAbsolute(imageWidth, imageHeight);
  }

  /// Create a BoundingBox from NormalizedBoundingBox with preview scaling
  static BoundingBox fromNormalizedWithPreview(
    NormalizedBoundingBox normalizedBox, {
    required int imageWidth,
    required int imageHeight,
    required double previewWidth,
    required double previewHeight,
  }) {
    return normalizedBox.toAbsoluteWithPreview(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      previewWidth: previewWidth,
      previewHeight: previewHeight,
    );
  }

  /// Create a BoundingBox from NormalizedBoundingBox with clamping
  static BoundingBox fromNormalizedClamped(
    NormalizedBoundingBox normalizedBox, {
    required int imageWidth,
    required int imageHeight,
    required double previewWidth,
    required double previewHeight,
  }) {
    return normalizedBox.toAbsoluteClamped(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      previewWidth: previewWidth,
      previewHeight: previewHeight,
    );
  }

  /// Calculate scale factors for converting from image to preview
  static Map<String, double> calculateScaleFactors({
    required int imageWidth,
    required int imageHeight,
    required double previewWidth,
    required double previewHeight,
  }) {
    return {
      'scaleX': previewWidth / imageWidth,
      'scaleY': previewHeight / imageHeight,
    };
  }

  /// Check if this bounding box intersects with another
  bool intersects(BoundingBox other) {
    return x < other.right &&
        right > other.x &&
        y < other.bottom &&
        bottom > other.y;
  }

  /// Calculate intersection area with another bounding box
  double intersectionArea(BoundingBox other) {
    if (!intersects(other)) {
      return 0.0;
    }

    final intersectionX = (right < other.right ? right : other.right) -
        (x > other.x ? x : other.x);
    final intersectionY = (bottom < other.bottom ? bottom : other.bottom) -
        (y > other.y ? y : other.y);

    return intersectionX * intersectionY;
  }

  /// Calculate union area with another bounding box
  double unionArea(BoundingBox other) {
    return area + other.area - intersectionArea(other);
  }

  /// Calculate Intersection over Union (IoU) with another bounding box
  double iou(BoundingBox other) {
    final intersection = intersectionArea(other);
    if (intersection == 0.0) {
      return 0.0;
    }
    return intersection / unionArea(other);
  }

  /// Validate the bounding box data
  bool get isValid {
    if (width <= 0 || height <= 0) {
      AppLogger.w('Invalid bounding box dimensions: ${width}x$height');
      return false;
    }

    if (x < 0 || y < 0) {
      AppLogger.w('Negative bounding box coordinates: ($x, $y)');
      return false;
    }

    return true;
  }

  /// Convert to Rect
  Rect toRect() {
    return Rect.fromLTWH(x, y, width, height);
  }

  @override
  String toString() {
    return 'BoundingBox(x: ${x.toStringAsFixed(1)}, y: ${y.toStringAsFixed(1)}, '
        'width: ${width.toStringAsFixed(1)}, height: ${height.toStringAsFixed(1)})';
  }
}
