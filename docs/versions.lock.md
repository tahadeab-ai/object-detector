# Toolchain & Dependency Versions Lockfile

**Project**: YOLO NCNN Detector (`tahadeab-ai/object-detector`)  
**Generated At**: 2026-11-15T20:10:00Z  
**Governance Policy**: F2 / RESTORE-6 (Exact environment versions; zero ranges, wildcards, or estimated versions).

---

## 1. Local Development Host (Windows 11)

| Subsystem / Tool | Pinned Version | Path / Executable | Status |
| :--- | :--- | :--- | :--- |
| **Operating System** | `Windows 11 Enterprise (Build 26100.3194)` | `C:\Windows\System32\` | VERIFIED |
| **Processor / Host CPU** | Intel Core i7 7th Gen (x86_64) | Physical Host | VERIFIED |
| **Host Memory (RAM)** | 16.0 GB | Physical Host | VERIFIED |
| **Host GPU** | NVIDIA Quadro P600 | Physical Host | VERIFIED |
| **Git** | `2.52.0.windows.1` | `C:\Program Files\Git\cmd\git.exe` | VERIFIED |
| **GitHub CLI (gh)** | `2.67.0` | `C:\Program Files\GitHub CLI\gh.exe` | VERIFIED (User: `tahadeab-ai`) |
| **Docker Engine** | `29.5.3 (build d1c06ef)` | `C:\Program Files\Docker\Docker\resources\bin\docker.exe` | VERIFIED |
| **Docker Compose** | `v5.1.4` | `docker compose` | VERIFIED |
| **Host Python Utility** | `3.11.9` | `C:\Users\O2\AppData\Local\Programs\Python\Python311\python.exe` | VERIFIED |

---

## 2. Mobile & Native Cross-Compilation Toolchains

| Toolchain / SDK | Pinned Version | Location / Source | Notes / Build Caps |
| :--- | :--- | :--- | :--- |
| **Flutter SDK** | `3.38.3` (Channel `stable`) | `C:\src\flutter\` | Target platform: `android-arm64` |
| **Dart SDK** | `3.10.1` (DevTools `2.51.1`) | `C:\src\flutter\bin\cache\dart-sdk\` | Null safety sound mode |
| **Rust Compiler (rustc)** | `1.99.1 (58cf8f9c3 2026-10-13)` | `C:\Users\O2\.cargo\bin\rustc.exe` | Linker: MSVC VC 14.31 |
| **Cargo Package Manager** | `1.99.1 (5f94df478 2026-08-27)` | `C:\Users\O2\.cargo\bin\cargo.exe` | `CARGO_BUILD_JOBS=2` |
| **Rust Installed Targets** | `aarch64-linux-android`<br>`x86_64-pc-windows-msvc` | `rustup target list` | Verified via MSVC test compile |
| **Android SDK API Levels** | Platforms `31`, `33`, `34`, `35`, `36` | `C:\Users\O2\AppData\Local\Android\Sdk` | `compileSdkVersion = 35`<br>`targetSdkVersion = 34` |
| **Android NDK** | `28.2.13676358` | `C:\Users\O2\AppData\Local\Android\Sdk\ndk\28.2.13676358` | Pinned in `build.gradle` |
| **Android NDK LLVM Tools** | `llvm-nm.exe`, `llvm-ar.exe`, `clang.cmd` | `.../toolchains/llvm/prebuilt/windows-x86_64/bin/` | A14 Symbol audit tool |
| **Android CMake** | `3.22.1-g37088a8-dirty` | `C:\Users\O2\AppData\Local\Android\Sdk\cmake\3.22.1\bin\` | Native build cap: `-j2` |
| **Android Ninja** | `1.10.2` | `C:\Users\O2\AppData\Local\Android\Sdk\cmake\3.22.1\bin\` | Underlying generator |
| **Android Build Tools** | `35.0.0`, `36.1.0` | `C:\Users\O2\AppData\Local\Android\Sdk\build-tools\` | Aapt2, zipalign, apksigner |
| **Java Development Kit** | OpenJDK `21.0.8` | `C:\Program Files\Android\Android Studio\jbr` | Android Studio bundled JBR |
| **Gradle Resource Caps** | `workers.max=2`<br>`jvmargs=-Xmx2048m`<br>`parallel=false` | `mobile_app/android/gradle.properties` | Prevents OOM / host thrashing |

---

## 3. Remote Google Colab Export Pipeline (`colab-mcp`)

| Component | Pinned Version | Execution Environment | Role |
| :--- | :--- | :--- | :--- |
| **Colab Kernel / OS** | `Linux-6.6.159+-x86_64-with-glibc2.39` | Google Cloud Compute (Colab) | Remote export runner |
| **Colab Python Runtime** | `3.13.18` | Colab container | Remote interpreter |
| **PyTorch** | `2.14.1+cpu` | Pip pre-installed | Reference FP32 forward pass |
| **TorchVision** | `0.29.1+cpu` | Pip pre-installed | Image transform utilities |
| **Ultralytics YOLO** | `8.4.214` | Pip installed | YOLO11n source graph (`yolo11n.pt`) |
| **Tencent NCNN (Python)** | `1.0.20261020` | Pip installed | Parity verification runner |
| **PNNX Binary** | `20260526` | Ultralytics / NCNN asset bundle | PyTorch -> NCNN graph compiler |

---

## 4. Deep Learning Model & Runtime Graph Contracts

| Property | Pinned Contract Value | Verification File |
| :--- | :--- | :--- |
| **Base Model Graph** | Ultralytics YOLO11 Nano (`yolo11n.pt`) | `colab_pipeline/export_yolo11_ncnn.py` |
| **Quantization Precision** | FP16 Half-Precision (`half=True`) | `mobile_app/assets/models/model.ncnn.bin` (~5.2 MB) |
| **Input Blob Name** | `in0` | `mobile_app/assets/models/model.ncnn.param` |
| **Output Blob Name** | `out0` | `mobile_app/assets/models/model.ncnn.param` |
| **Input Tensor Shape** | `[1, 3, 640, 640]` | Static PNNX input shape |
| **Output Tensor Shape** | `[1, 84, 8400]` (Row-Major) | Row-major layout (`decoder.rs`) |
| **COCO Classes Count** | `80` (Class IDs `0..79`) | `mobile_app/assets/models/coco80_labels_ar_en.json` |
| **Candidates Per Frame** | `8400` grid locations | Anchor-free detection tensor |
| **Tencent NCNN Native Tag**| `20261020` (`ncnn-20261020-android-vulkan.zip`) | `native_core/third_party/ncnn-android-vulkan/` |
| **Android STL** | `c++_shared` | Bundles `libc++_shared.so` |

---

## 5. Physical Hardware Target

| Property | Target Specification | Raw Hardware Audit |
| :--- | :--- | :--- |
| **Device Model** | Samsung Galaxy Note 10 (`SM-N970U`) | Confirmed via `adb devices -l` |
| **Device Serial Number** | `R58M95PJVZT` | Attached via USB, state `device` |
| **Target Architecture / ABI** | `arm64-v8a` | Strictly enforced in `abiFilters` |
| **SoC / Chipset** | Qualcomm Snapdragon 855 (`SM8150`) | Board `msmnile`, hardware `qcom` |
| **Android OS Version** | Android 12 (SDK API Level 31) | Fingerprint verified |
| **Target Inference Acceptance**| **CPU (ARM NEON 4T)**: $\ge 12$ FPS<br>**GPU (Vulkan)**: $\ge 20$ FPS | Post-60s warmup, 100-frame benchmark |
| **HUD Rendering Target** | $60.0$ FPS (Decoupled CustomPainter) | UI thread decoupled from inference |

---

## 6. Dependency Conflict Assessment

- **Linker / STL Conflicts**: ZERO. OpenMP is linked statically into `libyolo_ncnn.so` ONLY. Rust `yolo_ffi` is compiled strictly as `staticlib` (`libyolo_rust.a`), preventing duplicate STL or OpenMP runtimes (F1, A14).
- **Target ABI Conflicts**: ZERO. Emulator ABIs (`x86`, `x86_64`) are strictly excluded from release packaging (RESTORE-4).
- **NDK Path Space Conflicts**: ZERO. Relocation to `C:\dev\object-detector` eliminates all space characters from the build tree (RESTORE-1).
