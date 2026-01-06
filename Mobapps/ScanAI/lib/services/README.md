# Sistem Streaming Video

## Ringkasan

Sistem streaming video ini dirancang untuk mengirimkan frame video dari kamera perangkat ke server cloud (Google Cloud) untuk diproses dengan AI dan menerima hasil deteksi objek (bounding box) kembali ke perangkat.

## Arsitektur

Sistem streaming mengikuti arsitektur berlapis (layered architecture) dengan pemisahan tanggung jawab yang jelas:

```
┌─────────────────────────────────────────┐
│          Presentation Layer              │
│           (UI Widgets)                │
├─────────────────────────────────────────┤
│           CameraState                 │
│     (State Management)               │
├─────────────────────────────────────────┤
│        StreamingService               │
│     (High-level API)                │
├─────────────────────────────────────────┤
│      StreamingRepository             │
│   (Business Logic & Data)           │
├─────────────────────────────────────────┤
│     StreamingDataSource             │
│  (Data Access & Communication)       │
├─────────────────────────────────────────┤
│      WebSocketService                │
│      VideoEncoder                   │
│     (Low-level Services)             │
└─────────────────────────────────────────┘
```

## Komponen

### 1. WebSocketService (`lib/services/websocket_service.dart`)

Service ini menangani koneksi WebSocket dengan fitur-fitur:
- Koneksi dan disoneksi otomatis
- Mekanisme auto-reconnect dengan exponential backoff
- Heartbeat untuk menjaga koneksi tetap hidup
- Error handling dan retry logic
- Status monitoring

**Fitur Utama:**
- Auto-reconnect dengan exponential backoff
- Heartbeat mechanism
- Connection status monitoring
- Error handling dan retry logic

### 2. VideoEncoder (`lib/services/video_encoder.dart`)

Service ini menangani encoding frame video menjadi format yang efisien (JPEG/PNG):
- Konversi format gambar (YUV420, BGRA8888 ke RGB)
- Resize gambar sesuai target resolusi
- Encoding ke JPEG atau PNG
- Frame rate control
- Performance metrics

**Fitur Utama:**
- Konversi format gambar
- Resize dengan aspect ratio preservation
- Encoding ke JPEG/PNG
- Frame rate control
- Performance metrics

### 3. StreamingDataSource (`lib/data/datasources/streaming_datasource.dart`)

DataSource ini bertanggung jawab atas interaksi langsung dengan server:
- Mengirim frame yang telah di-encode
- Menerima dan parsing hasil deteksi
- Mengelola state streaming
- Error handling

**Fitur Utama:**
- Protokol komunikasi dengan server
- Parsing pesan (deteksi, heartbeat, error)
- State management
- Error handling

### 4. StreamingRepository (`lib/data/repositories/streaming_repository.dart`)

Repository ini menyediakan API yang bersih untuk presentation layer:
- Abstraksi dari detail implementasi data source
- Business logic terkait streaming
- Formatting data untuk UI
- Error handling

**Fitur Utama:**
- API yang bersih untuk presentation layer
- Business logic
- Data formatting
- Error handling

### 5. StreamingService (`lib/services/streaming_service.dart`)

Service ini menyediakan high-level API untuk aplikasi:
- Integrasi semua komponen streaming
- Stream management
- Configuration management
- Metrics collection

**Fitur Utama:**
- High-level API
- Stream management
- Configuration management
- Metrics collection

## Protokol Komunikasi

### Format Pesan ke Server

```json
{
  "type": "frame",
  "timestamp": 1634567890123,
  "format": "jpeg",
  "width": 640,
  "height": 480,
  "data": "<base64_encoded_image_data>"
}
```

### Format Pesan dari Server

#### Deteksi Objek
```json
{
  "type": "detection",
  "timestamp": 1634567890123,
  "imageWidth": 640,
  "imageHeight": 480,
  "objects": [
    {
      "className": "person",
      "confidence": 0.95,
      "bbox": {
        "x": 100,
        "y": 150,
        "width": 80,
        "height": 200
      }
    }
  ]
}
```

