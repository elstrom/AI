/// lib/data/entities/product.dart
/// Product model for product data from server.
library;

class Product {

  Product({
    required this.id,
    required this.name,
    this.sku,
    required this.categoryId,
    required this.price,
    this.isActive = 1,
    this.createdAt,
    this.updatedAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int,
      name: json['name'] as String,
      sku: json['sku'] as String?,
      categoryId: json['category_id'] as int? ?? 1,
      price: (json['price'] as num).toDouble(),
      isActive: json['is_active'] as int? ?? 1,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }
  final int id;
  final String name;
  final String? sku;
  final int categoryId;
  final double price;
  final int isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'sku': sku,
      'category_id': categoryId,
      'price': price,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}
