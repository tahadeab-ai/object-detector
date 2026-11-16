# ADR-001: Hybrid Tencent NCNN C++ and Rust FFI Native Core Architecture

**Status**: Accepted  
**Date**: 2026-11-15 (Updated: 2026-11-16)  
**Context**: YOLO NCNN Detector (`tahadeab-ai/object-detector`)  
**Deciders**: Principal Full-Stack & System Architect, Native Lead  

---

## 1. Context & Architectural Problem Statement

The application requires high-performance, real-time object detection (YOLO11n, 80 COCO classes) and multi-object tracking processing live camera frames on mobile Android hardware (Qualcomm Snapdragon 855 / `arm64-v8a`).

Key technical tensions:
1. **Inference Acceleration**: Tencent NCNN provides hand-tuned ARM NEON assembly kernels and Vulkan compute pipelines optimized for mobile SoCs.
2. **Business Logic & Safety**: Multi-object tracking state machines, IoU association, kinematic velocity gating, and bounding box filtering require guaranteed memory safety, zero data races, and zero heap allocation in the frame loop. Rust is optimal for these invariants.
3. **Android Dynamic Linker Hazard (A14)**: Loading multiple native shared libraries (`.so`) with distinct C++ and OpenMP runtimes (`libc++_shared.so`, `libgomp.so`, `libomp.so`) on Android causes symbol duplication, runtime clashes, memory bloat, and unpredictable crashes.

---

## 2. Decision & Technical Rationale

### 2.1 Two-Crate Rust Architecture (`native_core/rust/`)
We decompose the Rust layer into two distinct crates:
1. **`yolo_core` (Pure Rust)**:
   - Zero extern C/C++ dependencies.
   - Contains tensor decoding (`decoder.rs`), class-aware NMS (`nms.rs`), 4-state multi-object tracking (`tracker.rs`), and geometry/spatial zoning (`types.rs`).
   - Compiles and runs 100% natively on host MSVC/GNU toolchains for rapid, deterministic unit testing (`cargo test -p yolo_core`).
2. **`yolo_ffi` (C-ABI Bridge)**:
   - Configured strictly as `crate-type = ["staticlib"]` ONLY (emitting `libyolo_rust.a`).
   - Strictly forbids `cdylib` to prevent generating a second dynamic shared library (`libyolo_rust.so`).
   - Exposes zero-allocation C-ABI entrypoints to the C++ runner.

### 2.2 Whole-Archive Static Linking
In `native_core/CMakeLists.txt`, `libyolo_rust.a` is linked into the shared library using:
```cmake
-Wl,--whole-archive "${YOLO_RUST_LIB}" -Wl,--no-whole-archive
```
**Rationale**: By default, the GNU/LLVM linker strips unreferenced static library symbols during shared library creation. Because the C-ABI functions (`yolo_engine_init`, `yolo_engine_forward_yuv420`, etc.) are consumed dynamically via Dart FFI at runtime, whole-archive inclusion ensures that every exported symbol is retained in `libyolo_ncnn.so` without dead-code stripping.

### 2.3 Single Shared Library & OpenMP/STL Unification
1. Exactly **ONE** shared library is produced: `libyolo_ncnn.so`.
2. OpenMP is linked statically (`-fopenmp -static-openmp`) into `libyolo_ncnn.so`, preventing any duplicate OpenMP runtime dependencies.
3. Uses standard Android NDK `c++_shared` STL.
4. An NDK 28 compatibility shim (`std::__ndk1::__hash_memory`) bridges prebuilt NCNN glslang libraries without linking issues.

### 2.4 C-ABI Layout & Alignment Gate
To guarantee zero-copy ABI alignment between C++, Rust, and Dart FFI:
- `sizeof(YoloDetectionBox) == 40`, `alignof(YoloDetectionBox) == 4`
- `sizeof(YoloFrameResult) == 4024`, `alignof(YoloFrameResult) == 4`
Enforced by compile-time `static_assert` in C++ and `const _: () = { assert!(...) };` in Rust.

---

## 3. Scope Boundary & Historical Context

This project is a standalone, general-purpose computer vision platform (YOLO NCNN Detector).
Any legacy assistive, visually-impaired, TTS, or audio cooldown mechanisms from earlier prototype iterations (e.g. Project 1/OmniSight prototypes) are explicitly superseded and out-of-scope.
No assistive audio, speech synthesis (TTS), or accessibility cooldown timers exist in this repository.

---

## 4. Consequences & Verification Proof

- **Linker Output**: Verified via `llvm-nm.exe -D --defined-only`: all `yolo_engine_*` entrypoints are exported with `T` (text) visibility.
- **Zero Artifact Leaks**: Exactly ONE `.so` file (`libyolo_ncnn.so`, ~15.1 MB) exists in the build output; `libyolo_rust.so` count is zero.
- **Unit Testing Speed**: 9 host tests in `yolo_core` execute in 0.01 seconds without emulator or Android NDK runtime overhead.
