import 'package:flutter/material.dart';
import 'package:scanai_app/core/utils/ui_helper.dart';

/// Overlay widget untuk menampilkan status koneksi
/// Ditampilkan ketika server tidak terhubung atau sedang connecting
class ConnectionOverlay extends StatefulWidget {
  const ConnectionOverlay({
    super.key,
    required this.isConnecting,
    required this.hasError,
    required this.errorMessage,
    this.onRetry,
  });

  final bool isConnecting;
  final bool hasError;
  final String errorMessage;
  final VoidCallback? onRetry;

  @override
  State<ConnectionOverlay> createState() => _ConnectionOverlayState();
}

class _ConnectionOverlayState extends State<ConnectionOverlay> {
  bool _isDismissed = false;

  @override
  void didUpdateWidget(ConnectionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Reset dismissed state when error changes
    if (oldWidget.hasError != widget.hasError || 
        oldWidget.isConnecting != widget.isConnecting) {
      _isDismissed = false;
    }
    
    // Auto-dismiss error after 5 seconds
    if (widget.hasError && !widget.isConnecting && !_isDismissed) {
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && widget.hasError && !widget.isConnecting) {
          setState(() {
            _isDismissed = true;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if ((!widget.isConnecting && !widget.hasError) || _isDismissed) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () {
        // Dismiss overlay when tapped outside
        if (widget.hasError) {
          setState(() {
            _isDismissed = true;
          });
        }
      },
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: Center(
          child: GestureDetector(
            onTap: () {}, // Prevent tap from propagating to parent
            child: Container(
              margin: EdgeInsets.all(context.scaleW(32)),
              padding: EdgeInsets.all(context.scaleW(24)),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(context.scaleW(16)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.isConnecting) ...[
                    SizedBox(
                      width: context.scaleW(48),
                      height: context.scaleW(48),
                      child: CircularProgressIndicator(
                        strokeWidth: context.scaleW(4),
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    ),
                    SizedBox(height: context.scaleH(16)),
                    Text(
                      'Menghubungkan ke server...',
                      style: TextStyle(
                        fontSize: context.scaleSP(16),
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: context.scaleH(8)),
                    Text(
                      'Mohon tunggu sebentar',
                      style: TextStyle(
                        fontSize: context.scaleSP(14),
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ] else if (widget.hasError) ...[
                    Icon(
                      Icons.cloud_off,
                      size: context.scaleW(64),
                      color: Colors.orange,
                    ),
                    SizedBox(height: context.scaleH(16)),
                    Text(
                      'Server Tidak Terhubung',
                      style: TextStyle(
                        fontSize: context.scaleSP(18),
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: context.scaleH(12)),
                    Text(
                      _getErrorMessage(widget.errorMessage),
                      style: TextStyle(
                        fontSize: context.scaleSP(14),
                        color: Colors.grey[700],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: context.scaleH(16)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.onRetry != null)
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _isDismissed = true;
                              });
                              widget.onRetry?.call();
                            },
                            icon: Icon(Icons.refresh, size: context.scaleW(18)),
                            label: Text(
                              'Coba Lagi',
                              style: TextStyle(fontSize: context.scaleSP(14)),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                horizontal: context.scaleW(20),
                                vertical: context.scaleH(12),
                              ),
                            ),
                          ),
                        SizedBox(width: context.scaleW(12)),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isDismissed = true;
                            });
                          },
                          child: Text(
                            'Tutup',
                            style: TextStyle(fontSize: context.scaleSP(14)),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: context.scaleH(8)),
                    Text(
                      'Pesan ini akan hilang otomatis',
                      style: TextStyle(
                        fontSize: context.scaleSP(11),
                        color: Colors.grey[400],
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getErrorMessage(String error) {
    if (error.toLowerCase().contains('timeout')) {
      return 'Server tidak merespons.\nMohon tunggu atau coba lagi.';
    } else if (error.toLowerCase().contains('host') || 
               error.toLowerCase().contains('address')) {
      return 'Tidak dapat menemukan server.\nPeriksa koneksi jaringan Anda.';
    } else if (error.toLowerCase().contains('server down') ||
               error.toLowerCase().contains('server tidak aktif')) {
      return 'Server sedang tidak aktif.\nMohon tunggu atau hubungi admin.';
    } else {
      return 'Terjadi kesalahan koneksi.\nSilakan coba lagi.';
    }
  }
}
