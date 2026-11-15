# YOLO NCNN Detector

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL%203.0-blue.svg)](LICENSE)
[![Platform: Android](https://img.shields.io/badge/Platform-Android%20arm64--v8a-brightgreen.svg)](https://developer.android.com)
[![Engine: Tencent NCNN](https://img.shields.io/badge/Engine-Tencent%20NCNN%20Vulkan-orange.svg)](https://github.com/Tencent/ncnn)
[![Core: Pure Rust](https://img.shields.io/badge/Core-Rust%202021-red.svg)](native_core/rust/)
[![Flutter: 60 FPS HUD](https://img.shields.io/badge/UI-Flutter%2060%20FPS%20HUD-02569B.svg)](mobile_app/)

**YOLO NCNN Detector** (`tahadeab-ai/object-detector`) is a production-grade, real-time general object detection and multi-object tracking platform for Android (80 COCO classes) processing live camera frames in milliseconds.

The system combines **Tencent NCNN** (ARM NEON & Vulkan Compute GPU acceleration), a **pure Rust high-performance core** (anchor-free YOLO11 tensor decoding, class-aware NMS, and two-stage multi-object tracking), and a **bilingual Flutter mobile cockpit** (English LTR and Arabic RTL with decoupled 60 FPS HUD rendering).

---

## 1. System Architecture

```text
+-----------------------------------------------------------------------------------+
|                            Android Camera2 / NV21 Frame                           |
+-----------------------------------------------------------------------------------+
                                          │
                                          ▼
+-----------------------------------------------------------------------------------+
|                  Flutter Worker Isolate (Dedicated Background)                    |
|             (Single-slot latest-frame gate: drops stale frames instantly)         |
+-----------------------------------------------------------------------------------+
                                          │  Zero-Copy Pointer
                                          ▼
+-----------------------------------------------------------------------------------+
|                        Unified Native Engine (libyolo_ncnn.so)                     |
|                                                                                   |
|   1. ARM NEON C++ Runner:                                                         |
|      - YUV420/NV21 -> RGB letterbox & bilinear resize (640x640)                   |
|      - ncnn::Net extractor (CPU 4-Threads NEON or Vulkan Compute GPU)             |
|                                                                                   |
|   2. Static Rust Core (libyolo_rust.a linked via -Wl,--whole-archive):            |
|      - Anchor-free [1, 84, 8400] tensor decoder                                   |
|      - Class-aware Non-Maximum Suppression (IoU & confidence thresholds)          |
|      - 2-Stage association tracker (Constant-velocity prediction + kinematic cost)|
|      - EMA coordinate smoothing (alpha=0.65) & majority vote class stabilization  |
|      - Spatial zones (Left/Center/Right) & Proximity tiers (Near/Medium/Far)      |
+-----------------------------------------------------------------------------------+
                                          │  #[repr(C)] YoloFrameResult
                                          ▼
+-----------------------------------------------------------------------------------+
|                           Flutter UI Thread (Main)                                |
|   - Decoupled CustomPainter HUD at target 60 FPS                                  |
|   - Live glassmorphic telemetry bar (FPS, Pre/NCNN/Track latencies, chip toggle)   |
|   - Dynamic bilingual switching (English LTR <-> Arabic RTL, 80 COCO classes)     |
|   - Offline Sample Benchmark Mode (bundled real photos)                           |
+-----------------------------------------------------------------------------------+
                                          │  Asynchronous (1500ms timeout)
                                          ▼
+-----------------------------------------------------------------------------------+
|                    Optional Go + Redis Microservice (Docker)                      |
|   - Go 1.22+ Fiber REST & WebSocket streaming                                     |
|   - Redis 7 Streams (yolo:telemetry) & Sorted Sets (yolo:class_counts)            |
+-----------------------------------------------------------------------------------+
```

---

## 2. Key Features

- **Snapdragon 855 Hardware-Targeted**: Optimized specifically for Qualcomm Snapdragon 855 (`SM8150`, Samsung Galaxy Note 10 `SM-N970U`). Realistic inference targets at $640 \times 640$ FP16:
  - **CPU (ARM NEON 4 Big Cores)**: $\ge 12$ FPS
  - **GPU (Vulkan Compute)**: $\ge 20$ FPS
- **Decoupled 60 FPS UI**: Bounding box rendering runs decoupled from neural network inference via exponential moving average (EMA) interpolation.
- **Robust Multi-Object Tracking Engine**:
  - Full 4-state lifecycle: `TENTATIVE` (requires 3 consecutive hits) $\to$ `CONFIRMED` $\to$ `COASTING` (retained up to 30 frames) $\to$ `DELETED` (frame 31).
  - Two-stage association: high-confidence detections first, followed by low-confidence re-linking of coasting tracks to eliminate ID switches on crossing trajectories.
  - Zero dynamic heap allocation per frame (fixed-capacity buffers: max 100 tracks, 100 candidates).
- **Strict Scope Lock**: Standalone, general-purpose computer vision platform. Visually-impaired / assistive audio features are strictly excluded.
- **Bilingual Arabic/English**: Complete 80 COCO classes mapped to high-quality Modern Standard Arabic and English with seamless runtime switching.

---

## 3. Monorepo Directory Layout

```text
C:\dev\object-detector/
├── README.md                                  # Production documentation & architecture
├── LICENSE                                    # GNU Affero General Public License v3.0 (AGPL-3.0)
├── NOTICE                                     # Copyright and attribution notice
├── THIRD_PARTY_LICENSES.md                    # Ultralytics, NCNN, and asset licenses
├── .gitignore                                 # Excludes build/, target/, *.apk, key.properties
├── .cargo/
│   └── config.toml                            # NDK clang linker configuration for aarch64-linux-android
├── .github/
│   └── workflows/
│       └── android_release.yml                # Automated CI build & GitHub Release publisher
├── docs/
│   ├── ADR-001-hybrid-ncnn-rust-ffi.md        # Architecture Decision Record: C++ NCNN + Rust FFI
│   ├── assets_sources.md                      # Provenance & SHA256 hashes of sample photos
│   ├── benchmarks_note10.md                   # Real Snapdragon 855 physical benchmarks
│   └── versions.lock.md                       # Pinned environment & toolchain versions
├── colab_pipeline/
│   ├── export_yolo11_ncnn.py                  # PNNX export executed on Google Colab
│   ├── benchmark_ncnn_colab.py                # PyTorch vs NCNN numeric parity verification
│   └── upload_release_from_colab.sh           # Releases weights/assets to GitHub
├── native_core/
│   ├── CMakeLists.txt                         # Builds libyolo_ncnn.so linking libyolo_rust.a
│   ├── third_party/
│   │   └── ncnn-android-vulkan/               # arm64-v8a NCNN headers & prebuilt libs
│   ├── cpp/
│   │   ├── yolo_ncnn_c_api.h                  # Pure C header & #[repr(C)] structs
│   │   └── yolo_ncnn_runner.cpp               # ARM NEON YUV420->RGB + ncnn::Net forward
│   └── rust/
│       ├── Cargo.toml                         # Workspace definition: ["yolo_core", "yolo_ffi"]
│       ├── yolo_core/                         # Pure Rust: decoder, NMS, tracker (Host-testable)
│       │   ├── Cargo.toml
│       │   ├── src/
│       │   │   ├── lib.rs
│       │   │   ├── types.rs                   # Shared #[repr(C)] memory structs
│       │   │   ├── decoder.rs                 # YOLO11 [84, 8400] anchor-free decoder
│       │   │   ├── nms.rs                     # Class-aware NMS
│       │   │   └── tracker.rs                 # Two-stage kinematic tracking engine
│       │   └── tests/
│       │       └── tracker_invariants.rs      # 4 mandatory tracker unit-test invariants
│       └── yolo_ffi/                          # C-ABI bridge exposing yolo_* entrypoints
│           ├── Cargo.toml                     # crate-type = ["staticlib"] ONLY (libyolo_rust.a)
│           └── src/
│               └── lib.rs
├── mobile_app/
│   ├── pubspec.yaml                           # name: object_detector
│   ├── android/
│   │   ├── gradle.properties                  # workers.max=2, -Xmx2048m, parallel=false
│   │   └── app/
│   │       ├── build.gradle                   # applicationId: com.taha.yoloncnn, pinned NDK
│   │       └── src/main/AndroidManifest.xml   # Camera & Internet permissions
│   ├── assets/
│   │   ├── models/
│   │   │   ├── model.ncnn.param               # PNNX network graph
│   │   │   ├── model.ncnn.bin                 # PNNX FP16 weights (~5.35 MB)
│   │   │   ├── model_metadata.json            # Model contract from real graph
│   │   │   └── coco80_labels_ar_en.json       # Complete 80 COCO classes in AR & EN
│   │   └── samples/
│   │       ├── sample_street.jpg              # Real street photo
│   │       ├── sample_workspace.jpg           # Real office photo
│   │       └── sample_retail.jpg              # Real retail photo
│   └── lib/
│       ├── main.dart
│       ├── core/
│       │   ├── ffi/
│       │   │   ├── native_structs.dart        # Dart structs matching C/Rust memory layout
│       │   │   └── yolo_ncnn_ffi.dart         # Zero-allocation dynamic library loader
│       │   ├── models/
│       │   │   ├── detection_item.dart        # Tracked item with spatial & proximity tier
│       │   │   └── engine_telemetry.dart      # FPS and latency metrics
│       │   ├── l10n/
│       │   │   └── coco_labels_repository.dart# Bilingual class lookup repository
│       │   └── services/
│       │       ├── detection_event_bus.dart   # Neutral broadcast stream
│       │       └── telemetry_sync_client.dart # Non-blocking sync client for Go/Redis
│       └── features/
│           ├── cockpit/
│           │   ├── cockpit_screen.dart        # Main camera + HUD screen
│           │   ├── bbox_hud_painter.dart      # 60 FPS CustomPainter HUD
│           │   └── telemetry_top_bar.dart     # Glassmorphic latency & FPS telemetry bar
│           ├── sample_mode/
│           │   └── sample_benchmark_view.dart # Static image benchmark runner
│           └── settings/
│               └── engine_settings_sheet.dart # Threshold sliders & category filters
└── backend_go_redis/
    ├── docker-compose.yml                     # Redis 7 Alpine + Go telemetry service
    ├── Dockerfile
    ├── go.mod
    └── main.go                                # Go Fiber + WebSocket ingestion & Redis stream
```

---

## 4. Hardware Requirements & Host Constraints

- **Physical Target Hardware**:
  - Model: Samsung Galaxy Note 10 (`SM-N970U`)
  - SoC: Qualcomm Snapdragon 855 (`SM8150` / `msmnile`)
  - Target ABI: `arm64-v8a` strictly (`x86_64` emulators strictly forbidden)
  - Operating System: Android 12 (API level 31/32)
- **Local Host Environment Constraints**:
  - Operating System: Windows 10/11
  - RAM: 16 GB Host
  - Local PyTorch/Ultralytics training or export: **0% local compute** (all model exports run on Google Colab)
  - Gradle Resource Caps: `org.gradle.workers.max=2`, `org.gradle.jvmargs=-Xmx2048m`, `org.gradle.parallel=false`
  - Native Build Caps: `CARGO_BUILD_JOBS=2`, `cmake --build . -- -j2`
  - ISP Upload Limit: $<16$ MB continuous upload; release assets uploaded directly from Colab or CI.

---

## 5. Quickstart & Build Instructions

### Prerequisites
Ensure Flutter 3.38+, Rust 1.99+, Android NDK 28.2+, and CMake 3.22+ are installed.

```powershell
# 1. Step 0: Ensure monorepo resides at clean path
cd C:\dev\object-detector

# 2. Verify ADB connectivity with Galaxy Note 10
adb devices -l

# 3. Run Rust host unit tests (Zero C++ dependency)
cd native_core/rust
cargo test -p yolo_core

# 4. Run Flutter static analysis
cd ../../mobile_app
flutter analyze

# 5. Run application on attached Galaxy Note 10
flutter run -d R58M95PJVZT --release

# 6. (Optional) Run Telemetry Microservice via Docker
cd ../backend_go_redis
docker compose up -d
```

---

## 6. License

This repository is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**. See [LICENSE](LICENSE) for details.
