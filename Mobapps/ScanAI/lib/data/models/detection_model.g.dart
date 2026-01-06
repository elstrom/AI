// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'detection_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ServerResponse _$ServerResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'ServerResponse',
      json,
      ($checkedConvert) {
        final val = ServerResponse(
          success: $checkedConvert('success', (v) => v as bool),
          aiResults: $checkedConvert(
              'ai_results',
              (v) => v == null
                  ? null
                  : AIResults.fromJson(v as Map<String, dynamic>)),
        );
        return val;
      },
      fieldKeyMap: const {'aiResults': 'ai_results'},
    );

Map<String, dynamic> _$ServerResponseToJson(ServerResponse instance) =>
    <String, dynamic>{
      'success': instance.success,
      'ai_results': instance.aiResults,
    };

AIResults _$AIResultsFromJson(Map<String, dynamic> json) => $checkedCreate(
      'AIResults',
      json,
      ($checkedConvert) {
        final val = AIResults(
          detections: $checkedConvert(
              'detections',
              (v) =>
                  (v as List<dynamic>?)
                      ?.map((e) => ServerDetectionObject.fromJson(
                          e as Map<String, dynamic>))
                      .toList() ??
                  []),
        );
        return val;
      },
    );

Map<String, dynamic> _$AIResultsToJson(AIResults instance) => <String, dynamic>{
      'detections': instance.detections,
    };

ServerDetectionObject _$ServerDetectionObjectFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'ServerDetectionObject',
      json,
      ($checkedConvert) {
        final val = ServerDetectionObject(
          className: $checkedConvert('class_name', (v) => v as String),
          confidence:
              $checkedConvert('confidence', (v) => (v as num).toDouble()),
          bbox: $checkedConvert('bbox',
              (v) => NormalizedBoundingBox.fromJson(v as Map<String, dynamic>)),
        );
        return val;
      },
      fieldKeyMap: const {'className': 'class_name'},
    );

Map<String, dynamic> _$ServerDetectionObjectToJson(
        ServerDetectionObject instance) =>
    <String, dynamic>{
      'class_name': instance.className,
      'confidence': instance.confidence,
      'bbox': instance.bbox,
    };

NormalizedBoundingBox _$NormalizedBoundingBoxFromJson(
        Map<String, dynamic> json) =>
    $checkedCreate(
      'NormalizedBoundingBox',
      json,
      ($checkedConvert) {
        final val = NormalizedBoundingBox(
          xMin: $checkedConvert('x_min', (v) => (v as num?)?.toDouble() ?? 0.0),
          yMin: $checkedConvert('y_min', (v) => (v as num?)?.toDouble() ?? 0.0),
          xMax: $checkedConvert('x_max', (v) => (v as num?)?.toDouble() ?? 0.0),
          yMax: $checkedConvert('y_max', (v) => (v as num?)?.toDouble() ?? 0.0),
        );
        return val;
      },
      fieldKeyMap: const {
        'xMin': 'x_min',
        'yMin': 'y_min',
        'xMax': 'x_max',
        'yMax': 'y_max'
      },
    );

Map<String, dynamic> _$NormalizedBoundingBoxToJson(
        NormalizedBoundingBox instance) =>
    <String, dynamic>{
      'x_min': instance.xMin,
      'y_min': instance.yMin,
      'x_max': instance.xMax,
      'y_max': instance.yMax,
    };

DetectionModel _$DetectionModelFromJson(Map<String, dynamic> json) =>
    DetectionModel(
      objects: (json['objects'] as List<dynamic>)
          .map((e) => DetectionObject.fromJson(e as Map<String, dynamic>))
          .toList(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      imageWidth: (json['imageWidth'] as num).toInt(),
      imageHeight: (json['imageHeight'] as num).toInt(),
      frameId: json['frameId'] as String?,
      frameSequence: (json['frameSequence'] as num?)?.toInt(),
      processingTimeMs: (json['processingTimeMs'] as num?)?.toInt(),
      serverTimestamp: json['serverTimestamp'] == null
          ? null
          : DateTime.parse(json['serverTimestamp'] as String),
      totalDetectionsBeforeFilter:
          (json['totalDetectionsBeforeFilter'] as num?)?.toInt(),
      confidenceThreshold: (json['confidenceThreshold'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$DetectionModelToJson(DetectionModel instance) =>
    <String, dynamic>{
      'objects': instance.objects,
      'timestamp': instance.timestamp.toIso8601String(),
      'imageWidth': instance.imageWidth,
      'imageHeight': instance.imageHeight,
      'frameId': instance.frameId,
      'frameSequence': instance.frameSequence,
      'processingTimeMs': instance.processingTimeMs,
      'serverTimestamp': instance.serverTimestamp?.toIso8601String(),
      'totalDetectionsBeforeFilter': instance.totalDetectionsBeforeFilter,
      'confidenceThreshold': instance.confidenceThreshold,
    };

DetectionObject _$DetectionObjectFromJson(Map<String, dynamic> json) =>
    DetectionObject(
      className: json['className'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      bbox: BoundingBox.fromJson(json['bbox'] as Map<String, dynamic>),
      id: json['id'] as String?,
      classId: (json['classId'] as num?)?.toInt(),
      colorHex: json['colorHex'] as String?,
      trackId: json['trackId'] as String?,
    );

Map<String, dynamic> _$DetectionObjectToJson(DetectionObject instance) =>
    <String, dynamic>{
      'className': instance.className,
      'confidence': instance.confidence,
      'bbox': instance.bbox,
      'id': instance.id,
      'classId': instance.classId,
      'colorHex': instance.colorHex,
      'trackId': instance.trackId,
    };

BoundingBox _$BoundingBoxFromJson(Map<String, dynamic> json) => BoundingBox(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
    );

Map<String, dynamic> _$BoundingBoxToJson(BoundingBox instance) =>
    <String, dynamic>{
      'x': instance.x,
      'y': instance.y,
      'width': instance.width,
      'height': instance.height,
    };
