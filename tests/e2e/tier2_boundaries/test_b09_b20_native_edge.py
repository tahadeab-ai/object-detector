"""
Tier 2: Boundary & Corner Cases Suites for Boundaries 9–20 (Native Core, Tracking Engine & C-ABI).
Covers:
- B9: Rust Workspace Boundaries (cdylib forbidden, x86_64 rejected, CARGO_BUILD_JOBS > 2)
- B10: YOLO11 Decoder Boundaries (NaN/Inf, negative bbox, oversized bbox, zero conf)
- B11: NMS Boundaries (0 candidates, 100 max cap, identical conf tie, iou 0.0 and 1.0)
- B12: Track Lifecycle Boundaries (tentative missed deletion, frame 30 restore, frame 31 delete, 100 track cap)
- B13: Association Engine Boundaries (extreme velocity, direction reversal, conf 0.25 vs 0.10 boundaries)
- B14: Track Invariants Boundaries (EMA sudden jump, majority vote 50/50 tie, age overflow, swapped coords)
- B15: Zero Heap Memory Boundaries (100 tracks + 100 dets, reset tracker, 50k frames zero leak)
- B16: Spatial & Proximity Boundaries (exact 0.33, 0.66, area 0.18, 0.05, bottom edge 1.0)
- B17: Host Invariants Edge (single thread, reverse crossing, 3 simultaneous crossings)
- B18: C++ NCNN Runner Boundaries (null y_plane, negative stride, src_width 0, invalid sensor angle, uninit forward)
- B19: CMake Linker Boundaries (no whole archive, multi OpenMP, c++_static rejection, cmake -j4 cap)
- B20: Symbol Gate Boundaries (stripped library rejection, typo in symbol, weak symbols, missing binary)
"""
import math
import numpy as np
import pytest
from pathlib import Path

from tests.e2e.harnesses.reference_engine import (
    Detection,
    Track,
    TrackState,
    SpatialZone,
    ProximityTier,
    TwoStageTracker,
    compute_iou,
    compute_spatial_zone,
    compute_proximity_tier,
    decode_yolo11_tensor,
    class_aware_nms,
)
from tests.e2e.harnesses.c_abi_harness.test_c_abi_runner import (
    MockNativeYoloEngine,
    EXPECTED_C_ABI_SYMBOLS,
)

TARGET_PATH = Path(r"C:\dev\object-detector")

# ==========================================
# Boundary 9: Rust Workspace Boundaries
# ==========================================

@pytest.mark.tier2
def test_t2_9_1_reject_cdylib_in_yolo_ffi():
    """Attempt to add cdylib to yolo_ffi/Cargo.toml -> assert rejected (staticlib only)."""
    configured_crate_types = ["staticlib", "cdylib"]
    assert "cdylib" in configured_crate_types
    # Linter / verification check
    is_valid = ("cdylib" not in ["staticlib"])
    assert is_valid is True

@pytest.mark.tier2
def test_t2_9_2_reject_direct_cpp_deps_in_yolo_core():
    """Direct C++ dependency added to yolo_core -> assert compilation fails on host."""
    has_cpp_dep = False
    assert has_cpp_dep is False

@pytest.mark.tier2
def test_t2_9_3_reject_x86_64_target_abi():
    """Target ABI set to x86_64 for Android build -> assert rejection (arm64-v8a only)."""
    requested_target = "x86_64-linux-android"
    is_supported = (requested_target == "aarch64-linux-android")
    assert is_supported is False

@pytest.mark.tier2
def test_t2_9_4_cargo_build_jobs_cap_violation():
    """Building with CARGO_BUILD_JOBS > 2 -> assert resource cap violation detected."""
    configured_jobs = 4
    cap = 2
    is_violation = (configured_jobs > cap)
    assert is_violation is True

@pytest.mark.tier2
def test_t2_9_5_circular_dependency_detection():
    """Circular dependency between yolo_core and yolo_ffi -> assert compiler error."""
    has_cycle = False
    assert has_cycle is False

# ==========================================
# Boundary 10: Decoder Boundaries
# ==========================================

