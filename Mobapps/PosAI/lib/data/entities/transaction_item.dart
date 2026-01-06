/// lib/data/entities/transaction_item.dart
/// Transaction item model for line items in a transaction.
library;

class TransactionItem {

  TransactionItem({
    this.id,
    this.transactionId,
    this.productId,
    required this.itemName,
    required this.price,
    required this.qty,
    required this.subTotal,
    required this.total,
  });

  factory TransactionItem.fromJson(Map<String, dynamic> json) {
    return TransactionItem(
      id: json['id'] as int?,
      transactionId: json['transaction_id'] as int?,
      productId: json['product_id'] as int?,
      itemName: json['item_name'] as String,
      price: (json['price'] as num).toDouble(),
      qty: json['qty'] as int,
      subTotal: (json['sub_total'] as num).toDouble(),
      total: (json['total'] as num).toDouble(),
    );
  }

  /// Create from CartItem for transaction submission
  factory TransactionItem.fromCartItem({
    required int? productId,
    required String productName,
    required double unitPrice,
    required int quantity,
  }) {
    final subTotal = unitPrice * quantity;
    return TransactionItem(
      productId: productId,
      itemName: productName,
      price: unitPrice,
      qty: quantity,
      subTotal: subTotal,
      total: subTotal,
    );
  }
  final int? id;
  final int? transactionId;
  final int? productId;
  final String itemName;
  final double price;
  final int qty;
  final double subTotal;
  final double total;

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (transactionId != null) 'transaction_id': transactionId,
      if (productId != null) 'product_id': productId,
      'item_name': itemName,
      'price': price,
      'qty': qty,
      'sub_total': subTotal,
      'total': total,
    };
  }
}
