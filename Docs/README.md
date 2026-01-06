# 📚 Dokumentasi Utama ScanAI & PosAI

Dokumentasi ini mencakup seluruh ekosistem AI mulai dari pemrosesan di server hingga aplikasi kasir mobile.

## 🗺️ Panduan Dokumentasi Utama

| Dokumen | Deskripsi |
| :--- | :--- |
| **[System_architecture.md](System_architecture.md)** | Detail protokol biner (UPLINK), struktur paket UDP, dan alur gRPC. |
| **[DOKUMENTASI_FITUR.md](../Mobapps/ScanAI/DOKUMENTASI_FITUR.md)** | Detail fitur vision pada aplikasi mobile. |
| **[NEW_DATABASE_SCHEMA.md](../tool/sqlUI/NEW_DATABASE_SCHEMA.md)** | Struktur database SQLite yang digunakan oleh Go Server. |

---

## 🐍 Python AI Engine (Kondisi Saat Ini)

Backend AI (`/ai_system`) telah dioptimalkan dengan fitur berikut:

- **Ultra-Fast Decoding**: Menggunakan **TurboJPEG** (local library di `/tool/libjpeg-turbo64`) yang jauh lebih cepat daripada OpenCV standar.
- **Vectorized Post-processing**: Logika pemrosesan BBox menggunakan operasi matriks **NumPy**, meminimalkan penggunaan loop Python yang lambat.
- **Direct gRPC Workers**: Sistem dikonfigurasi menggunakan `direct_inference: true` (lihat `config.json`), yang berarti inferensi berjalan langsung di thread gRPC tanpa overhead thread-pool tambahan.
- **Smart Resize**: Otomatis menyesuaikan frame ke ukuran `320x320` atau `640x640` sesuai spesifikasi model ONNX.

---

## 🛠️ Manajemen Sistem (Scripts Utama)

Script ini berada di **folder root** untuk mengelola seluruh stack:

- **`start_system.py`**: Menjalankan Go Gateway dan Python AI secara bersamaan.
- **`stop_system.py`**: Menghentikan seluruh proses secara bersih (graceful shutdown).
- **`health_check.py`**: Verifikasi status port (8080 & 50051) dan konektivitas database.
- **`install.py`**: Tool otomasi untuk build dan install aplikasi Flutter ke device Android/iOS.

---

## ⚙️ Lokasi Penting
- **Database**: `../scanai.db` (SQLite dengan WAL Mode diaktifkan).
- **Model**: `Model_train/best.onnx`.
- **Logs**: Folder `/logs` untuk monitoring runtime.

---
© 2025 ScanAI - Sistem Kasir Masa Depan.