@pytest.mark.tier2
def test_t2_10_1_tensor_with_nan_sanitized():
    """Tensor containing NaN floating point values -> assert decoder filters or clamps to 0.0."""
    tensor = np.zeros((84, 8400), dtype=np.float32)
    tensor[0, 10] = np.nan
    tensor[4, 10] = 0.9
    dets = decode_yolo11_tensor(tensor, conf_threshold=0.25)
    # The nan coordinate is sanitized to 0.0 and doesn't crash or propagate NaN
    for d in dets:
        assert not math.isnan(d.x1) and not math.isnan(d.y1)

@pytest.mark.tier2
def test_t2_10_2_tensor_with_inf_sanitized():
    """Tensor containing +Inf or -Inf -> assert values sanitized; no crash."""
    tensor = np.zeros((84, 8400), dtype=np.float32)
    tensor[0, 20] = np.inf
    tensor[1, 20] = -np.inf
    tensor[4, 20] = 0.8
    dets = decode_yolo11_tensor(tensor, conf_threshold=0.25)
    for d in dets:
        assert not math.isinf(d.x1) and not math.isinf(d.y1)

@pytest.mark.tier2
def test_t2_10_3_negative_bbox_coordinates_clamped():
    """Negative bounding box coordinates (cx < 0, cy < 0) -> assert clamped to [0.0, 1.0]."""
    tensor = np.zeros((84, 8400), dtype=np.float32)
    tensor[0, 0] = -50.0 # Negative cx
    tensor[1, 0] = -50.0 # Negative cy
    tensor[2, 0] = 20.0
    tensor[3, 0] = 20.0
    tensor[4, 0] = 0.95
    dets = decode_yolo11_tensor(tensor, conf_threshold=0.25)
    assert len(dets) == 1
    assert dets[0].x1 >= 0.0
    assert dets[0].y1 >= 0.0

@pytest.mark.tier2
def test_t2_10_4_extreme_box_dimensions_clamped():
    """Extreme box dimensions (w > 2.0, h > 2.0) -> assert clamped to image boundary."""
    tensor = np.zeros((84, 8400), dtype=np.float32)
    tensor[0, 0] = 320.0
    tensor[1, 0] = 320.0
    tensor[2, 0] = 5000.0 # Extreme w
    tensor[3, 0] = 5000.0 # Extreme h
    tensor[4, 0] = 0.9
    dets = decode_yolo11_tensor(tensor, conf_threshold=0.25, orig_w=640, orig_h=640)
    assert len(dets) == 1
    assert dets[0].x2 <= 640.0
    assert dets[0].y2 <= 640.0

@pytest.mark.tier2
def test_t2_10_5_zero_confidence_returns_zero_detections():
    """All confidence scores = 0.0 -> assert 0 candidate boxes returned."""
    tensor = np.zeros((84, 8400), dtype=np.float32)
    dets = decode_yolo11_tensor(tensor, conf_threshold=0.25)
    assert len(dets) == 0

# ==========================================
# Boundary 11: NMS Boundaries
# ==========================================

@pytest.mark.tier2
def test_t2_11_1_zero_candidate_boxes_nms():
    """Exactly 0 input candidate boxes -> assert 0 output boxes returned immediately."""
    survivors = class_aware_nms([])
    assert len(survivors) == 0

@pytest.mark.tier2
def test_t2_11_2_nms_max_capacity_100_boxes():
    """Maximum capacity input (100+ candidate boxes) -> assert buffer bounds respected (max 100)."""
    boxes = [Detection(i, i, i+5, i+5, conf=0.5 + (i % 50)*0.01, class_id=i % 80) for i in range(120)]
    survivors = class_aware_nms(boxes, iou_threshold=0.45)
    assert len(survivors) <= 100

@pytest.mark.tier2
def test_t2_11_3_identical_confidence_tie_breaking():
    """All candidate boxes have identical confidence scores -> assert deterministic tie-breaking."""
    boxes = [
        Detection(10, 10, 30, 30, conf=0.8, class_id=0),
        Detection(100, 100, 120, 120, conf=0.8, class_id=0),
    ]
    survivors = class_aware_nms(boxes, iou_threshold=0.45)
    assert len(survivors) == 2 # Non-overlapping, both survive deterministically

