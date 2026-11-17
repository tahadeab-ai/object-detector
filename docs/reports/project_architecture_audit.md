# Primary Project Architecture Audit: `tahadeab-ai/object-detector`

**Report Type**: Baseline Architecture Audit (Phase 0)  
**Document**: `docs/reports/project_architecture_audit.md`  
**Target Device**: Samsung Galaxy Note 10 (`SM-N970U`), Qualcomm Snapdragon 855 (`SM8150`, Adreno 640)  
**Architecture**: `arm64-v8a` strictly  
**Status**: Stable Baseline Audited & Verified

---

## 1. System Inventory & Component Audit

```text
                                  +---------------------------------------+
                                  |            Flutter Mobile UI          |
                                  |     (Bilingual Cockpit, 60 FPS HUD)   |
                                  +---------------------------------------+
                                                      │
                                                      ▼
                                  +---------------------------------------+
                                  |       InferenceWorker Isolate         |
                                  |  (Single-slot gate, frame dropping)   |
                                  +---------------------------------------+
                                                      │ Dart FFI Zero-Alloc
                                                      ▼
                       +─────────────────────────────────────────────────────────────+
                       │               Unified Native C++ Runtime                    │
                       │                   (libyolo_ncnn.so)                         │
                       │                                                             │
                       │   - YUV420 / NV21 Direct Letterbox & Rotate into RGB canvas │
                       │   - NCNN Net Extractor (4-Thread NEON / Vulkan Compute)     │
                       │   - In-memory DFL decoding & tensor buffering               │
                       +─────────────────────────────────────────────────────────────+
                                                      │ C-ABI Pointers
                                                      ▼
                       +─────────────────────────────────────────────────────────────+
                       │                  Static Rust Engine Core                    │
                       │                     (libyolo_rust.a)                        │
                       │                                                             │
                       │   - Anchor-free [1, 84, 8400] output decoder                │
                       │   - Class-aware Non-Maximum Suppression (IoU)               │
                       │   - 2-Stage Multi-Object Association Tracker                │
                       │   - EMA coordinate filtering & majority class vote          │
                       +─────────────────────────────────────────────────────────────+
```

---

## 2. Detailed Audit by Subsystem

### 2.1 Flutter Subsystem
- **Camera Pipeline**:
  - Uses Flutter `camera: 0.11.4` streaming `CameraImage` frames.
  - Formats: Android `ImageFormatGroup.yuv420`.
  - Frame delivery: Streams from camera sensor into `InferenceWorker` via single-slot gate. If the worker isolate is busy processing a previous frame (`_isBusy == true`), incoming frames are dropped immediately without queue accumulation.
- **Isolate Communication**:
  - Dedicated background isolate `InferenceWorker` spawned with `ReceivePort` and `SendPort`.
  - Passes byte buffers (`Uint8List`) for Y, U, V planes along with strides and sensor orientation.
  - Emits `IsolateFrameResult` containing fixed detection array and latency telemetry.
- **Native FFI Bindings**:
  - Zero-heap allocation Dart FFI wrapper `YoloNcnnEngine` (`yolo_ncnn_ffi.dart`).
  - Pre-allocated native structs matching memory layout:
    - `YoloDetectionBox`: exactly 40 bytes, alignof 4.
    - `YoloFrameResult`: exactly 4024 bytes, alignof 4.
  - Verified by runtime gate in `test/layout_gate_test.dart` (Passed).
- **Cockpit UI & CustomPainter**:
  - `CockpitScreen`: Full-bleed camera preview with overlay `BboxHudPainter`.
  - `TelemetryTopBar`: Glassmorphic status bar displaying FPS, NCNN inference latency, tracker latency, object count, and backend selector.
  - `CockpitBottomDock`: Quick tactical actions: Language toggle (AR/EN), Sample benchmark, Torch, Freeze, Settings.
- **Localization**:
  - Full Arabic (RTL) and English (LTR) localization.
  - Typography: Google Cairo font family (`Cairo-Bold.ttf`, `Cairo-SemiBold.ttf`, `Cairo-Regular.ttf`).
  - Complete 80 COCO class translations in `coco_labels_repository.dart`.

### 2.2 C++ Native Subsystem (`native_core/cpp`)
- **Runtime File**: `yolo_ncnn_runner.cpp` (594 lines).
- **NCNN Initialization**:
  - Reads `model.ncnn.param` and `model.ncnn.bin`.
  - Automatically parses input blob name (`in0`) and output blob name (`out0`).
  - Configures CPU powersave mode `ncnn::set_cpu_powersave(2)` targeting the Snapdragon 855 cluster (4 Kryo 485 Gold big cores).
  - Configures FP16 packed storage and arithmetic:
    `use_fp16_packed = true`, `use_fp16_storage = true`, `use_fp16_arithmetic = true`.
- **Backend Selection**:
  - Supports CPU (4 threads) and Vulkan Compute (`ncnn::create_gpu_instance()`, `net.set_vulkan_device(0)`).
  - Implements automatic fallback to CPU if Vulkan load or extraction returns non-zero.
- **Image Preprocessing**:
  - Direct YUV420 to RGB letterbox conversion with sensor rotation (0°, 90°, 180°, 270°) into a fixed 640x640x3 canvas.
  - Zero heap allocation: uses static pre-allocated buffer `g_ctx.rgb_letterbox_buf`.
