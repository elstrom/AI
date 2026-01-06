/// lib/data/entities/transaction_header.dart
/// Transaction header model for transaction data from server.
library;

class TransactionHeader {

  TransactionHeader({
    this.id,
    this.code,
    required this.date,
    this.status = 'PENDING',
    required this.subtotal,
    this.discountTotal = 0.0,
    this.taxTotal = 0.0,
    required this.totalAmount,
    this.paidAmount = 0.0,
    this.changeAmount = 0.0,
    this.paymentMethod = 'CASH',
    this.userId,
  });

  factory TransactionHeader.fromJson(Map<String, dynamic> json) {
    return TransactionHeader(
      id: json['id'] as int?,
      code: json['code'] as String?,
      date: DateTime.parse(json['date'] as String),
      status: json['status'] as String? ?? 'PENDING',
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      discountTotal: (json['discount_total'] as num?)?.toDouble() ?? 0.0,
      taxTotal: (json['tax_total'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0.0,
      changeAmount: (json['change_amount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: json['payment_method'] as String? ?? 'CASH',
      userId: json['user_id'] as int?,
    );
  }
  final int? id;
  final String? code;
  final DateTime date;
  final String status;
  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double totalAmount;
  final double paidAmount;
  final double changeAmount;
  final String paymentMethod;
  final int? userId;

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (code != null) 'code': code,
      'date': date.toIso8601String(),
      'status': status,
      'subtotal': subtotal,
      'discount_total': discountTotal,
      'tax_total': taxTotal,
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'change_amount': changeAmount,
      'payment_method': paymentMethod,
      if (userId != null) 'user_id': userId,
    };
  }
}
