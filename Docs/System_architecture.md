# AI System Integration - Technical Protocol Reference

## 🚀 Overview

Sistem ini menggunakan sinkronisasi kecepatan tinggi antara perangkat mobile (ScanAI) dan server pusat (Serv_ScaI) menggunakan protokol biner di atas UDP untuk efisiensi maksimal.

---

## 📡 Protocol Details

### 1. Connection
- **Endpoint:** `udp://<SERVER_IP>:8080`
- **Session Control:** Diperlukan session ID unik per instance aplikasi untuk menangani lingkungan multi-user.

### 2. Binary Frame Protocol (Uplink)
Frame dikirim dari ScanAI ke Server menggunakan format biner kustom untuk meminimalkan overhead.

**Payload Structure:**
| Field | Size (Bytes) | Description |
| :--- | :--- | :--- |
| **Token Length** | 1 | Panjang string JWT token |
| **Token** | N | String JWT Bearer Token |
| **Session ID Length** | 1 | Panjang string Session ID |
| **Session ID** | N | String unik per instansi aplikasi |
| **Frame Sequence** | 8 | Big-endian uint64 untuk sinkronisasi frame |
| **Width** | 4 | Big-endian uint32 (Default: 640) |
| **Height** | 4 | Big-endian uint32 (Default: 360) |
| **Format Length** | 1 | Panjang string format |
| **Format** | N | String format (e.g., "jpeg") |
| **Image Data** | Remaining | Byte mentah gambar (JPEG/YUV) |

**Chunking Mechanism:**
Karena keterbatasan MTU pada UDP, payload dipecah menjadi chunk berukuran **1400 bytes** dengan header tambahan 12-byte:
- `MessageID` (8 bytes)
- `ChunkIndex` (2 bytes)
- `TotalChunks` (2 bytes)

### 3. Response Protocol (Downlink)
Hasil deteksi dikirim kembali dari Server ke ScanAI dalam format JSON (baik via WebSocket atau UDP reassembled).

**JSON Response format:**
```json
{
  "success": true,
  "frame_id": "123",
  "frame_sequence": 123,
  "processing_time_ms": 45,
  "ai_results": {
    "detections": [
      {
        "class_name": "lemper",
        "confidence": 0.98,
        "bbox": {
          "x_min": 0.1,
          "y_min": 0.2,
          "width": 0.3,
          "height": 0.4
        }
      }
    ]
  }
}
```

---

## 🛠️ Server-Side Management

Sistem server terdiri dari Go (Gateway) dan Python (AI Inference).

### 1. Go Gateway (Port 8080)
- **Role**: Menangani koneksi client, auth JWT, dan manajemen database.
- **AI Proxy**: Meneruskan frame ke Python via gRPC.
- **Session Resume**: Mengingat alamat UDP client berdasarkan Session ID.

### 2. Python AI Engine (Port 50051)
- **Role**: Melakukan inferensi model YOLO.
- **Optimasi**:
    - **TurboJPEG**: Akselerasi hardware-level untuk decoding JPEG.
    - **Vectorized Post-processing**: Perhitungan BBox menggunakan NumPy (paralel).
    - **Object Pooling**: Menghindari overhead inisialisasi model berulang kali.

### Menjalankan Sistem:
```bash
# Jalankan seluruh stack (Go + Python)
python start_system.py

# Berhenti
python stop_system.py
```

### Konfigurasi Database:
Pusat data berada di `scanai.db` (SQLite) dengan mode **Write-Ahead Logging (WAL)** untuk mendukung akses konkuren tinggi dari banyak kasir sekaligus.

---

## 📐 Koordinat & Scaling
- **Normalization:** Server mengembalikan koordinat `0.0` sampai `1.0`.
- **Scaling:** Client harus mengalikan koordinat tersebut dengan dimensi layar preview (bukan resolusi kamera) untuk menggambar Bounding Box secara akurat.
- **Top-Left Origin:** Koordinat (0,0) adalah pojok kiri atas layar.