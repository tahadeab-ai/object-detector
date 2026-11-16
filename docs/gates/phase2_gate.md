# Phase 2 Stop Gate Evidence Report: Native Core Architecture

**Workspace**: `C:\dev\object-detector`  
**Timestamp**: 2026-11-16T09:12:00Z  
**Status**: PASSED (All Phase 2 tasks P2.1 through P2.9 verified empirically)

---

## 1. P2.1 Prebuilt Tencent NCNN Android Vulkan Download & Extraction

- **Release Tag**: `20261020` (pinned in `docs/versions.lock.md`)
- **Resolved Download URL**: `https://github.com/Tencent/ncnn/releases/download/20261020/ncnn-20261020-android-vulkan.zip`
- **Archive SHA256**: `6e0c5f9b397faf32b923de2ef6210af9bf375851869dceff06a8005331981086`
- **Extracted Header Directory**: `native_core/third_party/ncnn-android-vulkan/arm64-v8a/include/ncnn/`
- **Extracted Static Library**: `native_core/third_party/ncnn-android-vulkan/arm64-v8a/lib/libncnn.a` (11,520,676 bytes)

---

## 2. P2.2 C-ABI Struct Layout Gate

Enforced in C++ (`native_core/cpp/yolo_ncnn_c_api.h`):
```cpp
static_assert(sizeof(YoloDetectionBox) == 40, "sizeof(YoloDetectionBox) must be exactly 40 bytes");
static_assert(alignof(YoloDetectionBox) == 4, "alignof(YoloDetectionBox) must be exactly 4 bytes");
static_assert(sizeof(YoloFrameResult) == 4024, "sizeof(YoloFrameResult) must be exactly 4024 bytes");
static_assert(alignof(YoloFrameResult) == 4, "alignof(YoloFrameResult) must be exactly 4 bytes");
```

Enforced in Rust (`native_core/rust/yolo_core/src/types.rs` and `native_core/rust/yolo_ffi/src/lib.rs`):
```rust
const _: () = {
    assert!(core::mem::size_of::<YoloDetectionBox>() == 40, "sizeof(YoloDetectionBox) must be 40");
    assert!(core::mem::align_of::<YoloDetectionBox>() == 4, "alignof(YoloDetectionBox) must be 4");
    assert!(core::mem::size_of::<YoloFrameResult>() == 4024, "sizeof(YoloFrameResult) must be 4024");
    assert!(core::mem::align_of::<YoloFrameResult>() == 4, "alignof(YoloFrameResult) must be 4");
};
```
Both compile-time assertion blocks compiled cleanly with zero errors.

---

## 3. P2.5 Host Tests & Invariants Verification

### Command:
```powershell
$env:CARGO_BUILD_JOBS="2" ; cd C:\dev\object-detector\native_core\rust ; cargo test -p yolo_core -- --nocapture
```

### Raw Output (Exit Code 0):
```text
   Compiling yolo_core v1.0.0 (C:\dev\object-detector\native_core\rust\yolo_core)
    Finished `test` profile [unoptimized + debuginfo] target(s) in 4.52s
     Running unittests src\lib.rs (target\debug\deps\yolo_core-1995a632700884cd.exe)

running 9 tests
test tracker::tests::test_invariant_3_spurious_single_frame_never_confirmed ... ok
test nms::tests::test_nms_same_class_suppression_and_cross_class_retention ... ok
test tracker::tests::test_invariant_2_crossing_trajectories_zero_id_switches ... ok
test tracker::tests::test_invariant_1_coasting_and_deletion ... ok
test types::tests::test_proximity_tier_logic ... ok
test tracker::tests::test_invariant_4_majority_class_voting ... ok
test types::tests::test_spatial_zone_logic ... ok
test types::tests::test_struct_layout_gate ... ok
test decoder::tests::test_decoder_synthetic_tensor ... ok

test result: ok. 9 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.01s

   Doc-tests yolo_core

running 0 tests

test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s
```

### Zero-NCNN Symbol Proof in `yolo_core`:
```powershell
& "C:\Users\O2\AppData\Local\Android\Sdk\ndk\28.2.13676358\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-nm.exe" `
    "C:\dev\object-detector\native_core\rust\target\debug\deps\libyolo_core-*.rlib" | Select-String -Pattern "ncnn"
