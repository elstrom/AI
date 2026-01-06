/// lib/presentation/screens/transaction_detail_screen.dart
/// Screen to view transaction details, items, and print receipt.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../config/app_config.dart';
import '../../data/entities/transaction_header.dart';
import '../../data/entities/transaction_item.dart';
import '../../data/repositories/transaction_repository.dart';

class TransactionDetailScreen extends StatefulWidget {

  const TransactionDetailScreen({super.key, required this.transaction});
  final TransactionHeader transaction;

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<TransactionHeader>('transaction', transaction));
  }
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  final TransactionRepository _transactionRepo = TransactionRepository();
  final AppConfig _config = AppConfig();

  List<TransactionItem> _items = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    if (widget.transaction.id == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final items =
          await _transactionRepo.getTransactionItems(widget.transaction.id!);
      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Gagal memuat detail barang: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _printReceipt() async {
    // Placeholder for printing logic
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mengirim ke printer...')),
    );
  }

  Future<void> _emailReceipt() async {
    // Placeholder for email logic
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mengirim struk ke email...')),
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
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Detail Transaksi',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : SafeArea(
                  child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Receipt Card
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Header
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: widget.transaction.status == 'CANCELLED'
                                    ? Colors.red.shade50
                                    : Colors.green.shade50,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(16)),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    widget.transaction.status == 'CANCELLED'
                                        ? Icons.cancel_outlined
                                        : Icons.check_circle_outline,
                                    size: 48,
                                    color:
                                        widget.transaction.status == 'CANCELLED'
                                            ? Colors.red
                                            : Colors.green,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    currencyFormat
                                        .format(widget.transaction.totalAmount),
                                    style: GoogleFonts.inter(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: widget.transaction.status ==
                                              'CANCELLED'
                                          ? Colors.red
                                          : Colors.green.shade800,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.transaction.code ?? 'NO CODE',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  Text(
                                    dateFormat.format(widget.transaction.date),
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Items List inside the receipt
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(20),
                              itemCount: _items.length,
                              separatorBuilder: (context, index) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Divider(
                                    height: 1,
                                    color: Colors.grey.withValues(alpha: 0.2)),
                              ),
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                return Row(
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${item.qty}x',
                                        style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black54),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        item.itemName,
                                        style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    Text(
                                      currencyFormat.format(item.subTotal),
                                      style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                );
                              },
                            ),

                            // Summary Section
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    _ReceiptRow(
                                      label: 'Subtotal',
                                      value: currencyFormat
                                          .format(widget.transaction.subtotal),
                                    ),
                                    const SizedBox(height: 8),
                                    _ReceiptRow(
                                      label: 'Pajak',
                                      value: currencyFormat
                                          .format(widget.transaction.taxTotal),
                                    ),
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 12),
                                      child: _DashedDivider(
                                          color: Colors.grey),
                                    ),
                                    _ReceiptRow(
                                      label: 'Total',
                                      value: currencyFormat.format(
                                          widget.transaction.totalAmount),
                                      isBold: true,
                                      valueColor: Colors.black,
                                    ),
                                    const SizedBox(height: 8),
                                    _ReceiptRow(
                                      label: 'Tunai',
                                      value: currencyFormat.format(
                                          widget.transaction.paidAmount),
                                      valueColor: Colors.green,
                                    ),
                                    _ReceiptRow(
                                      label: 'Kembalian',
                                      value: currencyFormat.format(
                                          widget.transaction.changeAmount),
                                      valueColor: Colors.orange.shade800,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _emailReceipt,
                              icon: const Icon(Icons.email_outlined),
                              label: const Text('Email'),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                side: BorderSide(
                                    color: theme.colorScheme.primary),
                                foregroundColor: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _printReceipt,
                              icon: const Icon(Icons.print),
                              label: const Text('Cetak'),
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: theme.colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {

  const _ReceiptRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
  });
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: isBold ? 14 : 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: isBold ? 14 : 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: valueColor ?? Colors.black87,
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
    properties.add(DiagnosticsProperty<bool>('isBold', isBold));
    properties.add(ColorProperty('valueColor', valueColor));
  }
}

class _DashedDivider extends StatelessWidget {

  const _DashedDivider({
    this.color = Colors.black,
  });
  final double height = 1.0;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const dashWidth = 5.0;
    const dashSpace = 3.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.constrainWidth();
        final dashCount = (boxWidth / (dashWidth + dashSpace)).floor();
        return Flex(
          direction: Axis.horizontal,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(dashCount, (_) {
            return SizedBox(
              width: dashWidth,
              height: height,
              child: DecoratedBox(
                decoration: BoxDecoration(color: color),
              ),
            );
          }),
        );
      },
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('height', height));
    properties.add(ColorProperty('color', color));
  }
}
