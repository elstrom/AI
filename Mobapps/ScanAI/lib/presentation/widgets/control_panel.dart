import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:scanai_app/presentation/state/camera_state.dart';
import 'package:scanai_app/core/constants/app_constants.dart';
import 'package:scanai_app/core/utils/ui_helper.dart';
import 'package:scanai_app/core/utils/logger.dart';

/// Control panel widget for camera actions
///
/// This widget provides a panel with buttons for controlling the camera
/// and streaming functionality, including capture, streaming, flash control,
/// and camera switching.
class ControlPanel extends StatelessWidget {
  const ControlPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final cameraState = Provider.of<CameraState>(context);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: context.isTablet ? 600 : double.infinity),
      child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: context.scaleW(16),
            vertical: context.scaleH(12),
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(context.scaleW(20)),
              topRight: Radius.circular(context.scaleW(20)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle indicator
                Container(
                  width: context.scaleW(40),
                  height: context.scaleH(4),
                  margin: EdgeInsets.only(bottom: context.scaleH(12)),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(context.scaleW(2)),
                  ),
                ),

                // Main control buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CaptureButton(cameraState: cameraState),
                    _StreamingButton(cameraState: cameraState),
                    _FlashButton(cameraState: cameraState),
                    _SwitchCameraButton(cameraState: cameraState),
                  ],
                ),

                // Simple Status Message
                SizedBox(height: context.scaleH(12)),
                _SimpleStatusInfo(cameraState: cameraState),
              ],
            ),
          ),
        ),
      );
  }
}

/// Capture button widget
/// On Android: Captures image/screenshot and saves to gallery
/// On iOS (streaming): Sends detection data to PosAI and switches app
class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.cameraState});
  final CameraState cameraState;

  @override
  Widget build(BuildContext context) {
    final isIOS = Platform.isIOS;
    final isStreaming = cameraState.isStreaming;
    
    // On iOS when streaming: show "Kirim" label instead of "Foto"
    final label = (isIOS && isStreaming) ? 'Kirim' : 'Foto';
    final icon = (isIOS && isStreaming) ? Icons.send : Icons.camera_alt;

    return _ControlButton(
      icon: icon,
      label: label,
      onPressed: cameraState.isInitialized
          ? () async {
              final messenger = ScaffoldMessenger.of(context);
              
              // iOS + Streaming = Send to PosAI and switch app
              if (isIOS && isStreaming) {
                await _sendToPosAI(context, messenger);
                return;
              }
              
              // Android or iOS not streaming = Original behavior (capture & save)
              await _captureAndSave(messenger);
            }
          : null,
      isPrimary: true,
      color: (isIOS && isStreaming) ? Colors.green : null,
    );
  }

  /// iOS: Send detection data to PosAI and switch app
  Future<void> _sendToPosAI(BuildContext context, ScaffoldMessengerState messenger) async {
    try {
      // Check if there's detection data
      if (!cameraState.hasDetectionToSend) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Tidak ada deteksi. Arahkan kamera ke produk.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(context.scaleW(20)),
          ),
        );
        return;
      }

      // Send to PosAI
      final success = await cameraState.sendDetectionToPosAI();
      if (success) {
        // PosAI will open automatically, no need for snackbar
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Gagal membuka PosAI. Pastikan PosAI terinstall.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(context.scaleW(20)),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(context.scaleW(20)),
        ),
      );
    }
  }

  /// Android/iOS (not streaming): Capture image and save to gallery
  Future<void> _captureAndSave(ScaffoldMessengerState messenger) async {
    try {
      Uint8List bytes;

      // If streaming, capture screenshot with detection overlay
      if (cameraState.isStreaming) {
        final capturedBytes = await cameraState.captureScreenshot();
        if (capturedBytes == null) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Gagal mengambil screenshot'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        bytes = capturedBytes;
      } else {
        // If not streaming, take regular camera photo
        final path = await cameraState.captureImage();
        if (path == null) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Gagal mengambil foto'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        bytes = await File(path).readAsBytes();
      }

      // Save to gallery
      final result = await ImageGallerySaverPlus.saveImage(
        bytes,
        quality: 100,
        name: 'ScanAI_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (result['isSuccess'] == true) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(cameraState.isStreaming
                ? 'Screenshot dengan deteksi berhasil disimpan'
                : 'Gambar berhasil disimpan ke galeri'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Gagal menyimpan ke galeri'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Gagal mengambil gambar: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<CameraState>('cameraState', cameraState));
  }
}

/// Streaming button widget
class _StreamingButton extends StatelessWidget {
  const _StreamingButton({required this.cameraState});
  final CameraState cameraState;

  @override
  Widget build(BuildContext context) {
    final isStreaming = cameraState.isStreaming;

    return _ControlButton(
      icon:
          isStreaming ? Icons.stop_circle_outlined : Icons.play_circle_outline,
      label: isStreaming ? 'Stop' : 'Mulai',
      onPressed: cameraState.isInitialized
          ? () async {
              if (isStreaming) {
                await cameraState.stopStreaming();
              } else {
                await cameraState.startStreaming();
              }
            }
          : null,
      color: isStreaming ? Colors.red : Colors.blue,
      isPrimary: true,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<CameraState>('cameraState', cameraState));
  }
}

/// Flash button widget
class _FlashButton extends StatelessWidget {
  const _FlashButton({required this.cameraState});
  final CameraState cameraState;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String label;

    switch (cameraState.flashMode) {
      case FlashMode.off:
        icon = Icons.flash_off;
        color = Colors.grey[700]!;
        label = 'Off';
        break;
      case FlashMode.on:
        icon = Icons.flash_on;
        color = Colors.orange;
        label = 'On';
        break;
      case FlashMode.auto:
        icon = Icons.flash_auto;
        color = Colors.blue;
        label = 'Auto';
        break;
    }

    return _ControlButton(
      icon: icon,
      label: label,
      onPressed: cameraState.isInitialized
          ? () async {
              try {
                await cameraState.toggleFlash();
              } catch (e) {
                AppLogger.e('Error toggling flash: $e', category: 'camera');
              }
            }
          : null,
      color: color,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<CameraState>('cameraState', cameraState));
  }
}

