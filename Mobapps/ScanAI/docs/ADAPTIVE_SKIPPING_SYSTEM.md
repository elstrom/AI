# Multi-Stage Progressive Adaptive Skipping System

## 📋 Overview

Sistem frame skipping yang secara otomatis menyesuaikan agresivitas skipping berdasarkan ukuran buffer dan kondisi server. Sistem ini memiliki 2 stage yang berbeda, dengan kemampuan upgrade otomatis saat server terbukti lambat, dan recovery otomatis saat server kembali cepat.

---

## 🎯 Tujuan

1. **Mencegah buffer overflow** - Mengurangi frame rate saat buffer penuh
2. **Adaptive bi-directional** - Naik saat server lambat, turun saat server cepat (recovery)
3. **Zero-gap target** - Meminimalkan gap antara `buffer_key` dan `buffer_size` di SYNC check
4. **Multi-stage escalation** - Upgrade ke mode lebih agresif saat server konsisten lambat

---

## 🔧 Cara Kerja

### **Stage 1: Per 10 Buffer Increment (Optimistic)**

Stage awal yang memberikan kesempatan kepada server untuk perform dengan baik.

```
Buffer Size  →  Skip Interval  →  Frame Rate (dari 30 FPS)
─────────────────────────────────────────────────────────
0-9          →  Skip 3         →  7.5 FPS  (25% frames sent)
10-19        →  Skip 4         →  6 FPS    (20% frames sent)
20-29        →  Skip 5         →  5 FPS    (16.7% frames sent)
30-39        →  Skip 6         →  4.3 FPS  (14.3% frames sent)
40-49        →  Skip 7         →  3.75 FPS (12.5% frames sent)
50-59        →  Skip 8         →  3.3 FPS  (11.1% frames sent)
60-69        →  Skip 9         →  3 FPS    (10% frames sent)
70-79        →  Skip 10        →  2.7 FPS  (9.1% frames sent)
80-89        →  Skip 11        →  2.5 FPS  (8.3% frames sent)
90-99        →  Skip 12        →  2.3 FPS  (7.7% frames sent)
≥ 100        →  RESET + UPGRADE TO STAGE 2
```

**Formula:**
```dart
skipInterval = (bufferSize / 10) + 3
```

---

### **Stage 2+: Per 5 Buffer Increment (Aggressive)**

Stage yang lebih agresif, diaktifkan setelah buffer mencapai 100 di Stage 1. Tetap di stage ini untuk reset selanjutnya.

```
Buffer Size  →  Skip Interval  →  Frame Rate (dari 30 FPS)
─────────────────────────────────────────────────────────
0-4          →  Skip 3         →  7.5 FPS  (25% frames sent)
5-9          →  Skip 4         →  6 FPS    (20% frames sent)
10-14        →  Skip 5         →  5 FPS    (16.7% frames sent)
15-19        →  Skip 6         →  4.3 FPS  (14.3% frames sent)
20-24        →  Skip 7         →  3.75 FPS (12.5% frames sent)
25-29        →  Skip 8         →  3.3 FPS  (11.1% frames sent)
30-34        →  Skip 9         →  3 FPS    (10% frames sent)
35-39        →  Skip 10        →  2.7 FPS  (9.1% frames sent)
40-44        →  Skip 11        →  2.5 FPS  (8.3% frames sent)
45-49        →  Skip 12        →  2.3 FPS  (7.7% frames sent)
50-54        →  Skip 13        →  2.1 FPS  (7.1% frames sent)
55-59        →  Skip 14        →  2 FPS    (6.7% frames sent)
60-64        →  Skip 15        →  1.9 FPS  (6.25% frames sent)
65-69        →  Skip 16        →  1.8 FPS  (5.9% frames sent)
70-74        →  Skip 17        →  1.7 FPS  (5.6% frames sent)
75-79        →  Skip 18        →  1.6 FPS  (5.3% frames sent)
80-84        →  Skip 19        →  1.5 FPS  (5% frames sent)
85-89        →  Skip 20        →  1.4 FPS  (4.8% frames sent)
90-94        →  Skip 21        →  1.4 FPS  (4.5% frames sent)
95-99        →  Skip 22        →  1.3 FPS  (4.3% frames sent)
≥ 100        →  RESET (STAY AT STAGE 2)
```

