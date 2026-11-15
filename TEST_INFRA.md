# E2E Test Infra: YOLO NCNN Detector (`tahadeab-ai/object-detector`)

## 1. Test Philosophy
- **Requirement-Driven & Opaque-Box**: All test cases derive strictly from `ORIGINAL_REQUEST.md` (Governing Prompt with Amendments A1–A22, RESTORE-1–8, and F1–F9) and user-facing specifications. Tests treat the system and its modules as black boxes accessed only through public interfaces, CLI commands, C-ABI dynamic exports, REST/WebSocket endpoints, and external file contracts.
- **Zero-Fabrication Compliance (RESTORE-3 / A5)**: Tests never mock or fabricate genuine inputs. All test assertions evaluate real data structures, actual file checksums, valid tensor shapes, and live network packets.
- **Four-Tier Testing Methodology**:
  - **Tier 1 — Feature Coverage**: Minimum 5 isolated happy-path tests per feature across all 40 features in the Feature Inventory (200 tests total).
  - **Tier 2 — Boundary & Corner Cases**: Minimum 5 boundary/corner/negative tests per feature exercising extremes, zero/null/overflow values, malformed inputs, and corrupted states (200 tests total).
  - **Tier 3 — Cross-Feature Combinations**: Pairwise and combinatorial integration tests verifying interactions between orthogonal subsystems (e.g., Vulkan GPU backend + Arabic RTL layout + 10 crossing tracks + WebSocket telemetry streaming) (40 tests total).
  - **Tier 4 — Real-World Application Scenarios**: Multi-feature end-to-end operational scenarios simulating real-world usage in surveillance, robotics, mobile benchmarking, and edge IoT (20 scenarios total).
- **Total Suite Scale**: **460 test cases minimum**.

---

## 2. Feature Inventory & Coverage Matrix (40 Features)

| # | Feature Name | Requirement Source | Tier 1 (Count) | Tier 2 (Count) | Tier 3 (Cross) |
|---|--------------|-------------------|:--------------:|:--------------:|:--------------:|
| 1 | Step 0 Monorepo Relocation | RESTORE-1 / A20 | 5 | 5 | ✓ |
| 2 | Git & Remote Repository Setup | A18, A17 | 5 | 5 | ✓ |
| 3 | Early ADB Device Audit | A18, RESTORE-4 / A3 | 5 | 5 | ✓ |
| 4 | Colab PNNX Model Export | R1, RESTORE-5 / A6 | 5 | 5 | ✓ |
| 5 | Colab Numeric Parity Check | A16, F6 | 5 | 5 | ✓ |
| 6 | Model Release Asset Transfer | A18, RESTORE-7 / A12 | 5 | 5 | ✓ |
| 7 | Real Sample Photo Acquisition | F4, RESTORE-7 / A12 | 5 | 5 | ✓ |
| 8 | Pinned Versions Lockfile | A7, F2 | 5 | 5 | ✓ |
| 9 | Rust Two-Crate Workspace Architecture | A13, F1 | 5 | 5 | ✓ |
| 10| YOLO11 Tensor Decoder | A8, §5.1 | 5 | 5 | ✓ |
| 11| Class-Aware Non-Maximum Suppression | A13, §5.1 | 5 | 5 | ✓ |
| 12| 4-State Track Lifecycle State Machine | A22, §4.1 | 5 | 5 | ✓ |
| 13| 2-Stage Association Engine | F8, A22, §4.2 | 5 | 5 | ✓ |
| 14| Track State Invariants (EMA, Velocity, Class Mode) | A22, §4.3 | 5 | 5 | ✓ |
| 15| Zero Heap Allocation Memory Model | A22, §4.4 | 5 | 5 | ✓ |
| 16| Spatial Zone & Proximity Tier Computation | A22, §3.3 | 5 | 5 | ✓ |
| 17| 4 Mandatory Host Unit Tests | A22, FIX-9, §4.6 | 5 | 5 | ✓ |
| 18| C++ NCNN Runner & NEON Preprocessing | A10, §5.2, §7.3 | 5 | 5 | ✓ |
| 19| CMake Shared Library Build (`libyolo_ncnn.so`) | A10, A14, F1 | 5 | 5 | ✓ |
| 20| Symbol Preservation Gate (`llvm-nm`) | A14, §5.3 | 5 | 5 | ✓ |
| 21| Flutter App Scaffolding & Android Caps | FIX-A1, RESTORE-5 | 5 | 5 | ✓ |
| 22| Dedicated Worker Isolate Pipeline | F7, §7.2 | 5 | 5 | ✓ |
| 23| Single-Slot Latest-Frame Gate | F7, §7.2 | 5 | 5 | ✓ |
| 24| Zero-Allocation Dart FFI Bindings | §5.2, §7.2 | 5 | 5 | ✓ |
| 25| Dynamic Metadata Graph Validator | RESTORE-7 / A9, §6.4 | 5 | 5 | ✓ |
| 26| Decoupled 60 FPS CustomPainter HUD | A11, §7.3 | 5 | 5 | ✓ |
| 27| Glassmorphic Telemetry Top Bar | §7.4 | 5 | 5 | ✓ |
| 28| Bilingual COCO Repository (80 classes, AR/EN) | RESTORE-7 / A12, §7.1 | 5 | 5 | ✓ |
| 29| Static Sample Benchmark Mode | F4, §7.4 | 5 | 5 | ✓ |
| 30| Scope Lock Static Grep Verification | FIX-A2, A22, §3.2 | 5 | 5 | ✓ |
| 31| On-Device Hardware Run (`R58M95PJVZT`) | F3, RESTORE-4 / A3 | 5 | 5 | ✓ |
| 32| Go Telemetry Microservice Core | R4, §8.1 | 5 | 5 | ✓ |
| 33| Redis Stream & Sorted Set Analytics | R4, §8.1 | 5 | 5 | ✓ |
| 34| Multi-Stage Docker & Compose Orchestration | R4, §8.1 | 5 | 5 | ✓ |
| 35| Mobile Offline-First Telemetry Sync Client | §8.2 | 5 | 5 | ✓ |
| 36| Release Keystore Generation | F5, §10 (Phase 5) | 5 | 5 | ✓ |
| 37| Release Signed APK Build (`arm64-v8a`) | RESTORE-5, FIX-9 | 5 | 5 | ✓ |
| 38| Snapdragon 855 100-Frame Benchmark Protocol | A19, RESTORE-6 / A11 | 5 | 5 | ✓ |
| 39| 30-Second Field Tracking Benchmark | A22, §4.6 | 5 | 5 | ✓ |
| 40| Multi-Asset Release Package & Checksum Manifest | RESTORE-7, §10 (Phase 5)| 5 | 5 | ✓ |
| **Total** | | | **200** | **200** | **60 (Pairs)** |

---

## 3. Test Architecture & Directory Layout

### 3.1. Directory Structure (`tests/e2e/`)
```text
tests/e2e/
├── run_e2e.py                          # Master test runner orchestrator
├── conftest.py                         # Pytest root configuration and fixtures
├── fixtures/                           # Test fixtures, mock tensors, sample photos
│   ├── tensors/
│   │   ├── valid_output_1_84_8400.bin  # Real FP32 tensor dump from Colab
│   │   ├── corrupted_nan_inf.bin       # Tensor with NaN and Inf values
│   │   ├── empty_zero_tensor.bin       # Zero-filled tensor
│   │   └── malformed_shape_80_8400.bin # Corrupted row count
│   ├── metadata/
│   │   ├── valid_model_metadata.json
│   │   ├── invalid_blob_metadata.json
│   │   └── corrupted_dims_metadata.json
│   ├── labels/
│   │   └── valid_coco80_labels.json
│   └── images/
│       ├── test_street.jpg
│       ├── test_workspace.jpg
│       └── test_retail.jpg
├── harnesses/                          # Native C/Rust & CLI test harnesses
│   ├── c_abi_harness/
│   │   ├── Makefile / CMakeLists.txt
│   │   └── test_c_abi_runner.c         # Tests libyolo_ncnn.so entrypoints directly
│   └── redis_telemetry_client.py       # Standalone client for Go/Redis microservice
├── tier1_features/                     # Tier 1 Feature Coverage Suites (F1–F40)
│   ├── test_f01_f08_preflight.py       # F1-F8: Relocation, git, adb, colab, photos, locks
│   ├── test_f09_f20_native_core.py     # F9-F20: Rust workspace, decoder, NMS, tracker, C-ABI
│   ├── test_f21_f31_mobile_cockpit.py  # F21-F31: Flutter app, isolate, gate, HUD, bilingual, grep
│   ├── test_f32_f35_telemetry.py       # F32-F35: Go service, Redis streams/sets, Docker, sync client
│   └── test_f36_f40_release.py         # F36-F40: Keystore, APK build, Snapdragon bench, checksums
├── tier2_boundaries/                   # Tier 2 Boundary & Negative Suites (B1–B40)
│   ├── test_b01_b08_preflight_edge.py
│   ├── test_b09_b20_native_edge.py
│   ├── test_b21_b31_mobile_edge.py
│   ├── test_b32_b35_telemetry_edge.py
│   └── test_b36_b40_release_edge.py
├── tier3_pairwise/                     # Tier 3 Combinatorial & Cross-Feature Interactions
│   ├── test_p01_backend_x_hud_x_tracks.py
│   ├── test_p02_rtl_x_multi_tracks_x_sync.py
│   ├── test_p03_vulkan_x_sample_x_telemetry.py
│   └── test_p04_concurrency_x_gate_x_relink.py
└── tier4_workloads/                    # Tier 4 Realistic End-to-End Application Scenarios
    ├── test_w01_urban_traffic_surveillance.py
    ├── test_w02_indoor_workspace_tracking.py
    ├── test_w03_retail_shelf_analytics.py
    ├── test_w04_extreme_occlusion_recovery.py
    └── test_w05_soak_thermal_stability.py
```

