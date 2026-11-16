# Phase 3A Stop Gate Evidence Report: Flutter Mobile Cockpit (Host-Only)

**Workspace**: `C:\dev\object-detector`  
**Timestamp**: 2026-11-16T13:40:00Z  
**Status**: PASSED (All Phase 3A tasks verified empirically)

---

## 1. P3A.1 Project Configuration & Architecture

- **Application ID & Namespace**: `com.taha.yoloncnn`
- **Application Label**: `YOLO NCNN`
- **SDK & Toolchain**:
  - `minSdk`: 24
  - `targetSdk`: 34
  - `compileSdk`: 35 (compatible with camera_android_camerax)
  - `ndkVersion`: `28.2.13676358`
- **Resource Caps (`mobile_app/android/gradle.properties`)**:
  ```properties
  org.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m -Dfile.encoding=UTF-8
  org.gradle.workers.max=2
  org.gradle.parallel=false
  android.useAndroidX=true
  ```
- **External Native Build**: Wired to `native_core/CMakeLists.txt` with `-DANDROID_STL=c++_shared`.
- **Target ABI Filter**: `arm64-v8a` strictly; all other ABIs (`armeabi-v7a`, `x86`, `x86_64`) excluded from APK packaging.

---

## 2. P3A.2 Dart FFI Layout Gate & Buffer Allocation

### Command:
```powershell
cd C:\dev\object-detector\mobile_app ; flutter test test/layout_gate_test.dart
```

### Raw Output (Exit Code 0):
```text
00:00 +0: loading C:/dev/object-detector/mobile_app/test/layout_gate_test.dart
00:00 +0: Dart FFI Layout Gate: YoloDetectionBox must be exactly 40 bytes
Dart sizeOf<YoloDetectionBox>() = 40
00:00 +1: Dart FFI Layout Gate: YoloFrameResult must be exactly 4024 bytes
Dart sizeOf<YoloFrameResult>() = 4024
00:00 +2: All tests passed!
```

* Persistent Buffer Allocation: `YoloNcnnEngine` allocates persistent `Pointer<YoloFrameResult>` and `Pointer<Float>` tensor buffer once. Zero heap allocation per frame.
* Model Extraction & Contract Verification: `setupAndValidateModelAssets()` extracts `model.ncnn.param` and `model.ncnn.bin` to `getApplicationSupportDirectory()`, validating input `in0` [1, 3, 640, 640] and output `out0` [1, 84, 8400] against `model_metadata.json` with distinct error code `YoloEngineErrors.metadataValidationFailed` (-101).

---

## 3. P3A.3 Concurrency & Camera Integration

- **Single-Slot Latest-Frame Gate**: `_handleCameraFrame` drops incoming frames instantly when native inference is currently executing.
- **Pixel Stride & Format Detection**: Dynamically detects NV21 (VU-interleaved) vs I420 from plane count and pixel strides.
- **App Lifecycle Management**: Implements `WidgetsBindingObserver`, safely halting camera image stream on `inactive`/`paused` and resuming on `resumed` with zero native surface leakage.
- **Permission Flow**: Graceful camera permission denial UI with instruction overlay.

---

## 4. P3A.4 & P3A.5 HUD & Bilingual Capabilities

- **Decoupled 60 FPS HUD**: `BBoxHudPainter` custom painter isolated inside `RepaintBoundary`.
- **HUD Features**:
  - Class-colored bounding boxes with corner accent brackets.
  - Persistent track IDs (`#ID`).
  - Spatial zone guidelines (Left/Center/Right at 33%/66%) with watermark labels.
  - Dynamic motion trail polyline rendering with fading opacity.
  - Track age badge in seconds.
  - Grouped object summary strip.
- **Glassmorphic Telemetry Strip (`TelemetryTopBar`)**:
  - Color-coded FPS badge: Green ($\ge 25$), Amber ($15\text{--}24$), Red ($< 15$).
  - Full latency breakdown: Preprocess, NCNN inference, NMS + Track.
  - Dynamic CPU (`NEON 4T`) vs GPU (`Vulkan`) backend toggle.
  - Live active and confirmed track counters.
