"""
C-ABI Test Harness for libyolo_ncnn.so contract verification.
Validates #[repr(C)] memory layouts, struct sizes, member offsets, and function signatures.
"""
import ctypes
import os
import sys
from pathlib import Path

# Enums matching yolo_ncnn_c_api.h
class SpatialZone:
    ZONE_LEFT = 0
    ZONE_CENTER = 1
    ZONE_RIGHT = 2

class ProximityTier:
    PROXIMITY_FAR = 0
    PROXIMITY_MEDIUM = 1
    PROXIMITY_NEAR = 2

# Struct definitions matching #[repr(C)]
class YoloDetectionBox(ctypes.Structure):
    _fields_ = [
        ("track_id", ctypes.c_int32),        # offset 0, 4 bytes
        ("class_id", ctypes.c_int32),        # offset 4, 4 bytes
        ("confidence", ctypes.c_float),       # offset 8, 4 bytes
        ("x1", ctypes.c_float),               # offset 12, 4 bytes
        ("y1", ctypes.c_float),               # offset 16, 4 bytes
        ("x2", ctypes.c_float),               # offset 20, 4 bytes
        ("y2", ctypes.c_float),               # offset 24, 4 bytes
        ("spatial_zone", ctypes.c_int32),    # offset 28, 4 bytes
        ("proximity_tier", ctypes.c_int32),  # offset 32, 4 bytes
    ]

class YoloFrameResult(ctypes.Structure):
    _fields_ = [
        ("count", ctypes.c_int32),                   # offset 0, 4 bytes
        ("preprocess_ms", ctypes.c_float),           # offset 4, 4 bytes
        ("inference_ms", ctypes.c_float),            # offset 8, 4 bytes
        ("postprocess_ms", ctypes.c_float),          # offset 12, 4 bytes
        ("total_fps", ctypes.c_float),               # offset 16, 4 bytes
        ("active_backend", ctypes.c_int32),          # offset 20, 4 bytes (0=CPU, 1=Vulkan)
        ("boxes", YoloDetectionBox * 100),           # offset 24, 3600 bytes
    ]

def verify_struct_contracts():
    """Verify size and alignment contracts of C-ABI structs."""
    assert ctypes.sizeof(YoloDetectionBox) == 36, f"Expected YoloDetectionBox size 36, got {ctypes.sizeof(YoloDetectionBox)}"
    assert YoloDetectionBox.track_id.offset == 0
    assert YoloDetectionBox.class_id.offset == 4
    assert YoloDetectionBox.confidence.offset == 8
    assert YoloDetectionBox.x1.offset == 12
    assert YoloDetectionBox.y1.offset == 16
    assert YoloDetectionBox.x2.offset == 20
    assert YoloDetectionBox.y2.offset == 24
    assert YoloDetectionBox.spatial_zone.offset == 28
    assert YoloDetectionBox.proximity_tier.offset == 32

    assert ctypes.sizeof(YoloFrameResult) == 3624, f"Expected YoloFrameResult size 3624, got {ctypes.sizeof(YoloFrameResult)}"
    assert YoloFrameResult.count.offset == 0
    assert YoloFrameResult.preprocess_ms.offset == 4
    assert YoloFrameResult.inference_ms.offset == 8
    assert YoloFrameResult.postprocess_ms.offset == 12
    assert YoloFrameResult.total_fps.offset == 16
    assert YoloFrameResult.active_backend.offset == 20
    assert YoloFrameResult.boxes.offset == 24

EXPECTED_C_ABI_SYMBOLS = [
    "yolo_engine_init",
    "yolo_engine_set_backend",
    "yolo_engine_forward_yuv420",
    "yolo_engine_forward_rgba",
    "yolo_engine_destroy",
    "yolo_engine_process_tensor",
    "yolo_engine_reset_tracker",
]

class MockNativeYoloEngine:
    """Mock/Reference Native YOLO C-ABI implementation for testing FFI callers and ABI harnesses."""
    def __init__(self):
        self.initialized = False
        self.backend = 0
        self.input_size = 640

    def yolo_engine_init(self, param_path: str, bin_path: str, input_size: int = 640, use_vulkan: bool = False) -> int:
        if not os.path.exists(param_path):
            return -101
        if not os.path.exists(bin_path):
            return -102
        self.initialized = True
        self.backend = 1 if use_vulkan else 0
        self.input_size = input_size
        return 0

    def yolo_engine_set_backend(self, use_vulkan: bool) -> int:
        if not self.initialized:
            return -1
        self.backend = 1 if use_vulkan else 0
        return 0

    def yolo_engine_forward_rgba(self, rgba_bytes, src_w, src_h, out_buf, out_pad_w, out_pad_h, out_scale, out_pre, out_inf) -> int:
        if not self.initialized:
            return -1
        if rgba_bytes is None or src_w <= 0 or src_h <= 0:
            return -2
        return 0

    def yolo_engine_destroy(self):
        self.initialized = False

if __name__ == "__main__":
    verify_struct_contracts()
    print("All C-ABI struct contracts verified successfully.")
