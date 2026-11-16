# ADR-001: Hybrid Tencent NCNN C++ and Rust FFI Native Core Architecture

**Status**: Accepted  
**Date**: 2026-11-15  
**Context**: YOLO NCNN Detector (`tahadeab-ai/object-detector`)  
**Deciders**: System Architect, Native Lead  

---

## 1. Context & Problem Statement

The application requires high-performance, real-time object detection (YOLO11n, 80 COCO classes) and multi-object tracking processing camera frames on Android hardware (Snapdragon 855 / arm64-v8a).
Key challenges:
1. **Inference Backend**: Tencent NCNN provides industry-leading ARM NEON and Vulkan GPU acceleration on mobile chipsets, with pre-compiled optimized kernels.
2. **Business Logic & Safety**: Multi-object tracking state machines, IoU association, kinematic velocity gating, and bounding box filtering require memory safety and zero data races. Rust excels at deterministic concurrency and zero-cost abstractions.
3. **Android Shared Library Footprint (A14)**: Loading multiple native dynamic libraries (`.so`) with independent C++ runtimes (`libc++_shared.so` / `libgnustl`) and OpenMP runtimes (`libgomp.so` / `libomp.so`) causes dynamic symbol collisions, undefined behavior, and memory bloat on Android.

---

## 2. Decision

We adopt a **Unified Single Native Shared Library** architecture:
1. **Rust Crate `yolo_ffi`**:
   - Configured with `crate-type = ["staticlib"]` ONLY.
   - Compiles to `libyolo_rust.a` for `aarch64-linux-android`.
   - Never emitted as a separate dynamic shared library (`cdylib`).
2. **Native C++ Engine & CMake**:
   - Links Tencent NCNN statically (`libncnn.a`).
   - Links the Rust static library (`libyolo_rust.a`).
   - Links Android NDK OpenMP statically.
   - Emits exactly ONE public dynamic shared library: `libyolo_ncnn.so`.
3. **Exported C-ABI Surface**:
   - Exports strictly 7 C-ABI symbols (`yolo_engine_init`, `yolo_engine_forward_yuv420`, `yolo_engine_reset_tracker`, `yolo_engine_destroy`, etc.) with hidden internal visibility.
   - Validated via `llvm-nm` symbol audit to verify zero unversioned dynamic leaks.

---

## 3. Scope Boundary & Historical Context

This project is a standalone, general-purpose computer vision platform (YOLO NCNN Detector).
Any legacy assistive, visually-impaired, TTS, or audio cooldown mechanisms from earlier prototype iterations (e.g. Project 1/OmniSight prototypes) are explicitly superseded and out-of-scope.
No assistive audio, speech synthesis (TTS), or accessibility cooldown timers exist in this repository.

---

## 4. Consequences

- **Positive**: Eliminates runtime symbol collisions between OpenMP and STL.
- **Positive**: Guarantees zero-copy frame handoff from C++ NCNN output to Rust tracker.
- **Positive**: Produces a clean, single-binary distribution in Flutter APK (`lib/arm64-v8a/libyolo_ncnn.so`).
- **Negative**: Requires cross-compilation orchestration where Rust `cargo build --target aarch64-linux-android` runs before CMake links the shared library.