**Formula:**
```dart
skipInterval = (bufferSize / 5) + 3
```

---

## 🔄 Bi-Directional Adaptive (Recovery)

Sistem ini **otomatis menyesuaikan** skip interval saat buffer size berubah:

### **Scenario 1: Server Lambat (Progressive UP)**

```
Timeline: Server response time = 200-500ms

T=0s:  Buffer 5   → Stage 1 → Skip 3  (25% sent)
T=2s:  Buffer 15  → Stage 1 → Skip 4  (20% sent) ⬆️
T=4s:  Buffer 35  → Stage 1 → Skip 6  (14% sent) ⬆️
T=6s:  Buffer 65  → Stage 1 → Skip 9  (10% sent) ⬆️
T=8s:  Buffer 95  → Stage 1 → Skip 12 (7.7% sent) ⬆️
T=10s: Buffer 100 → RESET! → UPGRADE TO STAGE 2 ⚠️

T=10s: Buffer 0   → Stage 2 → Skip 3  (25% sent) 🔄
T=11s: Buffer 10  → Stage 2 → Skip 5  (16.7% sent) ⬆️
T=12s: Buffer 25  → Stage 2 → Skip 8  (11% sent) ⬆️
T=14s: Buffer 50  → Stage 2 → Skip 13 (7.1% sent) ⬆️
T=16s: Buffer 80  → Stage 2 → Skip 19 (5% sent) ⬆️
```

### **Scenario 2: Server Cepat Lagi (Progressive DOWN - RECOVERY!)**

```
Timeline: Server speeds up (response time drops to 50-100ms)

T=0s:  Buffer 80  → Stage 2 → Skip 19 (5% sent)
T=1s:  Buffer 60  → Stage 2 → Skip 15 (6.25% sent) ⬇️ RECOVERY!
T=2s:  Buffer 40  → Stage 2 → Skip 11 (8.3% sent) ⬇️ RECOVERY!
T=3s:  Buffer 20  → Stage 2 → Skip 7  (12.5% sent) ⬇️ RECOVERY!
T=4s:  Buffer 10  → Stage 2 → Skip 5  (16.7% sent) ⬇️ RECOVERY!
T=5s:  Buffer 5   → Stage 2 → Skip 4  (20% sent) ⬇️ OPTIMAL!

Stage tetap 2, tapi interval turun = RECOVERY SUCCESSFUL! ✅
```

**Catatan:** Stage **tidak pernah turun** (one-way upgrade), hanya skip interval yang turun saat recovery.

---

## 📊 Expected Results

### **SYNC Gap Improvement**

**Sebelum (Fixed threshold system):**
```
[DEBUG] SYNC OK | buffer_key: 70, buffer_size: 19  ← GAP 51 ❌
[DEBUG] SYNC OK | buffer_key: 72, buffer_size: 17  ← GAP 55 ❌
```

**Sesudah (Multi-Stage Progressive Adaptive):**
```
Server optimal:
[DEBUG] SYNC OK | buffer_key: 50, buffer_size: 50  ← GAP 0 🎉
[DEBUG] SYNC OK | buffer_key: 55, buffer_size: 54  ← GAP 1 ✅

Server lambat:
[DEBUG] SYNC OK | buffer_key: 70, buffer_size: 68  ← GAP 2 ✅
[DEBUG] SYNC OK | buffer_key: 75, buffer_size: 73  ← GAP 2 ✅

Server recovery:
[DEBUG] SYNC OK | buffer_key: 30, buffer_size: 29  ← GAP 1 ✅
[DEBUG] SYNC OK | buffer_key: 35, buffer_size: 35  ← GAP 0 🎉
```

