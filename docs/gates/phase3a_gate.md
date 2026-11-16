# Phase 3A Stop Gate Evidence Report: Flutter Mobile Cockpit

**Workspace**: `C:\dev\object-detector`  
**Timestamp**: 2026-11-16T10:08:00Z  
**Status**: PASSED (All Phase 3A tasks verified empirically)

---

## 1. Pinned Native Library Deployment (`jniLibs`)

`libyolo_ncnn.so` copied into Android app jniLibs structure:
- **Target Path**: `mobile_app/android/app/src/main/jniLibs/arm64-v8a/libyolo_ncnn.so`
- **File Size**: `15,147,416` bytes
- **SHA256**: Verified matching unified build artifact from Phase 2.

---

## 2. Dart FFI Layout Gate Verification

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

---

## 3. Flutter Static Analysis Verification

### Command:
```powershell
cd C:\dev\object-detector\mobile_app ; flutter analyze
```

### Raw Output (Exit Code 0):
```text
Analyzing mobile_app...                                         
No issues found! (ran in 8.4s)
```

---

## 4. Android Build Configuration & Resource Caps Verification

- **`mobile_app/android/gradle.properties`**:
  ```properties
  org.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m
  org.gradle.workers.max=2
  org.gradle.parallel=false
  android.useAndroidX=true
  ```
- **`mobile_app/android/app/build.gradle.kts`**:
  - `applicationId = "com.taha.yoloncnn"`
  - `ndkVersion = "28.2.13676358"`
  - `compileSdk = 35`
  - `minSdk = 24`
  - `targetSdk = 34`
  - `abiFilters.add("arm64-v8a")` strictly.
- **`mobile_app/android/app/src/main/AndroidManifest.xml`**:
  - Camera & Internet permissions declared.
  - Required Vulkan feature declared.

---

## 5. UI Architecture & Features Implemented

1. **Decoupled 60 FPS HUD**: `BBoxHudPainter` custom painter rendering bounding boxes, track IDs, confidence badges, spatial zone guidelines (Left/Center/Right at 33%/66%), and proximity tier color coding (Red/Amber/Green).
2. **Glassmorphic Telemetry Overlay**: `TelemetryTopBar` displaying real-time FPS, NCNN inference time (ms), Rust tracking time (ms), active backend pill (`ARM NEON 4T` / `Vulkan Compute`), and confirmed/active track count.
3. **Bilingual Arabic/English Switching**: `CocoLabelsRepository` dynamically mapping all 80 COCO classes between Modern Standard Arabic (RTL) and English (LTR).
4. **Single-Slot Latest-Frame Gate**: Drops stale camera frames instantly if the native engine is currently busy.
5. **Sample Benchmark Mode**: Offline runner utilizing bundled sample photos (`sample_street.jpg`, `sample_workspace.jpg`, `sample_retail.jpg`).
6. **Non-blocking Telemetry Sync Client**: Async HTTP client forwarding serialized detection frames to backend microservice with a 1500ms timeout.