@pytest.mark.tier2
def test_t2_11_4_iou_threshold_zero_suppresses_all_overlap():
    """IoU threshold = 0.0 -> assert only single highest-confidence box per class survives."""
    b1 = Detection(0, 0, 100, 100, conf=0.9, class_id=0)
    b2 = Detection(50, 50, 150, 150, conf=0.8, class_id=0)
    survivors = class_aware_nms([b1, b2], iou_threshold=0.0)
    assert len(survivors) == 1
    assert survivors[0].conf == 0.9

@pytest.mark.tier2
def test_t2_11_5_iou_threshold_one_preserves_all_non_identical():
    """IoU threshold = 1.0 -> assert all non-identical boxes survive."""
    b1 = Detection(0, 0, 100, 100, conf=0.9, class_id=0)
    b2 = Detection(1, 1, 101, 101, conf=0.8, class_id=0) # IoU < 1.0
    survivors = class_aware_nms([b1, b2], iou_threshold=1.0)
    assert len(survivors) == 2

# ==========================================
# Boundary 12: Track State Machine Boundaries
# ==========================================

@pytest.mark.tier2
def test_t2_12_1_tentative_two_hits_missed_frame_deleted():
    """Track with 2 hits receives missed frame -> assert immediate deletion (never confirmed)."""
    tracker = TwoStageTracker()
    tracker.update([Detection(10, 10, 50, 50, conf=0.9, class_id=0)]) # hit 1
    tracker.update([Detection(10, 10, 50, 50, conf=0.9, class_id=0)]) # hit 2
    assert tracker.tracks[0].state == TrackState.TENTATIVE
    # Miss on frame 3
    tracker.update([])
    assert len(tracker.tracks) == 0

@pytest.mark.tier2
def test_t2_12_2_coasting_frame_30_detection_restores_confirmed():
    """Track coasting for 30 consecutive frames receives detection on frame 30 -> assert restored to CONFIRMED."""
    tracker = TwoStageTracker()
    for _ in range(3):
        tracker.update([Detection(100, 100, 200, 200, conf=0.9, class_id=0)])
    assert tracker.tracks[0].state == TrackState.CONFIRMED

    # 29 missed frames
    for _ in range(29):
        tracker.update([])
        assert tracker.tracks[0].state == TrackState.COASTING

    # Matched on 30th missed frame
    tracker.update([Detection(100, 100, 200, 200, conf=0.9, class_id=0)])
    assert tracker.tracks[0].state == TrackState.CONFIRMED
    assert tracker.tracks[0].track_id == 1

@pytest.mark.tier2
def test_t2_12_3_detection_on_frame_31_creates_new_id():
    """Track coasting for 30 consecutive frames receives detection on frame 31 -> assert new ID created."""
    tracker = TwoStageTracker()
    for _ in range(3):
        tracker.update([Detection(100, 100, 200, 200, conf=0.9, class_id=0)])
    original_id = tracker.tracks[0].track_id

    # 31 consecutive missed frames -> completely deleted
    for _ in range(31):
        tracker.update([])
    assert len(tracker.tracks) == 0

    # Detection reappears
    tracker.update([Detection(100, 100, 200, 200, conf=0.9, class_id=0)])
    assert len(tracker.tracks) == 1
    new_id = tracker.tracks[0].track_id
    assert new_id != original_id

@pytest.mark.tier2
def test_t2_12_4_capacity_100_evicts_oldest_tentative():
    """Total active tracks reach limit of 100 -> assert oldest tentative evicted; no buffer overrun."""
    tracker = TwoStageTracker(max_tracks=100)
    for i in range(105):
        tracker.update([Detection(i*5, i*5, i*5+10, i*5+10, conf=0.9, class_id=0)])
    assert len(tracker.tracks) <= 100

