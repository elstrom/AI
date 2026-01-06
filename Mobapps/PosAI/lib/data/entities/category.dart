/// lib/data/entities/category.dart
/// Category model for product categories from server.
library;

class Category {

  Category({
    required this.id,
    required this.name,
    this.isActive = 1,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as int,
      name: json['name'] as String,
      isActive: json['is_active'] as int? ?? 1,
    );
  }
  final int id;
  final String name;
  final int isActive;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'is_active': isActive,
    };
  }
}
