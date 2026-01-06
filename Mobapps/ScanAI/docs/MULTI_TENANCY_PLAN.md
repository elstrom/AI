# Rencana Implementasi Multi-Tenancy Database (Isolasi Data User)

**Tanggal:** 23 Desember 2025
**Status:** DRAFT (Menunggu Persetujuan)

## 1. Latar Belakang Masalah
Saat ini, tabel Master Data (`products` dan `categories`) bersifat **Global**. Artinya, semua user yang login ke aplikasi melihat daftar produk yang sama. Ini tidak sesuai dengan konsep SaaS/Cloud Server di mana setiap toko/user seharusnya hanya melihat datanya sendiri.

**Kondisi Saat Ini (Global):**
*   User A login -> Melihat Produk X, Y, Z.
*   User B login '-> Melihat Produk X, Y, Z (sama).
*   User A hapus Produk X -> Produk X hilang juga di User B.

**Target Kondisi (Multi-Tenant):**
*   User A login -> Melihat Produk milik A saja.
*   User B login -> Melihat Produk milik B saja.

## 2. Rencana Perubahan Database (Schema Migration)

Akan dilakukan penambahan kolom `user_id` pada tabel master data untuk mengikat kepemilikan data.

### 2.1. Tabel `categories`
```sql
ALTER TABLE categories ADD COLUMN user_id INTEGER;
-- Update data lama agar dimiliki oleh Admin (ID: 1) untuk mencegah crash
UPDATE categories SET user_id = 1 WHERE user_id IS NULL;
-- Enforce Foreign Key (Optional di SQLite, tapi bagus untuk integritas)
-- FOREIGN KEY(user_id) REFERENCES users(id)
```

### 2.2. Tabel `products`
```sql
ALTER TABLE products ADD COLUMN user_id INTEGER;
-- Update data lama agar dimiliki oleh Admin (ID: 1)
UPDATE products SET user_id = 1 WHERE user_id IS NULL;
```

## 3. Implementasi Backend (Go Server)

### 3.1. Update Structs (`database.go`)
Menambahkan field `UserID` pada struct Go agar bisa diproses.
```go
type Category struct {
    ID       int64  `json:"id"`
    UserID   int64  `json:"user_id"` // Field Baru
    Name     string `json:"name"`
    IsActive int    `json:"is_active"`
}

type Product struct {
    ID         int64     `json:"id"`
    UserID     int64     `json:"user_id"` // Field Baru
    Name       string    `json:"name"`
    // ... field lain
}
```

### 3.2. Update Query Logic (`database.go`)
Semua query `SELECT`, `INSERT`, `UPDATE`, `DELETE` wajib menyertakan filter `user_id`.

**Contoh Perubahan (GetAllProducts):**
*   **Lama:** `SELECT * FROM products WHERE is_active = 1`
*   **Baru:** `SELECT * FROM products WHERE is_active = 1 AND user_id = ?`

### 3.3. Update Handlers (`products.go` & `categories.go`)
Handler harus mengambil `user_id` dari **JWT Token** (Context) user yang sedang login, lalu mengirimkannya ke funsgi database.

**Alur:**
1.  Request masuk ke `/products`.
2.  Middleware Auth memvalidasi Token -> Ekstrak `UserID` (misal: 2).
3.  Handler memanggil `db.GetAllProducts(userID=2)`.
4.  Database hanya mengembalikan produk milik User 2.

## 4. Dampak pada Sistem PosAI (Mobile Client)

Secara umum, perubahan ini **TRANSPARAN** bagi PosAI (Minim perubahan kode), namun ada beberapa hal yang perlu diperhatikan:

### 4.1. API Calls (Tidak Ada Perubahan)
PosAI sudah mengirimkan `Authorization: Bearer <token>` di setiap request. Backend akan otomatis menggunakan token ini untuk memfilter data. PosAI tidak perlu mengirim param tambahan manual.

### 4.2. Mekanisme Sync (Otomatis Terisolasi)
Service `SyncService` dan `ProductRepository` di PosAI akan menerima daftar produk yang sudah terfilter dari server.
*   **Effect:** Saat User A login di PosAI, dia hanya akan mendownload produk miliknya.

### 4.3. Cache Lokal (`LocalDatabase`) - **PERLU PERHATIAN**
Karena PosAI menyimpan cache produk di HP (`sqlite`), ada potensi isu jika satu HP digunakan bergantian oleh user berbeda.
*   **Masalah:** User A logout -> User B login. Jika cache tidak dibersihkan, User B mungkin melihat produk User A sesaat sampai sync selesai.
*   **Solusi:** Memastikan fungsi `Logout` di PosAI membersihkan tabel master data (`products`, `categories`) di database lokal.

### 4.4. Pembuatan Produk Baru (Jika Ada Fitur Ini di PosAI)
Jika PosAI memiliki fitur tambah produk, backend akan otomatis meng-assign produk baru tersebut ke User yang sedang login (berdasarkan Token). Tidak ada perubahan input field di UI.

## 5. Strategi Eksekusi & Migrasi

Untuk menjaga kestabilan data yang ada:

1.  **Auto-Migration Script:**
    Membuat fungsi `MigrateSchemas()` di Go Server yang berjalan saat startup:
    *   Cek apakah kolom `user_id` sudah ada di `products`.
    *   Jika belum, jalan perintah `ALTER TABLE`.
    *   Set default `user_id = 1` untuk data eksisting agar tidak error/hilang.

2.  **Verifikasi:**
    *   Restart Server.
    *   Login sebagai User Admin (ID 1) -> Harus lihat semua produk lama.
    *   Register User Baru (ID 2) -> Login -> Harus lihat daftar produk KOSONG.

## 6. Kesimpulan
Perubahan ini sangat krusial untuk menjadikan sistem ScanAI benar-benar **Multi-Tenant**.
*   **Backend:** Perlu update signifikan (Struct, Query, Handler).
*   **Frontend (PosAI):** Minim perubahan, hanya memastikan pembersihan cache saat logout.