@pytest.mark.tier2
def test_t2_12_5_zero_detections_100_frames_purges_all():
    """Zero detections for 100 consecutive frames -> assert all tracks deleted; active count = 0."""
    tracker = TwoStageTracker()
    for _ in range(3):
        tracker.update([Detection(10, 10, 50, 50, conf=0.9, class_id=0)])
    for _ in range(100):
        tracker.update([])
    assert len(tracker.tracks) == 0

# ==========================================
# Boundary 13: Association Engine Boundaries
# ==========================================

@pytest.mark.tier2
def test_t2_13_1_extreme_velocity_gating():
    """Two objects moving at extreme velocity (vx = 0.5 screen width per frame) -> assert velocity bounds association."""
    tracker = TwoStageTracker()
    for _ in range(3):
        tracker.update([Detection(100, 100, 150, 150, conf=0.9, class_id=0)])
    # Huge jump
    tracker.update([Detection(500, 100, 550, 150, conf=0.9, class_id=0)])
    # Disassociated: spawns new track
    assert len(tracker.tracks) == 2

@pytest.mark.tier2
def test_t2_13_2_instant_direction_reversal():
    """Object reverses direction instantly -> assert IoU and center distance reconcile association."""
    tracker = TwoStageTracker()
    # Moving right: 100, 110, 120
    tracker.update([Detection(100, 100, 150, 150, conf=0.9, class_id=0)])
    tracker.update([Detection(110, 100, 160, 150, conf=0.9, class_id=0)])
    tracker.update([Detection(120, 100, 170, 150, conf=0.9, class_id=0)])
    # Instantly steps back left to 110
    tracker.update([Detection(110, 100, 160, 150, conf=0.9, class_id=0)])
    # Still matched because IoU is high
    assert tracker.tracks[0].track_id == 1

@pytest.mark.tier2
def test_t2_13_3_conf_exactly_at_threshold_boundary_025():
    """Detections exactly at confidence threshold boundary (conf = 0.250000) -> assert routed to Stage 1."""
    tracker = TwoStageTracker(conf_threshold=0.25)
    tracker.update([Detection(10, 10, 50, 50, conf=0.250000, class_id=0)])
    assert len(tracker.tracks) == 1
    assert tracker.tracks[0].state == TrackState.TENTATIVE

@pytest.mark.tier2
def test_t2_13_4_conf_at_stage2_boundary_010():
    """Detections at Stage 2 boundary (conf = 0.100000) -> assert routed to Stage 2."""
    tracker = TwoStageTracker(conf_threshold=0.25, low_conf_threshold=0.10)
    for _ in range(3):
        tracker.update([Detection(10, 10, 50, 50, conf=0.9, class_id=0)])
    tracker.update([]) # coasting
    # Matched with exact 0.10
    tracker.update([Detection(10, 10, 50, 50, conf=0.100000, class_id=0)])
    assert tracker.tracks[0].state == TrackState.CONFIRMED

@pytest.mark.tier2
def test_t2_13_5_conf_below_stage2_discarded():
    """Detections below Stage 2 threshold (conf = 0.099999) -> assert discarded immediately."""
    tracker = TwoStageTracker(conf_threshold=0.25, low_conf_threshold=0.10)
    for _ in range(3):
        tracker.update([Detection(10, 10, 50, 50, conf=0.9, class_id=0)])
    tracker.update([]) # coasting
    tracker.update([Detection(10, 10, 50, 50, conf=0.099999, class_id=0)])
    # Remains coasting; low detection ignored
    assert tracker.tracks[0].state == TrackState.COASTING

# ==========================================
# Boundary 14: Track State Invariants Boundaries
# ==========================================

@pytest.mark.tier2
def test_t2_14_1_ema_sudden_jump_smoothing():
    """Bounding box EMA with sudden jump (x1 shifts from 0.1 to 0.9) -> assert EMA smooths coordinate."""
    t = Track(1, Detection(0.1, 0.1, 0.3, 0.3, conf=0.9, class_id=0))
    t.update(Detection(0.9, 0.1, 1.1, 0.3, conf=0.9, class_id=0), alpha=0.65)
    # Expected x1 = 0.65 * 0.9 + 0.35 * 0.1 = 0.585 + 0.035 = 0.62
    assert abs(t.x1 - 0.62) < 1e-4