### 3.2. Test Runner Execution & CLI Interface
The master runner executes all suites or specific tiers with standard pass/fail semantics (exit code 0 for success, non-zero on failure):
```bash
# Run entire 4-tier E2E test suite (460 tests)
python tests/e2e/run_e2e.py --all

# Run specific tier
python tests/e2e/run_e2e.py --tier 1
python tests/e2e/run_e2e.py --tier 2
python tests/e2e/run_e2e.py --tier 3
python tests/e2e/run_e2e.py --tier 4

# Run with verbose logging and JUnit XML report generation
python tests/e2e/run_e2e.py --all --junit-xml build/e2e_results.xml --verbose
```

---

## 4. Tier 1: Feature Coverage Test Specifications (200 Tests)

### Features 1–8: Preflight, Environment & Model Pipeline
- **F1 (Step 0 Relocation)**:
  - T1.1.1: Verify target path `C:\dev\object-detector` contains zero space characters.
  - T1.1.2: Verify path total length is $\le 30$ characters.
  - T1.1.3: Verify write, create, and delete permissions in `C:\dev\object-detector`.
  - T1.1.4: Verify NDK and CMake execute cleanly without space-truncation errors in `C:\dev\object-detector`.
  - T1.1.5: Verify monorepo files exist at `C:\dev\object-detector` and not legacy spaced path.
- **F2 (Git & Remote Setup)**:
  - T1.2.1: Verify `.git` directory exists and git status is clean.
  - T1.2.2: Verify remote `origin` points strictly to `tahadeab-ai/object-detector`.
  - T1.2.3: Verify `LICENSE` contains full AGPL-3.0 text.
  - T1.2.4: Verify `NOTICE` and `THIRD_PARTY_LICENSES.md` exist and reference Ultralytics & NCNN.
  - T1.2.5: Verify `.gitignore` excludes `build/`, `target/`, `key.properties`, `*.keystore`, and `*.apk`.
- **F3 (Early ADB Device Audit)**:
  - T1.3.1: Execute `adb devices -l` and assert presence of device `R58M95PJVZT`.
  - T1.3.2: Verify device ABI reports `arm64-v8a`.
  - T1.3.3: Verify device model reports `SM-N970U` (Samsung Galaxy Note 10).
  - T1.3.4: Verify device hardware platform reports `SM8150` (Snapdragon 855).
  - T1.3.5: Verify battery level is $\ge 20\%$ and temperature is $\le 40^\circ\text{C}$.
- **F4 (Colab PNNX Model Export)**:
  - T1.4.1: Verify `export_yolo11_ncnn.py` exports `model.ncnn.param` and `model.ncnn.bin`.
  - T1.4.2: Verify FP16 weights file size is within expected bounds (~4.8 MB to ~5.8 MB).
  - T1.4.3: Verify PNNX graph input layer is named `in0` with shape `[1, 3, 640, 640]`.
  - T1.4.4: Verify PNNX graph output layer is named `out0` with shape `[1, 84, 8400]`.
  - T1.4.5: Verify dynamic generation of `model_metadata.json` matching exported graph.
- **F5 (Colab Numeric Parity Check)**:
  - T1.5.1: Execute `benchmark_ncnn_colab.py` on `bus.jpg` and assert exit code 0.
  - T1.5.2: Assert PyTorch FP32 vs NCNN FP16 detection count matches at conf=0.25, IoU=0.45.
  - T1.5.3: Assert detected class IDs match between PyTorch and NCNN on `bus.jpg`.
  - T1.5.4: Assert maximum absolute tensor numeric difference is within declared tolerance ($\le 0.15$ for FP16).
  - T1.5.5: Assert parity report outputs explicit `VERDICT: PASS`.
- **F6 (Model Release Asset Transfer)**:
  - T1.6.1: Verify GitHub release `model-v1` exists on `tahadeab-ai/object-detector`.
  - T1.6.2: Verify release contains `model.ncnn.param`, `model.ncnn.bin`, and `model_metadata.json`.
  - T1.6.3: Verify `gh release download` downloads all three files into `mobile_app/assets/models/`.
  - T1.6.4: Verify SHA256 of downloaded local files matches GitHub release asset digests.
  - T1.6.5: Verify files are non-empty and readable.
- **F7 (Real Sample Photo Acquisition)**:
  - T1.7.1: Verify `sample_street.jpg` exists in `mobile_app/assets/samples/` and is valid JPEG.
  - T1.7.2: Verify `sample_workspace.jpg` exists and is valid JPEG.
  - T1.7.3: Verify `sample_retail.jpg` exists and is valid JPEG.
  - T1.7.4: Verify `docs/assets_sources.md` contains source URLs, permissive licenses, and SHA256 digests.
  - T1.7.5: Verify each sample photo yields $\ge 1$ genuine detection when processed by model.
- **F8 (Pinned Versions Lockfile)**:
  - T1.8.1: Verify `docs/versions.lock.md` exists and contains exact pinned version for Flutter (3.38.3).
  - T1.8.2: Verify lockfile contains exact pinned versions for Rustc (1.99.1) and Cargo (1.99.1).
  - T1.8.3: Verify lockfile contains exact NDK version (`28.2.13676358`) and CMake (`3.22.1`).
  - T1.8.4: Verify lockfile contains exact NCNN release tag (`20261020` or equivalent).
  - T1.8.5: Verify lockfile contains zero wildcards (`*`), ranges (`^`, `~`), or "latest" keywords.

### Features 9–20: Native Core, Tracking Engine & C-ABI
- **F9 (Rust Workspace Architecture)**:
  - T1.9.1: Verify `native_core/rust/Cargo.toml` defines workspace members `["yolo_core", "yolo_ffi"]`.
  - T1.9.2: Verify `yolo_core` has zero C/C++ or system dependencies.
  - T1.9.3: Verify `yolo_ffi` crate-type is strictly `["staticlib"]` (NO `cdylib`, per F1).
  - T1.9.4: Verify `cargo check -p yolo_core` compiles cleanly on Windows host.
  - T1.9.5: Verify `cargo build -p yolo_ffi --target aarch64-linux-android --release` produces `libyolo_rust.a`.
- **F10 (YOLO11 Tensor Decoder)**:
  - T1.10.1: Decode a synthesized `[84, 8400]` tensor with 1 box at $(0.5, 0.5, 0.2, 0.2)$ conf=0.9; assert decoded box matches.
  - T1.10.2: Assert anchor-free box center $(c_x, c_y)$ and width/height $(w, h)$ unpack correctly to $(x_1, y_1, x_2, y_2)$.
  - T1.10.3: Assert letterbox padding $(pad_w, pad_h)$ and scale are inverted accurately to original image coordinates.
  - T1.10.4: Assert class score extraction selects maximum score over 80 COCO classes.
  - T1.10.5: Assert candidate boxes below `conf_threshold` are filtered out during decoding.
- **F11 (Class-Aware Non-Maximum Suppression)**:
  - T1.11.1: Feed 2 overlapping boxes of class 0 with IoU=0.8; assert only highest-confidence box survives.
  - T1.11.2: Feed 2 overlapping boxes of different classes (class 0 and class 2) with IoU=0.8; assert BOTH boxes survive (class-aware).
  - T1.11.3: Feed 5 identical duplicate boxes; assert exactly 1 box survives.
  - T1.11.4: Verify suppression threshold dynamically respects passed `iou_threshold` parameter.
  - T1.11.5: Verify output box list is sorted descending by confidence.
