import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:scanai_app/core/utils/logger.dart';
import 'package:scanai_app/core/utils/ui_helper.dart';

class PermissionGatePage extends StatefulWidget {
  const PermissionGatePage({super.key});

  @override
  State<PermissionGatePage> createState() => _PermissionGatePageState();
}

class _PermissionGatePageState extends State<PermissionGatePage> {
  bool _isCheckingPermissions = true;
  Map<String, PermissionStatus> _permissionStatus = {};

  // Required permissions
  final Map<String, Permission> _requiredPermissions = {
    'Camera': Permission.camera,
    'Notifikasi': Permission.notification,
  };

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() => _isCheckingPermissions = true);

    try {
      AppLogger.i('PermissionGatePage: Checking permissions (GATE ENTRY)',
          category: 'permissions');
      
      final statuses = <String, PermissionStatus>{};

      for (var entry in _requiredPermissions.entries) {
        final status = await entry.value.status;
        statuses[entry.key] = status;
        AppLogger.d('Permission ${entry.key}: $status',
            category: 'permissions');
      }

      setState(() {
        _permissionStatus = statuses;
        _isCheckingPermissions = false;
      });

      // Jika semua permission granted, langsung navigate
      if (_allPermissionsGranted()) {
        AppLogger.i('All permissions granted, opening gate to app initialization',
            category: 'permissions');
        _navigateToNextScreen();
      } else {
        AppLogger.w('Some permissions not granted, gate remains CLOSED',
            category: 'permissions',
            context: {'missing_permissions': statuses.entries
                .where((e) => !e.value.isGranted)
                .map((e) => e.key)
                .toList()});
      }
    } catch (e, stackTrace) {
      AppLogger.e('Error checking permissions: $e',
          category: 'permissions', error: e, stackTrace: stackTrace);

      setState(() => _isCheckingPermissions = false);
    }
  }

  bool _allPermissionsGranted() {
    return _permissionStatus.values.every((status) => status.isGranted);
  }

  Future<void> _requestPermissions() async {
    AppLogger.i('User requesting permissions', category: 'permissions');

    setState(() => _isCheckingPermissions = true);

    try {
      // Request semua permissions sekaligus
      final statuses = await _requiredPermissions.values.toList().request();

      // Update status
      final newStatuses = <String, PermissionStatus>{};
      _requiredPermissions.forEach((name, permission) {
        newStatuses[name] = statuses[permission] ?? PermissionStatus.denied;
      });

      setState(() {
        _permissionStatus = newStatuses;
        _isCheckingPermissions = false;
      });

      // Jika semua granted, navigate
      if (_allPermissionsGranted()) {
        AppLogger.i('All permissions granted, navigating to app',
            category: 'permissions');
        _navigateToNextScreen();
      } else {
        // Show dialog jika ada yang permanently denied
        _checkPermanentlyDenied();
      }
    } catch (e, stackTrace) {
      AppLogger.e('Error requesting permissions: $e',
          category: 'permissions', error: e, stackTrace: stackTrace);

      setState(() => _isCheckingPermissions = false);

      if (mounted) {
        _showErrorDialog('Gagal meminta izin. Silakan coba lagi.');
      }
    }
  }

  void _checkPermanentlyDenied() {
    final permanentlyDenied = _permissionStatus.entries
        .where((e) => e.value.isPermanentlyDenied)
        .map((e) => e.key)
        .toList();

    if (permanentlyDenied.isNotEmpty && mounted) {
      _showSettingsDialog(permanentlyDenied);
    }
  }

  void _showSettingsDialog(List<String> deniedPermissions) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Izin Diperlukan', style: TextStyle(fontSize: context.scaleSP(18), fontWeight: FontWeight.bold)),
        content: Text('Izin berikut telah ditolak secara permanen:\n\n'
            '${deniedPermissions.join(', ')}\n\n'
            'Silakan buka Pengaturan aplikasi untuk memberikan izin.',
            style: TextStyle(fontSize: context.scaleSP(14))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Batal', style: TextStyle(fontSize: context.scaleSP(14))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
              // Re-check setelah kembali dari settings
              Future.delayed(const Duration(seconds: 1), _checkPermissions);
            },
            child: Text('Buka Pengaturan', style: TextStyle(fontSize: context.scaleSP(14))),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Error', style: TextStyle(fontSize: context.scaleSP(18), fontWeight: FontWeight.bold)),
        content: Text(message, style: TextStyle(fontSize: context.scaleSP(14))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: TextStyle(fontSize: context.scaleSP(14))),
          ),
        ],
      ),
    );
  }

  void _navigateToNextScreen() {
    if (mounted) {
      // Navigate ke auth wrapper (login/splash)
      Navigator.of(context).pushReplacementNamed('/auth');
    }
  }

  void _exitApp() {
    AppLogger.i('User exiting app from permission gate',
        category: 'permissions');
    SystemNavigator.pop(); // Keluar dari aplikasi
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A237E), Color(0xFF0D47A1)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: context.isTablet ? 600 : double.infinity),
              child: _isCheckingPermissions
                  ? _buildLoadingView()
                  : _buildPermissionView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: context.scaleW(40),
            height: context.scaleW(40),
            child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
          ),
          SizedBox(height: context.scaleH(24)),
          Text(
            'Memeriksa izin aplikasi...',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: context.scaleSP(16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionView() {
    final allGranted = _allPermissionsGranted();

    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.all(context.scaleW(24)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // App Icon
                Center(
                  child: Container(
                    padding: EdgeInsets.all(context.scaleW(20)),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.security,
                      size: context.scaleW(80),
                      color: Colors.white,
                    ),
                  ),
                ),
                SizedBox(height: context.scaleH(32)),

                // Title
                Text(
                  'Izin Aplikasi Diperlukan',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: context.scaleSP(24),
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: context.scaleH(16)),

                // Description
                Text(
                  'ScanAI memerlukan izin berikut untuk berfungsi dengan baik:',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: context.scaleSP(14),
                    color: Colors.white70,
                  ),
                ),
                SizedBox(height: context.scaleH(32)),

                // Permission List
                ..._buildPermissionCards(),

                SizedBox(height: context.scaleH(40)),

                // Action Buttons
                if (!allGranted) ...[
                  ElevatedButton.icon(
                    onPressed: _requestPermissions,
                    icon: Icon(Icons.check_circle_outline, size: context.scaleW(20)),
                    label: Text('IZINKAN', style: TextStyle(fontSize: context.scaleSP(14), fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: context.scaleH(16)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(context.scaleW(12)),
                      ),
                    ),
                  ),
                  SizedBox(height: context.scaleH(12)),
                  OutlinedButton.icon(
                    onPressed: _exitApp,
                    icon: Icon(Icons.exit_to_app, size: context.scaleW(20)),
                    label: Text('KELUAR', style: TextStyle(fontSize: context.scaleSP(14), fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: EdgeInsets.symmetric(vertical: context.scaleH(16)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(context.scaleW(12)),
                      ),
                    ),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: _navigateToNextScreen,
                    icon: Icon(Icons.arrow_forward, size: context.scaleW(20)),
                    label: Text('LANJUTKAN', style: TextStyle(fontSize: context.scaleSP(14), fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: context.scaleH(16)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(context.scaleW(12)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildPermissionCards() {
    return _requiredPermissions.entries.map((entry) {
      final name = entry.key;
      final status = _permissionStatus[name] ?? PermissionStatus.denied;
      final isGranted = status.isGranted;

      String description;
      IconData icon;

      switch (name) {
        case 'Camera':
          description = isGranted
              ? 'Kamera dapat digunakan untuk memindai objek'
              : 'Kamera tidak dapat dijalankan. Aplikasi memerlukan akses kamera untuk memindai objek.';
          icon = Icons.camera_alt;
          break;
        case 'Notifikasi':
          description = isGranted
              ? 'Notifikasi aktif untuk status aplikasi'
              : 'Aplikasi tidak akan bisa berjalan di background tanpa izin notifikasi.';
          icon = Icons.notifications;
          break;
        default:
          description = isGranted ? 'Izin diberikan' : 'Izin ditolak';
          icon = Icons.info;
      }

      return Padding(
        padding: EdgeInsets.only(bottom: context.scaleH(16)),
        child: Container(
          padding: EdgeInsets.all(context.scaleW(16)),
          decoration: BoxDecoration(
            color: isGranted
                ? Colors.green.withValues(alpha: 0.2)
                : Colors.red.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(context.scaleW(12)),
            border: Border.all(
              color: isGranted
                  ? Colors.green.withValues(alpha: 0.5)
                  : Colors.red.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(context.scaleW(12)),
                decoration: BoxDecoration(
                  color: isGranted
                      ? Colors.green.withValues(alpha: 0.3)
                      : Colors.red.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: context.scaleW(24),
                ),
              ),
              SizedBox(width: context.scaleW(16)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.inter(
                            fontSize: context.scaleSP(16),
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: context.scaleW(8)),
                        Icon(
                          isGranted ? Icons.check_circle : Icons.cancel,
                          color: isGranted ? Colors.green : Colors.red,
                          size: context.scaleW(20),
                        ),
                      ],
                    ),
                    SizedBox(height: context.scaleH(4)),
                    Text(
                      description,
                      style: GoogleFonts.inter(
                        fontSize: context.scaleSP(12),
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }
}