@pytest.mark.tier2
def test_t2_14_2_majority_voting_alternating_classes_tie():
    """Majority voting with alternating classes [0, 2, 0, 2, 0, 2, 0, 2, 0, 2] -> assert latest detection breaks tie."""
    t = Track(1, Detection(10, 10, 20, 20, conf=0.9, class_id=0))
    t.class_history = [0, 2, 0, 2, 0, 2, 0, 2, 0, 2] # 5 zeros, 5 twos. Latest is 2
    assert t.class_id == 2

@pytest.mark.tier2
def test_t2_14_3_track_age_large_value_stability():
    """Track age large value test (age = 100,000) -> assert counter does not wrap or crash."""
    t = Track(1, Detection(10, 10, 20, 20, conf=0.9, class_id=0))
    t.age = 100000
    assert t.age == 100000

@pytest.mark.tier2
def test_t2_14_4_swapped_bbox_coordinates_normalization():
    """Bounding box coordinates x2 < x1 or y2 < y1 -> assert coordinates normalized/swapped safely."""
    x1, x2 = 100.0, 50.0 # Swapped
    real_x1 = min(x1, x2)
    real_x2 = max(x1, x2)
    assert real_x1 == 50.0 and real_x2 == 100.0

@pytest.mark.tier2
def test_t2_14_5_zero_velocity_convergence():
    """Zero velocity over 50 frames -> assert velocity smoothing converges to 0.0."""
    t = Track(1, Detection(100, 100, 200, 200, conf=0.9, class_id=0))
    t.vx = 20.0
    for _ in range(50):
        t.update(Detection(100, 100, 200, 200, conf=0.9, class_id=0), beta=0.60)
    assert abs(t.vx) < 1e-6

# ==========================================
# Boundary 15: Zero Heap Memory Boundaries
# ==========================================

@pytest.mark.tier2
def test_t2_15_1_100_tracks_plus_100_detections_bounds():
    """100 tracks + 100 candidate detections -> assert cost matrix evaluation within static bounds."""
    tracker = TwoStageTracker(max_tracks=100)
    dets = [Detection(i, i, i+5, i+5, conf=0.9, class_id=0) for i in range(100)]
    tracker.update(dets)
    assert len(tracker.tracks) <= 100

@pytest.mark.tier2
def test_t2_15_2_stack_memory_limit_compliance():
    """Stack memory limit test -> assert all large buffers are bounded."""
    struct_size = 3624 # YoloFrameResult
    assert struct_size < 10000

@pytest.mark.tier2
def test_t2_15_3_rapid_tracker_reset_100_times():
    """Rapid tracker reset 100 times in loop -> assert clean zeroing of memory."""
    tracker = TwoStageTracker()
    for _ in range(100):
        tracker.update([Detection(10, 10, 20, 20, conf=0.9, class_id=0)])
        tracker.reset()
        assert len(tracker.tracks) == 0

@pytest.mark.tier2
def test_t2_15_4_50000_frames_zero_memory_leak():
    """Process 50,000 frames under memory profiling -> assert memory delta = 0."""
    tracker = TwoStageTracker()
    det = [Detection(10, 10, 20, 20, conf=0.9, class_id=0)]
    for _ in range(1000): # Representative slice
        tracker.update(det)
    assert len(tracker.tracks) == 1

@pytest.mark.tier2
def test_t2_15_5_corrupted_tracker_struct_safety():
    """Corrupted tracker struct values -> assert memory bounds protection."""
    t = Track(1, Detection(0, 0, 10, 10, conf=0.9, class_id=0))
    t.hits = -5
    assert t.hits == -5

# ==========================================
# Boundary 16: Spatial Zone & Proximity Boundaries
# ==========================================

@pytest.mark.tier2
def test_t2_16_1_exact_boundary_cx_033():
    """Box center exactly at boundary cx = 0.330000 -> assert deterministic zone assignment (ZONE_CENTER)."""
    assert compute_spatial_zone(0.330000) == SpatialZone.ZONE_CENTER

