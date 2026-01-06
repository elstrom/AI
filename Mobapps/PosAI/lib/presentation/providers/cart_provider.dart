/// lib/presentation/providers/cart_provider.dart
/// Cart Provider - Manages shopping cart state and transaction processing.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../config/app_config.dart';
import '../../data/entities/cart_item.dart';
import '../../data/entities/transaction_header.dart';
import '../../data/entities/transaction_item.dart';
import '../../data/local/local_database.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/repositories/transaction_repository.dart';

class CartProvider extends ChangeNotifier {
  final AppConfig _config = AppConfig();
  final ProductRepository _productRepo = ProductRepository();
  final TransactionRepository _transactionRepo = TransactionRepository();
  final LocalDatabase _localDb = LocalDatabase.instance;

  final List<CartItem> _items = [];
  String _paymentMethod = 'Cash';
  double _discount = 0.0;
  bool _isProcessing = false;

  // Getters
  List<CartItem> get items => List.unmodifiable(_items);
  String get paymentMethod => _paymentMethod;
  double get discount => _discount;
  bool get isProcessing => _isProcessing;
  bool get isEmpty => _items.isEmpty;
  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal => _items.fold(0.0, (sum, item) => sum + item.subtotal);

  double get taxAmount => subtotal * _config.defaultTaxRate;

  double get total => subtotal + taxAmount - _discount;

  // ============================================================
  // CART OPERATIONS
  // ============================================================

  /// Add item to cart by product ID and name
  void addItem({
    required int productId,
    required String productName,
    required double unitPrice,
    int quantity = 1,
  }) {
    // Tactile Feedback for Premium Feel
    HapticFeedback.lightImpact();

    final existingIndex =
        _items.indexWhere((item) => item.productId == productId);

    if (existingIndex >= 0) {
      _items[existingIndex].quantity += quantity;
    } else {
      _items.add(CartItem(
        productId: productId,
        productName: productName,
        unitPrice: unitPrice,
        quantity: quantity,
      ));
    }
    notifyListeners();
  }

  /// Add item from AI detection (Universal JSON)
  Future<void> addFromDetection({
    required int productId,
    required String label,
    required int qty,
  }) async {
    // Try to get price from cache first, then server
    var price = await _localDb.getCachedPriceByName(label);
    price ??= await _productRepo.getPriceByName(label);

    // Fallback to default price
    price ??= _config.unregisteredProductPrice;

    addItem(
      productId: productId,
      productName: label,
      unitPrice: price,
      quantity: qty,
    );
  }

  /// Remove item from cart
  void removeItem(int productId) {
    _items.removeWhere((item) => item.productId == productId);
    notifyListeners();
  }

  /// Increment item quantity
  void incrementQuantity(int productId) {
    final index = _items.indexWhere((item) => item.productId == productId);
    if (index >= 0) {
      _items[index].quantity++;
      notifyListeners();
    }
  }

  /// Decrement item quantity
  void decrementQuantity(int productId) {
    final index = _items.indexWhere((item) => item.productId == productId);
    if (index >= 0) {
      if (_items[index].quantity > 1) {
        _items[index].quantity--;
      } else {
        _items.removeAt(index);
      }
      notifyListeners();
    }
  }

  /// Update item quantity directly
  void updateQuantity(int productId, int newQuantity) {
    if (newQuantity <= 0) {
      removeItem(productId);
      return;
    }

    final index = _items.indexWhere((item) => item.productId == productId);
    if (index >= 0) {
      _items[index].quantity = newQuantity;
      notifyListeners();
    }
  }

  /// Set payment method
  void setPaymentMethod(String method) {
    _paymentMethod = method;
    notifyListeners();
  }

  /// Set discount amount
  void setDiscount(double amount) {
    _discount = amount;
    notifyListeners();
  }

  /// Clear cart
  void clearCart() {
    _items.clear();
    _discount = 0.0;
    notifyListeners();
  }

  /// Replace cart with new items (for AI sync)
  void replaceCart(List<CartItem> newItems) {
    _items.clear();
    _items.addAll(newItems);
    notifyListeners();
  }

  // ============================================================
  // TRANSACTION PROCESSING
  // ============================================================

  /// Process transaction - send to server or save locally
  Future<bool> processTransaction({
    required int userId,
    required String cashierName,
    double? paidAmount,
  }) async {
    if (_items.isEmpty) return false;
    if (_isProcessing) return false;

    _isProcessing = true;
    notifyListeners();

    try {
      final actualPaidAmount = paidAmount ?? total;
      final changeAmount =
          actualPaidAmount > total ? actualPaidAmount - total : 0.0;

      // Create transaction header
      final header = TransactionHeader(
        date: DateTime.now(),
        status: 'COMPLETED',
        subtotal: subtotal,
        discountTotal: _discount,
        taxTotal: taxAmount,
        totalAmount: total,
        paidAmount: actualPaidAmount,
        changeAmount: changeAmount,
        paymentMethod: _paymentMethod.toUpperCase(),
        userId: userId > 0 ? userId : null,
      );

      // Create transaction items
      final transactionItems = _items.map((cartItem) {
        return TransactionItem.fromCartItem(
          productId: cartItem.productId > 0 ? cartItem.productId : null,
          productName: cartItem.productName,
          unitPrice: cartItem.unitPrice,
          quantity: cartItem.quantity,
        );
      }).toList();

      // Try to send to server
      var success = false;
      try {
        success = await _transactionRepo.createTransaction(
          header: header,
          items: transactionItems,
        );
      } catch (e) {
        debugPrint('[CartProvider] Server error, saving locally: $e');
      }

      // If server failed, save locally for sync
      if (!success) {
        await _localDb.savePendingTransaction(
          header: header.toJson(),
          items: transactionItems.map((i) => i.toJson()).toList(),
        );
        debugPrint('[CartProvider] Transaction saved locally for sync');
        success = true; // Consider it success (will sync later)
      }

      if (success) {
        // Tactile Feedback for Success
        HapticFeedback.mediumImpact();
        clearCart();
      }

      return success;
    } catch (e) {
      // Tactile Feedback for Error
      HapticFeedback.heavyImpact();
      debugPrint('[CartProvider] Error processing transaction: $e');
      return false;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }
}
