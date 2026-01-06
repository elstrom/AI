/// lib/presentation/widgets/cart_widget.dart
/// Cart Widget - Shows items in cart with qty editing, total, and payment.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../services/auth_service.dart';
import '../providers/cart_provider.dart';

import 'package:pos_ai/core/utils/ui_helper.dart';

class CartWidget extends StatelessWidget {
  const CartWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = AppConfig();
    final currencyFormat = NumberFormat.currency(
      locale: config.locale,
      symbol: '${config.currencySymbol} ',
      decimalDigits: 0,
    );

    return Consumer<CartProvider>(
      builder: (context, cart, child) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(context.scaleW(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: context.scaleW(16),
                offset: Offset(0, context.scaleW(4)),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(context.scaleW(16)),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(context.scaleW(16))),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.shopping_cart_rounded,
                      color: theme.colorScheme.primary,
                      size: context.scaleW(24),
                    ),
                    SizedBox(width: context.scaleW(12)),
                    Text(
                      'Keranjang Belanja',
                      style: GoogleFonts.inter(
                        fontSize: context.scaleSP(16),
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    if (cart.itemCount > 0)
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: context.scaleW(10), vertical: context.scaleH(4)),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(context.scaleW(12)),
                        ),
                        child: Text(
                          '${cart.itemCount} item',
                          style: GoogleFonts.inter(
                            fontSize: context.scaleSP(12),
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Cart Items List
              Expanded(
                child: cart.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.shopping_basket_outlined,
                              size: context.scaleW(64),
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.2),
                            ),
                            SizedBox(height: context.scaleH(16)),
                            Text(
                              'Keranjang kosong',
                              style: GoogleFonts.inter(
                                fontSize: context.scaleSP(16),
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            SizedBox(height: context.scaleH(8)),
                            Text(
                              'Barang akan muncul dari AI',
                              style: GoogleFonts.inter(
                                fontSize: context.scaleSP(13),
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.symmetric(
                            horizontal: context.scaleW(12), vertical: context.scaleH(8)),
                        itemCount: cart.items.length,
                        itemBuilder: (context, index) {
                          final item = cart.items[index];
                          return _CartItemTile(
                            productName: item.productName,
                            unitPrice: item.unitPrice,
                            quantity: item.quantity,
                            subtotal: item.subtotal,
                            currencyFormat: currencyFormat,
                            onIncrement: () =>
                                cart.incrementQuantity(item.productId),
                            onDecrement: () =>
                                cart.decrementQuantity(item.productId),
                            onRemove: () => cart.removeItem(item.productId),
                          );
                        },
                      ),
              ),

              // Summary & Payment Section
              Container(
                padding: EdgeInsets.all(context.scaleW(16)),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(context.scaleW(16))),
                ),
                child: Column(
                  children: [
                    // Payment Method Dropdown
                    Row(
                      children: [
                        Text(
                          'Metode Bayar:',
                          style: GoogleFonts.inter(
                            fontSize: context.scaleSP(13),
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.7),
                          ),
                        ),
                        SizedBox(width: context.scaleW(12)),
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: context.scaleW(12)),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(context.scaleW(8)),
                              border: Border.all(
                                color: theme.colorScheme.outline
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: cart.paymentMethod,
                                isExpanded: true,
                                style: TextStyle(fontSize: context.scaleSP(14), color: theme.colorScheme.onSurface),
                                items: config.paymentMethods.map((method) {
                                  return DropdownMenuItem(
                                    value: method,
                                    child: Text(method),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    cart.setPaymentMethod(value);
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: context.scaleH(16)),

                    // Summary Lines
                    _SummaryLine(
                      label: 'Subtotal',
                      value: currencyFormat.format(cart.subtotal),
                    ),
                    SizedBox(height: context.scaleH(4)),
                    _SummaryLine(
                      label:
                          'PPN (${(config.defaultTaxRate * 100).toStringAsFixed(0)}%)',
                      value: currencyFormat.format(cart.taxAmount),
                    ),
                    if (cart.discount > 0) ...[
                      SizedBox(height: context.scaleH(4)),
                      _SummaryLine(
                        label: 'Diskon',
                        value: '-${currencyFormat.format(cart.discount)}',
                        valueColor: Colors.green,
                      ),
                    ],
                    Divider(height: context.scaleH(24)),

                    // Total
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TOTAL',
                          style: GoogleFonts.inter(
                            fontSize: context.scaleSP(18),
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          currencyFormat.format(cart.total),
                          style: GoogleFonts.inter(
                            fontSize: context.scaleSP(24),
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: context.scaleH(16)),

                    // Pay Button
                    SizedBox(
                      width: double.infinity,
                      height: context.scaleH(56),
                      child: ElevatedButton(
                        onPressed: cart.isEmpty || cart.isProcessing
                            ? null
                            : () => _processPayment(context, cart),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(context.scaleW(12)),
                          ),
                          elevation: 4,
                        ),
                        child: cart.isProcessing
                            ? SizedBox(
                                width: context.scaleW(24),
                                height: context.scaleW(24),
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.payment_rounded, size: context.scaleW(24)),
                                  SizedBox(width: context.scaleW(12)),
                                  Text(
                                    'PROSES BAYAR',
                                    style: GoogleFonts.inter(
                                      fontSize: context.scaleSP(16),
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _processPayment(BuildContext context, CartProvider cart) async {
    final authService = context.read<AuthService>();
    final config = AppConfig();

    // Save totals before cart is cleared
    final totalAmount = cart.total;
    final itemCount = cart.itemCount;
    final paymentMethod = cart.paymentMethod;
    double? paidAmount;
    var changeAmount = 0.0;

    // If Cash, ask for amount paid
    if (paymentMethod == 'Cash') {
      final result = await showDialog<double>(
        context: context,
        builder: (ctx) => _PaymentAmountDialog(totalAmount: totalAmount),
      );

      if (result == null) return; // Cancelled
      paidAmount = result;
      changeAmount = paidAmount - totalAmount;
    }

    final success = await cart.processTransaction(
      userId: authService.currentUser?.userId ?? 0,
      cashierName: authService.cashierName,
      paidAmount: paidAmount,
    );

    if (context.mounted) {
      if (success) {
        // Show success dialog
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(
              Icons.check_circle,
              color: Colors.green.shade600,
              size: context.scaleW(64),
            ),
            title: Text(
              'Transaksi Berhasil!',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: context.scaleSP(18)),
              textAlign: TextAlign.center,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${config.currencySymbol} ${NumberFormat('#,###').format(totalAmount)}',
                  style: GoogleFonts.inter(
                    fontSize: context.scaleSP(32),
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
                if (paidAmount != null) ...[
                  SizedBox(height: context.scaleH(8)),
                  Text(
                    'Tunai: ${NumberFormat('#,###').format(paidAmount)}',
                    style: GoogleFonts.inter(fontSize: context.scaleSP(14)),
                  ),
                  Text(
                    'Kembalian: ${NumberFormat('#,###').format(changeAmount)}',
                    style: GoogleFonts.inter(
                      fontSize: context.scaleSP(16),
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ],
                SizedBox(height: context.scaleH(8)),
                Text(
                  '$itemCount item • $paymentMethod',
                  style: GoogleFonts.inter(
                    fontSize: context.scaleSP(14),
                    color: Theme.of(ctx)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
                ),
                SizedBox(height: context.scaleH(16)),
                Text(
                  'Terima kasih!',
                  style: GoogleFonts.inter(fontSize: context.scaleSP(16)),
                ),
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.scaleW(8))),
                  ),
                  child: Text('OK', style: TextStyle(fontSize: context.scaleSP(14))),
                ),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Gagal memproses transaksi. Silakan coba lagi.', style: TextStyle(fontSize: context.scaleSP(14))),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    }
  }
}

class _PaymentAmountDialog extends StatefulWidget {

  const _PaymentAmountDialog({required this.totalAmount});
  final double totalAmount;

  @override
  State<_PaymentAmountDialog> createState() => _PaymentAmountDialogState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('totalAmount', totalAmount));
  }
}

class _PaymentAmountDialogState extends State<_PaymentAmountDialog> {
  final TextEditingController _controller = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat('#,###');
  double _change = 0;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_calculateChange);
  }

  void _calculateChange() {
    final text = _controller.text.replaceAll('.', '').replaceAll(',', '');
    final paid = double.tryParse(text) ?? 0;
    setState(() {
      _change = paid - widget.totalAmount;
      if (paid < widget.totalAmount && text.isNotEmpty) {
        _errorText = 'Nominal kurang';
      } else {
        _errorText = null;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.replaceAll('.', '').replaceAll(',', '');
    final paid = double.tryParse(text) ?? 0;
    if (paid >= widget.totalAmount) {
      Navigator.pop(context, paid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Masukkan Jumlah Uang', style: TextStyle(fontSize: context.scaleSP(18), fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            style: TextStyle(fontSize: context.scaleSP(16)),
            decoration: InputDecoration(
              labelText: 'Uang Diterima',
              labelStyle: TextStyle(fontSize: context.scaleSP(14)),
              errorText: _errorText,
              errorStyle: TextStyle(fontSize: context.scaleSP(12)),
              prefixText: 'Rp ',
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          SizedBox(height: context.scaleH(16)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: context.scaleSP(14))),
              Text(_currencyFormat.format(widget.totalAmount), style: TextStyle(fontSize: context.scaleSP(14))),
            ],
          ),
          SizedBox(height: context.scaleH(8)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Kembalian:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: context.scaleSP(14))),
              Text(
                _currencyFormat.format(_change > 0 ? _change : 0),
                style: TextStyle(
                  color: _change >= 0 ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: context.scaleSP(18),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Batal', style: TextStyle(fontSize: context.scaleSP(14))),
        ),
        ElevatedButton(
          onPressed: _errorText == null && _controller.text.isNotEmpty
              ? _submit
              : null,
          child: Text('Bayar', style: TextStyle(fontSize: context.scaleSP(14))),
        ),
      ],
    );
  }
}

class _CartItemTile extends StatelessWidget {

  const _CartItemTile({
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    required this.subtotal,
    required this.currencyFormat,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });
  final String productName;
  final double unitPrice;
  final int quantity;
  final double subtotal;
  final NumberFormat currencyFormat;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: EdgeInsets.only(bottom: context.scaleH(8)),
      padding: EdgeInsets.all(context.scaleW(12)),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(context.scaleW(12)),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: GoogleFonts.inter(
                    fontSize: context.scaleSP(14),
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: context.scaleH(4)),
                Text(
                  '${currencyFormat.format(unitPrice)} x $quantity',
                  style: GoogleFonts.inter(
                    fontSize: context.scaleSP(12),
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),

          // Quantity Controls
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(context.scaleW(8)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.remove, size: context.scaleW(18)),
                  onPressed: onDecrement,
                  constraints:
                      BoxConstraints(minWidth: context.scaleW(36), minHeight: context.scaleW(36)),
                  padding: EdgeInsets.zero,
                ),
                Container(
                  width: context.scaleW(32),
                  alignment: Alignment.center,
                  child: Text(
                    '$quantity',
                    style: GoogleFonts.inter(
                      fontSize: context.scaleSP(14),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.add, size: context.scaleW(18)),
                  onPressed: onIncrement,
                  constraints:
                      BoxConstraints(minWidth: context.scaleW(36), minHeight: context.scaleW(36)),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          SizedBox(width: context.scaleW(12)),

          // Subtotal
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                currencyFormat.format(subtotal),
                style: GoogleFonts.inter(
                  fontSize: context.scaleSP(14),
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: context.scaleW(18),
                  color: Colors.red.shade400,
                ),
                onPressed: onRemove,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(minWidth: context.scaleW(24), minHeight: context.scaleW(24)),
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
    properties.add(StringProperty('productName', productName));
    properties.add(DoubleProperty('unitPrice', unitPrice));
    properties.add(IntProperty('quantity', quantity));
    properties.add(DoubleProperty('subtotal', subtotal));
    properties.add(DiagnosticsProperty<NumberFormat>('currencyFormat', currencyFormat));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onIncrement', onIncrement));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onDecrement', onDecrement));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onRemove', onRemove));
  }
}

class _SummaryLine extends StatelessWidget {

  const _SummaryLine({
    required this.label,
    required this.value,
    this.valueColor,
  });
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: context.scaleSP(13),
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: context.scaleSP(13),
            fontWeight: FontWeight.w500,
            color: valueColor ?? theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('label', label));
    properties.add(StringProperty('value', value));
    properties.add(ColorProperty('valueColor', valueColor));
  }
}