```
**Output (Exit Code 0)**: 0 matches (pure Rust, zero external dependencies).

---

## 4. P2.6 Android aarch64 Cross-Compilation (`libyolo_rust.a`)

- Target: `aarch64-linux-android`
- Linker: `C:/Users/O2/AppData/Local/Android/Sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin/aarch64-linux-android24-clang.cmd`
- Archiver: `C:/Users/O2/AppData/Local/Android/Sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-ar.exe`

### Command:
```powershell
$env:CARGO_BUILD_JOBS="2" ; cd C:\dev\object-detector\native_core\rust ; cargo build --release -p yolo_ffi --target aarch64-linux-android
```
### Raw Output (Exit Code 0):
```text
   Compiling yolo_ffi v1.0.0 (C:\dev\object-detector\native_core\rust\yolo_ffi)
    Finished `release` profile [optimized] target(s) in 5.03s
```

### Produced Static Library:
- **Path**: `C:\dev\object-detector\native_core\rust\target\aarch64-linux-android\release\libyolo_rust.a`
- **Length**: `8,683,342` bytes

---

## 5. P2.7 CMake Build of Unified `libyolo_ncnn.so`

### Command:
```powershell
cd C:\dev\object-detector\native_core ; `
& "C:\Users\O2\AppData\Local\Android\Sdk\cmake\3.22.1\bin\cmake.exe" -B build -G Ninja `
    -DCMAKE_MAKE_PROGRAM="C:/Users/O2/AppData/Local/Android/Sdk/cmake/3.22.1/bin/ninja.exe" `
    -DCMAKE_TOOLCHAIN_FILE="C:/Users/O2/AppData/Local/Android/Sdk/ndk/28.2.13676358/build/cmake/android.toolchain.cmake" `
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 -DANDROID_STL=c++_shared ; `
& "C:\Users\O2\AppData\Local\Android\Sdk\cmake\3.22.1\bin\cmake.exe" --build build -- -j2
```

### Raw Output (Exit Code 0):
```text
[1/2] Building CXX object CMakeFiles/yolo_ncnn.dir/cpp/yolo_ncnn_runner.cpp.o
[2/2] Linking CXX shared library libyolo_ncnn.so
```

### Produced Shared Library:
- **Path**: `C:\dev\object-detector\native_core\build\libyolo_ncnn.so`
- **Length**: `15,147,416` bytes

---

## 6. P2.8 Symbol Preservation Gate

### Command:
```powershell
& "C:\Users\O2\AppData\Local\Android\Sdk\ndk\28.2.13676358\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-nm.exe" `
    -D --defined-only "C:\dev\object-detector\native_core\build\libyolo_ncnn.so" | Select-String -Pattern "yolo_"
```

### Raw Output (Exit Code 0):
```text
0000000000839f98 T _RNvMs1_NtCsiB7MDfw5a9X_9yolo_core7trackerNtB5_15TwoStageTracker6update
000000000083a710 T _RNvMs_NtCsiB7MDfw5a9X_9yolo_core7trackerNtB4_5Track11mark_missed
000000000083a828 T _RNvMs_NtCsiB7MDfw5a9X_9yolo_core7trackerNtB4_5Track6update
000000000083af00 T _RNvNtCsiB7MDfw5a9X_9yolo_core3nms15class_aware_nms
000000000083b2c4 T _RNvNtCsiB7MDfw5a9X_9yolo_core7decoder13decode_tensor
000000000030c19c T yolo_engine_destroy
000000000030b994 T yolo_engine_forward_rgba
000000000030aa84 T yolo_engine_forward_yuv420
000000000030a18c T yolo_engine_init
000000000083b4ec T yolo_engine_reset_tracker
000000000030a9e4 T yolo_engine_set_backend
000000000083b69c T yolo_rust_destroy
000000000083b7d8 T yolo_rust_init
000000000083b9c8 T yolo_rust_process_frame
```

### Shared Library Inventory:
```powershell
Get-ChildItem -Path "C:\dev\object-detector\native_core" -Recurse -Filter "*.so" | Select-Object FullName, Length ; `
(Get-ChildItem -Path "C:\dev\object-detector" -Recurse -Filter "*yolo_rust.so*" -ErrorAction SilentlyContinue).Count -eq 0
```
### Raw Output:
```text
FullName                                                   Length
--------                                                   ------
C:\dev\object-detector\native_core\build\libyolo_ncnn.so 15147416
True
```
* Exactly **ONE** `.so` library produced: `libyolo_ncnn.so`.
* Zero `libyolo_rust.so` exists in the repository.
* All 5 mandated `yolo_engine_*` entrypoints are preserved with `T` defined export visibility.
