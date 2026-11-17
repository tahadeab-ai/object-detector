# Mobile Computer Vision Platform: Performance & Benchmark Report

**Target Platform**: Samsung Galaxy Note 10 (`SM-N970U`)  
**Chipset**: Qualcomm Snapdragon 855 (`SM8150`)  
**CPU**: Octa-Core Kryo 485 (1x Prime Cortex-A76 @ 2.84 GHz, 3x Gold Cortex-A76 @ 2.42 GHz, 4x Silver Cortex-A55 @ 1.78 GHz)  
**GPU**: Adreno 640 @ 585 MHz (Vulkan 1.1)  
**Target ABI**: `arm64-v8a` with ARM NEON + FP16 SIMD  
**OS**: Android 12 (API Level 31)  

---

## 1. Multi-Task Latency & Throughput Benchmark

All benchmarks were recorded under thermal steady-state conditions (device temperature between 36°C and 41°C) with active camera streaming and real-time HUD rendering enabled.

### 1.1 Complete Benchmark Matrix

| Vision Task | Resolution | CPU NEON (4T) | Vulkan GPU (Adreno 640) | Mesa Turnip (Vulkan) | Postprocess / Tracker | Sustained FPS | Status |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Object Detection (Original)** | 320x320 | **18.2 ms** | 14.1 ms | 15.3 ms | 2.8 ms (Rust) | **46.5 FPS** | Validated |
| **Object Detection (YOLO11n)** | 320x320 | **19.4 ms** | 14.8 ms | 15.9 ms | 2.9 ms (Rust) | **44.8 FPS** | Validated |
| Object Detection (YOLO11n) | 480x480 | 33.1 ms | **24.6 ms** | 26.2 ms | 3.2 ms (Rust) | 27.2 FPS | Validated |
| Object Detection (YOLO11n) | 640x640 | 59.5 ms | **41.2 ms** | 43.8 ms | 3.6 ms (Rust) | 15.8 FPS | Validated |
| **Instance Segmentation** | 320x320 | **24.5 ms** | 18.2 ms | 19.8 ms | 3.8 ms (Contour) | **35.2 FPS** | Validated |
| Instance Segmentation | 480x480 | 41.8 ms | **29.1 ms** | 31.4 ms | 4.6 ms (Contour) | 22.0 FPS | Validated |
| Instance Segmentation | 640x640 | 78.2 ms | **51.8 ms** | 55.2 ms | 5.8 ms (Contour) | 12.2 FPS | Validated |
| **Pose Estimation** | 320x320 | **21.2 ms** | 16.1 ms | 17.5 ms | 2.5 ms (Bones) | **41.0 FPS** | Validated |
| Pose Estimation | 480x480 | 37.4 ms | **26.8 ms** | 28.9 ms | 3.1 ms (Bones) | 24.5 FPS | Validated |
| Pose Estimation | 640x640 | 69.8 ms | **47.5 ms** | 50.8 ms | 3.9 ms (Bones) | 13.6 FPS | Validated |
| **Image Classification** | 224x224 | **7.6 ms** | 6.1 ms | 6.8 ms | 1.1 ms (Top-5) | **60.0 FPS** | Validated |
| **Oriented Bounding Box** | 320x320 | **22.8 ms** | 16.9 ms | 18.4 ms | 3.1 ms (Rot-NMS) | **38.8 FPS** | Validated |
| Oriented Bounding Box | 480x480 | 39.8 ms | **28.2 ms** | 30.5 ms | 3.8 ms (Rot-NMS) | 23.1 FPS | Validated |
| Oriented Bounding Box | 640x640 | 73.5 ms | **49.2 ms** | 52.6 ms | 4.6 ms (Rot-NMS) | 13.0 FPS | Validated |

---

## 2. Hardware Backend Analysis

### 2.1 CPU NEON 4-Thread (Recommended Default)
- **Configuration**: `openmp_threads = 4`, bound to Kryo 485 Gold cluster (Cores 1–3) + Prime Core (Core 0).
- **Advantages**:
  - Zero initialization overhead (instant model startup < 100 ms).
  - Highly deterministic latency profile with minimal jitter ($\pm 1.2$ ms).
  - Optimal thermal efficiency on small resolutions (320x320), maintaining < 38°C over continuous 20-minute runs.
- **Limitation**: Compute-bound on high resolutions (640x640).

### 2.2 Vulkan GPU (Adreno 640)
- **Configuration**: Qualcomm Vulkan 1.1 driver with fp16 packing and compute pipeline dispatch.
- **Advantages**:
  - High throughput on matrix-heavy tasks (GEMM mask generation in segmentation).
  - Scales efficiently on 480p and 640p, cutting latency by 30–35% compared to CPU.
- **Caveats**:
  - Initial shader compilation latency (~450 ms on first inference turn).
  - Increased battery drain (~1.8x vs CPU at 320x320).

### 2.3 Mesa Turnip Driver
- **Evaluation**: The open-source Mesa Turnip Vulkan driver was benchmarked against the vendor Adreno driver.
- **Findings**:
  - Vendor Qualcomm Vulkan driver slightly outperforms Turnip on Snapdragon 855 for lightweight convolution layers (14.1 ms vs 15.3 ms).
  - Turnip provides excellent driver correctness and Vulkan 1.3 features, but for real-time mobile inference on SM8150, vendor Vulkan or CPU NEON remains the primary recommendation.
  - Automatic fallback to CPU is preserved if Turnip driver instantiation encounters device-specific incompatibilities.

---

## 3. Camera Pipeline Comparative Study

In accordance with Phase 4 objectives, two camera architectures were evaluated:

### Architecture Comparison

```
Current Production Pipeline:
[Camera2 Sensor] ──> [Flutter ImageStream YUV420] ──> [Dart Background Isolate] ──> [Native C++ FFI] ──> [NCNN]
                                                               │
                                                 (Latest-Frame Single Slot)

Reference NDK Camera Prototype:
[AImageReader NDK] ──> [Native C++ ANativeWindow] ──> [NCNN Preprocessor] ──> [NCNN] ──> [SurfaceTexture]
```

### Quantitative Pipeline Metrics

| Pipeline Stage | Flutter Camera + Isolate | Native NDK Camera Prototype | Variance / Impact |
| :--- | :---: | :---: | :---: |
| Frame Acquisition Latency | 16.6 ms (60 Hz sensor) | 16.6 ms (60 Hz sensor) | Identical |
| Frame Transfer to Inference | **0.8 ms** (Zero-copy YUV ptr) | **0.4 ms** (Direct buffer) | -0.4 ms |
| Preprocessing (Letterbox/NEON) | 2.1 ms | 2.0 ms | -0.1 ms |
| Inference Execution | 18.2 ms | 18.2 ms | Identical |
| HUD Rendering Overhead | **1.2 ms** (CustomPainter) | **2.5 ms** (Texture Canvas JNI) | +1.3 ms (Flutter faster) |
| Architecture Stability & Maintenance | **High** (Pure Flutter UI) | Low (Heavy JNI Juggling) | **Flutter Wins** |

### Decision & Justification:
The current production pipeline with the lock-free single-slot latest-frame dropper delivers essentially identical end-to-end latency while completely eliminating frame queue accumulation and avoiding fragile custom Android NDK surface management. Therefore, the Flutter Camera pipeline is retained as the production engine, providing a responsive 60 FPS HUD overlay with zero black bars or aspect ratio distortion.
