/// lib/presentation/screens/dashboard_screen.dart
/// Main Dashboard Screen - Split View layout for POS.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../config/routes.dart';
import '../../core/websocket/websocket_service.dart';
import '../../data/repositories/product_repository.dart';
import '../../services/auth_service.dart';
import '../providers/cart_provider.dart';
import '../widgets/live_items_widget.dart';
import '../widgets/cart_widget.dart';
import '../widgets/manual_input_widget.dart';

import 'package:pos_ai/core/utils/ui_helper.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  bool _aiActive = false;
  bool _isDialogShowing = false;
  int _currentTabIndex = 0;
  TabController? _tabController;
  bool _showManualInput = false; // For landscape mode toggle

  @override
  void initState() {
    super.initState();
    final wsService = context.read<WebSocketService>();
    // Listen for state changes to show dialogs
    wsService.addListener(_onWsServiceChange);

    // Start WebSocket listener on dashboard load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      wsService.startListening();
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    context.read<WebSocketService>().removeListener(_onWsServiceChange);
    super.dispose();
  }

  void _onWsServiceChange() {
    final wsService = context.read<WebSocketService>();
    if (wsService.connectionState == WsConnectionState.appNotInstalled &&
        !_isDialogShowing) {
      _showInstallDialog();
    }
  }

  void _toggleAI() {
    final wsService = context.read<WebSocketService>();
    setState(() => _aiActive = !_aiActive);

    if (_aiActive) {
      wsService.sendCommand('start');
    } else {
      wsService.sendCommand('stop');
      wsService.clearItems();
    }
  }

  Future<void> _addAIItemsToCart() async {
    final wsService = context.read<WebSocketService>();
    final cartProvider = context.read<CartProvider>();
    final productRepo = ProductRepository();
    final config = AppConfig();

    var addedCount = 0;
    for (final item in wsService.currentItems) {
      // Try to find product by name to get the real price
      var price = config.unregisteredProductPrice;
      var productId = item.id ?? 0;

      try {
        final products = await productRepo.searchProducts(item.label);
        if (products.isNotEmpty) {
          // Find exact match or use first result
          final product = products.firstWhere(
            (p) => p.name.toLowerCase() == item.label.toLowerCase(),
            orElse: () => products.first,
          );
          price = product.price;
          productId = product.id;
        }
      } catch (e) {
        // Use default price if fetch fails
        debugPrint('[Dashboard] Error fetching product price: $e');
      }

      cartProvider.addItem(
        productId: productId,
        productName: item.label,
        unitPrice: price,
        quantity: item.qty,
      );
      addedCount++;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$addedCount item ditambahkan ke keranjang', style: TextStyle(fontSize: context.scaleSP(14))),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authService = context.watch<AuthService>();
    final wsService = context.watch<WebSocketService>();
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'POS AI',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: context.scaleSP(20)),
        ),
        actions: [
          // AI Toggle & Activation Switch with connection status color and tooltip
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.scaleW(8)),
            child: Tooltip(
              message: wsService.statusMessage,
              child: InkWell(
                onTap: () {
                  if (!wsService.isConnected) {
                    // Not connected: Launch ScanAI logic
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Membuka ScanAI...', style: TextStyle(fontSize: context.scaleSP(14))),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    wsService.launchScanAI();
                  } else {
                    // Connected: Bring to front or just toggle
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('ScanAI Terhubung & Aktif', style: TextStyle(fontSize: context.scaleSP(14))),
                        duration: const Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(context.scaleW(12)),
                child: Row(
                  children: [
                    Padding(
                      padding: EdgeInsets.only(left: context.scaleW(8)),
                      child: Text(
                        'AI',
                        style: GoogleFonts.inter(
                          fontSize: context.scaleSP(13),
                          fontWeight: FontWeight.bold,
                          color: _getAiStatusColor(wsService.connectionState),
                        ),
                      ),
                    ),
                    Switch(
                      value: _aiActive && wsService.isConnected,
                      onChanged: (val) {
                        if (!wsService.isConnected) {
                          wsService.launchScanAI();
                          return;
                        }
                        _toggleAI();
                      },
                      activeTrackColor:
                          _getAiStatusColor(wsService.connectionState)
                              .withValues(alpha: 0.5),
                      inactiveTrackColor:
                          _getAiStatusColor(wsService.connectionState)
                              .withValues(alpha: 0.3),
                      thumbColor: WidgetStateProperty.resolveWith((states) {
                        return _getAiStatusColor(wsService.connectionState);
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // User Menu
          PopupMenuButton<String>(
            icon: CircleAvatar(
              radius: context.scaleW(18),
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
              child: Text(
                authService.cashierName.isNotEmpty
                    ? authService.cashierName[0].toUpperCase()
                    : '?',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.bold,
                  fontSize: context.scaleSP(14),
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            onSelected: (value) {
              switch (value) {
                case 'account':
                  Navigator.pushNamed(context, AppRoutes.account);
                  break;
                case 'products':
                  Navigator.pushNamed(context, AppRoutes.products);
                  break;
                case 'history':
                  Navigator.pushNamed(context, AppRoutes.history);
                  break;
                case 'logout':
                  authService.logout();
                  Navigator.pushReplacementNamed(context, AppRoutes.login);
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'user',
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authService.cashierName,
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: context.scaleSP(14)),
                    ),
                    Text(
                      authService.currentUser?.planType ?? 'Cashier',
                      style: GoogleFonts.inter(
                        fontSize: context.scaleSP(12),
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'account',
                child: Row(
                  children: [
                    Icon(Icons.person_outline,
                        size: context.scaleW(20), color: theme.colorScheme.onSurface),
                    SizedBox(width: context.scaleW(12)),
                    Text('Akun Saya', style: TextStyle(fontSize: context.scaleSP(14))),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'products',
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        size: context.scaleW(20), color: theme.colorScheme.onSurface),
                    SizedBox(width: context.scaleW(12)),
                    Text('Kelola Produk', style: TextStyle(fontSize: context.scaleSP(14))),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'history',
                child: Row(
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: context.scaleW(20), color: theme.colorScheme.onSurface),
                    SizedBox(width: context.scaleW(12)),
                    Text('Riwayat Transaksi', style: TextStyle(fontSize: context.scaleSP(14))),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: context.scaleW(20), color: Colors.red.shade400),
                    SizedBox(width: context.scaleW(12)),
                    Text('Keluar',
                        style: TextStyle(color: Colors.red.shade400, fontSize: context.scaleSP(14))),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(width: context.scaleW(8)),
        ],
      ),
      body: SafeArea(
        child: isLandscape ? _buildLandscapeLayout() : _buildPortraitLayout(),
      ),
      // FAB hanya muncul jika ada items AI dan di tab AI Detection (index 0), bukan di Manual/Cart
      floatingActionButton: wsService.currentItems.isNotEmpty &&
              (isLandscape ? !_showManualInput : _currentTabIndex == 0)
          ? FloatingActionButton(
              onPressed: _addAIItemsToCart,
              tooltip: 'Tambah ke Keranjang',
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              child: Icon(Icons.add_shopping_cart, size: context.scaleW(24)),
            )
          : null,
    );
  }

  Widget _buildLandscapeLayout() {
    return Padding(
      padding: EdgeInsets.all(context.scaleW(16)),
      child: Row(
        children: [
          // Left: Live Items or Manual Input with toggle button
          Expanded(
            flex: 4,
            child: Column(
              children: [
                // Toggle button for AI/Manual mode
                Container(
                  margin: EdgeInsets.only(bottom: context.scaleH(8)),
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('Deteksi AI', style: TextStyle(fontSize: context.scaleSP(13))),
                        icon: Icon(Icons.qr_code_scanner, size: context.scaleW(18)),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('Produk', style: TextStyle(fontSize: context.scaleSP(13))),
                        icon: Icon(Icons.inventory_2, size: context.scaleW(18)),
                      ),
                    ],
                    selected: {_showManualInput},
                    onSelectionChanged: (Set<bool> selection) {
                      setState(() => _showManualInput = selection.first);
                    },
                  ),
                ),
                // Content based on toggle
                Expanded(
                  child: _showManualInput
                      ? const ManualInputWidget()
                      : const LiveItemsWidget(),
                ),
              ],
            ),
          ),
          SizedBox(width: context.scaleW(16)),
          // Right: Cart
          const Expanded(
            flex: 5,
            child: CartWidget(),
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitLayout() {
    // Initialize TabController if not yet done (3 tabs now)
    _tabController ??= TabController(length: 3, vsync: this)
      ..addListener(() {
        if (!_tabController!.indexIsChanging) {
          setState(() {
            _currentTabIndex = _tabController!.index;
          });
        }
      });

    return Column(
      children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: TabBar(
            controller: _tabController,
            labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: context.scaleSP(13)),
            tabs: [
              Tab(text: 'AI', icon: Icon(Icons.qr_code_scanner, size: context.scaleW(20))),
              Tab(text: 'Produk', icon: Icon(Icons.inventory_2, size: context.scaleW(20))),
              Tab(text: 'Keranjang', icon: Icon(Icons.shopping_cart, size: context.scaleW(20))),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              Padding(
                padding: EdgeInsets.all(context.scaleW(16)),
                child: const LiveItemsWidget(),
              ),
              const ManualInputWidget(),
              Padding(
                padding: EdgeInsets.all(context.scaleW(16)),
                child: const CartWidget(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Returns color based on WebSocket connection state.
  /// Grey = Disconnected/Default (ScanAI not opened)
  /// Red = Error/App Not Installed/App Not Running
  /// Green = Connected
  Color _getAiStatusColor(WsConnectionState state) {
    switch (state) {
      case WsConnectionState.connected:
        return Colors.green;
      case WsConnectionState.appNotInstalled:
      case WsConnectionState.appNotRunning:
      case WsConnectionState.error:
        return Colors.red;
      case WsConnectionState.disconnected:
      case WsConnectionState.connecting:
        return Colors.grey;
    }
  }

  void _showInstallDialog() {
    _isDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: context.scaleW(24)),
            SizedBox(width: context.scaleW(10)),
            Text('ScanAI Required', style: TextStyle(fontSize: context.scaleSP(18), fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Aplikasi ScanAI tidak ditemukan di perangkat ini. Harap instal aplikasi ScanAI terlebih dahulu untuk menggunakan fitur deteksi cerdas.',
          style: TextStyle(fontSize: context.scaleSP(14)),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _isDialogShowing = false;
              Navigator.pop(context);
            },
            child: Text('Nanti Saja', style: TextStyle(fontSize: context.scaleSP(14))),
          ),
          ElevatedButton(
            onPressed: () {
              // Usually we would redirect to a download link or Play Store
              // For now we just close and maybe log
              _isDialogShowing = false;
              Navigator.pop(context);
            },
            child: Text('Instal Sekarang', style: TextStyle(fontSize: context.scaleSP(14))),
          ),
        ],
      ),
    ).then((_) => _isDialogShowing = false);
  }
}