- **F12 (4-State Track Lifecycle State Machine)**:
  - T1.12.1: Assert new detection initializes a track in `TENTATIVE` state with hits=1, age=1.
  - T1.12.2: Assert 3 consecutive matched detections promote track from `TENTATIVE` to `CONFIRMED`.
  - T1.12.3: Assert single missed frame on `CONFIRMED` track transitions it to `COASTING` with time_since_update=1.
  - T1.12.4: Assert matched detection on `COASTING` track restores it to `CONFIRMED`.
  - T1.12.5: Assert track reaching time_since_update=31 transitions to `DELETED`.
- **F13 (2-Stage Association Engine)**:
  - T1.13.1: Verify Stage 1 associates high-confidence detections ($\ge 0.25$) using hybrid IoU + velocity prediction cost.
  - T1.13.2: Verify constant-velocity kinematic projection computes expected track position $p_{t+1} = p_t + v$.
  - T1.13.3: Verify Stage 2 matches remaining coasting tracks with low-confidence detections ($0.10 \le \text{conf} < 0.25$).
  - T1.13.4: Assert low-confidence detections never spawn new `TENTATIVE` tracks.
  - T1.13.5: Assert center-distance gating prevents association between distant objects with accidental IoU.
- **F14 (Track State Invariants)**:
  - T1.14.1: Assert bounding box EMA applies smoothing parameter $\alpha = 0.65$ exclusively to $[x_1, y_1, x_2, y_2]$.
  - T1.14.2: Assert velocity vector $(v_x, v_y)$ is smoothed across consecutive frames using $\beta = 0.60$.
  - T1.14.3: Assert circular buffer of length 10 maintains matched class history.
  - T1.14.4: Assert majority voting calculates statistical mode over history to determine reported `class_id`.
  - T1.14.5: Assert tie in majority voting breaks in favor of latest detection.
- **F15 (Zero Heap Allocation Memory Model)**:
  - T1.15.1: Verify `tracker.rs` uses fixed array `[Track; 100]` for active tracks buffer.
  - T1.15.2: Verify candidate boxes buffer uses fixed array `[CandidateBox; 100]`.
  - T1.15.3: Verify association cost matrix uses fixed array `[[f32; 100]; 100]`.
  - T1.15.4: Assert `tracker.update(...)` execution performs zero heap allocations (`malloc`/`Vec::push`).
  - T1.15.5: Assert processing 1000 consecutive frames exhibits zero memory growth.
- **F16 (Spatial Zone & Proximity Tier Computation)**:
  - T1.16.1: Assert box center $c_x < 0.33$ assigns `spatial_zone = 0` (`ZONE_LEFT`).
  - T1.16.2: Assert box center $0.33 \le c_x \le 0.66$ assigns `spatial_zone = 1` (`ZONE_CENTER`).
  - T1.16.3: Assert box center $c_x > 0.66$ assigns `spatial_zone = 2` (`ZONE_RIGHT`).
  - T1.16.4: Assert normalized area $\ge 0.18$ or bottom edge $y_2 \ge 0.82$ assigns `proximity_tier = 2` (`PROXIMITY_NEAR`).
  - T1.16.5: Assert area $< 0.05$ and $y_2 < 0.55$ assigns `proximity_tier = 0` (`PROXIMITY_FAR`).
- **F17 (4 Mandatory Host Unit Tests)**:
  - T1.17.1: Execute `test_invariant_1_coasting_survival_and_frame_31_deletion` and assert pass.
  - T1.17.2: Execute `test_invariant_2_zero_id_switches_on_crossing` and assert pass (zero ID swaps).
  - T1.17.3: Execute `test_invariant_3_spurious_detection_never_confirmed` and assert pass.
  - T1.17.4: Execute `test_invariant_4_class_id_majority_voting_stability` and assert pass under noisy inputs.
  - T1.17.5: Execute entire `cargo test -p yolo_core` suite under `CARGO_BUILD_JOBS=2` and assert exit code 0.
- **F18 (C++ NCNN Runner & NEON Preprocessing)**:
  - T1.18.1: Verify `yolo_ncnn_runner.cpp` implements `yolo_engine_init` with blob name verification.
  - T1.18.2: Verify `yolo_engine_forward_rgba` performs letterbox resize to $640 \times 640$ with padding color 114.
  - T1.18.3: Verify `yolo_engine_forward_yuv420` converts YUV420 to RGB using ARM NEON SIMD routines.
  - T1.18.4: Verify sensor rotation (90° / 270°) is applied accurately based on `sensor_orientation` parameter.
  - T1.18.5: Verify thread count is fixed to 4 threads (`opt.num_threads = 4`).
- **F19 (CMake Shared Library Build)**:
  - T1.19.1: Verify `native_core/CMakeLists.txt` links `libyolo_rust.a` via `-Wl,--whole-archive`.
  - T1.19.2: Verify CMake links against NCNN Vulkan package for `arm64-v8a`.
  - T1.19.3: Verify STL is configured as `ANDROID_STL=c++_shared`.
  - T1.19.4: Verify CMake build produces single unified shared library `libyolo_ncnn.so`.
  - T1.19.5: Verify NO secondary dynamic library `libyolo_rust.so` is emitted.
- **F20 (Symbol Preservation Gate)**:
  - T1.20.1: Run `llvm-nm -D --defined-only libyolo_ncnn.so` and verify `yolo_engine_init` exported with type `T`.
  - T1.20.2: Verify `yolo_engine_set_backend` exported with type `T`.
  - T1.20.3: Verify `yolo_engine_forward_yuv420` and `yolo_engine_forward_rgba` exported with type `T`.
  - T1.20.4: Verify `yolo_engine_destroy` exported with type `T`.
  - T1.20.5: Verify `yolo_engine_process_tensor` and `yolo_engine_reset_tracker` exported with type `T`.

### Features 21–31: Flutter Mobile Cockpit, HUD, Bilingual & Scope Lock
- **F21 (Flutter App Scaffolding & Android Caps)**:
  - T1.21.1: Verify `mobile_app/pubspec.yaml` name is `object_detector`.
  - T1.21.2: Verify `mobile_app/android/app/build.gradle` defines `applicationId "com.taha.yoloncnn"`.
  - T1.21.3: Verify `gradle.properties` sets `org.gradle.workers.max=2` and `parallel=false`.
  - T1.21.4: Verify `abiFilters 'arm64-v8a'` is strictly enforced in `build.gradle`.
  - T1.21.5: Run `flutter analyze` and assert 0 errors and 0 warnings.
- **F22 (Dedicated Worker Isolate Pipeline)**:
  - T1.22.1: Verify background worker isolate is spawned at app startup.
  - T1.22.2: Verify camera frame pointers/planes are dispatched via isolate `SendPort`.
  - T1.22.3: Verify worker isolate calls native C-ABI forward pass without blocking UI isolate.
  - T1.22.4: Verify inference results (`YoloFrameResult`) are returned to UI isolate via `ReceivePort`.
  - T1.22.5: Verify isolate handles graceful teardown upon app disposal.
- **F23 (Single-Slot Latest-Frame Gate)**:
  - T1.23.1: Assert incoming frame is accepted when `isProcessing == false`.
  - T1.23.2: Assert incoming frame is immediately dropped when `isProcessing == true`.
  - T1.23.3: Verify frame queue backlog length is always $\le 1$ frame.
  - T1.23.4: Verify `isProcessing` flag resets cleanly after worker completes frame.
  - T1.23.5: Verify zero frame accumulation or memory leaks over 500 dropped frames.
- **F24 (Zero-Allocation Dart FFI Bindings)**:
  - T1.24.1: Verify `YoloDetectionBox` struct layout in Dart matches C-ABI size (36 bytes).
  - T1.24.2: Verify `YoloFrameResult` struct layout matches C-ABI size (3624 bytes).
  - T1.24.3: Verify `yolo_engine_init` FFI function pointer resolves successfully from `libyolo_ncnn.so`.
  - T1.24.4: Verify `yolo_engine_forward_rgba` FFI function pointer resolves successfully.
  - T1.24.5: Verify `yolo_engine_destroy` FFI function pointer resolves successfully.
- **F25 (Dynamic Metadata Graph Validator)**:
  - T1.25.1: Assert engine init succeeds (`0`) when `model_metadata.json` matches `model.ncnn.param`.
  - T1.25.2: Assert engine init returns `-101` when param file is missing.
  - T1.25.3: Assert engine init returns `-102` when bin file is missing.
  - T1.25.4: Assert engine init returns `-103` when blob names mismatch.
  - T1.25.5: Assert engine init returns `-104` when tensor shapes mismatch.
