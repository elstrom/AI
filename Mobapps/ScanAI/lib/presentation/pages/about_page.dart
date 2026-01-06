import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:scanai_app/core/constants/config_service.dart';
import 'package:scanai_app/services/auth_service.dart';
import 'package:scanai_app/core/utils/ui_helper.dart';
import 'package:scanai_app/presentation/state/camera_state.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  Future<void> _handleLogout() async {
    // Show confirmation dialog
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Logout', style: TextStyle(fontSize: context.scaleSP(18), fontWeight: FontWeight.bold)),
        content: Text('Yakin ingin logout?', style: TextStyle(fontSize: context.scaleSP(14))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Batal', style: TextStyle(fontSize: context.scaleSP(14))),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Logout', style: TextStyle(fontSize: context.scaleSP(14), color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldLogout == true && mounted) {
      // Stop camera streaming and turn off flash before logout
      try {
        final cameraState = Provider.of<CameraState>(context, listen: false);
        if (cameraState.isStreaming) {
          await cameraState.stopStreaming();
        }
        // Flash will be turned off automatically when streaming stops
      } catch (e) {
        // Ignore errors during cleanup
      }
      
      // Perform logout
      final authService = AuthService();
      await authService.logout();

      if (mounted) {
        // Navigate to /auth route and remove all previous routes
        // AuthWrapper will detect logout and show LoginPage
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/auth',
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final configService = ConfigService();

    return Scaffold(
      appBar: AppBar(
        title: Text('About', style: TextStyle(fontSize: context.scaleSP(20))),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, size: context.scaleW(24)),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: context.isTablet ? 650 : double.infinity),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(context.scaleW(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App logo and name
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: context.scaleW(100),
                          height: context.scaleW(100),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(context.scaleW(16)),
                          ),
                          child: Icon(
                            Icons.camera,
                            color: Colors.white,
                            size: context.scaleW(64),
                          ),
                        ),
                        SizedBox(height: context.scaleH(16)),
                        Text(
                          configService.appName,
                          style: TextStyle(
                            fontSize: context.scaleSP(24),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Version ${configService.appVersion}',
                          style: TextStyle(fontSize: context.scaleSP(16), color: Colors.grey),
                        ),
                        Text(
                          'Build ${configService.buildNumber}',
                          style: TextStyle(fontSize: context.scaleSP(14), color: Colors.grey),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: context.scaleH(32)),

                  // Description
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.scaleW(12))),
                    child: Padding(
                      padding: EdgeInsets.all(context.scaleW(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'About ScanAI',
                            style: TextStyle(
                              fontSize: context.scaleSP(18),
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[800],
                            ),
                          ),
                          SizedBox(height: context.scaleH(8)),
                          Text(
                            'ScanAI is a cutting-edge real-time object detection platform designed for seamless performance. Leveraging high-performance WebSocket streaming and advanced AI models, ScanAI identifies and labels objects with precision and speed.',
                            style: TextStyle(
                              fontSize: context.scaleSP(14),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: context.scaleH(16)),

                  // Account Information (NEW)
                  Consumer<AuthService>(
                    builder: (context, auth, _) {
                      final user = auth.currentUser;
                      if (user == null) return const SizedBox.shrink();
                      
                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.scaleW(12))),
                        child: Padding(
                          padding: EdgeInsets.all(context.scaleW(16)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.account_circle, color: Colors.blue, size: context.scaleW(28)),
                                  SizedBox(width: context.scaleW(8)),
                                  Text(
                                    'Account Information',
                                    style: TextStyle(
                                      fontSize: context.scaleSP(18),
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[800],
                                    ),
                                  ),
                                ],
                              ),
                              Divider(height: context.scaleH(24)),
                              _AccountRow(
                                label: 'Username',
                                value: user.username,
                                icon: Icons.person_outline,
                              ),
                              _AccountRow(
                                label: 'Plan Type',
                                value: user.planType.toUpperCase(),
                                icon: Icons.star_outline,
                                valueColor: user.planType.toLowerCase() == 'pro' ? Colors.orange[800] : null,
                              ),
                              _AccountRow(
                                label: 'User ID',
                                value: '#${user.id}',
                                icon: Icons.tag,
                              ),
                              if (user.planExpiredAt != null)
                                _AccountRow(
                                  label: 'Subscription Ends',
                                  value: user.planExpiredAt.toString().substring(0, 10),
                                  icon: Icons.calendar_today_outlined,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  SizedBox(height: context.scaleH(16)),

                  // Features (Simplified)
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.scaleW(12))),
                    child: Padding(
                      padding: EdgeInsets.all(context.scaleW(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Key Features',
                            style: TextStyle(
                              fontSize: context.scaleSP(18),
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[800],
                            ),
                          ),
                          SizedBox(height: context.scaleH(12)),
                          const _FeatureItem(
                            icon: Icons.bolt,
                            title: 'Real-time Detection',
                            description: 'Low-latency AI object identification',
                          ),
                          const _FeatureItem(
                            icon: Icons.cloud_sync,
                            title: 'Cloud Edge Processing',
                            description: 'High-performance remote AI analysis',
                          ),
                          const _FeatureItem(
                            icon: Icons.camera_alt_outlined,
                            title: 'Smart Camera',
                            description: 'Advanced frame capture optimizations',
                          ),
                          const _FeatureItem(
                            icon: Icons.flash_auto,
                            title: 'Auto Flash Mode',
                            description: 'Intelligent lighting adjustment for detection',
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: context.scaleH(16)),

                  // Credits
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(context.scaleW(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Credits',
                            style: TextStyle(
                              fontSize: context.scaleSP(18),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: context.scaleH(8)),
                          Text(
                            'Developed by the ScanAI Team',
                            style: TextStyle(fontSize: context.scaleSP(16)),
                          ),
                          SizedBox(height: context.scaleH(8)),
                          Text(
                            '© 2023 ScanAI. All rights reserved.',
                            style: TextStyle(fontSize: context.scaleSP(14), color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: context.scaleH(16)),

                  // Links
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(context.scaleW(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Links',
                            style: TextStyle(
                              fontSize: context.scaleSP(18),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: context.scaleH(8)),
                          ListTile(
                            leading: Icon(Icons.language, size: context.scaleW(24)),
                            title: Text('Website', style: TextStyle(fontSize: context.scaleSP(16))),
                            onTap: () {
                              // TODO: Open website
                            },
                          ),
                          ListTile(
                            leading: Icon(Icons.privacy_tip, size: context.scaleW(24)),
                            title: Text('Privacy Policy', style: TextStyle(fontSize: context.scaleSP(16))),
                            onTap: () {
                              // TODO: Open privacy policy
                            },
                          ),
                          ListTile(
                            leading: Icon(Icons.description, size: context.scaleW(24)),
                            title: Text('Terms of Service', style: TextStyle(fontSize: context.scaleSP(16))),
                            onTap: () {
                              // TODO: Open terms of service
                            },
                          ),
                          ListTile(
                            leading: Icon(Icons.contact_support, size: context.scaleW(24)),
                            title: Text('Contact Support', style: TextStyle(fontSize: context.scaleSP(16))),
                            onTap: () {
                              // TODO: Open contact support
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: context.scaleH(32)),

                  // Logout Button
                  SizedBox(
                    width: double.infinity,
                    height: context.scaleH(56),
                    child: ElevatedButton.icon(
                      onPressed: _handleLogout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(context.scaleW(12)),
                        ),
                      ),
                      icon: Icon(Icons.logout, size: context.scaleW(24)),
                      label: Text(
                        'Log Out',
                        style: TextStyle(
                          fontSize: context.scaleSP(18),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: context.scaleH(32)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Feature item widget
class _FeatureItem extends StatelessWidget {
  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.scaleH(4)),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue, size: context.scaleW(24)),
          SizedBox(width: context.scaleW(8)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: context.scaleSP(14)),
                ),
                Text(description, style: TextStyle(color: Colors.grey, fontSize: context.scaleSP(12))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<IconData>('icon', icon));
    properties.add(StringProperty('title', title));
    properties.add(StringProperty('description', description));
  }
}


/// Account information row widget
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.scaleH(8)),
      child: Row(
        children: [
          Icon(icon, size: context.scaleW(20), color: Colors.grey[600]),
          SizedBox(width: context.scaleW(12)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: context.scaleSP(12),
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: context.scaleSP(15),
                  fontWeight: FontWeight.bold,
                  color: valueColor ?? Colors.black87,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('label', label));
    properties.add(StringProperty('value', value));
    properties.add(DiagnosticsProperty<IconData>('icon', icon));
    properties.add(ColorProperty('valueColor', valueColor));
  }
}