/// Switch camera button widget
class _SwitchCameraButton extends StatelessWidget {
  const _SwitchCameraButton({required this.cameraState});
  final CameraState cameraState;

  @override
  Widget build(BuildContext context) {
    return _ControlButton(
      icon: Icons.flip_camera_ios,
      label: 'Ganti',
      onPressed:
          cameraState.isInitialized && (cameraState.cameras?.length ?? 0) > 1
              ? () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await cameraState.switchCamera();
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Kamera berhasil diganti'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Gagal mengganti kamera: $e'),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              : null,
      color: Colors.grey[700],
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<CameraState>('cameraState', cameraState));
  }
}

/// Reusable control button widget
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.isPrimary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final buttonColor = color ??
        (isPrimary ? Theme.of(context).primaryColor : Colors.grey[600]);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: isPrimary
                ? buttonColor?.withValues(alpha: 0.1)
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(context.scaleW(50)),
            child: Padding(
              padding: EdgeInsets.all(context.scaleW(8)),
              child: Icon(
                icon,
                size: isPrimary ? context.scaleW(32) : context.scaleW(24),
                color: isEnabled ? buttonColor : Colors.grey[300],
              ),
            ),
          ),
        ),
        SizedBox(height: context.scaleH(4)),
        Text(
          label,
          style: TextStyle(
            color: isEnabled ? Colors.black87 : Colors.grey[400],
            fontSize: context.scaleSP(12),
            fontWeight: isPrimary ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<IconData>('icon', icon));
    properties.add(StringProperty('label', label));
    properties.add(ObjectFlagProperty<VoidCallback?>.has('onPressed', onPressed));
    properties.add(ColorProperty('color', color));
    properties.add(DiagnosticsProperty<bool>('isPrimary', isPrimary));
  }
}

/// Simple status info widget
class _SimpleStatusInfo extends StatelessWidget {
  const _SimpleStatusInfo({required this.cameraState});
  final CameraState cameraState;

  @override
  Widget build(BuildContext context) {
    var statusText = AppConstants.statusReadyToScan;
    Color statusColor = Colors.grey;

    final cameraStatus = cameraState.cameraStatus;
    final isConnected = cameraState.isConnected;
    final isStreaming = cameraState.isStreaming;
    final connectionStatus = cameraState.connectionStatus;

    if (cameraStatus == CameraStatus.initializing) {
      statusText = AppConstants.statusInitializing;
      statusColor = Colors.orange;
    } else if (cameraStatus == CameraStatus.error) {
      statusText = connectionStatus.isNotEmpty
          ? connectionStatus
          : AppConstants.statusAppError;
      statusColor = Colors.redAccent;
    } else if (cameraStatus == CameraStatus.connecting) {
      statusText = AppConstants.statusConnecting;
      statusColor = Colors.amber;
    } else if (!isConnected) {
      if (connectionStatus != 'Disconnected' && connectionStatus.isNotEmpty) {
        statusText = connectionStatus;
      } else {
        statusText = AppConstants.statusDisconnected;
      }
      statusColor = Colors.red;
    } else if (isStreaming) {
      if (cameraState.detectedObjectsCount > 0) {
        statusText =
            '${cameraState.detectedObjectsCount} ${AppConstants.statusObjectsDetected}';
        statusColor = Colors.teal;
      } else {
        statusText = AppConstants.statusScanning;
        statusColor = Colors.lightBlue;
      }
    } else if (isConnected) {
      statusText = AppConstants.statusReadyToScan;
      statusColor = Colors.green;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: context.scaleW(16), vertical: context.scaleH(8)),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(context.scaleW(20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: context.scaleW(8),
            height: context.scaleW(8),
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: context.scaleW(8)),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: context.scaleSP(14),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<CameraState>('cameraState', cameraState));
  }
}
