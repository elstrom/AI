/// lib/services/sync_service.dart
/// Service for automatic synchronization of offline data with server.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../data/local/local_database.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../data/entities/transaction_header.dart';
import '../data/entities/transaction_item.dart';

/// Sync status enum
enum SyncStatus {
  idle,
  syncing,
  success,
  error,
  offline,
}

/// Sync service for offline data synchronization.
/// Automatically syncs pending transactions and caches products.
class SyncService extends ChangeNotifier {

  SyncService._();
  static SyncService? _instance;

  final LocalDatabase _localDb = LocalDatabase.instance;
  final ProductRepository _productRepo = ProductRepository();
  final TransactionRepository _transactionRepo = TransactionRepository();
  final AppConfig _config = AppConfig();

  Timer? _syncTimer;
  Timer? _connectivityTimer;

  SyncStatus _status = SyncStatus.idle;
  String? _lastError;
  int _pendingCount = 0;
  bool _isOnline = true;
  DateTime? _lastSync;

  static SyncService get instance {
    _instance ??= SyncService._();
    return _instance!;
  }

  // Getters
  SyncStatus get status => _status;
  String? get lastError => _lastError;
  int get pendingCount => _pendingCount;
  bool get isOnline => _isOnline;
  DateTime? get lastSync => _lastSync;
  bool get hasPendingItems => _pendingCount > 0;

  /// Initialize sync service
  Future<void> initialize() async {
    debugPrint('[SyncService] Initializing...');

    // Check initial connectivity
    await _checkConnectivity();

    // Update pending count
    await _updatePendingCount();

    // Start periodic sync (every 30 seconds)
    _syncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => syncIfNeeded(),
    );

