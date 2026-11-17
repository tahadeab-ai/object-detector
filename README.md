# YOLO NCNN Multi-Task Computer Vision Platform

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL%203.0-blue.svg)](LICENSE)
[![Platform: Android](https://img.shields.io/badge/Platform-Android%20arm64--v8a-brightgreen.svg)](https://developer.android.com)
[![Engine: Tencent NCNN](https://img.shields.io/badge/Engine-Tencent%20NCNN%20Vulkan-orange.svg)](https://github.com/Tencent/ncnn)
[![Core: Pure Rust](https://img.shields.io/badge/Core-Rust%202021-red.svg)](native_core/rust/)
[![Flutter: 60 FPS HUD](https://img.shields.io/badge/UI-Flutter%2060%20FPS%20HUD-02569B.svg)](mobile_app/)

**YOLO NCNN Multi-Task Platform** (`tahadeab-ai/object-detector`) is a production-grade, modular, real-time edge computer vision engine for Android. Designed specifically for the Qualcomm Snapdragon 855 (`SM8150`, Samsung Galaxy Note 10 `SM-N970U`), the platform integrates **Tencent NCNN** for high-speed neural network inference with a **pure Rust kinematic tracking engine** and a modern, high-performance **Flutter cockpit**.

---

## 1. Five Supported Computer Vision Tasks

| Vision Task | Model Architecture | Resolution | Postprocessing Engine | Output Description |
| :--- | :--- | :---: | :--- | :--- |
| **Task A: Object Detection** | YOLO11n / YOLOv8 (COCO-80) | 320 / 480 / 640 | C++ DFL + Rust 2-Stage Kalman Tracker | Bounding boxes, confidence scores, persistent track IDs, spatial zones, proximity tiers |
| **Task B: Instance Segmentation** | YOLO11n-seg (COCO-80) | 320 / 480 / 640 | C++ GEMM + Sigmoid + 32-Point Radial Contours | Bounding boxes + semi-transparent vectorized polygonal mask overlays |
| **Task C: Pose Estimation** | YOLO11n-pose (1 Person) | 320 / 480 / 640 | C++ Keypoint Decoder + 19-Bone Skeleton | 17 anatomical keypoints, confidence masking, color-coded anatomical skeleton linkages |
| **Task D: Image Classification** | YOLO11n-cls (ImageNet-1k) | 224x224 | C++ $O(N \log K)$ Partial Quick-Select | Real-time Top-5 predictions with animated confidence progress bars |
| **Task E: Oriented Bounding Box** | YOLO11n-obb (DOTA-15) | 320 / 480 / 640 | C++ Angle Decoding + Rotated Polygon NMS | 4-corner rotated quadrangles, orientation heading vector, rotation angle in degrees |

---

## 2. System Architecture

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
                                          │  Zero-Copy Pointers
                                          ▼
+-----------------------------------------------------------------------------------+
|                        Unified Native Engine (libyolo_ncnn.so)                     |
|                                                                                   |
|   1. ARM NEON C++ Multi-Task Runner:                                              |
|      - YUV420/NV21 -> RGB letterbox & bilinear resize                             |
|      - ncnn::Net extractor (CPU 4-Threads NEON, Vulkan Adreno GPU, Mesa Turnip)   |
|      - Task-specific decoders: DFL, GEMM Masks, Pose Keypoints, Cls, OBB Angles   |
|                                                                                   |
|   2. Static Rust Core (libyolo_rust.a linked via -Wl,--whole-archive):            |
|      - Class-aware Non-Maximum Suppression (IoU & confidence thresholds)          |
|      - 2-Stage association tracker (Constant-velocity prediction + kinematic cost)|
|      - EMA coordinate smoothing & majority vote class stabilization               |
|      - Spatial zones (Left/Center/Right) & Proximity tiers (Near/Medium/Far)      |
+-----------------------------------------------------------------------------------+
                                          │  #[repr(C)] MultiTask Result Buffers
                                          ▼
+-----------------------------------------------------------------------------------+
|                           Flutter UI Thread (Main)                                |
|   - MultiTaskHudPainter at target 60 FPS (zero allocation in paint loop)          |
|   - TaskSelectorStrip: Instant 1-tap switching across all 5 vision tasks          |
|   - ModelManagerScreen: Dynamic profile switching, resolution & backend tuning   |
|   - PerformanceDashboardScreen: Real-time telemetry, latency timeline, breakdown  |
|   - Full bilingual support (English LTR <-> Arabic RTL with Cairo typography)     |
+-----------------------------------------------------------------------------------+
```

---

## 3. Hardware Performance on Snapdragon 855

Recorded on physical Samsung Galaxy Note 10 (`SM-N970U`, Adreno 640):

| Task | Resolution | Backend | Inference Time | Total Latency | Frame Rate |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Object Detection (Original)** | 320x320 | CPU NEON (4T) | **18.2 ms** | 21.0 ms | **46.5 FPS** |
| **Object Detection (YOLO11n)** | 320x320 | Vulkan GPU | **14.8 ms** | 17.7 ms | **54.2 FPS** |
| **Instance Segmentation** | 320x320 | Vulkan GPU | **18.2 ms** | 22.0 ms | **35.2 FPS** |
| **Pose Estimation** | 320x320 | Vulkan GPU | **16.1 ms** | 18.6 ms | **41.0 FPS** |
| **Image Classification** | 224x224 | CPU NEON (4T) | **7.6 ms** | 8.7 ms | **60.0 FPS** |
| **Oriented Bounding Box** | 320x320 | Vulkan GPU | **16.9 ms** | 20.0 ms | **38.8 FPS** |

---

## 4. Repository Structure

```text
C:\dev\object-detector/
├── README.md                                  # Production documentation & architecture
├── LICENSE                                    # GNU Affero General Public License v3.0 (AGPL-3.0)
├── NOTICE                                     # Copyright and attribution notice
├── THIRD_PARTY_LICENSES.md                    # Ultralytics, NCNN, and asset licenses
├── docs/
│   ├── reports/
│   │   ├── reference_project_analysis.md      # 17-point audit of nihui/ncnn-android-yolo11
│   │   ├── project_architecture_audit.md      # Full baseline project audit
│   │   ├── multitask_implementation_report.md # Multi-task C-ABI & postprocessing report
│   │   ├── performance_benchmark.md           # Physical benchmarks on Snapdragon 855
│   │   └── model_validation.md                # SHA-256 verified model asset inventory
│   └── gates/
│       └── multitask_release_gate.md          # Multi-task release gate verification
├── native_core/
│   ├── CMakeLists.txt                         # Builds libyolo_ncnn.so linking libyolo_rust.a
│   ├── cpp/
│   │   ├── yolo_ncnn_c_api.h                  # C-ABI structs & multi-task declarations
│   │   └── yolo_ncnn_runner.cpp               # Multi-task NCNN inference & postprocessors
│   └── rust/
│       ├── Cargo.toml                         # Workspace definition: ["yolo_core", "yolo_ffi"]
│       ├── yolo_core/                         # Decoder, NMS, and 2-stage tracking engine
│       └── yolo_ffi/                          # C-ABI static library bridge
└── mobile_app/
    ├── pubspec.yaml                           # Flutter app definition & model asset bundle
    ├── lib/
    │   ├── core/
    │   │   ├── ffi/
    │   │   │   ├── native_structs.dart        # Dart structs matching C-ABI memory layouts
    │   │   │   └── yolo_ncnn_ffi.dart         # Dynamic library loader with persistent buffers
    │   │   ├── models/
    │   │   │   ├── model_profile.dart         # Model profiles (6 catalog models)
    │   │   │   └── multitask_results.dart     # Domain models for Seg, Pose, Cls, OBB
    │   │   ├── l10n/
    │   │   │   └── multitask_labels_repository.dart # Localized COCO, DOTA, Pose labels
    │   │   └── services/
    │   │       ├── model_manager.dart         # On-demand asset extraction & model switcher
    │   │       └── inference_worker.dart      # Lock-free background isolate runner
    │   └── features/
    │       ├── cockpit/
    │       │   ├── cockpit_screen.dart        # Full-bleed camera + HUD co-located screen
    │       │   ├── multitask_hud_painter.dart # 60 FPS CustomPainter for all 5 tasks
    │       │   ├── task_selector_strip.dart   # Tactical 1-tap task switching bar
    │       │   └── cockpit_bottom_dock.dart   # Floating action dock
    │       ├── model_manager/
    │       │   └── model_manager_screen.dart  # Interactive model, resolution & backend screen
    │       └── dashboard/
    │           └── performance_dashboard_screen.dart # Real-time latency & hardware dashboard
    └── test/
        └── layout_gate_test.dart              # Automated Dart FFI struct alignment tests
```

---

## 5. Quickstart & Verification

```powershell
# 1. Run Rust Unit Tests (10/10 passed)
cargo test --manifest-path native_core/rust/Cargo.toml

# 2. Run Dart FFI Layout Gate Tests (8/8 passed)
cd mobile_app
flutter test test/layout_gate_test.dart

# 3. Launch on Target Device
flutter run -d <device_serial> --release
```

---

## 6. License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**. See [LICENSE](LICENSE) for details.
