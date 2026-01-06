/// lib/data/entities/cart_item.dart
/// Cart item model for local cart management (before transaction commit).
/// This represents an item in the current shopping cart.
library;

class CartItem {

  CartItem({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
  });

  /// Create from Universal JSON received from ScanAI
  factory CartItem.fromUniversalJson(
    Map<String, dynamic> json, {
    required double price,
  }) {
    return CartItem(
      productId: json['id'] as int? ?? 0,
      productName: json['label'] as String,
      unitPrice: price,
      quantity: json['qty'] as int? ?? 1,
    );
  }
  final int productId;
  final String productName;
  final double unitPrice;
  int quantity;

  double get subtotal => unitPrice * quantity;

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'product_name': productName,
      'unit_price': unitPrice,
      'quantity': quantity,
      'subtotal': subtotal,
    };
  }
}
