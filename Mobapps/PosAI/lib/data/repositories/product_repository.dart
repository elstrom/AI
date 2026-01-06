/// lib/data/repositories/product_repository.dart
/// Repository for product operations via Server API.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config/app_config.dart';
import '../../services/auth_service.dart';
import '../entities/product.dart';
import '../local/local_database.dart';

class ProductRepository {
  final AppConfig _config = AppConfig();
  final AuthService _authService = AuthService();

  /// Fetch all products with offline support
  Future<List<Product>> getAllProducts() async {
    try {
      // Try fetching from server
      final response = await http
          .get(
            Uri.parse(_config.productsEndpoint),
            headers: _authService.authHeaders, // ✅ AUTH HEADER
          )
          .timeout(const Duration(seconds: 5)); // Short timeout for offline check

      // ✅ 401 HANDLING
      if (response.statusCode == 401) {
        await _authService.handleSessionExpired();
        return await _getCachedProducts();
      }

      if (response.statusCode == 200) {
        final jsonList =
            json.decode(response.body) as List<dynamic>;
        final products = jsonList
            .map((json) => Product.fromJson(json as Map<String, dynamic>))
            .toList();

        // Cache data locally
        await _cacheProducts(products);
        return products;
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      // Fallback to local cache if offline or server error
      return _getCachedProducts();
    }
  }

  Future<void> _cacheProducts(List<Product> products) async {
    try {
      final db = LocalDatabase.instance;
      await db.cacheProducts(products);
    } catch (e) {
      // Ignore cache errors, don't block app
    }
  }

  Future<List<Product>> _getCachedProducts() async {
    try {
      final db = LocalDatabase.instance;
      return await db.getCachedProducts();
    } catch (e) {
      return [];
    }
  }

  /// Search products by name
  Future<List<Product>> searchProducts(String query) async {
    try {
      final response = await http.get(
        Uri.parse('${_config.productsEndpoint}?name=$query'),
        headers: _authService.authHeaders, // ✅ AUTH HEADER
      );

      // ✅ 401 HANDLING
      if (response.statusCode == 401) {
        await _authService.handleSessionExpired();
        return [];
      }

      if (response.statusCode == 200) {
        final jsonList =
            json.decode(response.body) as List<dynamic>;
        return jsonList
            .map((json) => Product.fromJson(json as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Failed to search products: ${response.statusCode}');
      }
    } catch (e) {
      return [];
    }
  }

  /// Get product by ID
  Future<Product?> getProductById(int id) async {
    try {
      final response = await http.get(
        Uri.parse('${_config.productsEndpoint}/$id'),
        headers: _authService.authHeaders, // ✅ AUTH HEADER
      );

      // ✅ 401 HANDLING
      if (response.statusCode == 401) {
        await _authService.handleSessionExpired();
        return null;
      }

      if (response.statusCode == 200) {
        return Product.fromJson(
            json.decode(response.body) as Map<String, dynamic>);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to get product: ${response.statusCode}');
      }
    } catch (e) {
      return null;
    }
  }

  /// Get product price by name (for AI detection matching)
  Future<double?> getPriceByName(String name) async {
    try {
      final products = await searchProducts(name);
      // Find exact match first
      for (final product in products) {
        if (product.name.toLowerCase() == name.toLowerCase()) {
          return product.price;
        }
      }
      // Return first match if no exact match
      if (products.isNotEmpty) {
        return products.first.price;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Create new product
  Future<bool> createProduct(Product product) async {
    try {
      final response = await http.post(
        Uri.parse(_config.productsEndpoint),
        headers: _authService.authHeaders, // ✅ AUTH HEADER
        body: json.encode(product.toJson()),
      );

      // ✅ 401 HANDLING
      if (response.statusCode == 401) {
        await _authService.handleSessionExpired();
        return false;
      }

      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Update existing product
  Future<bool> updateProduct(Product product) async {
    if (product.id == 0) return false;

    try {
      final response = await http.put(
        Uri.parse('${_config.productsEndpoint}/${product.id}'),
        headers: _authService.authHeaders, // ✅ AUTH HEADER
        body: json.encode(product.toJson()),
      );

      // ✅ 401 HANDLING
      if (response.statusCode == 401) {
        await _authService.handleSessionExpired();
        return false;
      }

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Delete product
  Future<bool> deleteProduct(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('${_config.productsEndpoint}/$id'),
        headers: _authService.authHeaders, // ✅ AUTH HEADER
      );

      // ✅ 401 HANDLING
      if (response.statusCode == 401) {
        await _authService.handleSessionExpired();
        return false;
      }

      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      return false;
    }
  }
}