#### Heartbeat
```json
{
  "type": "heartbeat",
  "timestamp": 1634567890123
}
```

#### Error
```json
{
  "type": "error",
  "code": "CONNECTION_ERROR",
  "message": "Failed to process frame"
}
```

## Integrasi dengan UI

### CameraState (`lib/presentation/state/camera_state.dart`)

State management untuk kamera dan streaming:
- Mengelola state kamera
- Mengelola state streaming
- Integrasi dengan UI melalui Provider
- Error handling

### Widget UI

#### ControlPanel (`lib/presentation/widgets/control_panel.dart`)
Panel kontrol untuk:
- Start/stop streaming
- Capture gambar
- Kontrol flash
- Switch kamera
- Status indicators

#### StatusIndicator (`lib/presentation/widgets/status_indicator.dart`)
Widget untuk menampilkan status:
- Connection status
- Streaming status
- Detection status
- FPS
- Streaming metrics

#### StreamingMonitor (`lib/presentation/widgets/streaming_monitor.dart`)
Widget monitoring streaming yang detail:
- Status koneksi
- Metrik streaming
- Performance metrics
- Error status

## Error Handling

Sistem ini memiliki mekanisme error handling yang komprehensif:

1. **Connection Errors**: Auto-reconnect dengan exponential backoff
2. **Encoding Errors**: Logging dan fallback ke format lain
3. **Streaming Errors**: Notifikasi ke UI dan recovery otomatis
4. **UI Errors**: User-friendly error messages

## Performance Optimization

### Bandwidth Management
- Frame rate control
- Resolusi dinamis
- Compression quality adjustment
- Frame skipping saat network congestion

### Memory Management
- Efficient image processing
- Object pooling
- Proper resource disposal

## Konfigurasi

### WebSocket Configuration
```dart
updateRetryConfiguration({
  int? maxRetryAttempts,
  Duration? initialRetryDelay,
  Duration? maxRetryDelay,
});
```

### Encoder Configuration
```dart
updateEncoderConfiguration({
  int? quality,
  int? targetWidth,
  int? targetHeight,
  String? format,
  double? targetFps,
});
```

### Heartbeat Configuration
```dart
updateHeartbeatConfiguration({
  Duration? interval,
});
```

## Monitoring dan Metrics

Sistem ini menyediakan berbagai metrics untuk monitoring:

### Connection Metrics
- Connection status
- Reconnection attempts
- Latency

### Streaming Metrics
- Frames sent/received
- FPS aktual
- Bandwidth usage

### Performance Metrics
- Encoding time
- Frame size
- CPU/memory usage

## Cara Penggunaan

### Inisialisasi
```dart
final cameraState = CameraState();
await cameraState.initializeCamera();
```

### Start Streaming
```dart
await cameraState.connectToServer();
await cameraState.startStreaming();
```

### Stop Streaming
```dart
await cameraState.stopStreaming();
await cameraState.disconnectFromServer();
```

### Konfigurasi
```dart
cameraState.updateStreamingConfiguration(
  quality: 85,
  targetWidth: 640,
  targetHeight: 480,
  format: 'jpeg',
  targetFps: 15.0,
);
```

### Monitoring
```dart
final metrics = cameraState.getCurrentMetrics();
final formattedStats = cameraState.getFormattedStats();
```

## Kesimpulan

Sistem streaming video ini menyediakan solusi yang lengkap dan efisien untuk streaming video real-time dengan fitur-fitur:

1. **Arsitektur yang bersih** dengan pemisahan tanggung jawab yang jelas
2. **Error handling yang robust** dengan auto-recovery
3. **Performance optimization** dengan berbagai mekanisme kontrol
4. **Monitoring komprehensif** dengan berbagai metrics
5. **Integrasi UI yang mudah** dengan state management yang baik

Sistem ini dirancang untuk dapat diandalkan dalam aplikasi deteksi objek real-time dengan latency rendah dan bandwidth usage yang optimal.