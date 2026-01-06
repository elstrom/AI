# Smart Context Windows - Implementation Documentation

## ✅ Status: IMPLEMENTED
Fitur ini telah diimplementasikan sepenuhnya di `lib/core/logic/snapshot_dispatcher.dart` dan aktif secara default.

## 🎯 Tujuan
Menstabilkan data deteksi dari AI agar tidak terjadi "flickering" atau angka yang melompat-lompat pada layar Kasir (PosAI). Sistem ini menggunakan mekanisme konsensus berbasis waktu untuk menemukan nilai yang paling akurat.

## 🔧 Mekanisme Teknis

### 1. Sliding Window (200ms)
Dispatcher mengumpulkan seluruh frame deteksi mentah dalam jendela waktu 200ms. Frame yang lebih tua dari 200ms akan otomatis dihapus dari buffer setiap 100ms (sliding interval).

### 2. Mayoritas Suara (Majority Voting)
Untuk setiap jenis item (misal: "lemper"), sistem menghitung jumlah kemunculan di setiap frame dalam buffer.
- **Konsep**: Jika dalam 5 frame terakhir deteksi menunjukkan angka [5, 5, 5, 7, 5], maka angka **5** yang akan dikirim ke POS, karena angka 7 dianggap sebagai anomali/glitch sesaat.

### 3. Validasi Keberadaan (Presence Check)
Item hanya dianggap valid jika muncul setidaknya dalam **30%** frame di dalam jendela waktu. Jika kurang dari itu, item dianggap sebagai noise visual.

### 4. Validasi Stabilitas Posisi (IoU Check)
Sistem menghitung **Intersection over Union (IoU)** antar frame untuk memastikan objek diam atau bergerak secara wajar. Jika posisi kotak (BBox) melompat secara drastis dalam waktu singkat, sistem akan menunda update angka tersebut hingga posisi kembali stabil.

### 5. Tie-Breaker (Pemecah Seri)
Jika terdapat dua angka yang memiliki frekuensi kemunculan yang sama (misal: 2 frame bilang '5', 2 frame bilang '6'):
1. **Last Stable Result**: Menggunakan angka yang dikirim pada interval sebelumnya.
2. **Median**: Memilih angka tengah dari kumpulan data untuk menghindari fluktuasi ekstrem.

## 📊 Parameter Konfigurasi (`snapshot_dispatcher.dart`)
- `_windowDurationMs`: **200ms** (Durasi jendela pengumpulan).
- `_slidingIntervalMs`: **100ms** (Interval pengiriman data ke PosAI).
- `_iouThreshold`: **0.3** (Ambang batas stabilitas posisi).
- `_minPresenceRatio`: **0.3** (Minimal konsistensi kemunculan).

## 🚀 Dampak Positif
- **Zero Flickering**: Angka di keranjang belanja PosAI sangat stabil.
- **High Accuracy**: Mengurangi kesalahan hitung akibat tangan lewat atau bayangan sesaat.
- **Smooth UX**: Transisi angka terasa lebih mantap dan terpercaya bagi kasir.
