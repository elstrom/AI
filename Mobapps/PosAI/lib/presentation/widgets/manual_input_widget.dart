/// lib/presentation/widgets/manual_input_widget.dart
/// Widget for manual product input and catalog browsing.
library;

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../data/entities/category.dart';
import '../../data/entities/product.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/product_repository.dart';
import '../providers/cart_provider.dart';

import 'package:pos_ai/core/utils/ui_helper.dart';

class ManualInputWidget extends StatefulWidget {
  const ManualInputWidget({super.key});

  @override
  State<ManualInputWidget> createState() => _ManualInputWidgetState();
}

class _ManualInputWidgetState extends State<ManualInputWidget> {
  final TextEditingController _searchController = TextEditingController();
  final ProductRepository _productRepo = ProductRepository();
  final CategoryRepository _categoryRepo = CategoryRepository();
  final AppConfig _config = AppConfig();

  List<Product> _allProducts = [];
  List<Category> _categories = [];
  bool _isLoading = true;
  String? _error;

  List<Product> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final productsFuture = _productRepo.getAllProducts();
      final categoriesFuture = _categoryRepo.getAllCategories();

      final results = await Future.wait([productsFuture, categoriesFuture]);

      if (mounted) {
        setState(() {
          _allProducts = results[0] as List<Product>;
          _categories = results[1] as List<Category>;

          // Ensure we have a default category for products with ID=0 or unknown
          if (!_categories.any((c) => c.id == 1)) {
            // In case category 1 is missing/deleted but products use it
            _categories.add(Category(id: 1, name: 'Umum'));
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Gagal memuat data: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _searchProducts(String query) {
    if (query.length < 2) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchResults = _allProducts
          .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  void _addToCart(Product product) {
    final cart = context.read<CartProvider>();
    cart.addItem(
      productId: product.id,
      productName: product.name,
      unitPrice: product.price,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.name} ditambahkan'),
        duration: const Duration(milliseconds: 600),
        behavior: SnackBarBehavior.floating,
        width: context.scaleW(200),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.currency(
      locale: _config.locale,
      symbol: '${_config.currencySymbol} ',
      decimalDigits: 0,
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Search
          Padding(
            padding: EdgeInsets.all(context.scaleW(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchController,
                  style: TextStyle(fontSize: context.scaleSP(16)),
                  onChanged: _searchProducts,
                  decoration: InputDecoration(
                    hintText: 'Cari produk...',
                    hintStyle: TextStyle(fontSize: context.scaleSP(14)),
                    prefixIcon: Icon(Icons.search, size: context.scaleW(20)),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, size: context.scaleW(20)),
                            onPressed: () {
                              _searchController.clear();
                              _searchProducts('');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(context.scaleW(12)),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _buildContent(theme, currencyFormat),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme, NumberFormat currencyFormat) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: context.scaleW(48), color: Colors.orange),
            SizedBox(height: context.scaleH(16)),
            Text(_error!, style: TextStyle(fontSize: context.scaleSP(14))),
            SizedBox(height: context.scaleH(8)),
            ElevatedButton(
                onPressed: _loadData, child: Text('Coba Lagi', style: TextStyle(fontSize: context.scaleSP(14)))),
          ],
        ),
      );
    }

    // Search Mode
    if (_isSearching) {
      if (_searchResults.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: context.scaleW(48), color: Colors.grey[400]),
              SizedBox(height: context.scaleH(16)),
              Text('Tidak ditemukan',
                  style: TextStyle(color: Colors.grey[600], fontSize: context.scaleSP(14))),
            ],
          ),
        );
      }
      return ListView.builder(
        padding: EdgeInsets.all(context.scaleW(16)),
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          return _ProductListTile(
            product: _searchResults[index],
            currencyFormat: currencyFormat,
            onTap: () => _addToCart(_searchResults[index]),
          );
        },
      );
    }

    // Catalog Mode (Grouped by Category)
    if (_allProducts.isEmpty) {
      return Center(child: Text('Belum ada data produk', style: TextStyle(fontSize: context.scaleSP(14))));
    }

    // Group products
    final grouped = <int, List<Product>>{};
    for (var p in _allProducts) {
      if (!grouped.containsKey(p.categoryId)) {
        grouped[p.categoryId] = [];
      }
      grouped[p.categoryId]!.add(p);
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: context.scaleW(16), vertical: context.scaleH(8)),
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final category = _categories[index];
        final products = grouped[category.id] ?? [];

        if (products.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: context.scaleH(12)),
              child: Row(
                children: [
                  Container(
                    width: context.scaleW(4),
                    height: context.scaleH(18),
                    decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(context.scaleW(2))),
                  ),
                  SizedBox(width: context.scaleW(8)),
                  Text(
                    category.name,
                    style: GoogleFonts.inter(
                      fontSize: context.scaleSP(16),
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(width: context.scaleW(8)),
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: context.scaleW(8), vertical: context.scaleH(2)),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(context.scaleW(12)),
                    ),
                    child: Text(
                      '${products.length}',
                      style: TextStyle(
                          fontSize: context.scaleSP(12),
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),

            // Products Grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: context.scaleW(200),
                childAspectRatio: 0.8,
                crossAxisSpacing: context.scaleW(12),
                mainAxisSpacing: context.scaleH(12),
              ),
              itemCount: products.length,
              itemBuilder: (context, pIndex) {
                return _ProductCard(
                  product: products[pIndex],
                  currencyFormat: currencyFormat,
                  onTap: () => _addToCart(products[pIndex]),
                );
              },
            ),
            SizedBox(height: context.scaleH(16)),
            Divider(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)),
          ],
        );
      },
    );
  }
}

class _ProductListTile extends StatelessWidget {

  const _ProductListTile({
    required this.product,
    required this.currencyFormat,
    required this.onTap,
  });
  final Product product;
  final NumberFormat currencyFormat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.only(bottom: context.scaleH(8)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            product.name.isNotEmpty ? product.name[0].toUpperCase() : '?',
            style: TextStyle(color: theme.colorScheme.onPrimaryContainer, fontSize: context.scaleSP(14)),
          ),
        ),
        title: Text(product.name,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: context.scaleSP(14))),
        subtitle: Text(currencyFormat.format(product.price), style: TextStyle(fontSize: context.scaleSP(12))),
        trailing: Icon(Icons.add_circle, color: theme.colorScheme.primary, size: context.scaleW(24)),
        onTap: onTap,
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Product>('product', product));
    properties.add(DiagnosticsProperty<NumberFormat>('currencyFormat', currencyFormat));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}

class _ProductCard extends StatelessWidget {

  const _ProductCard({
    required this.product,
    required this.currencyFormat,
    required this.onTap,
  });
  final Product product;
  final NumberFormat currencyFormat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.scaleW(12))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image Placeholder (or real image if available)
            Expanded(
              flex: 3,
              child: Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Center(
                  child: Text(
                    product.name.isNotEmpty
                        ? product.name[0].toUpperCase()
                        : '?',
                    style: GoogleFonts.inter(
                      fontSize: context.scaleSP(32),
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),
            // Info
            Expanded(
              flex: 2,
              child: Padding(
                padding: EdgeInsets.all(context.scaleW(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: context.scaleSP(14),
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          currencyFormat.format(product.price),
                          style: GoogleFonts.inter(
                            fontSize: context.scaleSP(14),
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Icon(Icons.add_circle_outline,
                            size: context.scaleW(20), color: theme.colorScheme.primary),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Product>('product', product));
    properties.add(DiagnosticsProperty<NumberFormat>('currencyFormat', currencyFormat));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}