- **F26 (Decoupled 60 FPS CustomPainter HUD)**:
  - T1.26.1: Verify `bbox_hud_painter.dart` compiles and repaints at 60 FPS via `AnimationController`.
  - T1.26.2: Verify bounding box coordinates are mapped from normalized $[0.0, 1.0]$ to Canvas dimensions.
  - T1.26.3: Verify track ID badges render persistent `#<id>` labels.
  - T1.26.4: Verify motion trail vectors render past trajectory centers.
  - T1.26.5: Verify proximity tier changes stroke width (FAR: 1.5px, MEDIUM: 2.5px, NEAR: 4.0px).
- **F27 (Glassmorphic Telemetry Top Bar)**:
  - T1.27.1: Verify telemetry bar displays live FPS numeric badge.
  - T1.27.2: Verify latency breakdown displays `Pre / NCNN / Track` in milliseconds.
  - T1.27.3: Verify backend toggle switches between CPU and Vulkan.
  - T1.27.4: Verify active tracks counter displays number of confirmed tracks.
  - T1.27.5: Verify `BackdropFilter` applies blur effect (`sigmaX: 10, sigmaY: 10`).
- **F28 (Bilingual COCO Repository)**:
  - T1.28.1: Verify `coco80_labels_ar_en.json` contains exactly 80 items (IDs 0..79).
  - T1.28.2: Verify class 0 maps to English `"person"` and Arabic `"شخص"`.
  - T1.28.3: Verify class 79 maps to English `"toothbrush"` and Arabic `"فرشاة أسنان"`.
  - T1.28.4: Verify switching locale dynamically changes label text between Arabic and English.
  - T1.28.5: Verify switching to Arabic updates UI layout to `TextDirection.rtl`.
- **F29 (Static Sample Benchmark Mode)**:
  - T1.29.1: Verify sample mode executes inference on `sample_street.jpg` without camera access.
  - T1.29.2: Verify sample mode executes on `sample_workspace.jpg`.
  - T1.29.3: Verify sample mode executes on `sample_retail.jpg`.
  - T1.29.4: Verify benchmark displays latency table for 10 consecutive iterations.
  - T1.29.5: Verify annotated detections are rendered on static sample view.
- **F30 (Scope Lock Static Grep Verification)**:
  - T1.30.1: Assert grep for `"omnisight"` returns 0 matches across monorepo (except ADR-001).
  - T1.30.2: Assert grep for `"AssistiveAudioConsumer"` returns 0 matches.
  - T1.30.3: Assert grep for `"TTS"` in source files returns 0 matches.
  - T1.30.4: Assert grep for `"blind"` in source files returns 0 matches.
  - T1.30.5: Assert grep for `"cooldown"` and `"Project 1 of 2"` returns 0 matches.
- **F31 (On-Device Hardware Run)**:
  - T1.31.1: Verify physical Galaxy Note 10 (`R58M95PJVZT`) is recognized by Flutter tooling (`flutter devices`).
  - T1.31.2: Verify app installs cleanly via `flutter run -d R58M95PJVZT --release`.
  - T1.31.3: Verify app launches on device and opens main cockpit screen.
  - T1.31.4: Verify camera permission prompt is handled at runtime.
  - T1.31.5: Verify `adb logcat` shows native `yolo_engine_init` success on Snapdragon 855.

### Features 32–35: Go + Redis Telemetry Microservice
- **F32 (Go Telemetry Microservice Core)**:
  - T1.32.1: Verify `backend_go_redis/go.mod` defines module and compiles with Go 1.22+.
  - T1.32.2: Verify `GET /health` returns HTTP 200 with JSON `{"status": "ok", "redis": "connected"}`.
  - T1.32.3: Verify `POST /api/v1/telemetry` accepts valid payload and returns HTTP 202 Accepted.
  - T1.32.4: Verify `GET /api/v1/analytics/summary` returns aggregated metrics JSON.
  - T1.32.5: Verify `WS /ws/telemetry` accepts WebSocket connection and upgrades cleanly.
- **F33 (Redis Stream & Sorted Set Analytics)**:
  - T1.33.1: Verify telemetry payload is appended to Redis stream `yolo:telemetry` (`XADD`).
  - T1.33.2: Verify stream capping keeps stream length $\le 100,000$ entries (`MAXLEN ~ 100000`).
  - T1.33.3: Verify detected class counts increment Redis sorted set `yolo:class_counts` (`ZINCRBY`).
  - T1.33.4: Verify querying `yolo:class_counts` returns accurate top detected classes.
  - T1.33.5: Verify Redis data persistence (`appendonly yes`).
- **F34 (Multi-Stage Docker & Compose Orchestration)**:
  - T1.34.1: Verify `backend_go_redis/Dockerfile` uses multi-stage build (`golang:1.22-alpine` -> `alpine:3.20`).
  - T1.34.2: Verify service container runs as non-root user `appuser`.
  - T1.34.3: Verify `docker-compose.yml` configures Redis 7 Alpine and Telemetry service.
  - T1.34.4: Run `docker compose config` and assert valid compose syntax.
  - T1.34.5: Verify containers start up, link network, and pass health checks.
- **F35 (Mobile Offline-First Telemetry Sync Client)**:
  - T1.35.1: Verify telemetry client is disabled by default in mobile app settings.
  - T1.35.2: Verify metrics are batched at 2.0-second intervals when enabled.
  - T1.35.3: Verify HTTP POST request has a strict 1500 ms timeout configured.
  - T1.35.4: Assert network timeout drops metric packet without stalling camera pipeline.
  - T1.35.5: Assert camera FPS and UI rendering are unaffected by microservice disconnection.

### Features 36–40: Hardware Verification, Signing & Release
- **F36 (Release Keystore Generation)**:
  - T1.36.1: Verify `keytool` generates 2048-bit RSA key `object_detector_key`.
  - T1.36.2: Verify keystore file `release.keystore` is created with validity $\ge 10000$ days.
  - T1.36.3: Verify `key.properties` is populated with storepass, keypass, and alias.
  - T1.36.4: Verify `key.properties` and `*.keystore` are excluded from git repository.
  - T1.36.5: Verify `key.properties.example` template is committed to git.
- **F37 (Release Signed APK Build)**:
  - T1.37.1: Verify `flutter build apk --release --target-platform android-arm64` completes with exit code 0.
  - T1.37.2: Verify output artifact is renamed to `object-detector-v1.0.0-arm64-v8a.apk`.
  - T1.37.3: Verify APK contains `libyolo_ncnn.so` in `lib/arm64-v8a/`.
  - T1.37.4: Verify APK contains `libc++_shared.so` in `lib/arm64-v8a/`.
  - T1.37.5: Verify APK signature verifies with `apksigner verify --verbose`.
- **F38 (Snapdragon 855 100-Frame Benchmark Protocol)**:
  - T1.38.1: Verify 60-second warm-up is executed on physical Note 10 before benchmark capture.
  - T1.38.2: Assert frame 1 is excluded from benchmark calculations.
  - T1.38.3: Assert CPU NEON 4T mode achieves median $\ge 12.0$ FPS on Snapdragon 855.
  - T1.38.4: Assert Vulkan GPU mode achieves median $\ge 20.0$ FPS on Adreno 640.
  - T1.38.5: Verify `docs/benchmarks_note10.md` records Median and P95 latency breakdown.
- **F39 (30-Second Field Tracking Benchmark)**:
  - T1.39.1: Execute 30-second continuous tracking test on Note 10 in dynamic multi-object environment.
  - T1.39.2: Assert total track ID switches during 30-second run is exactly 0.
  - T1.39.3: Record average track lifetime in seconds in benchmark documentation.
  - T1.39.4: Record confirmed tracks count vs deleted tracks count.
  - T1.39.5: Attach raw `adb logcat` timestamped trace to `docs/benchmarks_note10.md`.
- **F40 (Multi-Asset Release Package & Checksum Manifest)**:
  - T1.40.1: Verify `SHA256SUMS.txt` is generated covering APK, `.param`, `.bin`, and metadata JSON.
  - T1.40.2: Verify `sha256sum -c SHA256SUMS.txt` verifies 100% of files cleanly.
  - T1.40.3: Verify GitHub release `v1.0.0` is drafted/published with release notes and assets.
  - T1.40.4: Verify all release asset download links resolve to HTTP 200.
  - T1.40.5: Verify release is marked as final release (or `v1.0.0-rc1` if device declined).

---

## 5. Tier 2: Boundary & Corner Cases Test Specifications (200 Tests)

### Features 1–8: Preflight & Environment Boundaries
- **B1 (Relocation Boundaries)**:
  - T2.1.1: Attempt build with path containing spaces -> assert build system rejects or warns.
  - T2.1.2: Path length boundary test at exactly 260 characters (MAX_PATH limit) -> assert clean handling.
  - T2.1.3: Deep subdirectory nesting ($\ge 10$ levels) -> assert path resolution succeeds.
  - T2.1.4: Read-only directory permissions on `C:\dev\object-detector` -> assert clear failure message.
  - T2.1.5: Unicode characters in parent paths -> verify isolation in `C:\dev\object-detector`.
