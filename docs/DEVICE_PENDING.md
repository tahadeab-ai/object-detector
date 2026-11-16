# Deferred Physical Device Verification Items (F10 Device-Absent Mode)

**Mode**: F10 Device-Absent Mode active for Phases 2, 3A, and 4.  
**Target Hardware**: Samsung Galaxy Note 10 (`SM-N970U`, serial `R58M95PJVZT`, Qualcomm Snapdragon 855 / `msmnile`, `arm64-v8a`).  
**Status**: The device is physically disconnected. In accordance with rule F10, execution does NOT pause and no emulator is launched. All on-device tests and live hardware profiling steps listed below are deferred strictly to Phase 5.

---

## Deferred Device Verification Register

| Phase / Task ID | Deferred Item Description | Verification Prerequisite | Mandatory Threshold at Phase 5 Gate |
| :--- | :--- | :--- | :--- |
| **Phase 2 / D-P2.1** | Live on-device load of `libyolo_ncnn.so` via `System.loadLibrary` | Physical Note 10 USB connection | Dynamic linker loads without dlopen errors or missing symbols |
| **Phase 2 / D-P2.2** | Snapdragon 855 ARM NEON 4T vs Adreno 640 Vulkan backend selection | Physical Note 10 GPU driver / Vulkan | `use_vulkan_compute=true` initializes successfully or falls back cleanly |
| **Phase 3A / D-P3.1**| Flutter live camera stream binding (`camera` plugin NV21 / YUV420) | Physical camera sensor (`ro.product.model=SM-N970U`) | Camera frame buffer passes cleanly to worker isolate without dropped frame cascade |
| **Phase 3A / D-P3.2**| Decoupled 60.0 FPS HUD rendering on Note 10 Dynamic AMOLED display | Physical Note 10 screen display | CustomPainter overlay renders independently of native inference loop |
| **Phase 4 / D-P4.1** | Go microservice telemetry sync over local device Wi-Fi/ADB port reverse | Physical device network interface | Redis stream client receives serialized detection payloads |
| **Phase 5 / D-P5.1** | 60-second warmup + 100-frame sustained FPS benchmark | Physical Snapdragon 855 hardware | CPU NEON $\ge 12.0$ FPS; Vulkan GPU $\ge 20.0$ FPS |
| **Phase 5 / D-P5.2** | Battery & thermal throttling soak profile | Note 10 battery / thermal sysfs nodes | Temperature $\le 42.0^\circ\text{C}$; zero memory leak over 30-minute run |
| **Phase 5 / D-P5.3** | Live multi-object crossing tracking benchmark | Physical camera scene | $\le 1$ ID switch over 30 seconds of live multi-object tracking |

---

## Integrity Attestation
Per Zero-Fabrication Principle (A5 / RESTORE-3), zero synthetic benchmarks, zero mock logcats, and zero emulated screenshots are generated for any of the above items during Phases 2, 3A, and 4.
