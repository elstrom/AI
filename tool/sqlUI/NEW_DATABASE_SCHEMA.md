# ScanAI POS Database Schema - Current Specification

Dokumen ini merinci struktur database aktif yang digunakan oleh Central Server. Struktur ini dirancang untuk skalabilitas, keamanan data, dan pelacakan inventory yang akurat.

---

## 1. Core POS (Master Data)

### 📦 Table: `categories`
Tabel referensi untuk mengelompokkan produk.
- `id`: INTEGER PRIMARY KEY AUTOINCREMENT
- `name`: TEXT NOT NULL
- `is_active`: BOOLEAN DEFAULT TRUE

### 🏷️ Table: `products`
Data master barang yang dijual.
- `id`: INTEGER PRIMARY KEY AUTOINCREMENT
- `name`: TEXT NOT NULL
- `sku`: TEXT UNIQUE (Kode Produk/Barcode)
- `category_id`: INTEGER (Foreign Key ke `categories.id`)
- `price`: DECIMAL(15, 2)
- `is_active`: BOOLEAN DEFAULT TRUE

### 👥 Table: `users`
Data pengguna sistem dengan info paket langganan.
- `id`: INTEGER PRIMARY KEY AUTOINCREMENT
- `username`: TEXT UNIQUE NOT NULL
- `password_hash`: TEXT NOT NULL
- `plan_type`: TEXT DEFAULT 'free' (free/pro/enterprise)
- `plan_expired_at`: TIMESTAMP

---

## 2. Sales & Transactions

### 🧾 Table: `transactions`
Header transaksi penjualan (pusat pencatatan struk).
- `id`: INTEGER PRIMARY KEY AUTOINCREMENT
- `code`: TEXT UNIQUE NOT NULL (Format: TRX-YYYYMMDD-SEQ)
- `date`: TIMESTAMP DEFAULT CURRENT_TIMESTAMP
- `status`: TEXT (PAID, CANCELLED, PENDING)
- `total_amount`: DECIMAL(15, 2)
- `paid_amount`: DECIMAL(15, 2)
- `change_amount`: DECIMAL(15, 2)
- `payment_method`: TEXT (CASH, QRIS, DEBIT)
- `user_id`: INTEGER

### 🛒 Table: `transaction_items`
Detail barang dalam satu transaksi. Bersifat snapshot (menyimpan nama & harga saat kejadian).
- `id`: INTEGER PRIMARY KEY AUTOINCREMENT
- `transaction_id`: INTEGER (FK `transactions.id`)
- `product_id`: INTEGER (FK `products.id`)
- `item_name`: TEXT
- `price`: DECIMAL(15, 2)
- `qty`: INTEGER
- `sub_total`: DECIMAL(15, 2)

---

## 3. Finance & Inventory Logging

### 💰 Table: `cash_movements`
Mencatat pergerakan uang masuk dari setiap transaksi.
- `id`: INTEGER PRIMARY KEY AUTOINCREMENT
- `transaction_id`: INTEGER
- `amount`: DECIMAL(15, 2)
- `payment_method`: TEXT

### 📉 Table: `stock_sales`
Log pengurangan stok spesifik karena penjualan.
- `id`: INTEGER PRIMARY KEY AUTOINCREMENT
- `product_id`: INTEGER
- `transaction_id`: INTEGER
- `qty`: INTEGER

---

## 4. System & Security

### 🛡️ Table: `audit_logs`
Jejak audit keamanan sistem ("Who did what").
- `id`: INTEGER PRIMARY KEY AUTOINCREMENT
- `user_id`: INTEGER
- `entity`: TEXT (e.g., "products")
- `action`: TEXT (CREATE, UPDATE, DELETE)
- `changed_fields`: JSON/TEXT

### 🤖 Table: `ai_models`
Katalog model AI yang tersedia. Memberitahu ScanAI label barang apa yang dikenali.
- `id`: INTEGER PRIMARY KEY AUTOINCREMENT
- `name`: TEXT
- `version`: TEXT
- `labels`: TEXT (JSON Array)
- `is_active`: BOOLEAN

---

## 🔄 Transaction Logic (ACID)
Setiap transaksi Checkout dijamin integritasnya dengan membungkus 4 operasi insert (`transactions`, `transaction_items`, `cash_movements`, `stock_sales`) dalam satu **Database Transaction**. Jika satu gagal, seluruh operasi dibatalkan.