- **B2 (Git & Remote Boundaries)**:
  - T2.2.1: Commit attempt with uncommitted `key.properties` -> assert `.gitignore` prevents staging.
  - T2.2.2: Commit attempt with `*.apk` file -> assert `.gitignore` blocks inclusion.
  - T2.2.3: Push to invalid remote URL -> assert error caught and reported.
  - T2.2.4: Empty initial commit validation -> assert repository requires non-empty root commit.
  - T2.2.5: Detached HEAD state detection -> assert test runner detects branch state.
- **B3 (ADB Device Boundaries)**:
  - T2.3.1: Zero devices attached (`adb devices` returns empty) -> assert `WAITING_FOR_PHYSICAL_DEVICE`.
  - T2.3.2: Device in `unauthorized` state -> assert explicit warning and guidance to accept USB debugging prompt.
  - T2.3.3: Device in `offline` state -> assert diagnostic error and USB reconnect recommendation.
  - T2.3.4: Multiple devices attached (e.g. tablet + phone) -> assert explicit serial `-s R58M95PJVZT` targeting.
  - T2.3.5: Device battery below 5% -> assert warning about thermal/frequency throttling.
- **B4 (Colab Export Boundaries)**:
  - T2.4.1: Colab session unreachable (`open_colab_browser_connection` returns false) -> assert immediate `BLOCKED`.
  - T2.4.2: PyTorch model weights missing or corrupt -> assert export halts with explicit error.
  - T2.4.3: Output shape mismatch (e.g. $[1, 80, 8400]$ instead of $[1, 84, 8400]$) -> assert hard block with param dump.
  - T2.4.4: Dynamic input shape export -> assert rejection; static $640 \times 640$ strictly required.
  - T2.4.5: FP32 vs FP16 precision overflow in PNNX export -> assert FP16 conversion passes validation.
- **B5 (Colab Numeric Parity Boundaries)**:
  - T2.5.1: Numeric diff exceeds tolerance threshold ($> 0.20$) -> assert parity check reports FAIL.
  - T2.5.2: Zero detections on `bus.jpg` -> assert parity check fails.
  - T2.5.3: Detection count mismatch between PyTorch and NCNN -> assert parity check fails.
  - T2.5.4: Detection class label mismatch -> assert parity check fails.
  - T2.5.5: Corrupted `bus.jpg` (0-byte file) -> assert image decode error handled gracefully.
- **B6 (Release Asset Transfer Boundaries)**:
  - T2.6.1: Single upload continuous transfer $> 16$ MB from local host -> assert ISP cap rule enforced.
  - T2.6.2: Network drop during `gh release download` -> assert download retries or reports failure.
  - T2.6.3: Corrupted SHA256 digest on downloaded release asset -> assert checksum check fails.
  - T2.6.4: Release asset tag does not exist -> assert clear error message.
  - T2.6.5: Download into non-existent directory -> assert directory is auto-created.
- **B7 (Sample Photo Boundaries)**:
  - T2.7.1: Zero-byte image file -> assert decode returns error, no native crash.
  - T2.7.2: Corrupted JPEG header -> assert decoder fails gracefully with status code.
  - T2.7.3: Extreme aspect ratio image ($10 \times 2000$ pixels) -> assert letterbox padding computes valid bounds.
  - T2.7.4: Ultra-high-resolution image ($8000 \times 6000$ pixels) -> assert memory allocation remains bounded.
  - T2.7.5: Blank white image (zero features) -> assert detection count = 0 without error.
- **B8 (Versions Lockfile Boundaries)**:
  - T2.8.1: Missing toolchain entry in `docs/versions.lock.md` -> assert validation fails.
  - T2.8.2: Version string containing wildcard `3.38.*` -> assert validation fails.
  - T2.8.3: Version string containing range `>=1.99.0` -> assert validation fails.
  - T2.8.4: Mismatch between lockfile and installed `rustc -V` -> assert conflict declared.
  - T2.8.5: Mismatch between lockfile and installed NDK version -> assert conflict declared.

### Features 9–20: Native Core & Tracking Engine Boundaries
- **B9 (Rust Workspace Boundaries)**:
  - T2.9.1: Attempt to add `cdylib` to `yolo_ffi/Cargo.toml` -> assert build/linter rejects duplicate library.
  - T2.9.2: Direct C++ dependency added to `yolo_core` -> assert compilation fails on host.
  - T2.9.3: Target ABI set to `x86_64` for Android build -> assert rejection (arm64-v8a only).
  - T2.9.4: Building with `CARGO_BUILD_JOBS > 2` -> assert resource cap violation detected.
  - T2.9.5: Circular dependency between `yolo_core` and `yolo_ffi` -> assert compiler error.
- **B10 (Decoder Boundaries)**:
  - T2.10.1: Tensor containing `NaN` floating point values -> assert decoder filters or clamps to 0.0.
  - T2.10.2: Tensor containing `+Inf` or `-Inf` -> assert values sanitized; no crash.
  - T2.10.3: Negative bounding box coordinates ($c_x < 0, c_y < 0$) -> assert clamped to $[0.0, 1.0]$.
  - T2.10.4: Extreme box dimensions ($w > 2.0, h > 2.0$) -> assert clamped to image boundary.
  - T2.10.5: All confidence scores = 0.0 -> assert 0 candidate boxes returned.
- **B11 (NMS Boundaries)**:
  - T2.11.1: Exactly 0 input candidate boxes -> assert 0 output boxes returned immediately.
  - T2.11.2: Maximum capacity input (100 candidate boxes) -> assert buffer bounds respected without overflow.
  - T2.11.3: All candidate boxes have identical confidence scores -> assert deterministic tie-breaking.
  - T2.11.4: IoU threshold = 0.0 -> assert only single highest-confidence box per class survives.
  - T2.11.5: IoU threshold = 1.0 -> assert all non-identical boxes survive.
- **B12 (Track State Machine Boundaries)**:
  - T2.12.1: Track with 2 hits receives missed frame -> assert immediate deletion (never confirmed).
  - T2.12.2: Track coasting for 30 consecutive frames receives detection on frame 30 -> assert restored to CONFIRMED.
  - T2.12.3: Track coasting for 30 consecutive frames receives detection on frame 31 -> assert track was already deleted; new ID created.
  - T2.12.4: Total active tracks reach capacity limit of 100 -> assert oldest tentative track evicted; no buffer overrun.
  - T2.12.5: Zero detections for 100 consecutive frames -> assert all tracks deleted; active count = 0.
- **B13 (Association Engine Boundaries)**:
  - T2.13.1: Two objects moving at extreme velocity ($v_x = 0.5$ per frame) -> assert velocity gating bounds association.
  - T2.13.2: Object reverses direction instantly -> assert IoU and center distance reconcile association.
  - T2.13.3: Detections exactly at confidence threshold boundary ($\text{conf} = 0.250000$) -> assert routed to Stage 1.
  - T2.13.4: Detections at Stage 2 boundary ($\text{conf} = 0.100000$) -> assert routed to Stage 2.
  - T2.13.5: Detections below Stage 2 threshold ($\text{conf} = 0.099999$) -> assert discarded immediately.
- **B14 (Track State Invariants Boundaries)**:
  - T2.14.1: Bounding box EMA with sudden jump ($x_1$ shifts from 0.1 to 0.9 in 1 frame) -> assert EMA smooths coordinate.
  - T2.14.2: Majority voting with alternating classes $[0, 2, 0, 2, 0, 2, 0, 2, 0, 2]$ -> assert latest detection breaks tie.
  - T2.14.3: Track age overflow test (track survives $10^6$ frames) -> assert age counter does not wrap or crash.
  - T2.14.4: Bounding box coordinates $x_2 < x_1$ or $y_2 < y_1$ -> assert coordinates normalized/swapped safely.
  - T2.14.5: Zero velocity $(v_x = 0, v_y = 0)$ over 50 frames -> assert velocity smoothing converges to 0.0.
- **B15 (Zero Heap Memory Boundaries)**:
  - T2.15.1: 100 tracks + 100 candidate detections -> assert cost matrix evaluation executes within static memory.
  - T2.15.2: Stack memory limit test -> assert all large buffers are statically or structure-allocated.
  - T2.15.3: Rapid tracker reset (`yolo_engine_reset_tracker`) 100 times in loop -> assert clean zeroing of memory.
  - T2.15.4: Process 50,000 frames under memory profiling -> assert memory usage delta is 0 bytes.
  - T2.15.5: Corrupted tracker struct passed to update -> assert memory bounds protection.
