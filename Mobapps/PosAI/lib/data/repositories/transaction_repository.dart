/// lib/data/repositories/transaction_repository.dart
/// Repository for transaction operations via Server API.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../config/app_config.dart';
import '../../services/auth_service.dart';
import '../entities/transaction_header.dart';
import '../entities/transaction_item.dart';
import '../local/local_database.dart';

class TransactionRepository {
  final AppConfig _config = AppConfig();
  final AuthService _authService = AuthService();

  /// Create new transaction (header + items)
  Future<bool> createTransaction({
    required TransactionHeader header,
    required List<TransactionItem> items,
    bool isSyncing = false,
  }) async {
    final payload = {
      'header': header.toJson(),
      'items': items.map((item) => item.toJson()).toList(),
    };

    try {
      final response = await http
          .post(
            Uri.parse(_config.transactionsEndpoint),
            headers: _authService.authHeaders, // ✅ AUTH HEADER
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 5));

      // ✅ 401 HANDLING
      if (response.statusCode == 401) {
        await _authService.handleSessionExpired();
        return false;
      }

      if (response.statusCode == 201 || response.statusCode == 200) {
        return true;
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      // If we are already syncing, don't save again to avoid duplication
      if (isSyncing) {
        return false;
      }

      // Offline fallback: Save to local DB to sync later
      try {
        await LocalDatabase.instance.savePendingTransaction(
          header: header.toJson(),
          items: items.map((item) => item.toJson()).toList(),
        );
        return true; // Return true so UI thinks it succeeded
      } catch (dbError) {
        return false;
      }
    }
  }

  /// Fetch all transactions (headers only)
  Future<List<TransactionHeader>> getAllTransactions() async {
    try {
      final response = await http.get(
        Uri.parse(_config.transactionsEndpoint),
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
            .map((json) =>
                TransactionHeader.fromJson(json as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Failed to load transactions: ${response.statusCode}');
      }
    } catch (e) {
      // Return empty list on error (graceful degradation)
      return [];
    }
  }

  /// Fetch transaction details (items) by transaction ID
  Future<List<TransactionItem>> getTransactionItems(int transactionId) async {
    try {
      final response = await http.get(
        Uri.parse('${_config.transactionsEndpoint}/$transactionId/items'),
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
            .map((json) => TransactionItem.fromJson(json as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception(
            'Failed to load transaction items: ${response.statusCode}');
      }
    } catch (e) {
      // Return empty list on error (graceful degradation)
      return [];
    }
  }

  /// Fetch transactions by date range
  Future<List<TransactionHeader>> getTransactionsByDateRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(
          '${_config.transactionsEndpoint}?start=${startDate.toIso8601String()}&end=${endDate.toIso8601String()}',
        ),
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
            .map((json) =>
                TransactionHeader.fromJson(json as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Failed to load transactions: ${response.statusCode}');
      }
    } catch (e) {
      // Return empty list on error (graceful degradation)
      return [];
    }
  }

  /// Cancel a transaction
  Future<bool> cancelTransaction(int transactionId) async {
    try {
      final response = await http.post(
        Uri.parse('${_config.transactionsEndpoint}/$transactionId/cancel'),
        headers: _authService.authHeaders, // ✅ AUTH HEADER
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
}
