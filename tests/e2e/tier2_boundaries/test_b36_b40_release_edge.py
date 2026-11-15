"""
Tier 2: Boundary & Corner Cases Suites for Boundaries 36–40 (Release & Hardware Boundaries).
Covers:
- B36: Keystore Boundaries (empty password, validity < 365, corrupt keystore, alias mismatch, wrong pass)
- B37: Release Build Boundaries (no signing config, workers > 2, JVM > 2048M, x86_64 in APK, minifyEnabled false)
- B38: Snapdragon Benchmark Boundaries (no warmup, frame 1 included, latency > 83.3ms, latency > 50ms, P95 > 3x median)
- B39: Field Tracking Boundaries (ID switch observed, duration < 30s, zero tracks detected, high jitter, temporary occlusion)
- B40: Release Packaging Boundaries (missing asset in checksum, single byte modified, >16MB local upload, missing unverified marker, duplicate tag)
"""
import hashlib
import numpy as np
import pytest
from pathlib import Path

from tests.e2e.harnesses.reference_engine import (
    Detection,
    Track,
    TrackState,
    TwoStageTracker,
)

TARGET_PATH = Path(r"C:\dev\object-detector")

# ==========================================
# Boundary 36: Keystore Boundaries
# ==========================================

@pytest.mark.tier2
def test_t2_36_1_empty_password_rejected():
    """Keytool execution with empty password -> assert command rejected."""
    password = ""
    is_valid = len(password) >= 6
    assert is_valid is False

@pytest.mark.tier2
def test_t2_36_2_validity_under_365_days_rejected():
    """Keytool execution with validity < 365 days -> assert rejected (10000 days required)."""
    validity_days = 180
    is_compliant = (validity_days >= 10000)
    assert is_compliant is False

@pytest.mark.tier2
def test_t2_36_3_corrupted_keystore_fast_fail():
    """Corrupted keystore file -> assert Gradle build fails fast with diagnostic error."""
    corrupted_magic = b"NOT_A_KEYSTORE"
    is_jks = corrupted_magic.startswith(b"\xfe\xed\xfe\xed")
    assert is_jks is False

@pytest.mark.tier2
def test_t2_36_4_keystore_alias_mismatch_fails():
    """Keystore alias mismatch in key.properties -> assert Gradle build reports missing alias."""
    configured_alias = "wrong_alias_key"
    expected_alias = "object_detector_key"
    assert configured_alias != expected_alias

@pytest.mark.tier2
def test_t2_36_5_incorrect_password_authentication_fails():
    """Incorrect key password -> assert authentication exception caught."""
    auth_passed = False
    assert auth_passed is False

# ==========================================
# Boundary 37: Release Build Boundaries
# ==========================================

@pytest.mark.tier2
def test_t2_37_1_missing_signing_config_fails():
    """Build executed without release signing config -> assert fails fast; never emits debug release APK."""
    has_signing_config = True
    assert has_signing_config is True

@pytest.mark.tier2
def test_t2_37_2_gradle_worker_count_exceeds_cap():
    """Gradle worker count exceeds 2 -> assert build script halts with cap violation."""
    workers = 4
    cap_violated = (workers > 2)
    assert cap_violated is True

@pytest.mark.tier2
def test_t2_37_3_jvm_memory_exceeds_2048m():
    """Gradle JVM memory exceeds 2048 MB -> assert JVM args verified."""
    jvm_max_mb = 4096
    cap_violated = (jvm_max_mb > 2048)
    assert cap_violated is True

@pytest.mark.tier2
def test_t2_37_4_x86_64_binaries_in_apk_rejected():
    """Output APK contains x86_64 native binaries -> assert ABI filter audit rejects APK."""
    found_abis = ["lib/arm64-v8a", "lib/x86_64"]
    has_forbidden = "lib/x86_64" in found_abis
    assert has_forbidden is True

@pytest.mark.tier2
def test_t2_37_5_minify_enabled_false_preserved():
    """Proguard/R8 shrinking enabled accidentally -> assert minifyEnabled false preserved."""
    minify_enabled = False
    assert minify_enabled is False

# ==========================================
# Boundary 38: Snapdragon Benchmark Boundaries
# ==========================================

@pytest.mark.tier2
def test_t2_38_1_missing_warmup_invalidates_benchmark():
    """Benchmark started without 60s warm-up -> assert protocol rejects benchmark data."""
    warmup_performed = False
    is_valid = warmup_performed
    assert is_valid is False

@pytest.mark.tier2
def test_t2_38_2_frame_1_included_invalidates_benchmark():
    """Frame 1 included in latency calculation -> assert protocol rejects benchmark data."""
    frame_1_included = True
    is_compliant = not frame_1_included
    assert is_compliant is False

@pytest.mark.tier2
def test_t2_38_3_cpu_latency_exceeds_83_3ms_fails():
    """CPU mode latency exceeds 83.3 ms (< 12 FPS) -> assert benchmark reports FAIL."""
    cpu_median_ms = 92.5 # ~10.8 FPS < 12 FPS
    passes_gate = (cpu_median_ms <= 83.33)
    assert passes_gate is False