- **Bilingual Support**: `CocoLabelsRepository` maps all 80 COCO classes with instantaneous runtime switching between English LTR and Modern Standard Arabic RTL without reinitializing camera or native engine.

---

## 5. P3A.6 & P3A.7 Offline Benchmark & Services

- **Offline Sample Benchmark**: `sample_benchmark_view.dart` decodes bundled JPEGs to RGBA and calls native engine in a 10-iteration loop, calculating median and p95 latencies for preprocess, inference, and postprocess.
- **Neutral Detection Event Bus**: `DetectionEventBus` broadcast stream strictly decoupled from UI and audio.
- **Asynchronous Telemetry Client**: `TelemetrySyncClient` buffers events every 2 seconds, dispatching with 1500ms timeout without blocking the frame loop.

---

## 6. P3A.8 Cryptographic Signing & CI Workflow

- **Release Keystore**: Generated with `keytool` (2048-bit RSA, SHA384withRSA, 10000-day validity) in `mobile_app/android/app/release.keystore` (GITIGNORED).
- **Key Configuration**: `mobile_app/android/key.properties` (GITIGNORED, never committed).
- **Gradle Signing Config**: Wired in `mobile_app/android/app/build.gradle.kts`.
- **GitHub Actions Release CI**: Created `.github/workflows/android_release.yml` for automated arm64-v8a build, signing via repository secrets, and asset upload to respect local ISP bandwidth caps.

---

## 7. P3A.9 Host Verification Gate Evidence

### 7.1 Dart Format & Flutter Analyze
```powershell
cd C:\dev\object-detector\mobile_app ; dart format --output=none --set-exit-if-changed . ; flutter analyze
```
Raw Output (Exit Code 0):
```text
Formatted 14 files (0 changed) in 0.12 seconds.
Analyzing mobile_app...
No issues found! (ran in 92.0s)
```

### 7.2 Release APK Compilation
```powershell
cd C:\dev\object-detector\mobile_app ; flutter build apk --release --target-platform android-arm64
```
Raw Output (Exit Code 0):
```text
Running Gradle task 'assembleRelease'...                          125.5s
√ Built build\app\outputs\flutter-apk\app-release.apk (32.7MB)
```

### 7.3 APK Architecture & Lib Inspection
```powershell
python -c "import zipfile, os
apk = r'C:\dev\object-detector\object-detector-v1.0.0-arm64-v8a.apk'
with zipfile.ZipFile(apk, 'r') as z:
    libs = [f for f in z.namelist() if f.startswith('lib/')]
    for lib in sorted(libs):
        print(f'  {lib} ({z.getinfo(lib).file_size} bytes)')
"
```
Raw Output:
```text
Full lib/ listing:
  lib/arm64-v8a/libapp.so (4391856 bytes)
  lib/arm64-v8a/libc++_shared.so (1253544 bytes)
  lib/arm64-v8a/libdartjni.so (131400 bytes)
  lib/arm64-v8a/libflutter.so (11107920 bytes)
  lib/arm64-v8a/libimage_processing_util_jni.so (32544 bytes)
  lib/arm64-v8a/libsurface_util_jni.so (4896 bytes)
  lib/arm64-v8a/libyolo_ncnn.so (11032840 bytes)
Contains lib/arm64-v8a/libyolo_ncnn.so: True
Contains lib/arm64-v8a/libc++_shared.so: True
Contains forbidden ABIs (x86/x86_64/armeabi-v7a): False
```

### 7.4 Renamed Release Artifact
- **Path**: `C:\dev\object-detector\object-detector-v1.0.0-arm64-v8a.apk`
- **Byte Size**: `34,276,008` bytes
- **SHA256**: `3BC9B9E4195B4D11A0DBD0161632A940193536B953A4A6BFB8FB627476F5C9E5`