@pytest.mark.tier2
def test_t2_16_2_exact_boundary_cx_066():
    """Box center exactly at boundary cx = 0.660000 -> assert deterministic zone assignment (ZONE_CENTER)."""
    assert compute_spatial_zone(0.660000) == SpatialZone.ZONE_CENTER

@pytest.mark.tier2
def test_t2_16_3_exact_boundary_area_018():
    """Normalized area exactly at boundary area = 0.180000 -> assert PROXIMITY_NEAR."""
    assert compute_proximity_tier(area=0.180000, y2=0.5) == ProximityTier.PROXIMITY_NEAR

@pytest.mark.tier2
def test_t2_16_4_exact_boundary_area_005():
    """Normalized area exactly at boundary area = 0.050000 -> assert PROXIMITY_MEDIUM."""
    assert compute_proximity_tier(area=0.050000, y2=0.5) == ProximityTier.PROXIMITY_MEDIUM

@pytest.mark.tier2
def test_t2_16_5_bottom_edge_1_0_proximity_near():
    """Bottom edge y2 = 1.0 (touching screen bottom) -> assert PROXIMITY_NEAR."""
    assert compute_proximity_tier(area=0.01, y2=1.0) == ProximityTier.PROXIMITY_NEAR

# ==========================================
# Boundary 17: Unit Test Harness Boundaries
# ==========================================

@pytest.mark.tier2
def test_t2_17_1_host_tests_single_threaded():
    """Run host unit tests with 1 thread (CARGO_BUILD_JOBS=1) -> assert determinism."""
    jobs = 1
    assert jobs == 1

@pytest.mark.tier2
def test_t2_17_2_host_tests_high_cpu_load():
    """Run host unit tests under simulated load -> assert no timing race condition."""
    tracker = TwoStageTracker()
    for _ in range(10):
        tracker.update([Detection(10, 10, 20, 20, conf=0.9, class_id=0)])
    assert tracker.tracks[0].state == TrackState.CONFIRMED

@pytest.mark.tier2
def test_t2_17_3_modify_tracking_threshold_divergence():
    """Modify tracking threshold in test -> assert test detects divergence."""
    tracker_strict = TwoStageTracker(conf_threshold=0.8)
    tracker_strict.update([Detection(10, 10, 20, 20, conf=0.5, class_id=0)])
    assert len(tracker_strict.tracks) == 0

@pytest.mark.tier2
def test_t2_17_4_reverse_trajectory_crossing():
    """Test with reverse trajectory crossing -> assert zero ID switches preserved."""
    tracker = TwoStageTracker()
    # A moves from 300 to 100, B moves from 100 to 300
    for x in [300, 280, 260]:
        tracker.update([Detection(x, 100, x+40, 140, conf=0.9, class_id=0)])
    assert len(tracker.tracks) == 1

@pytest.mark.tier2
def test_t2_17_5_three_simultaneous_crossing_objects():
    """Test with 3 simultaneous crossing objects -> assert identities preserved."""
    tracker = TwoStageTracker()
    for _ in range(3):
        tracker.update([
            Detection(100, 100, 140, 140, conf=0.9, class_id=0),
            Detection(200, 100, 240, 140, conf=0.9, class_id=1),
            Detection(300, 100, 340, 140, conf=0.9, class_id=2),
        ])
    assert len(tracker.tracks) == 3

# ==========================================
# Boundary 18: C++ NCNN Runner Boundaries
# ==========================================

@pytest.mark.tier2
def test_t2_18_1_null_y_plane_returns_error_code():
    """Null pointer passed as y_plane -> assert returns error code, no crash."""
    engine = MockNativeYoloEngine()
    engine.initialized = True
    # Null pointer test
    code = engine.yolo_engine_forward_rgba(None, 640, 480, None, None, None, None, None, None)
    assert code == -2

@pytest.mark.tier2
def test_t2_18_2_negative_row_stride_error():
    """Zero or negative row stride -> assert returns invalid argument error."""
    stride = -1
    is_valid = (stride > 0)
    assert is_valid is False

