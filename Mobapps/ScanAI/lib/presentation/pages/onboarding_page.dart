import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scanai_app/core/utils/ui_helper.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isID = true; // Default ID
  late AnimationController _pulseController;
  late AnimationController _landingController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _landingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isID = (prefs.getString('app_lang') ?? 'id') == 'id';
    });
  }

  Future<void> _toggleLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isID = !_isID;
      prefs.setString('app_lang', _isID ? 'id' : 'en');
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pulseController.dispose();
    _landingController.dispose();
    super.dispose();
  }

  String _t(String id, String en) => _isID ? id : en;

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/permission_gate');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Dynamic Background
          AnimatedPositioned(
            duration: const Duration(milliseconds: 500),
            top: -100,
            right: -50,
            child: _AnimatedBlob(
              color: _getColor(_currentPage).withValues(alpha: 0.15),
              size: 400,
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top Bar
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.scaleW(24),
                    vertical: context.scaleH(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildLogo(),
                      _buildLanguageToggle(),
                    ],
                  ),
                ),

                // Main Content (Interactive Mockups)
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) => setState(() => _currentPage = index),
                    children: [
                      _buildLandingSlide(),
                      _buildPermissionSlide1(),
                      _buildPermissionSlide2(),
                      _buildPermissionSlide3(),
                      _buildLoginSlide(),
                      _buildCameraSlide5(),
                      _buildCameraSlide6(),
                      _buildCameraSlide7(),
                      _buildAboutSlide(),
                    ],
                  ),
                ),

                // Bottom Content
                _buildBottomUI(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(context.scaleW(6)),
          decoration: BoxDecoration(
            color: Colors.blueAccent,
            borderRadius: BorderRadius.circular(context.scaleW(8)),
          ),
          child: Icon(Icons.auto_awesome, color: Colors.white, size: context.scaleW(14)),
        ),
        SizedBox(width: context.scaleW(8)),
        Text(
          'ScanAI Tutorial',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: context.scaleSP(16),
          ),
        ),
      ],
    );
  }

  Widget _buildLanguageToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: InkWell(
        onTap: _toggleLanguage,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _toggleItem('ID', _isID),
              _toggleItem('EN', !_isID),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleItem(String label, bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: active ? Colors.blueAccent : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: active ? Colors.white : Colors.white54,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // --- SLIDES ---

  Widget _buildLandingSlide() {
    return Container(
      padding: EdgeInsets.all(context.scaleW(40)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: Tween(begin: 1.0, end: 1.05).animate(_landingController),
            child: Container(
              width: context.scaleW(180),
              height: context.scaleW(180),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Colors.blueAccent, Colors.transparent],
                  stops: [0.3, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent.withValues(alpha: 0.3),
                    blurRadius: 50,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 80),
            ),
          ),
          const SizedBox(height: 60),
          Text(
            _t('Selamat Datang di ScanAI', 'Welcome to ScanAI'),
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: context.scaleSP(32),
              fontWeight: FontWeight.bold,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _t(
              'Asisten deteksi objek real-time Anda. Mari pelajari cara kerja aplikasi ini dalam hitungan detik.',
              'Your real-time object detection assistant. Let\'s learn how this app works in seconds.',
            ),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: context.scaleSP(15),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionSlide1() {
    return _OnboardingSlideBase(
      mockupData: _MockupData(
        image: 'assets/images/onboarding/img1.jpeg',
        highlightAlignment: const Alignment(0, 0), // Base state
      ),
      pulseAnimation: _pulseController,
      title: _t('Pintu Perizinan', 'Permission Gate'),
      description: _t(
        'ScanAI membutuhkan izin Kamera dan Notifikasi agar dapat berfungsi secara optimal di perangkat Anda.',
        'ScanAI requires Camera and Notification permissions to function optimally on your device.',
      ),
      color: const Color(0xFF6366F1),
    );
  }

  Widget _buildPermissionSlide2() {
    return _OnboardingSlideBase(
      mockupData: _MockupData(
        image: 'assets/images/onboarding/img2.jpeg',
        highlightAlignment: const Alignment(0.3, 0.33), // Warning icon area
      ),
      pulseAnimation: _pulseController,
      title: _t('Peringatan Izin', 'Permission Warning'),
      description: _t(
        'Jika ada izin yang belum diberikan, sistem akan menampilkan ikon peringatan merah dan popup sebagai pengingat.',
        'If any permission is not granted, the system will show a red warning icon and popup as a reminder.',
      ),
      color: Colors.orange,
    );
  }

  Widget _buildPermissionSlide3() {
    return _OnboardingSlideBase(
      mockupData: _MockupData(
        image: 'assets/images/onboarding/img3.jpeg',
        highlightAlignment: const Alignment(0, 0.75), // Permission list area
      ),
      pulseAnimation: _pulseController,
      title: _t('Izin Berhasil', 'Permission Success'),
      description: _t(
        'Pastikan kedua izin sudah dicentang hijau. Tekan tombol Cek Izin untuk memverifikasi ulang.',
        'Ensure both permissions are checked green. Tap Check Permissions to re-verify.',
      ),
      color: Colors.green,
    );
  }

  Widget _buildLoginSlide() {
    return _OnboardingSlideBase(
      mockupData: _MockupData(
        image: 'assets/images/onboarding/img4.jpeg',
        highlightAlignment: const Alignment(0, 0.72), // Login area
      ),
      pulseAnimation: _pulseController,
      title: _t('Keamanan Akses', 'Secure Access'),
      description: _t(
        'Gunakan akun resmi Anda atau gunakan tombol bypass "OFFLINE REVIEW" untuk mencoba fitur aplikasi. Anda juga dapat akun admin1 pada username dan password sebagai taham percobaan terbatas',
        'Use your official account or use the "OFFLINE REVIEW" bypass button to try the features. You can also use the admin1 account on username and password as a limited trial.',
      ),
      color: const Color(0xFFEC4899),
    );
  }

  Widget _buildCameraSlide5() {
    return _OnboardingSlideBase(
      mockupData: _MockupData(
        image: 'assets/images/onboarding/img5.jpeg',
        highlightAlignment: const Alignment(0.0, 1.05), // System status indicator
      ),
      pulseAnimation: _pulseController,
      title: _t('Status Sistem', 'System Status'),
      description: _t(
        'Ikon di bawah tengah menunjukkan status koneksi server. Status akan "Memindai" jika sudah siap.',
        'The bottom middle icon shows server connection status. Status will be "Scanning" if ready.',
      ),
      color: Colors.redAccent,
    );
  }

  Widget _buildCameraSlide6() {
    return _OnboardingSlideBase(
      mockupData: _MockupData(
        image: 'assets/images/onboarding/img6.jpeg',
        highlightAlignment: const Alignment(-0.22, 0.82), // Bottom panel
      ),
      pulseAnimation: _pulseController,
      title: _t('Panel Kontrol', 'Control Panel'),
      description: _t(
        'Melalui panel bawah, Anda dapat mengambil Foto, memulai streaming, mengaktifkan Flash atau mengganti kamera.',
        'Via the bottom panel, you can take Photos, start streaming, activate Flash, or switch cameras.',
      ),
      color: Colors.blueAccent,
    );
  }

  Widget _buildCameraSlide7() {
    return _OnboardingSlideBase(
      mockupData: _MockupData(
        image: 'assets/images/onboarding/img7.jpeg',
        highlightAlignment: const Alignment(-0.22, 0.82), // Detection center
      ),
      pulseAnimation: _pulseController,
      title: _t('Deteksi Pintar', 'Smart Detection'),
      description: _t(
        'Aktifkan mode Streaming untuk mendeteksi objek secara real-time dengan bantuan kecerdasan buatan.',
        'Enable Streaming mode to detect objects in real-time with the help of artificial intelligence.',
      ),
      color: Colors.teal,
    );
  }

  Widget _buildAboutSlide() {
    return _OnboardingSlideBase(
      mockupData: _MockupData(
        image: 'assets/images/onboarding/img8.jpeg',
        highlightAlignment: const Alignment(0, 0.95), // Logout button
      ),
      pulseAnimation: _pulseController,
      title: _t('Profil & Support', 'Profile & Support'),
      description: _t(
        'Pada halaman about anda dapat melihat detail paket berlangganan atau tekan tombol Logout jika ingin mengganti akun Anda.',
        'On the about page, you can view subscription details or tap the Logout button if you want to switch your account.',
      ),
      color: const Color(0xFF10B981),
    );
  }

  Widget _buildBottomUI() {
    var totalPages = 9;
    var isLast = _currentPage == totalPages - 1;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: context.scaleW(32), vertical: context.scaleH(20)),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, const Color(0xFF0F172A).withValues(alpha: 0.8)],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Indicators
          Row(
            children: List.generate(totalPages, _buildCircleIndicator),
          ),

          // Navigation
          Row(
            children: [
              if (!isLast)
                TextButton(
                  onPressed: _completeOnboarding,
                  child: Text(_t('LEWATI', 'SKIP'), style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
                ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: () {
                  if (isLast) {
                    _completeOnboarding();
                  } else {
                    _pageController.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.easeOutQuart);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _getColor(_currentPage),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: Text(
                  isLast ? _t('MULAI', 'START') : _t('LANJUT', 'NEXT'),
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCircleIndicator(int index) {
    var active = _currentPage == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(right: 6),
      height: 4,
      width: active ? 16 : 4,
      decoration: BoxDecoration(
        color: active ? _getColor(_currentPage) : Colors.white24,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  Color _getColor(int index) {
    switch(index) {
      case 0: return Colors.blueAccent;
      case 1: return const Color(0xFF6366F1);
      case 2: return Colors.orange;
      case 3: return Colors.green;
      case 4: return const Color(0xFFEC4899);
      case 5: return Colors.redAccent;
      case 6: return Colors.blueAccent;
      case 7: return Colors.teal;
      case 8: return const Color(0xFF10B981);
      default: return Colors.blueAccent;
    }
  }
}

class _MockupData {

  _MockupData({required this.image, required this.highlightAlignment});
  final String image;
  final Alignment highlightAlignment;
}

class _OnboardingSlideBase extends StatelessWidget {

  const _OnboardingSlideBase({
    required this.mockupData,
    required this.pulseAnimation,
    required this.title,
    required this.description,
    required this.color,
  });
  
  final _MockupData mockupData;
  final Animation<double> pulseAnimation;
  final String title;
  final String description;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.scaleW(24)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // The Interactive Mockup Area
          Expanded(
            flex: 6,
            child: Center(
              child: AspectRatio(
                aspectRatio: 9/19.5,
                child: Container(
                  margin: EdgeInsets.symmetric(vertical: context.scaleH(10)),
                  decoration: BoxDecoration(
                    color: Colors.black, // Phone bezel
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade800, width: 4),
                    boxShadow: [
                      BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 40),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          mockupData.image,
                          fit: BoxFit.fill,
                        ),
                        
                        Align(
                          alignment: mockupData.highlightAlignment,
                          child: _PulseCircle(
                            pulseAnimation: pulseAnimation, 
                            child: const SizedBox(width: 1, height: 1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Text Content
          Expanded(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: context.scaleSP(26), fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    description,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: Colors.white70, fontSize: context.scaleSP(14), height: 1.5),
                  ),
                ),
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
    properties.add(DiagnosticsProperty<_MockupData>('mockupData', mockupData));
    properties.add(DiagnosticsProperty<Animation<double>>('pulseAnimation', pulseAnimation));
    properties.add(StringProperty('title', title));
    properties.add(StringProperty('description', description));
    properties.add(ColorProperty('color', color));
  }
}

class _PulseCircle extends StatelessWidget {
  const _PulseCircle({required this.pulseAnimation, required this.child});
  final Animation<double> pulseAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        FadeTransition(
          opacity: Tween(begin: 0.6, end: 0.0).animate(pulseAnimation),
          child: ScaleTransition(
            scale: Tween(begin: 1.0, end: 2.5).animate(pulseAnimation),
            child: Container(width: 50, height: 50, decoration: BoxDecoration(border: Border.all(color: Colors.blueAccent, width: 2), shape: BoxShape.circle)),
          ),
        ),
        FadeTransition(
          opacity: Tween(begin: 0.4, end: 0.0).animate(CurvedAnimation(parent: pulseAnimation, curve: const Interval(0.2, 1.0))),
          child: ScaleTransition(
            scale: Tween(begin: 1.0, end: 2.0).animate(pulseAnimation),
            child: Container(width: 50, height: 50, decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.3), shape: BoxShape.circle)),
          ),
        ),
        child,
      ],
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Animation<double>>('pulseAnimation', pulseAnimation));
  }
}

class _AnimatedBlob extends StatelessWidget {
  const _AnimatedBlob({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: 100, spreadRadius: 50)]));
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ColorProperty('color', color));
    properties.add(DoubleProperty('size', size));
  }
}
