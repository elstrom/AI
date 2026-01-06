import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:scanai_app/presentation/state/camera_state.dart';
import 'package:scanai_app/presentation/widgets/camera_preview.dart';
import 'package:scanai_app/presentation/widgets/control_panel.dart';
import 'package:scanai_app/presentation/widgets/streaming_monitor.dart';
import 'package:scanai_app/core/utils/ui_helper.dart';
import 'package:scanai_app/services/auth_service.dart';

/// Main camera page for object detection
///
/// This page displays the camera preview and handles the UI
/// for the real-time object detection feature.

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  bool _showMonitor = false;
  final GlobalKey _repaintBoundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    
    // Set token expiration callback (one-time setup)
    AuthService.onTokenExpired = _showTokenExpiredToast;
    
    // Set the RepaintBoundary key in CameraState after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final cameraState = Provider.of<CameraState>(context, listen: false);
        cameraState.repaintBoundaryKey = _repaintBoundaryKey;
      }
    });
  }

  /// Show token expired toast (called via static callback)
  void _showTokenExpiredToast() {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.lock_clock, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Token login expired. Silakan login ulang untuk melanjutkan.',
                style: TextStyle(
                  fontSize: context.scaleSP(14),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(context.scaleW(16)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.scaleW(12)),
        ),
      ),
    );
  }

  /// Handle back button press - Double tap to exit
  /// 1x tap: Show Toast only
  /// 2x tap: Exit App
  DateTime? _lastBackPressed;
  
  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    const backPressDuration = Duration(seconds: 2);
    
    if (_lastBackPressed == null || now.difference(_lastBackPressed!) > backPressDuration) {
      // Klik PERTAMA - Hanya kasih tau user, jangan minimize, jangan exit
      _lastBackPressed = now;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, color: Colors.white, size: context.scaleW(16)),
              SizedBox(width: context.scaleW(8)),
              Flexible(
                child: Text(
                  'Tekan lagi untuk keluar',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: context.scaleSP(13),
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF222222).withValues(alpha: 0.95),
          duration: const Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.symmetric(
            horizontal: context.scaleW(50),
            vertical: context.scaleH(30),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: context.scaleW(16),
            vertical: context.scaleH(12),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.scaleW(50)),
            side: const BorderSide(color: Colors.white24),
          ),
          elevation: 8,
        ),
      );
      
      return false; // Tetap di aplikasi
    }
    
    // Klik KEDUA - Keluar Total
    final cameraState = Provider.of<CameraState>(context, listen: false);
    try {
      if (cameraState.isStreaming) await cameraState.stopStreaming();
      await cameraState.stopPreview();
    } catch (e) {
      // Abaikan error saat cleanup
    }
    
    // Perintah keluar permanen
    SystemChannels.platform.invokeMethod('SystemNavigator.pop');
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // We handle pop manually
      onPopInvoked: (bool didPop) async {
        if (didPop) {
          return;
        }

        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          // Add back button for iOS
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios, color: Colors.white, size: context.scaleW(20)),
            onPressed: () async {
              final shouldPop = await _onWillPop();
              if (shouldPop && mounted) {
                Navigator.of(context).pop();
              }
            },
            tooltip: 'Kembali',
          ),
          title: Text(
            'ScanAI',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: context.scaleSP(20),
            ),
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: Icon(Icons.info, color: Colors.white, size: context.scaleW(24)),
              onPressed: () {
                Navigator.pushNamed(context, '/about');
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            // Full screen camera preview wrapped with RepaintBoundary for screenshot
            Positioned.fill(
              child: RepaintBoundary(
                key: _repaintBoundaryKey,
                child: const CameraPreviewWidget(),
              ),
            ),

            // Streaming monitor overlay - responsive positioning
            Positioned(
              // Position below the AppBar
              top: MediaQuery.of(context).padding.top + kToolbarHeight + context.scaleH(10),
              right: context.scaleW(0),
              child: _showMonitor
                  ? GestureDetector(
                      onTap: () {
                        setState(() {
                          _showMonitor = false;
                        });
                      },
                      child: StreamingMonitor(
                        expanded: true,
                        onTap: () {
                          setState(() {
                            _showMonitor = false;
                          });
                        },
                      ),
                    )
                  : IconButton(
                      icon: Icon(Icons.analytics, color: Colors.white, size: context.scaleW(24)),
                      onPressed: () {
                        setState(() {
                          _showMonitor = true;
                        });
                      },
                      tooltip: 'Show System Monitor',
                    ),
            ),

            // Control panel at the bottom
            const Align(
              alignment: Alignment.bottomCenter,
              child: ControlPanel(),
            ),
          ],
        ),
      ),
    );
  }
}
