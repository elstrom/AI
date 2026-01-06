import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scanai_app/core/utils/ui_helper.dart';
import 'package:scanai_app/core/constants/app_constants.dart';
import 'package:scanai_app/presentation/state/camera_state.dart';
import 'package:scanai_app/presentation/widgets/detection_overlay.dart';
import 'package:scanai_app/core/utils/logger.dart';

class CameraPreviewWidget extends StatefulWidget {
  const CameraPreviewWidget({super.key});

  @override
  State<CameraPreviewWidget> createState() => _CameraPreviewWidgetState();
}

class _CameraPreviewWidgetState extends State<CameraPreviewWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final cameraState = Provider.of<CameraState>(context, listen: false);
        _initializeCamera(cameraState);
      }
    });
  }

  Future<void> _initializeCamera(CameraState cameraState) async {
    if (cameraState.isInitialized) {
      return;
    }
    try {
      await cameraState.initializeCamera();
    } catch (e) {
      AppLogger.e('Camera initialization error: $e', category: 'camera');
    }
  }

  static final Map<String, Color> _colorMap = AppConstants.objectClassColors.map(
    (key, value) => MapEntry(key, Color(value)),
  );

  @override
  Widget build(BuildContext context) {
    return Consumer<CameraState>(
      builder: (context, cameraState, child) {
        return Container(
          color: Colors.black,
          child: Stack(
            children: [
              // Camera preview using Texture widget
              Positioned.fill(
                bottom: context.isTablet ? context.scaleH(160) : context.scaleH(140), // Space for control panel
                child: _buildCameraContent(context, cameraState),
              ),

              // Detection overlay
              if (cameraState.isInitialized)
                Positioned.fill(
                  bottom: context.isTablet ? context.scaleH(160) : context.scaleH(140),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return DetectionOverlayWithStats(
                        detectionResult: cameraState.detectionResult,
                        previewWidth: constraints.maxWidth,
                        previewHeight: constraints.maxHeight,
                        fps: cameraState.fps,
                        colorMap: _colorMap,
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCameraContent(BuildContext context, CameraState cameraState) {
    // Don't show error overlay - errors are shown in status notification only
    // This keeps the camera preview clean and allows users to see the camera feed
    // even when there are connection errors
    
    if (!cameraState.isInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            SizedBox(height: context.scaleH(16)),
            Text(
              'Initializing camera...',
              style: TextStyle(color: Colors.white70, fontSize: context.scaleSP(16)),
            ),
          ],
        ),
      );
    }

    // Use Texture widget if we have a valid textureId
    final textureId = cameraState.textureId;
    if (textureId >= 0) {
      return Texture(textureId: textureId);
    }

    // Fallback to frame-by-frame display if texture not available
    if (cameraState.currentDisplayFrame != null) {
      return SizedBox.expand(
        child: Image.memory(
          cameraState.currentDisplayFrame!,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => Center(
            child: Icon(Icons.broken_image, color: Colors.white54, size: context.scaleW(48)),
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam_off, color: Colors.white54, size: context.scaleW(48)),
          SizedBox(height: context.scaleH(16)),
          Text(
            'Waiting for camera feed...',
            style: TextStyle(color: Colors.white70, fontSize: context.scaleSP(16)),
          ),
        ],
      ),
    );
  }
}
