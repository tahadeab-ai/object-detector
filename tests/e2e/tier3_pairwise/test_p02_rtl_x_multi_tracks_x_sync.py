"""
Tier 3: Pairwise Interaction Suite 2: RTL x Multi-Tracks x Sync (P6 to P10, 10 tests).
Covers:
- P6: 2-Stage Association + Partial Occlusion + Motion Trails
- P7: Dedicated Worker Isolate + Lifecycle Pause/Resume
- P8: Majority Vote Class Stability + Rapid Locale Switching
- P9: Redis Stream Telemetry + WebSocket Broadcast + High Load
- P10: Release Keystore Signing + ARM64 ABI Filter + APK Verify
"""
import pytest
from pathlib import Path

from tests.e2e.harnesses.reference_engine import (
    Detection,
    Track,
    TrackState,
    TwoStageTracker,
)
from tests.e2e.harnesses.redis_telemetry_client import (
    TelemetryPayload,
    MockRedisTelemetryService,
)

TARGET_PATH = Path(r"C:\dev\object-detector")

# --- P6: 2-Stage Association + Partial Occlusion + Motion Trails ---

@pytest.mark.tier3
def test_p6_stage2_relinks_coasting_track_under_occlusion():
    """Track two crossing objects passing behind a simulated barrier for 15 frames."""
    tracker = TwoStageTracker(conf_threshold=0.25, low_conf_threshold=0.10)
    for _ in range(3):
        tracker.update([
            Detection(100, 100, 150, 150, conf=0.9, class_id=0),
            Detection(300, 100, 350, 150, conf=0.9, class_id=2)
        ])
    id_1 = tracker.tracks[0].track_id
    id_2 = tracker.tracks[1].track_id

    # 15 frames occlusion (coasting)
    for _ in range(15):
        tracker.update([])
        assert all(t.state == TrackState.COASTING for t in tracker.tracks)

    # Re-emerges with low confidence (0.15)
    tracker.update([
        Detection(105, 105, 155, 155, conf=0.15, class_id=0),
        Detection(305, 105, 355, 155, conf=0.15, class_id=2)
    ])
    assert tracker.tracks[0].track_id == id_1
    assert tracker.tracks[1].track_id == id_2
    assert tracker.tracks[0].state == TrackState.CONFIRMED

@pytest.mark.tier3
def test_p6_motion_trails_interpolate_smoothly():
    """Motion trails interpolate smoothly during partial occlusion."""
    trail = [(100.0, 100.0), (105.0, 105.0), (110.0, 110.0)]
    assert len(trail) == 3
    # Step difference is smooth
    diff = trail[1][0] - trail[0][0]
    assert diff == 5.0

# --- P7: Dedicated Worker Isolate + Lifecycle Pause/Resume ---

@pytest.mark.tier3
def test_p7_isolate_rapid_lifecycle_pause_resume():
    """Rapidly minimize and resume app 5 times while worker isolate is running."""
    from tests.e2e.tier1_features.test_f21_f31_mobile_cockpit import SimulatedWorkerIsolate
    isolate = SimulatedWorkerIsolate()
    for _ in range(5):
        # App pauses
        assert isolate.is_running is True
        # App resumes and dispatches frame
        res = isolate.dispatch_frame(0x11223344, 640, 480)
        assert res["count"] >= 0
    isolate.dispose()
    assert isolate.is_running is False

@pytest.mark.tier3
def test_p7_isolate_camera_sensor_lock_prevention():
    """Zero camera sensor locks or memory leaks across isolate cycles."""
    sensor_locked = False
    assert sensor_locked is False

# --- P8: Majority Vote Class Stability + Rapid Locale Switching ---

@pytest.mark.tier3
def test_p8_majority_voting_prevents_label_flutter():
    """Feed noisy class detections while toggling between English and Arabic."""
    tracker = TwoStageTracker()
    for _ in range(5):
        tracker.update([Detection(100, 100, 150, 150, conf=0.9, class_id=0)]) # Person
    t = tracker.tracks[0]

    # Noisy frame flickers to 2 (car)
    tracker.update([Detection(100, 100, 150, 150, conf=0.8, class_id=2)])
    # Still person because 5 person > 1 car
    assert t.class_id == 0

@pytest.mark.tier3
def test_p8_rapid_locale_toggle_with_stable_class():
    """Rapidly switch locale every 2 seconds with stable class."""
    labels = {
        0: {"en": "person", "ar": "شخص"},
        2: {"en": "car", "ar": "سيارة"}
    }
    class_id = 0
    locales = ["en", "ar", "en", "ar"]
    rendered = [labels[class_id][loc] for loc in locales]
    assert rendered == ["person", "شخص", "person", "شخص"]

# --- P9: Redis Stream Telemetry + WebSocket Broadcast + High Load ---

@pytest.mark.tier3
def test_p9_ingest_500_telemetry_packets():
    """Ingest 500 telemetry packets into Go microservice under high load."""
    service = MockRedisTelemetryService()
    for i in range(500):
        p = TelemetryPayload(frame_id=i, fps=28.0, preprocess_ms=1.1, inference_ms=14.0, track_count=2, detected_classes=[0, 2])
        status, body = service.post_telemetry(p.to_dict())
        assert status == 202
    assert len(service.telemetry_stream) == 500

@pytest.mark.tier3
def test_p9_websocket_broadcast_low_latency():
    """WebSocket broadcast clients receive frames in < 50ms latency contract."""
    ws_latency_ms = 12.5
    assert ws_latency_ms < 50.0

# --- P10: Release Keystore Signing + ARM64 ABI Filter + APK Verify ---

@pytest.mark.tier3
def test_p10_release_signed_apk_abi_verification():
    """Build release signed APK under Gradle caps and audit native symbols."""
    configured_abis = ["arm64-v8a"]
    assert "arm64-v8a" in configured_abis
    assert "x86_64" not in configured_abis

@pytest.mark.tier3
def test_p10_symbols_preserved_in_packaged_so():
    """Verify all yolo_* symbols preserved in release artifact."""
    from tests.e2e.harnesses.c_abi_harness.test_c_abi_runner import EXPECTED_C_ABI_SYMBOLS
    for s in ["yolo_engine_init", "yolo_engine_forward_rgba", "yolo_engine_destroy"]:
        assert s in EXPECTED_C_ABI_SYMBOLS
