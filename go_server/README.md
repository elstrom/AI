# Go Server - ScanAI Gateway & Transaction Manager

Pusat kendali backend yang menangani komunikasi data berat (Video Stream) dan manajemen database (REST API).

## 🚀 Fitur Utama
- **Hybrid Communication**:
    - **WebSocket/UDP Server**: Menerima binary frame (chunked) dari smartphone dengan overhead minimal. Mendukung session resume.
    - **REST API**: Menyediakan endpoint untuk sinkronisasi produk, kategori, dan pencatatan transaksi.
- **AI gRPC Bridge (Direct Mode)**: Menjadi perantara (proxy) ultra-cepat antara client mobile dan sistem AI Python. Menggunakan `direct_inference` untuk meminimalkan latency.
- **Robust Database (SQLite)**: 
    - Mengelola `scanai.db` dengan WAL Mode.
    - Mendukung: Transaction Header, Items, Cash Movement, Stock History, dan Audit Logs.
- **Memory Management**: Dilengkapi dengan monitor memori otomatis untuk stabilitas jangka panjang.
- **Concurrency Control**: Mode Single-Writer untuk integritas data database yang maksimal.

## 📂 Struktur Project
```
go_server/
├── cmd/server/main.go       # Entry point
├── internal/
│   ├── api/                 # REST API Handlers (Transaction, Product)
│   ├── database/            # SQLite Models & Operations (GORM)
│   ├── grpc/                # gRPC Client ke Python AI
│   └── websocket/           # WebSocket & UDP Binary Handlers
├── proto/                   # Definisi Protobuf
└── config.yaml              # Konfigurasi Server
```

## 🛠️ Konfigurasi (config.yaml)
```yaml
server:
  port: "8080"
  db_path: "./scanai.db"

grpc:
  target: "localhost:50051"

frame_skip:
  base_skip_ratio: 0.0 # Control server-side skipping
```

## 📡 Protocol Interface

### 1. Frame Uplink (UDP Binary)
Server mendengarkan di port **8080** untuk paket UDP biner yang berisi frame gambar terkompresi.

### 2. Transaction API (HTTP)
- `POST /api/v1/transactions`: Mencatat hasil belanja dari PosAI.
- `GET /api/v1/products`: Mengambil daftar produk terbaru.
- `POST /api/v1/auth/login`: Autentikasi user kasir.

## 🔨 Cara Menjalankan
1. Pastikan Go 1.21+ terinstal.
2. Jalankan: `go run cmd/server/main.go`
3. Server akan mulai mendengarkan di `0.0.0.0:8080`.