- **B16 (Spatial Zone & Proximity Boundaries)**:
  - T2.16.1: Box center exactly at boundary $c_x = 0.330000$ -> assert deterministic zone assignment.
  - T2.16.2: Box center exactly at boundary $c_x = 0.660000$ -> assert deterministic zone assignment.
  - T2.16.3: Normalized area exactly at boundary $\text{area} = 0.180000$ -> assert `PROXIMITY_NEAR`.
  - T2.16.4: Normalized area exactly at boundary $\text{area} = 0.050000$ -> assert `PROXIMITY_MEDIUM`.
  - T2.16.5: Bottom edge $y_2 = 1.0$ (touching screen bottom) -> assert `PROXIMITY_NEAR`.
- **B17 (Unit Test Harness Boundaries)**:
  - T2.17.1: Run host unit tests with 1 thread (`CARGO_BUILD_JOBS=1`) -> assert tests pass deterministically.
  - T2.17.2: Run host unit tests under high CPU load -> assert no timing-dependent race conditions.
  - T2.17.3: Modify tracking threshold in test -> assert test detects divergence.
  - T2.17.4: Test with reverse trajectory crossing -> assert zero ID switches preserved.
  - T2.17.5: Test with 3 simultaneous crossing objects -> assert identities preserved.
- **B18 (C++ NCNN Runner Boundaries)**:
  - T2.18.1: Null pointer passed as `y_plane` in `yolo_engine_forward_yuv420` -> assert returns error code, no crash.
  - T2.18.2: Zero or negative row stride ($y\_row\_stride \le 0$) -> assert returns invalid argument error.
  - T2.18.3: Image width/height mismatch ($src\_width = 0$) -> assert returns error code.
  - T2.18.4: Sensor orientation outside valid set $\{0, 90, 180, 270\}$ -> assert defaults to 0 without crash.
  - T2.18.5: Calling `forward` before `yolo_engine_init` -> assert returns uninitialized error code (-1).
- **B19 (CMake Linker Boundaries)**:
  - T2.19.1: Build without `-Wl,--whole-archive` -> assert symbol preservation gate catches missing symbols.
  - T2.19.2: Link with multiple OpenMP libraries -> assert linker fails or duplicate symbol detector triggers.
  - T2.19.3: Link with incorrect STL (`c++_static` instead of `c++_shared`) -> assert build rule flags error.
  - T2.19.4: Building with `cmake --build . -- -j4` -> assert resource cap violation ($j > 2$).
  - T2.19.5: Missing NDK toolchain file -> assert build halts with clear diagnostic.
- **B20 (Symbol Gate Boundaries)**:
  - T2.20.1: Strip symbols via `llvm-strip` -> assert symbol preservation gate rejects stripped library.
  - T2.20.2: Typo in exported symbol name (e.g. `yolo_init` instead of `yolo_engine_init`) -> assert gate fails.
  - T2.20.3: Symbol exported as weak (`W`) instead of text (`T`) -> assert gate fails.
  - T2.20.4: `llvm-nm` run on non-existent library file -> assert gate detects missing binary.
  - T2.20.5: Extra unintended symbols exposed -> assert audit logs warning.

### Features 21–31: Mobile Cockpit & HUD Boundaries
- **B21 (Flutter Config Boundaries)**:
  - T2.21.1: Gradle heap allocation exceeding 2048 MB -> assert `-Xmx2048m` cap strictly limits JVM.
  - T2.21.2: Gradle worker count exceeding 2 -> assert `org.gradle.workers.max=2` cap enforced.
  - T2.21.3: Attempt to compile with `minSdkVersion < 24` -> assert build rejects.
  - T2.21.4: Missing camera permission in `AndroidManifest.xml` -> assert build check fails.
  - T2.21.5: Missing internet permission -> assert build check fails.
- **B22 (Worker Isolate Boundaries)**:
  - T2.22.1: Native exception thrown inside worker isolate -> assert isolate catches and does not crash app.
  - T2.22.2: Large payload transfer across isolate port -> assert zero-copy pointer semantics prevent latency.
  - T2.22.3: Rapid background/foreground switching (10 times in 5s) -> assert worker isolate pauses/resumes cleanly.
  - T2.22.4: Out-of-order frame returns -> assert frame timestamping enforces monotonically increasing display.
  - T2.22.5: Worker isolate termination while inference in flight -> assert native memory freed.
- **B23 (Single-Slot Frame Gate Boundaries)**:
  - T2.23.1: Camera delivers frames at 60 FPS while inference takes 80 ms -> assert 4 out of 5 frames dropped.
  - T2.23.2: Frame arrives at exact instant inference completes -> assert race condition resolved safely.
  - T2.23.3: Dropping 10,000 frames continuously -> assert zero memory growth or resource leakage.
  - T2.23.4: Camera stream paused for 60s -> assert gate remains ready for first resume frame.
  - T2.23.5: Null frame delivered by camera controller -> assert dropped without error.
- **B24 (FFI Struct Boundaries)**:
  - T2.24.1: Struct field alignment mismatch -> assert size assertions catch byte shift.
  - T2.24.2: Maximum box count in `YoloFrameResult` ($count = 100$) -> assert boundary index 99 read safely.
  - T2.24.3: Invalid count value ($count = 101$ or $count = -1$) -> assert clamped to $[0, 100]$.
  - T2.24.4: Null pointer passed to FFI forward call -> assert C-ABI returns error code.
  - T2.24.5: Multiple concurrent calls to non-thread-safe FFI entrypoints -> assert worker isolate serializes calls.
- **B25 (Dynamic Metadata Validator Boundaries)**:
  - T2.25.1: Param file with 0 layers -> assert validator returns error code.
  - T2.25.2: Metadata JSON with invalid JSON syntax -> assert validator catches parse error.
  - T2.25.3: Input tensor dimensions $640 \times 480$ instead of $640 \times 640$ -> assert shape mismatch (-104).
  - T2.25.4: Missing output blob name `out0` -> assert blob name mismatch (-103).
  - T2.25.5: Corrupted FP16 weights binary file (truncated by 50%) -> assert NCNN load returns -102.
- **B26 (HUD CustomPainter Boundaries)**:
  - T2.26.1: Zero detected tracks -> assert Canvas renders camera feed without overlay or error.
  - T2.26.2: 100 simultaneous tracks -> assert Canvas renders all boxes within 16.6 ms frame budget.
  - T2.26.3: Bounding box coordinates outside screen bounds ($[-0.5, -0.5, 1.5, 1.5]$) -> assert clipped to Canvas.
  - T2.26.4: Motion trail vector with 100 historical points -> assert polyline points capped to max 15.
  - T2.26.5: Screen size change (foldable/tablet split-screen) -> assert painter recalculates aspect ratio.
- **B27 (Telemetry Top Bar Boundaries)**:
  - T2.27.1: Zero frames processed yet (cold start) -> assert displays `-- FPS` and `-- ms`.
  - T2.27.2: FPS exceeds 120 FPS -> assert display formats cleanly.
  - T2.27.3: Vulkan toggle clicked while Vulkan backend is unavailable -> assert toast warning and CPU retention.
  - T2.27.4: Rapid toggling between CPU and Vulkan (10 clicks in 2s) -> assert toggle debounced.
  - T2.27.5: Active tracks counter exceeds 99 -> assert badge layout does not overflow.
- **B28 (Bilingual COCO Boundaries)**:
  - T2.28.1: Class ID negative ($class\_id = -1$) -> assert returns `"unknown (-1)"`.
  - T2.28.2: Class ID exceeding COCO range ($class\_id = 80$) -> assert returns `"unknown (80)"`.
  - T2.28.3: Unsupported locale string (`locale = "fr"`) -> assert falls back to English `"en"`.
  - T2.28.4: Rapid language switching while rendering 50 boxes -> assert zero text flickering or layout jump.
  - T2.28.5: Missing Arabic font glyphs -> assert system font fallback renders valid Arabic text.
- **B29 (Static Sample Mode Boundaries)**:
  - T2.29.1: Sample image missing from APK assets -> assert user-facing error message displayed.
  - T2.29.2: Sample image resolution differs from $640 \times 640$ -> assert letterboxing operates identically to live camera.
  - T2.29.3: Running 500 consecutive benchmark iterations -> assert median and P95 statistics remain stable.
  - T2.29.4: Switching between sample images during active benchmark -> assert current iteration finishes cleanly.
  - T2.29.5: Memory usage before vs after sample mode benchmark -> assert delta $\approx 0$ MB.
- **B30 (Scope Lock Static Boundaries)**:
  - T2.30.1: Accidental addition of comment containing `"blind"` -> assert CI grep fails.
  - T2.30.2: Adding TTS dependency to `pubspec.yaml` -> assert CI grep fails.
  - T2.30.3: Renaming variable to include `"omnisight"` -> assert CI grep fails.
  - T2.30.4: Adding cooldown timer logic -> assert CI grep fails.
  - T2.30.5: Verifying ADR-001 historical reference is permitted while all other occurrences are rejected.