- **Memory Management**:
  - Static engine context `EngineContext g_ctx` protected by `std::mutex g_engine_mutex`.
  - Zero heap allocations during the active per-frame inference loop.

### 2.3 Rust Subsystem (`native_core/rust`)
- **Crates**:
  - `yolo_core`: Core decoding algorithms, NMS, and multi-object tracker. Zero C++ dependencies.
  - `yolo_ffi`: C-ABI bridge providing `#[no_mangle] pub extern "C" fn yolo_rust_process_frame`.
- **Anchor-Free Decoder**:
  - Decodes `[1, 84, 8400]` raw tensor: `(cx, cy, w, h)` + 80 class scores.
  - Corrects letterbox scale and padding offsets to map detections back to sensor dimensions.
- **Class-Aware NMS**:
  - Groups candidates by class and applies intersection-over-union suppression with configurable threshold.
- **Two-Stage Multi-Object Tracker**:
  - 4-state lifecycle: `TENTATIVE` -> `CONFIRMED` -> `COASTING` -> `DELETED`.
  - Cost matrix combines kinematic distance and box IoU.
  - First-stage association on high-confidence detections; second-stage recovery on coasting tracks.
  - Majority class voting over track history to eliminate flickering class labels.
  - EMA smoothing ($\alpha = 0.65$) on box coordinates.
- **Test Suite**:
  - 9 comprehensive unit tests in `yolo_core` verifying NMS, tracker invariants, spatial zoning, and struct memory layout. (100% Passing).

### 2.4 Assets & Artifacts
- **Model Files**:
  - `mobile_app/assets/models/model.ncnn.param` (22,713 bytes).
  - `mobile_app/assets/models/model.ncnn.bin` (5,350,176 bytes, FP16).
  - Verified SHA-256 in `model_metadata.json`: `18298e4ce44f5c641b634759b2a6f2e8cd00a2c7df6a99c84ad5403cabedb151`.
- **Precompiled Native Binary**:
  - `mobile_app/android/app/src/main/jniLibs/arm64-v8a/libyolo_ncnn.so` (15,156,480 bytes).
  - Links static NCNN Vulkan + OpenMP + `libyolo_rust.a`.

---

## 3. What Works vs. What Needs Improvement

### 3.1 Proven, High-Stability Components (MUST PRESERVE)
1. **Flutter 60 FPS Decoupled HUD**: Bounding box rendering runs smoothly decoupled from inference using CustomPainter.
2. **Rust Tracking Engine**: 2-stage association, coasting retention up to 30 frames, and majority voting provide rock-solid object persistence.
3. **Bilingual Arabic/English UI**: Beautiful Cairo font typography and right-to-left layout.
4. **Isolate Zero-Queue Frame Dropper**: Guarantees zero frame lag and prevents memory bloat under rapid camera streaming.
5. **Snapdragon 855 Optimization**: 4-thread big-core CPU affinity and Vulkan compute fallback.

### 3.2 Key Gaps & Required Improvements
1. **Single-Task Limitation**: The engine currently supports only Object Detection (`[1, 84, 8400]`). There is zero support for Segmentation, Pose, Classification, or OBB.
2. **Hardcoded Buffer Sizes**: Preprocessing and tensor buffers are hardcoded to `640x640x3` and `84x8400`. Multi-task models require dynamic resolutions (e.g. 224 for Cls, 320/480/640 for Det/Seg/Pose, 512/1024 for OBB) and varying output channel shapes.
3. **No Dynamic Model Manager**: The app loads a single hardcoded model on startup. There is no runtime model switcher, task catalog, or memory-safe model unloader.
4. **Postprocessing Separation**: The current pipeline routes all tensors directly to Rust `yolo_rust_process_frame`. Segmentation (GEMM + masks), Pose (keypoint skeletons), Classification (top-K), and OBB (rotated geometry) require specialized C++ postprocessing contracts.
5. **Navigation & Task Selection UI**: The UI currently consists of a single cockpit screen without task navigation tabs or a performance benchmark dashboard.

---

## 4. Phase-by-Phase Evolution Plan

- **Phase 1**: Native Inference Engine modularization (common task runner interface, multi-task dispatch, dynamic resolution buffers).
- **Phase 2**: Implement the 5 vision tasks (Det with Rust tracker preserved, Seg with NCNN GEMM masks, Pose with 17 keypoints, Cls with Top-5, OBB with rotated NMS).
- **Phase 3**: Implement dynamic ModelManager (metadata schema, dynamic asset extraction, safe unloading).
- **Phase 4**: Camera pipeline evaluation (optimized Flutter camera vs. isolated NDK camera prototype).
- **Phase 5**: CPU / Vulkan backend selection with Turnip capability detection and automatic fallback.
- **Phase 6**: Performance profiles (Fast, Balanced, Accuracy).
- **Phase 7**: Modern Flutter multi-task UI (navigation tabs, task HUD painters, performance dashboard, Arabic/English preserved).
- **Phase 8-10**: Benchmarking, quality assurance, documentation, and release APK.

*Audit completed and verified against local workspace.*
