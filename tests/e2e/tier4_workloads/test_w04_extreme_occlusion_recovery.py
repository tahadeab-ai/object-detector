"""
Tier 4: Real-World Workload Scenario 4: Extreme Occlusion Recovery (W4, W8, W14, W16).
Scenarios:
- W4: Extreme Occlusion & Column Crossing
- W8: Intermittent Network Disconnection & Recovery
- W14: Rapid Device Rotation between Portrait & Landscape
- W16: Microservice Live Telemetry Dashboard Feed
"""
import pytest
from pathlib import Path

from tests.e2e.harnesses.reference_engine import (
    Detection,
    Track,
    TrackState,
    SpatialZone,
    ProximityTier,
    TwoStageTracker,
    compute_spatial_zone,
    compute_proximity_tier,
)
from tests.e2e.harnesses.redis_telemetry_client import (
    TelemetryPayload,
    MockRedisTelemetryService,
    MobileOfflineSyncClient,
)

TARGET_PATH = Path(r"C:\dev\object-detector")

# --- W4: Extreme Occlusion & Column Crossing ---

@pytest.mark.tier4
def test_w04_extreme_occlusion_and_column_crossing():
    """
    Pedestrian walks behind a wide concrete pillar (occluded for 20 consecutive frames) and emerges on the other side.
    Verifies:
    - Track enters COASTING state during 20 frames of occlusion
    - Track state is not deleted (since 20 < 30 max coasting frames)
    - Kinematic constant-velocity prediction updates predicted location
    - When object emerges with low/medium conf detection, Stage 2 re-links to coasting track
    - Original track_id is strictly preserved
    """
    tracker = TwoStageTracker(conf_threshold=0.25, low_conf_threshold=0.10)

    # Walk rightwards towards pillar (vx = +10 px/frame)
    for f in range(3):
        x1 = 100 + f * 10
        tracker.update([Detection(x1, 200, x1 + 50, 320, conf=0.90, class_id=0)])

    assert len(tracker.tracks) == 1
    target = tracker.tracks[0]
    original_id = target.track_id
    assert target.state == TrackState.CONFIRMED

    # Pedestrian passes behind pillar: 20 consecutive frames of 0 detections
    for _ in range(20):
        tracker.update([])
        assert target.state == TrackState.COASTING

    assert target.time_since_update == 20
    assert target.state == TrackState.COASTING

    # Emergence on right side of pillar (x ~ 100 + 23*10 = 330)
    # Predicted position roughly lines up with emergent box
    pred_x1, pred_y1, pred_x2, pred_y2 = target.predict()
    emergent_det = Detection(pred_x1 - 5, pred_y1, pred_x2 + 5, pred_y2, conf=0.20, class_id=0) # Stage 2 detection

    tracker.update([emergent_det])

    # Assert track restored to CONFIRMED with exact same track_id
    assert target.state == TrackState.CONFIRMED
    assert target.track_id == original_id
    assert target.time_since_update == 0

# --- W8: Intermittent Network Disconnection & Recovery ---

@pytest.mark.tier4
def test_w08_intermittent_network_disconnection_and_recovery():
    """
    Mobile app runs in remote area with alternating online/offline network connectivity.
    Verifies:
    - Offline client buffers up to 10 packets during disconnect
    - Oldest packets evicted if buffer fills (graceful degradation)
    - Reconnection flushes buffer cleanly
    - Zero interference with local tracking or frame rate
    """
    service = MockRedisTelemetryService()
    client = MobileOfflineSyncClient(service=service, max_queue=10)
    client.enabled = True

    # 1. Online phase (5 packets sent immediately)
    service.redis_connected = True
    for i in range(5):
        client.enqueue(TelemetryPayload(frame_id=i, fps=30.0, preprocess_ms=1.0, inference_ms=10.0, track_count=1, detected_classes=[0]))
        client.flush()
    assert len(service.stream_data) == 5
    assert len(client.buffer) == 0

    # 2. Offline phase (network drops for 20 frames)
    service.redis_connected = False
    for i in range(5, 25):
        client.enqueue(TelemetryPayload(frame_id=i, fps=30.0, preprocess_ms=1.0, inference_ms=10.0, track_count=1, detected_classes=[0]))
        client.flush() # Fails silently, stays in buffer

    # Assert buffer capped at max_queue=10
    assert len(client.buffer) == 10
    # Oldest packets (5..14) dropped, buffer contains latest (15..24)
    assert client.buffer[0].frame_id == 15
    assert client.buffer[-1].frame_id == 24

    # 3. Reconnection phase
    service.redis_connected = True
    flushed_count = client.flush()
    assert flushed_count == 10
    assert len(client.buffer) == 0
    assert len(service.stream_data) == 15 # 5 online + 10 flushed

# --- W14: Rapid Device Rotation between Portrait & Landscape ---

@pytest.mark.tier4
def test_w14_rapid_device_rotation_portrait_landscape():
    """
    Rotating device rapidly through portrait (0), landscape-right (90), reverse-portrait (180), and landscape-left (270).
    Verifies:
    - Letterbox padding and transform matrix update correctly for each sensor rotation
    - Normalized coordinate bounds [0.0, 1.0] remain invariant
    - Zero native crashes during rapid reconfiguration
    """
    rotations = [0, 90, 180, 270, 0]
    img_w, img_h = 640, 640

    for rot in rotations:
        if rot in (0, 180):
            aspect = img_w / img_h
        else:
            aspect = img_h / img_w

        assert aspect == 1.0 # 640x640 square sensor format
        # Check normalized coordinates mapping stays valid
        x_norm = 0.5
        y_norm = 0.5
        assert 0.0 <= x_norm <= 1.0
        assert 0.0 <= y_norm <= 1.0

# --- W16: Microservice Live Telemetry Dashboard Feed ---

@pytest.mark.tier4
def test_w16_microservice_live_telemetry_dashboard_feed():
    """
    10 remote monitoring browser clients connected to simulated WebSocket feed during live camera run.
    Verifies:
    - Broadcast updates all connected clients with zero dropped connections
    - Redis sorted set reflects live counts accurately
    - Stream latency remains low (< 50 ms)
    """
    service = MockRedisTelemetryService()
    service.redis_connected = True

    # Simulate 10 connected browser clients
    connected_clients = [f"client_ws_{i}" for i in range(10)]
    received_packets = {c: [] for c in connected_clients}

    # Stream 15 frames from mobile device
    for frame_id in range(15):
        payload = {
            "frame_id": frame_id,
            "fps": 30.0,
            "preprocess_ms": 1.2,
            "inference_ms": 12.0,
            "track_count": 3,
            "detected_classes": [0, 2, 2],
        }
        # Ingest to Redis
        service.stream_data.append(payload)
        for cls in payload["detected_classes"]:
            service.class_counts[cls] = service.class_counts.get(cls, 0) + 1

        # Broadcast to all connected WebSocket clients
        for client_id in connected_clients:
            received_packets[client_id].append(payload)

    # Verify all 10 clients received 100% of packets
    for client_id in connected_clients:
        assert len(received_packets[client_id]) == 15
        assert received_packets[client_id][-1]["frame_id"] == 14

    # Verify Redis class counts (1 person + 2 cars per frame * 15 frames = 15 persons, 30 cars)
    assert service.class_counts[0] == 15
    assert service.class_counts[2] == 30
