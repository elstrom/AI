/// lib/data/local/local_database.dart
/// Local SQLite database for offline caching and pending transactions.
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../entities/product.dart';

/// Pending transaction wrapper for sync
class PendingTransaction {

  PendingTransaction({
    required this.id,
    required this.header,
    required this.items,
    this.retryCount = 0,
    this.lastError,
  });
  final int id;
  final Map<String, dynamic> header;
  final List<Map<String, dynamic>> items;
  final int retryCount;
  final String? lastError;
}

/// Local database singleton for PosAI
class LocalDatabase {

  LocalDatabase._();
  static LocalDatabase? _instance;
  static Database? _database;

  static LocalDatabase get instance {
    _instance ??= LocalDatabase._();
    return _instance!;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'posai_cache.db');

    debugPrint('[LocalDatabase] Initializing database at $path');

    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Products cache table
    await db.execute('''
      CREATE TABLE products_cache (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        sku TEXT,
        category_id INTEGER NOT NULL,
        price REAL NOT NULL,
        is_active INTEGER DEFAULT 1,
        cached_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Pending transactions table
    await db.execute('''
      CREATE TABLE pending_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        header_json TEXT NOT NULL,
        items_json TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        retry_count INTEGER DEFAULT 0,
        last_error TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        synced_at TIMESTAMP
      )
    ''');

    // Create indexes
    await db.execute('CREATE INDEX idx_products_name ON products_cache(name)');
    await db.execute(
        'CREATE INDEX idx_pending_status ON pending_transactions(status)');

    debugPrint('[LocalDatabase] Database created successfully');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle future migrations here
    debugPrint('[LocalDatabase] Upgrading from $oldVersion to $newVersion');
  }

  // ============================================================
  // PRODUCT CACHE METHODS
  // ============================================================

  /// Cache products from server
  Future<void> cacheProducts(List<Product> products) async {
    final db = await database;

    await db.transaction((txn) async {
      // Clear existing cache
      await txn.delete('products_cache');

      // Insert new products
      for (final product in products) {
        await txn.insert('products_cache', {
          'id': product.id,
          'name': product.name,
          'sku': product.sku,
          'category_id': product.categoryId,
          'price': product.price,
          'is_active': product.isActive,
          'cached_at': DateTime.now().toIso8601String(),
        });
      }
    });

    debugPrint('[LocalDatabase] Cached ${products.length} products');
  }

  /// Get all cached products
  Future<List<Product>> getCachedProducts() async {
    final db = await database;
    final result = await db.query('products_cache', where: 'is_active = 1');

    return result.map((row) {
      return Product(
        id: row['id'] as int,
        name: row['name'] as String,
        sku: row['sku'] as String?,
        categoryId: row['category_id'] as int,
        price: row['price'] as double,
        isActive: row['is_active'] as int,
      );
    }).toList();
  }

  /// Get product price by name from cache
  Future<double?> getCachedPriceByName(String name) async {
    final db = await database;
    final result = await db.query(
      'products_cache',
      where: 'name = ? AND is_active = 1',
      whereArgs: [name],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return result.first['price'] as double;
    }

    // Try partial match
    final partialResult = await db.query(
      'products_cache',
      where: 'name LIKE ? AND is_active = 1',
      whereArgs: ['%$name%'],
      limit: 1,
    );

    if (partialResult.isNotEmpty) {
      return partialResult.first['price'] as double;
    }

    return null;
  }

  // ============================================================
  // PENDING TRANSACTION METHODS
  // ============================================================

  /// Save transaction for offline sync
  Future<int> savePendingTransaction({
    required Map<String, dynamic> header,
    required List<Map<String, dynamic>> items,
  }) async {
    final db = await database;

    final id = await db.insert('pending_transactions', {
      'header_json': json.encode(header),
      'items_json': json.encode(items),
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });

    debugPrint('[LocalDatabase] Saved pending transaction ID: $id');
    return id;
  }

  /// Get all pending transactions
  Future<List<PendingTransaction>> getPendingTransactions() async {
    final db = await database;
    final result = await db.query(
      'pending_transactions',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at ASC',
    );

    return result.map((row) {
      return PendingTransaction(
        id: row['id'] as int,
        header:
            json.decode(row['header_json'] as String) as Map<String, dynamic>,
        items: (json.decode(row['items_json'] as String) as List<dynamic>)
            .cast<Map<String, dynamic>>(),
        retryCount: row['retry_count'] as int? ?? 0,
        lastError: row['last_error'] as String?,
      );
    }).toList();
  }

  /// Get pending transaction count
  Future<int> getPendingTransactionCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM pending_transactions WHERE status = ?',
      ['pending'],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Mark transaction as synced
  Future<void> markTransactionSynced(int id) async {
    final db = await database;
    await db.update(
      'pending_transactions',
      {
        'status': 'synced',
        'synced_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    debugPrint('[LocalDatabase] Transaction $id marked as synced');
  }

  /// Mark transaction as failed
  Future<void> markTransactionFailed(int id, String error) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE pending_transactions SET retry_count = retry_count + 1, last_error = ? WHERE id = ?',
      [error, id],
    );
    debugPrint('[LocalDatabase] Transaction $id marked as failed: $error');
  }

  /// Cleanup synced transactions older than specified days
  Future<int> cleanupSyncedTransactions({int olderThanDays = 7}) async {
    final db = await database;
    final cutoffDate = DateTime.now()
        .subtract(Duration(days: olderThanDays))
        .toIso8601String();

    final count = await db.delete(
      'pending_transactions',
      where: 'status = ? AND synced_at < ?',
      whereArgs: ['synced', cutoffDate],
    );

    debugPrint('[LocalDatabase] Cleaned up $count old synced transactions');
    return count;
  }

  /// Close database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