    // Start connectivity check (every 10 seconds)
    _connectivityTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkConnectivity(),
    );

    debugPrint('[SyncService] Initialized with $_pendingCount pending items');
  }

  /// Dispose sync service
  @override
  void dispose() {
    _syncTimer?.cancel();
    _connectivityTimer?.cancel();
    super.dispose();
  }

  /// Check server connectivity
  Future<bool> _checkConnectivity() async {
    try {
      final response = await http
          .get(
            Uri.parse('${_config.serverApiUrl}/health'),
          )
          .timeout(const Duration(seconds: 5));

      final wasOffline = !_isOnline;
      _isOnline = response.statusCode == 200;

      if (wasOffline && _isOnline) {
        debugPrint('[SyncService] Connection restored, triggering sync...');
        syncIfNeeded();
      }

      return _isOnline;
    } catch (e) {
      _isOnline = false;
      return false;
    }
  }

  /// Update pending transaction count
  Future<void> _updatePendingCount() async {
    _pendingCount = await _localDb.getPendingTransactionCount();
    notifyListeners();
  }

  /// Sync if there are pending items and we're online
  Future<void> syncIfNeeded() async {
    if (!_isOnline || _status == SyncStatus.syncing) {
      return;
    }

    await _updatePendingCount();

    if (_pendingCount > 0) {
      await syncPendingTransactions();
    }
  }

  /// Force sync now
  Future<bool> syncNow() async {
    if (_status == SyncStatus.syncing) {
      return false;
    }

    await _checkConnectivity();

    if (!_isOnline) {
      _setStatus(SyncStatus.offline);
      return false;
    }

    return syncPendingTransactions();
  }

  /// Sync pending transactions to server
  Future<bool> syncPendingTransactions() async {
    if (_status == SyncStatus.syncing) return false;

    _setStatus(SyncStatus.syncing);
    _lastError = null;

    try {
      final pendingList = await _localDb.getPendingTransactions();

      if (pendingList.isEmpty) {
        _setStatus(SyncStatus.success);
        _lastSync = DateTime.now();
        await _updatePendingCount();
        return true;
      }

      debugPrint(
          '[SyncService] Syncing ${pendingList.length} pending transactions...');

      var successCount = 0;
      var failCount = 0;

      for (final pending in pendingList) {
        try {
          // Skip if too many retries
          if (pending.retryCount >= 5) {
            debugPrint(
                '[SyncService] Skipping transaction ${pending.id} - too many retries');
            continue;
          }

          // Parse header and items
          final headerData = pending.header;
          final itemsData = pending.items;

          // Create header object
          final header = TransactionHeader(
            date: DateTime.parse(headerData['date'] as String),
            status: headerData['status'] as String? ?? 'COMPLETED',
            subtotal: (headerData['subtotal'] as num?)?.toDouble() ?? 0.0,
            discountTotal:
                (headerData['discount_total'] as num?)?.toDouble() ?? 0.0,
            taxTotal: (headerData['tax_total'] as num?)?.toDouble() ?? 0.0,
            totalAmount:
                (headerData['total_amount'] as num?)?.toDouble() ?? 0.0,
            paidAmount: (headerData['paid_amount'] as num?)?.toDouble() ?? 0.0,
            changeAmount:
                (headerData['change_amount'] as num?)?.toDouble() ?? 0.0,
            paymentMethod: headerData['payment_method'] as String? ?? 'CASH',
            userId: headerData['user_id'] as int?,
          );

          // Create items
          final items = itemsData
              .map((item) => TransactionItem(
                    productId: item['product_id'] as int?,
                    itemName: item['item_name'] as String? ?? '',
                    price: (item['price'] as num).toDouble(),
                    qty: item['qty'] as int,
                    subTotal: (item['sub_total'] as num).toDouble(),
                    total: (item['total'] as num).toDouble(),
                  ))
              .toList();

          // Submit to server
          final result = await _transactionRepo.createTransaction(
            header: header,
            items: items,
            isSyncing: true,
          );

          if (result) {
            await _localDb.markTransactionSynced(pending.id);
            successCount++;
            debugPrint(
                '[SyncService] Transaction ${pending.id} synced successfully');
          } else {
            await _localDb.markTransactionFailed(
                pending.id, 'Server returned false');
            failCount++;
          }
        } catch (e) {
          await _localDb.markTransactionFailed(pending.id, e.toString());
          failCount++;
          debugPrint(
              '[SyncService] Failed to sync transaction ${pending.id}: $e');
        }
      }

      await _updatePendingCount();

      if (failCount == 0) {
        _setStatus(SyncStatus.success);
        _lastSync = DateTime.now();
        debugPrint(
            '[SyncService] All $successCount transactions synced successfully');
        return true;
      } else {
        _lastError =
            '$failCount of ${successCount + failCount} transactions failed';
        _setStatus(SyncStatus.error);
        return false;
      }
    } catch (e) {
      _lastError = e.toString();
      _setStatus(SyncStatus.error);
      debugPrint('[SyncService] Sync error: $e');
      return false;
    }
  }

  /// Cache products from server
  Future<bool> cacheProducts() async {
    if (!_isOnline) {
      debugPrint('[SyncService] Cannot cache products - offline');
      return false;
    }

    try {
      final products = await _productRepo.getAllProducts();
      await _localDb.cacheProducts(products);
      debugPrint('[SyncService] Cached ${products.length} products');
      return true;
    } catch (e) {
      debugPrint('[SyncService] Failed to cache products: $e');
      return false;
    }
  }

  /// Cleanup old synced transactions
  Future<int> cleanup({int olderThanDays = 7}) async {
    return _localDb.cleanupSyncedTransactions(
        olderThanDays: olderThanDays);
  }

  void _setStatus(SyncStatus newStatus) {
    _status = newStatus;
    notifyListeners();
  }

  /// Get status message for UI
  String get statusMessage {
    switch (_status) {
      case SyncStatus.idle:
        return _pendingCount > 0
            ? '$_pendingCount transaksi tertunda'
            : 'Tersinkronisasi';
      case SyncStatus.syncing:
        return 'Menyinkronkan...';
      case SyncStatus.success:
        return 'Sinkronisasi berhasil';
      case SyncStatus.error:
        return 'Gagal: $_lastError';
      case SyncStatus.offline:
        return 'Offline - $_pendingCount tertunda';
    }
  }
}