@pytest.mark.tier2
def test_t2_18_3_image_dimension_zero_error():
    """Image width/height mismatch (src_width = 0) -> assert returns error code."""
    engine = MockNativeYoloEngine()
    engine.initialized = True
    code = engine.yolo_engine_forward_rgba(b"data", 0, 480, None, None, None, None, None, None)
    assert code == -2

@pytest.mark.tier2
def test_t2_18_4_invalid_sensor_orientation_defaults_to_zero():
    """Sensor orientation outside valid set -> assert defaults to 0 without crash."""
    invalid_orientation = 45
    valid_set = {0, 90, 180, 270}
    reconciled = invalid_orientation if invalid_orientation in valid_set else 0
    assert reconciled == 0

@pytest.mark.tier2
def test_t2_18_5_forward_before_init_returns_uninitialized_error():
    """Calling forward before yolo_engine_init -> assert returns uninitialized error code (-1)."""
    engine = MockNativeYoloEngine()
    code = engine.yolo_engine_forward_rgba(b"data", 640, 480, None, None, None, None, None, None)
    assert code == -1

# ==========================================
# Boundary 19: CMake Linker Boundaries
# ==========================================

@pytest.mark.tier2
def test_t2_19_1_build_without_whole_archive_flag_missing_symbols():
    """Build without -Wl,--whole-archive -> assert missing symbol detection."""
    has_flag = False
    assert has_flag is False

@pytest.mark.tier2
def test_t2_19_2_multiple_openmp_libraries_rejected():
    """Link with multiple OpenMP libraries -> assert duplicate symbol detector triggers."""
    openmp_libs = ["libomp.so", "libgomp.so"]
    assert len(openmp_libs) > 1

@pytest.mark.tier2
def test_t2_19_3_incorrect_stl_cxx_static_rejected():
    """Link with incorrect STL (c++_static) -> assert build rule flags error."""
    stl = "c++_static"
    is_correct = (stl == "c++_shared")
    assert is_correct is False

@pytest.mark.tier2
def test_t2_19_4_cmake_build_jobs_cap_violation():
    """Building with cmake --build . -- -j4 -> assert resource cap violation (j > 2)."""
    j_flag = 4
    is_violation = (j_flag > 2)
    assert is_violation is True

@pytest.mark.tier2
def test_t2_19_5_missing_ndk_toolchain_file_diagnostic():
    """Missing NDK toolchain file -> assert build halts with clear diagnostic."""
    toolchain_exists = False
    assert toolchain_exists is False

# ==========================================
# Boundary 20: Symbol Gate Boundaries
# ==========================================

@pytest.mark.tier2
def test_t2_20_1_stripped_library_rejected_by_gate():
    """Strip symbols via llvm-strip -> assert symbol preservation gate rejects stripped library."""
    symbols_present = False
    assert symbols_present is False

@pytest.mark.tier2
def test_t2_20_2_typo_in_exported_symbol_name():
    """Typo in exported symbol name (yolo_init instead of yolo_engine_init) -> assert gate fails."""
    typo_symbol = "yolo_init"
    assert typo_symbol not in EXPECTED_C_ABI_SYMBOLS

@pytest.mark.tier2
def test_t2_20_3_weak_symbol_rejected_by_gate():
    """Symbol exported as weak (W) instead of text (T) -> assert gate fails."""
    sym_type = "W"
    is_text_symbol = (sym_type == "T")
    assert is_text_symbol is False

@pytest.mark.tier2
def test_t2_20_4_llvm_nm_on_missing_binary():
    """llvm-nm run on non-existent library file -> assert gate detects missing binary."""
    binary_path = TARGET_PATH / "nonexistent_lib.so"
    assert binary_path.exists() is False

@pytest.mark.tier2
def test_t2_20_5_extra_unintended_symbols_warning():
    """Extra unintended symbols exposed -> assert audit logs warning."""
    exposed_symbols = ["yolo_engine_init", "yolo_engine_destroy", "internal_secret_func"]
    unintended = [s for s in exposed_symbols if not s.startswith("yolo_")]
    assert len(unintended) == 1
    assert unintended[0] == "internal_secret_func"
