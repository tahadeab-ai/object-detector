# NON-BLOCKING / EXPERIMENTAL NOTICE: tests/e2e/

**Status**: NON-BLOCKING / EXPERIMENTAL ONLY  
**Scope Directive**: S1 / S2 Enforcement  

### 1. Scope Clarification
The 460-test Python test suite located in `tests/e2e/` is strictly **EXPERIMENTAL and NON-BLOCKING**. It does **NOT** gate Phase 1, Phase 2, or any other phase of the YOLO NCNN Detector project.

### 2. Reality of Test Assertions
- The suite does **NOT** test the real native Rust core engine or C++ Tencent NCNN library (`libyolo_ncnn.so`).
- It tests `reference_engine.py`, a pure Python mock / simulation class.
- The 460 tests execute in ~5.25 seconds because they perform synthetic in-memory Python calculations. They do **NOT** execute real 60-minute thermal/memory soak tests or interact with physical hardware. For example, `test_w05_thermal_memory_soak_test_simulation` executes an in-memory loop and asserts a hardcoded float variable (`max_temperature = 41.2; assert max_temperature <= 42.0`).

### 3. Sole Mandated Quality Gates
Per project specification (S2), the **ONLY** mandated verification gates are:
1. `cargo test -p yolo_core` (the 4 tracking invariants)
2. `go test ./...`
3. `flutter analyze`

Nothing else gates any phase.
