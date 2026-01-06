import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanai_app/data/models/detection_model.dart';
import 'package:scanai_app/core/constants/app_constants.dart';

void main() {
  test('DetectionModel parses server response (snake_case) correctly', () {
    // JSON response from Server (as per README_INTEGRATION.md)
    const jsonString = '''
    {
      "success": true,
      "message": "Frame processed successfully",
      "frame_id": "unique-frame-id-123",
      "timestamp": "2023-10-27T10:00:00Z",
      "processing_time_ms": 45,
      "original_width": 1280,
      "original_height": 720,
      "ai_results": {
        "detections": [
          {
            "class_name": "0", 
            "confidence": 0.95,
            "bbox": {
              "x_min": 0.1,
              "y_min": 0.2,
              "width": 0.3,
              "height": 0.4
            }
          }
        ]
      },
      "orientation_info": {
         "top": "y_min (0.0)",
         "bottom": "y_max (1.0)",
         "left": "x_min (0.0)",
         "right": "x_max (1.0)"
      }
    }
    ''';

    final jsonData = jsonDecode(jsonString);

    // 1. Parse into ServerResponse
    final serverResponse = ServerResponse.fromJson(jsonData);

    expect(serverResponse.success, isTrue);
    expect(serverResponse.aiResults.detections.length, 1);

    final detection = serverResponse.aiResults.detections.first;
    expect(detection.className, '0'); // Snake case parsing check
    expect(detection.confidence, 0.95);
    expect(detection.bbox.xMin, 0.1);
    expect(detection.bbox.width, 0.3);

    // 2. Convert to Client DetectionModel (via Parser)
    final clientModel = ServerResponseParser.fromServerResponse(
      serverResponse,
      imageWidth: 640,
      imageHeight: 360,
    );

    expect(clientModel.objects.length, 1);
    final obj = clientModel.objects.first;
    expect(obj.confidence, 0.95);

    // Check Config Mapping (class "0" -> "cucur" in AppConstants)
    // AppConstants.objectClasses['0'] is 'cucur'
    expect(AppConstants.objectClasses['0'], 'cucur');
    expect(obj.className, 'cucur');
  });
}
