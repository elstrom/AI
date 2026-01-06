/// lib/data/repositories/category_repository.dart
/// Repository for category operations via Server API.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config/app_config.dart';
import '../entities/category.dart';

class CategoryRepository {
  final AppConfig _config = AppConfig();

  String get _endpoint => '${_config.serverApiUrl}/categories';

  /// Fetch all categories
  Future<List<Category>> getAllCategories() async {
    final response = await http.get(
      Uri.parse(_endpoint),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final jsonList =
          json.decode(response.body) as List<dynamic>;
      return jsonList
          .map((json) => Category.fromJson(json as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception('Failed to load categories: ${response.statusCode}');
    }
  }

  /// Get category by ID
  Future<Category?> getCategoryById(int id) async {
    final response = await http.get(
      Uri.parse('$_endpoint/$id'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return Category.fromJson(
          json.decode(response.body) as Map<String, dynamic>);
    } else if (response.statusCode == 404) {
      return null;
    } else {
      throw Exception('Failed to get category: ${response.statusCode}');
    }
  }

  /// Create new category
  Future<bool> createCategory(Category category) async {
    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(category.toJson()),
    );

    return response.statusCode == 201 || response.statusCode == 200;
  }

  /// Update existing category
  Future<bool> updateCategory(Category category) async {
    if (category.id == 0) return false;
    final response = await http.put(
      Uri.parse('$_endpoint/${category.id}'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(category.toJson()),
    );

    return response.statusCode == 200;
  }

  /// Delete category
  Future<bool> deleteCategory(int id) async {
    final response = await http.delete(
      Uri.parse('$_endpoint/$id'),
      headers: {'Content-Type': 'application/json'},
    );

    return response.statusCode == 200 || response.statusCode == 204;
  }
}