---

## 🎮 Stage Upgrade Logic

```
┌─────────────────────────────────────────────────────┐
│                    START                            │
│                  Stage 1 (Per 10)                   │
└─────────────────┬───────────────────────────────────┘
                  │
                  │ Buffer naik seiring waktu
                  │
                  ▼
         ┌────────────────┐
         │ Buffer ≥ 100?  │
         └────┬───────┬───┘
              │ No    │ Yes
              │       │
              │       ▼
              │  ┌─────────────────────────┐
              │  │ RESET BUFFER            │
              │  │ UPGRADE TO STAGE 2      │
              │  │ (Per 5 - More Aggressive)│
              │  └─────────┬───────────────┘
              │            │
              │            ▼
              │  ┌─────────────────────────┐
              │  │     Stage 2 (Per 5)     │
              │  └─────────┬───────────────┘
              │            │
              │            │ Buffer naik lagi
              │            │
              │            ▼
              │   ┌────────────────┐
              │   │ Buffer ≥ 100?  │
              │   └────┬───────┬───┘
              │        │ No    │ Yes
              │        │       │
              │        │       ▼
              │        │  ┌─────────────────┐
              │        │  │ RESET BUFFER    │
              │        │  │ STAY AT STAGE 2 │
              │        │  └────────┬────────┘
              │        │           │
              │        └───────────┘
              │
              └──► Continue adaptive skipping
```

---

## 🔍 Monitoring & Logging

### **Log Output Examples:**

**Stage 1 - Normal Operation:**
```
[INFO] ⬆️ Stage 1 (per 10): buffer=15 → interval=4 (20.0% frames sent)
[INFO] ⬆️ Stage 1 (per 10): buffer=25 → interval=5 (16.7% frames sent)
```

**Stage Upgrade:**
```
[WARN] Buffer ≥ 100, force reset triggered
[WARN] ⬆️ Upgraded to Stage 2 (per 5 increment) - Server is consistently slow!
```

**Stage 2 - Aggressive Mode:**
```
[INFO] ⬆️ Stage 2 (per 5): buffer=20 → interval=7 (12.5% frames sent)
[INFO] ⬆️ Stage 2 (per 5): buffer=45 → interval=12 (7.7% frames sent)
```

**Recovery:**
```
[INFO] ⬇️ Stage 2 (per 5): buffer=30 → interval=9 (10.0% frames sent)
[INFO] ⬇️ Stage 2 (per 5): buffer=15 → interval=6 (14.3% frames sent)
```

**Throttling Check (Every 4 seconds):**
```
[DEBUG] Throttling Check: stage=2, bufferSize=45, sent=1250, ack=1180
```

---

## ⚙️ Configuration

### **Constants:**

```dart
// Critical threshold - triggers reset & stage upgrade
static const int _thresholdCritical = 100;

// Initial stage
int _currentStage = 1; // Start optimistic

// Base skip interval (minimum)
// Formula: skipInterval = (bufferSize / incrementStep) + 3
// Minimum interval = 3 (when buffer = 0)
```

### **Tuning Parameters:**

Jika ingin adjust behavior:

1. **Ubah base interval** (saat ini = 3):
   ```dart
   dynamicInterval = (_currentBufferSize ~/ incrementStep) + 4; // Lebih agresif
   ```

2. **Ubah increment step** Stage 1 (saat ini = 10):
   ```dart
   incrementStep = 15; // Lebih smooth transition
   ```

3. **Ubah increment step** Stage 2 (saat ini = 5):
   ```dart
   incrementStep = 3; // Lebih agresif
   ```

4. **Ubah critical threshold** (saat ini = 100):
   ```dart
   static const int _thresholdCritical = 80; // Reset lebih cepat
   ```

---