- **B31 (Physical Device Hardware Boundaries)**:
  - T2.31.1: Device disconnected during active `flutter run` -> assert CLI reports device lost cleanly.
  - T2.31.2: Device screen turned off during benchmark -> assert benchmark pauses until screen unlocked.
  - T2.31.3: Device thermal level reaching `THROTTLED` -> assert benchmark records temperature and logs warning.
  - T2.31.4: Low available storage on device ($< 500$ MB) -> assert install warning reported.
  - T2.31.5: Android 12 permission revocation while app running -> assert lifecycle observer catches state.

### Features 32–40: Telemetry Microservice & Release Boundaries
- **B32 (Go Microservice Boundaries)**:
  - T2.32.1: Malformed JSON body sent to `/api/v1/telemetry` -> assert returns HTTP 400 Bad Request.
  - T2.32.2: Oversized telemetry payload ($> 1$ MB) -> assert request body limit rejects payload.
  - T2.32.3: Telemetry payload with missing required fields -> assert schema validation returns 422.
  - T2.32.4: 1000 concurrent HTTP POST requests -> assert server handles load without crashing.
  - T2.32.5: Redis connection dropped -> assert `/health` returns HTTP 503 Service Unavailable.
- **B33 (Redis Boundaries)**:
  - T2.33.1: Redis reaches max memory limit (256 MB) -> assert eviction policy `allkeys-lru` operates.
  - T2.33.2: Stream length exceeds 100,000 entries -> assert approximate trimming `MAXLEN ~ 100000` caps stream.
  - T2.33.3: Incrementing non-existent class in sorted set -> assert class created with score = 1.
  - T2.33.4: Redis server restart -> assert append-only file (AOF) restores telemetry stream.
  - T2.33.5: Extremely long class name string ($> 1000$ chars) -> assert sanitized before `ZINCRBY`.
- **B34 (Docker Orchestration Boundaries)**:
  - T2.34.1: Port 8080 already in use on host -> assert docker-compose reports port conflict.
  - T2.34.2: Port 6379 already in use -> assert docker-compose reports port conflict.
  - T2.34.3: Container killed via `SIGKILL` -> assert restart policy `unless-stopped` restarts container.
  - T2.34.4: Service container health check timeout -> assert container flagged as unhealthy.
  - T2.34.5: Disk space exhaustion during volume write -> assert volume error handled gracefully.
- **B35 (Mobile Sync Client Boundaries)**:
  - T2.35.1: Microservice returns HTTP 500 Internal Error -> assert mobile client discards packet and retries.
  - T2.35.2: Network latency = 3000 ms (exceeds 1500 ms timeout) -> assert client aborts request at 1500 ms.
  - T2.35.3: Offline queue reaches 10 packets -> assert oldest packet dropped; queue bounded.
  - T2.35.4: DNS resolution failure for telemetry host -> assert client logs debug message and backs off.
  - T2.35.5: Cellular data switch during upload -> assert socket error caught without app disruption.
- **B36 (Keystore Boundaries)**:
  - T2.36.1: Keytool execution with empty password -> assert command rejected.
  - T2.36.2: Keytool execution with validity $< 365$ days -> assert rejected (10000 days required).
  - T2.36.3: Corrupted keystore file -> assert Gradle build fails fast with diagnostic error.
  - T2.36.4: Keystore alias mismatch in `key.properties` -> assert Gradle build reports missing alias.
  - T2.36.5: Incorrect key password -> assert authentication exception caught.
- **B37 (Release Build Boundaries)**:
  - T2.37.1: Build executed without release signing config -> assert fails fast; never emits debug release APK.
  - T2.37.2: Gradle worker count exceeds 2 -> assert build script halts with cap violation.
  - T2.37.3: Gradle JVM memory exceeds 2048 MB -> assert JVM args verified.
  - T2.37.4: Output APK contains `x86_64` native binaries -> assert ABI filter audit rejects APK.
  - T2.37.5: Proguard/R8 shrinking enabled accidentally -> assert `minifyEnabled false` preserved.
- **B38 (Snapdragon Benchmark Boundaries)**:
  - T2.38.1: Benchmark started without 60s warm-up -> assert protocol rejects benchmark data.
  - T2.38.2: Frame 1 included in latency calculation -> assert protocol rejects benchmark data.
  - T2.38.3: CPU mode latency exceeds 83.3 ms ($< 12$ FPS) -> assert benchmark reports FAIL.
  - T2.38.4: Vulkan mode latency exceeds 50.0 ms ($< 20$ FPS) -> assert benchmark reports FAIL.
  - T2.38.5: P95 latency is $> 3\times$ median (extreme stutter) -> assert benchmark flags stability warning.
- **B39 (Field Tracking Boundaries)**:
  - T2.39.1: Single track ID switch observed during 30s test -> assert field benchmark reports FAIL.
  - T2.39.2: Test duration is $< 30$ seconds -> assert test invalidated.
  - T2.39.3: Zero tracks detected during 30s test (empty scene) -> assert test invalidated.
  - T2.39.4: High camera jitter/shake during tracking -> assert kinematic gating preserves IDs.
  - T2.39.5: Complete temporary scene occlusion (black frame for 10 frames) -> assert coasting retains tracks.
- **B40 (Release Packaging Boundaries)**:
  - T2.40.1: `SHA256SUMS.txt` missing any of the 4 core assets -> assert checksum verification fails.
  - T2.40.2: One byte modified in release APK after checksum generation -> assert checksum mismatch.
  - T2.40.3: Uploading release asset $> 16$ MB directly from local machine -> assert blocked by ISP rule.
  - T2.40.4: Pre-release tag missing `UNVERIFIED_ON_DEVICE` marker when hardware unattached -> assert rejected.
  - T2.40.5: Duplicate release tag creation attempt -> assert GitHub API error handled cleanly.

---

## 6. Tier 3: Cross-Feature Combinations & Pairwise Interactions (40 Tests)

The Tier 3 suite verifies that orthogonal features interact correctly when activated concurrently.

| # | Pairwise Interaction | Features Exercised | Test Scenario | Acceptance Criteria |
|---|----------------------|--------------------|---------------|---------------------|
| P1 | Vulkan Backend + Decoupled HUD + High Track Count | F18, F26, F15 | Execute Vulkan inference with 50 simultaneous tracks rendered on 60 FPS CustomPainter HUD | HUD maintains $\ge 55$ FPS; inference $\ge 20$ FPS; zero heap allocation spikes |
| P2 | RTL Arabic Layout + Multi-Object Tracking + Spatial Zones | F28, F14, F16 | Switch language to Arabic (`ar`) while tracking 10 crossing objects across Left, Center, and Right zones | Text renders right-to-left; spatial zone calculation unchanged; zero track ID switches |
| P3 | Single-Slot Gate + Rapid Camera Orientation Switch | F23, F18, F22 | Rotate device through 0°, 90°, 180°, 270° while camera feeds 30 FPS under heavy inference | Letterbox coordinates rotate upright; zero frame accumulation; no orientation lag |
| P4 | Static Sample Mode + CPU NEON + Telemetry Sync | F29, F18, F35 | Run 100 sample benchmark frames on CPU while background telemetry client syncs metrics | Sample benchmark latency unaffected by HTTP network sync; metrics stream to Redis |
| P5 | Dynamic Metadata Validation + Engine Re-init + Vulkan | F25, F18, F24 | Re-initialize native engine with Vulkan backend enabled while validating metadata JSON | Clean re-initialization; no memory leaks; valid blob names verified |
| P6 | 2-Stage Association + Partial Occlusion + Motion Trails | F13, F14, F26 | Track two crossing objects passing behind a simulated barrier for 15 frames | Stage 2 re-links coasting tracks; motion trails interpolate smoothly; zero ID swaps |
| P7 | Dedicated Worker Isolate + Lifecycle Pause/Resume | F22, F23, F31 | Rapidly minimize and resume app 5 times while worker isolate is executing native FFI | Isolate pauses and resumes cleanly; zero camera sensor locks or memory leaks |
| P8 | Majority Vote Class Stability + Rapid Locale Switching | F14, F28, F26 | Feed noisy class detections while toggling between English and Arabic every 2 seconds | Majority vote prevents label fluttering; UI updates text direction seamlessly |
| P9 | Redis Stream Telemetry + WebSocket Broadcast + High Load | F32, F33, F34 | Ingest 500 telemetry packets/sec into Go microservice while 5 WebSocket clients stream live | Stream trimmed to 100k; WebSocket clients receive frames in $< 50$ ms latency |
| P10| Release Keystore Signing + ARM64 ABI Filter + APK Verify | F36, F37, F20 | Build release signed APK under Gradle caps and audit native symbols in packaged `.so` | APK signed with release key; contains only `arm64-v8a`; all `yolo_*` symbols intact |
| P11| Proximity Tier Warning + Audio Decoupling + Spatial HUD | F16, F26, F30 | Detect object transitioning from FAR to NEAR proximity in CENTER zone | HUD renders pulsing warning border; zero TTS/audio triggered (scope lock verified) |
| P12| Offline Telemetry Network Drop + Reconnection Buffer | F35, F32, F33 | Disconnect Wi-Fi for 30s during active tracking, then reconnect | Buffer caps at 10 packets; reconnect flushes queued metrics; camera pipeline unaffected |
| P13| Vulkan GPU Fallback + Thermal Throttling Simulation | F18, F27, F38 | Simulate Vulkan context failure on GPU | Engine falls back to CPU NEON automatically; telemetry bar updates backend badge |
| P14| Zero Heap Core + High Frame Count (10,000 frames) | F15, F12, F13 | Process 10,000 consecutive frames through tracker on host test harness | Heap allocation delta = 0 bytes; maximum latency variance $\le 5\%$ |
| P15| Colab Model Parity + Dynamic Init Validation | F5, F25, F6 | Validate Colab exported `.param` directly against native `yolo_engine_init` | Native graph parser validates layers and dimensions without runtime mismatch |
| P16| Bilingual COCO Lookup + Out-of-Bounds Detection | F28, F10, F26 | Feed invalid detection index (class ID = 85) to bilingual repository | Safely returns fallback string; HUD renders label without throwing exception |
| P17| 30s Field Tracking + ADB Logcat Profiling | F39, F38, F31 | Execute 30s live tracking test on Note 10 while capturing continuous raw logcat | Logcat verifies native inference times; zero track ID switches documented |
| P18| Docker Compose Multi-Container + Redis Persistence | F34, F33, F32 | Restart Docker Compose stack while telemetry data is populated in Redis volume | Telemetry stream and class counts persist cleanly across container recreation |
| P19| Spurious Detection Suppression + 2-Stage Low-Conf Gating| F12, F13, F17 | Inject single-frame low-confidence detection at random screen coordinates | Spurious detection rejected; never transitions to CONFIRMED or COASTING |
| P20| Checksum Manifest + Multi-Asset GitHub Release | F40, F37, F6 | Verify all release artifacts against `SHA256SUMS.txt` prior to release publication | 100% checksum match; release assets verified for public download |