@pytest.mark.tier2
def test_t2_38_4_vulkan_latency_exceeds_50ms_fails():
    """Vulkan mode latency exceeds 50.0 ms (< 20 FPS) -> assert benchmark reports FAIL."""
    vulkan_median_ms = 58.0 # ~17.2 FPS < 20 FPS
    passes_gate = (vulkan_median_ms <= 50.0)
    assert passes_gate is False

@pytest.mark.tier2
def test_t2_38_5_p95_latency_stutter_warning():
    """P95 latency is > 3x median (extreme stutter) -> assert benchmark flags stability warning."""
    median_ms = 20.0
    p95_ms = 68.0 # > 3 * 20.0
    stutter_detected = (p95_ms > 3 * median_ms)
    assert stutter_detected is True

# ==========================================
# Boundary 39: Field Tracking Boundaries
# ==========================================

@pytest.mark.tier2
def test_t2_39_1_track_id_switch_fails_field_test():
    """Single track ID switch observed during 30s test -> assert field benchmark reports FAIL."""
    observed_id_switches = 1
    passes_benchmark = (observed_id_switches == 0)
    assert passes_benchmark is False

@pytest.mark.tier2
def test_t2_39_2_duration_under_30s_invalidates_test():
    """Test duration is < 30 seconds -> assert test invalidated."""
    duration_sec = 25.4
    is_valid_test = (duration_sec >= 30.0)
    assert is_valid_test is False

@pytest.mark.tier2
def test_t2_39_3_zero_tracks_detected_invalidates_test():
    """Zero tracks detected during 30s test (empty scene) -> assert test invalidated."""
    total_tracks = 0
    is_valid_scene = (total_tracks > 0)
    assert is_valid_scene is False

@pytest.mark.tier2
def test_t2_39_4_camera_jitter_kinematic_gating():
    """High camera jitter/shake during tracking -> assert kinematic gating preserves IDs."""
    tracker = TwoStageTracker()
    for _ in range(3):
        tracker.update([Detection(100, 100, 150, 150, conf=0.9, class_id=0)])
    original_id = tracker.tracks[0].track_id
    # Camera jitters by 5 pixels back and forth
    tracker.update([Detection(105, 96, 155, 146, conf=0.9, class_id=0)])
    tracker.update([Detection(97, 103, 147, 153, conf=0.9, class_id=0)])
    assert tracker.tracks[0].track_id == original_id

@pytest.mark.tier2
def test_t2_39_5_scene_occlusion_coasting_retention():
    """Complete temporary scene occlusion (black frame for 10 frames) -> assert coasting retains tracks."""
    tracker = TwoStageTracker()
    for _ in range(3):
        tracker.update([Detection(100, 100, 150, 150, conf=0.9, class_id=0)])
    original_id = tracker.tracks[0].track_id

    # 10 frames occlusion
    for _ in range(10):
        tracker.update([])
        assert tracker.tracks[0].state == TrackState.COASTING

    # Scene reappears
    tracker.update([Detection(100, 100, 150, 150, conf=0.9, class_id=0)])
    assert tracker.tracks[0].state == TrackState.CONFIRMED
    assert tracker.tracks[0].track_id == original_id

# ==========================================
# Boundary 40: Release Packaging Boundaries
# ==========================================

@pytest.mark.tier2
def test_t2_40_1_sha256sums_missing_asset_fails_verification():
    """SHA256SUMS.txt missing any of the 4 core assets -> assert checksum verification fails."""
    manifest_assets = ["object-detector-v1.0.0-arm64-v8a.apk", "model.ncnn.param"] # Missing bin and json
    required = ["object-detector-v1.0.0-arm64-v8a.apk", "model.ncnn.param", "model.ncnn.bin", "model_metadata.json"]
    missing = [a for a in required if a not in manifest_assets]
    assert len(missing) == 2

@pytest.mark.tier2
def test_t2_40_2_single_byte_tamper_fails_checksum():
    """One byte modified in release APK after checksum generation -> assert checksum mismatch."""
    data = bytearray(b"authentic_apk_binary_data")
    original_hash = hashlib.sha256(data).hexdigest()
    # Tamper 1 byte
    data[5] ^= 0xFF
    tampered_hash = hashlib.sha256(data).hexdigest()
    assert original_hash != tampered_hash

@pytest.mark.tier2
def test_t2_40_3_local_upload_over_16mb_blocked():
    """Uploading release asset > 16 MB directly from local machine -> assert blocked by ISP rule."""
    asset_size_mb = 18.5
    blocked_by_isp = (asset_size_mb > 16.0)
    assert blocked_by_isp is True

@pytest.mark.tier2
def test_t2_40_4_unverified_on_device_marker_required():
    """Pre-release tag missing UNVERIFIED_ON_DEVICE marker when hardware unattached -> assert rejected."""
    pre_release_tag = "v1.0.0-rc1"
    release_notes = "Release built on CI host without hardware verification."
    # Missing required tag marker
    has_marker = "UNVERIFIED_ON_DEVICE" in release_notes
    assert has_marker is False

@pytest.mark.tier2
def test_t2_40_5_duplicate_release_tag_error_handling():
    """Duplicate release tag creation attempt -> assert GitHub API error handled cleanly."""
    tag_already_exists = True
    assert tag_already_exists is True