## 🎯 Benefits

1. **✅ Self-Balancing** - Otomatis adjust tanpa manual tuning
2. **✅ Bi-Directional** - Naik saat lambat, turun saat cepat (recovery)
3. **✅ Progressive** - Smooth transition, tidak ada "loncat" interval
4. **✅ Multi-Stage** - Escalate ke mode lebih agresif saat perlu
5. **✅ Zero-Gap Target** - Buffer size ≈ frame key untuk perfect sync
6. **✅ Network Resilient** - Handle kondisi network yang berubah-ubah

---

## 📈 Performance Metrics

### **Expected Behavior:**

| Network Condition | Stage | Avg Buffer | Avg Interval | Frame Rate | SYNC Gap |
|-------------------|-------|------------|--------------|------------|----------|
| Optimal (50ms)    | 1     | 5-10       | 3-4          | 6-7.5 FPS  | 0-2      |
| Good (100ms)      | 1     | 10-20      | 4-5          | 5-6 FPS    | 1-3      |
| Moderate (200ms)  | 1-2   | 20-40      | 5-8          | 3-5 FPS    | 2-5      |
| Slow (300ms)      | 2     | 40-60      | 11-15        | 1.9-2.5 FPS| 3-8      |
| Very Slow (500ms) | 2     | 60-80      | 15-19        | 1.5-1.9 FPS| 5-10     |

---

## 🔧 Implementation Location

**File:** `lib/core/logic/adaptive_frame_skipper.dart`

**Class:** `AdaptiveFrameSkipper`

**Key Methods:**
- `shouldSkip()`: Inti logika penentuan apakah frame harus di-skip.
- `updateBufferSize(int value)`: Menerima update ukuran buffer server.
- `markAckReceived()`: Menandai paket berhasil diproses (untuk recovery).

**State Variables:**
- `int _currentStage` - Stage saat ini (1 atau 2+).
- `int _currentBufferSize` - Ukuran buffer server terakhir.
- `int _inputFrameCount` - Counter frame untuk perhitungan modulo skip.
- `int _lastLoggedInterval` - Untuk tracking perubahan interval di log.

---

## 📝 Version History

**v2.0** - Multi-Stage Progressive Adaptive Skipping System
- ✅ Implemented 2-stage system (per 10 → per 5)
- ✅ Added bi-directional adaptive (recovery)
- ✅ One-way stage upgrade (never downgrade)
- ✅ Enhanced logging for monitoring

**v1.0** - Fixed Threshold System (Deprecated)
- ❌ Fixed thresholds (15, 30, 100)
- ❌ No recovery mechanism
- ❌ No stage escalation

---

## 🎓 Theory

### **Why Progressive?**

Bertahap mengurangi frame rate lebih smooth daripada loncat drastis. User experience lebih baik dengan transition yang halus.

### **Why Multi-Stage?**

Server yang konsisten lambat perlu treatment berbeda. Stage 2 (per 5) memberikan granularity lebih tinggi untuk fine-tuning skip rate.

### **Why Bi-Directional?**

Network condition berubah-ubah. Sistem harus bisa **recover** saat kondisi membaik, tidak hanya **escalate** saat memburuk.

### **Why One-Way Stage Upgrade?**

Stage upgrade adalah indikator bahwa server **pernah** sangat lambat. Tetap di stage agresif mencegah buffer overflow di masa depan jika kondisi buruk terulang.

---

## 🚀 Future Improvements

Potential enhancements:

1. **Stage 3** - Ultra aggressive (per 3) untuk kondisi ekstrem
2. **Adaptive increment step** - Dynamically adjust step size
3. **Predictive skipping** - ML-based prediction of server latency
4. **Time-based stage downgrade** - Downgrade stage setelah X menit stabil
5. **Per-device tuning** - Different thresholds for different devices

---

**Created:** 2025-12-21  
**Author:** AI Assistant  
**Status:** Production Ready ✅