---

## 7. Tier 4: Real-World Application Scenarios (20 Scenarios)

| # | Scenario Name | Features Exercised | Operational Description | Success Acceptance Criteria |
|---|---------------|--------------------|-------------------------|-----------------------------|
| W1 | Urban Traffic Multi-Lane Surveillance | F10, F11, F12, F13, F14, F16, F26 | High-density multi-lane roadway with cars, buses, trucks, and pedestrians crossing paths simultaneously | Tracks maintained across crossing lanes; zero ID switches; vehicles classified accurately; spatial zones logged |
| W2 | Indoor Office & Electronics Asset Tracking | F10, F14, F16, F28, F29 | Indoor workspace scene with laptops, cell phones, chairs, cups, and people moving in tight proximity | Bilingual Arabic/English labels render; proximity tiers shift as user approaches desk; no label flutter |
| W3 | Retail Store Shelf Stock & Foot Traffic | F10, F12, F16, F32, F33, F35 | Retail aisle tracking bottles, apples, bananas, and shoppers; telemetry streaming to Redis backend | Class detection counts aggregated in `yolo:class_counts`; telemetry stream logs foot traffic in real time |
| W4 | Extreme Occlusion & Column Crossing | F12, F13, F14, F17 | Pedestrian walks behind a wide concrete pillar (occluded for 20 consecutive frames) and emerges on other side | Track enters COASTING; re-linked via Stage 2 upon emergence; original `track_id` preserved |
| W5 | 60-Minute Thermal & Memory Soak Test | F15, F22, F23, F31, F38 | Continuous 60-minute live camera inference on physical Galaxy Note 10 under ambient room temperature | Zero memory leakage; frame gate drops excess frames without lag; device temperature stabilizes $\le 42^\circ\text{C}$ |
| W6 | Dynamic Language Switching during Live Pursuit | F28, F26, F27, F14 | User switches UI language between Arabic (RTL) and English (LTR) every 5 seconds while tracking 5 moving targets | HUD flips layout dynamically without dropping inference frames or resetting tracker IDs |
| W7 | Dual-Backend Performance Benchmark Comparison | F18, F27, F29, F38 | Run standardized 100-frame benchmark on `sample_street.jpg` under CPU NEON 4T, then switch to Vulkan GPU | Median CPU latency $\le 83.3$ ms ($\ge 12$ FPS); median GPU latency $\le 50.0$ ms ($\ge 20$ FPS); results logged |
| W8 | Intermittent Network Disconnection & Recovery | F35, F32, F33 | Mobile app runs in remote area with alternating 30s online / 30s offline network connectivity | App maintains full 60 FPS UI and inference; telemetry client buffers and reconnects without user intervention |
| W9 | Camera Stream Rapid Lifecycle Interruptions | F22, F23, F31 | Phone receives incoming call, user locks screen, opens notification tray, and resumes app repeatedly | Camera controller releases and re-acquires camera hardware cleanly; zero crash or screen freeze |
| W10| High-Speed Vehicle Drive-By Tracking | F13, F14, F16, F26 | Fast vehicle enters frame at high speed, traverses screen in 8 frames, and exits boundary | Kinematic velocity prediction maintains track across trajectory; motion trails render path; clean track deletion |
| W11| Nighttime Low-Light Detections with Low Confidence | F10, F11, F13, F14 | Low-contrast night video where object scores fluctuate between 0.12 and 0.35 | Stage 2 association prevents premature track termination; majority voting preserves class stability |
| W12| Crowd Congestion & Bounding Box Overlap | F11, F12, F13, F15 | Dense crowd scene with 20+ overlapping pedestrians walking in opposite directions | Class-aware NMS and center-distance gating prevent identity cross-talk; active tracks capped safely at 100 |
| W13| Warehouse Inventory Barcode & Box Verification | F10, F16, F28, F32 | Scanning warehouse inventory boxes; spatial zone categorizes Left/Center/Right staging areas | Real-time classification logged to Redis backend; telemetry dashboard displays active item count |
| W14| Rapid Device Rotation between Portrait & Landscape | F18, F26, F27 | Rotating Note 10 rapidly through portrait, landscape-left, and landscape-right orientations | Native letterbox rotates image coordinates dynamically; HUD overlays remain perfectly aligned with physical objects |
| W15| End-to-End Release Validation from Clean Machine | F36, F37, F40, F31 | Installing release signed APK on fresh Galaxy Note 10 with zero pre-existing configuration | App installs, launches, passes permissions, initializes native engine, and achieves performance targets |
| W16| Microservice Live Telemetry Dashboard Feed | F32, F33, F34 | 10 remote monitoring browser clients connected to WebSocket `/ws/telemetry` during live camera run | WebSocket broadcast updates connected clients with 0 dropped connections; Redis sorted set reflects live counts |
| W17| Sensor Obstruction (Camera Covered & Uncovered) | F10, F12, F14 | User covers camera lens with hand (all black frames) for 10 seconds, then uncovers | Tracks coast and delete gracefully after 30 frames; new tracks initialize instantly when scene is visible |
| W18| Mixed Class Crossing (Bicycle Crosses Pedestrian) | F11, F13, F14, F17 | Cyclist rides directly across the path of a walking pedestrian | Class-aware association prevents class swapping; pedestrian retains ID; cyclist retains ID |
| W19| Static Sample Batch Benchmark for CI Integration | F29, F18, F20 | Headless execution of sample benchmark across all 3 bundled photographs in automated CI runner | Exports structured JSON report with latency metrics and detection counts; exits with code 0 |
| W20| Full Production Deployment Smoke Test | F1–F40 (All) | Comprehensive deployment smoke test exercising monorepo relocation, native build, APK signing, and live run | 100% of functional requirements verified; zero regressions; `TEST_READY.md` criteria satisfied |

---

## 8. Coverage Thresholds & Quality Gates
- **Total Minimum Test Count**: 460 tests (200 Tier 1 + 200 Tier 2 + 40 Tier 3 + 20 Tier 4).
- **Pass Semantics**: Strict 100% pass rate (0 failures, 0 errors, 0 unhandled exceptions).
- **Execution Performance**: Host unit and boundary test suites must execute in $< 60$ seconds.
- **Publication Gate**: `TEST_READY.md` is published only when the test harness infrastructure, test case suites, and test runners are implemented, verified by peer review, and passing 100%.
