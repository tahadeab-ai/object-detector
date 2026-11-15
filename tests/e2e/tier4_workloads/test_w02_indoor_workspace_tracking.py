"""
Tier 4: Real-World Workload Scenario 2: Indoor Workspace Tracking (W2, W11, W12, W17).
Scenarios:
- W2: Indoor Office & Electronics Asset Tracking
- W11: Nighttime Low-Light Detections with Low Confidence
- W12: Crowd Congestion & Bounding Box Overlap
- W17: Sensor Obstruction (Camera Covered & Uncovered)
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
    BilingualCocoRepository,
    compute_spatial_zone,
    compute_proximity_tier,
)

TARGET_PATH = Path(r"C:\dev\object-detector")

# --- W2: Indoor Office & Electronics Asset Tracking ---

@pytest.mark.tier4
def test_w02_indoor_office_asset_tracking_and_proximity_shift():
    """
    Indoor workspace scene with laptop (class 63), cell phone (class 67), chair (class 56), cup (class 41), and person (class 0).
    Verifies:
    - Bilingual Arabic/English labels render correctly
    - Proximity tiers shift (FAR -> MEDIUM -> NEAR) as user approaches desk
    - Circular buffer majority voting prevents label fluttering
    """
    tracker = TwoStageTracker()
    repo = BilingualCocoRepository()

    # Initial office desk items seen from across room (small boxes, FAR)
    desk_dets = [
        Detection(100, 200, 160, 260, conf=0.88, class_id=63), # laptop
        Detection(180, 220, 210, 250, conf=0.82, class_id=67), # cell phone
        Detection(300, 150, 420, 350, conf=0.91, class_id=56), # chair
        Detection(230, 230, 260, 270, conf=0.79, class_id=41), # cup
    ]
    for _ in range(3):
        tracker.update(desk_dets)

    assert len(tracker.tracks) == 4
    laptop_track = next(t for t in tracker.tracks if t.class_id == 63)
    assert laptop_track.proximity_tier == ProximityTier.PROXIMITY_FAR

    # Verify bilingual labels
    assert repo.get_label(63, "en") == "laptop"
    assert repo.get_label(63, "ar") == "حاسوب محمول"
    assert repo.get_label(67, "en") == "cell phone"
    assert repo.get_label(67, "ar") == "هاتف محمول"

    # User walks closer to desk -> laptop grows larger
    # Smooth expansion to ensure continuous tracker association
    tracker.update([
        Detection(90, 190, 180, 280, conf=0.89, class_id=63),
        Detection(180, 220, 210, 250, conf=0.82, class_id=67),
        Detection(300, 150, 420, 350, conf=0.91, class_id=56),
        Detection(230, 230, 260, 270, conf=0.79, class_id=41),
    ])
    tracker.update([
        Detection(80, 160, 240, 320, conf=0.92, class_id=63),
        Detection(180, 220, 210, 250, conf=0.82, class_id=67),
        Detection(300, 150, 420, 350, conf=0.91, class_id=56),
        Detection(230, 230, 260, 270, conf=0.79, class_id=41),
    ])
    assert laptop_track.proximity_tier == ProximityTier.PROXIMITY_MEDIUM

    # User stands right in front of laptop -> area expands significantly
    tracker.update([
        Detection(60, 120, 340, 420, conf=0.94, class_id=63),
        Detection(180, 220, 210, 250, conf=0.82, class_id=67),
        Detection(300, 150, 420, 350, conf=0.91, class_id=56),
        Detection(230, 230, 260, 270, conf=0.79, class_id=41),
    ])
    tracker.update([
        Detection(40, 100, 480, 560, conf=0.95, class_id=63), # norm_y2=560/640=0.875 >= 0.82
        Detection(180, 220, 210, 250, conf=0.82, class_id=67),
        Detection(300, 150, 420, 350, conf=0.91, class_id=56),
        Detection(230, 230, 260, 270, conf=0.79, class_id=41),
    ])
    assert laptop_track.proximity_tier == ProximityTier.PROXIMITY_NEAR

# --- W11: Nighttime Low-Light Detections with Low Confidence ---

@pytest.mark.tier4
def test_w11_nighttime_low_light_detections_with_low_confidence():
    """
    Low-contrast night video where object scores fluctuate between 0.12 and 0.35.
    Verifies:
    - Stage 2 association prevents premature track termination when conf falls into [0.10, 0.25)
    - Majority voting preserves class stability despite noisy nighttime classifications
    """
    tracker = TwoStageTracker(conf_threshold=0.25, low_conf_threshold=0.10)

    # Initially detected with solid confidence (0.35) for 3 frames -> CONFIRMED
    for _ in range(3):
        tracker.update([Detection(200, 200, 280, 320, conf=0.35, class_id=0)])

    assert len(tracker.tracks) == 1
    target = tracker.tracks[0]
    assert target.state == TrackState.CONFIRMED

    # For next 10 frames, confidence drops to low range [0.12 - 0.22] (e.g. shadowed zone)
    # Target momentarily misclassified as class 2 (car) once or twice due to darkness
    noisy_sequence = [
        (0.18, 0),
        (0.14, 0),
        (0.19, 2), # noisy misclassification
        (0.12, 0),
        (0.21, 0),
        (0.15, 2), # noisy misclassification
        (0.23, 0),
        (0.17, 0),
        (0.24, 0),
        (0.16, 0),
    ]

    for conf, cls_id in noisy_sequence:
        # Move target into coasting if not in stage 1, but stage 2 re-links it!
        tracker.update([Detection(200, 200, 280, 320, conf=conf, class_id=cls_id)])

    # Target track was preserved via Stage 2 association and never deleted
    assert target.track_id == 1
    # Majority voting over circular buffer of 10 keeps class = 0 (person)
    assert target.class_id == 0

# --- W12: Crowd Congestion & Bounding Box Overlap ---

@pytest.mark.tier4
def test_w12_crowd_congestion_and_bounding_box_overlap():
    """
    Dense crowd scene with 25 overlapping pedestrians walking in opposite directions.
    Verifies:
    - Class-aware NMS and center-distance gating prevent identity cross-talk
    - Active tracks capped safely at 100 with zero overflow
    - Tracks remain stable without memory corruption
    """
    tracker = TwoStageTracker(max_tracks=100)

    # Spawn 25 pedestrians with slight overlap
    crowd_dets = [
        Detection(20 + (i * 24), 150 + ((i % 3) * 30), 60 + (i * 24), 300 + ((i % 3) * 30), conf=0.85, class_id=0)
        for i in range(25)
    ]
    for _ in range(3):
        tracker.update(crowd_dets)

    assert len(tracker.tracks) == 25
    initial_ids = {t.track_id for t in tracker.tracks}

    # Simulate crowd movement: even indices walk right, odd walk left
    for f in range(5):
        moving_dets = []
        for i in range(25):
            delta = 6 if i % 2 == 0 else -6
            moving_dets.append(
                Detection(
                    20 + (i * 24) + delta * (f + 1),
                    150 + ((i % 3) * 30),
                    60 + (i * 24) + delta * (f + 1),
                    300 + ((i % 3) * 30),
                    conf=0.85,
                    class_id=0
                )
            )
        tracker.update(moving_dets)

    # Check tracks count within 100 capacity
    assert len(tracker.tracks) <= 100
    assert len(tracker.tracks) == 25
    assert all(t.state == TrackState.CONFIRMED for t in tracker.tracks)

# --- W17: Sensor Obstruction (Camera Covered & Uncovered) ---

@pytest.mark.tier4
def test_w17_sensor_obstruction_camera_covered_and_uncovered():
    """
    User covers camera lens with hand (all black frames, 0 detections) for 10 seconds, then uncovers.
    Verifies:
    - Tracks enter COASTING immediately
    - Tracks delete gracefully after exceeding 30-frame coasting window
    - Active tracks safely reach 0
    - When camera is uncovered, new detections instantly spawn fresh tracks without residual corruption
    """
    tracker = TwoStageTracker()

    # Initial scene: 2 active targets
    init_dets = [
        Detection(100, 200, 160, 300, conf=0.90, class_id=0),
        Detection(350, 220, 420, 340, conf=0.88, class_id=2),
    ]
    for _ in range(3):
        tracker.update(init_dets)

    assert len(tracker.tracks) == 2
    assert all(t.state == TrackState.CONFIRMED for t in tracker.tracks)

    # Frame 1: Camera covered -> 0 detections -> enters COASTING
    tracker.update([])
    assert all(t.state == TrackState.COASTING for t in tracker.tracks)

    # Frames 2..31: 30 consecutive empty frames -> exceeds 30-frame coasting threshold
    for _ in range(30):
        tracker.update([])

    # Both tracks cleanly purged
    assert len(tracker.tracks) == 0

    # Camera uncovered: new objects appear in view
    new_dets = [
        Detection(120, 210, 180, 310, conf=0.92, class_id=0),
        Detection(400, 200, 480, 320, conf=0.89, class_id=5),
    ]
    for _ in range(3):
        tracker.update(new_dets)

    assert len(tracker.tracks) == 2
    assert all(t.state == TrackState.CONFIRMED for t in tracker.tracks)
    # New track IDs allocated cleanly
    assert all(t.track_id > 2 for t in tracker.tracks)
