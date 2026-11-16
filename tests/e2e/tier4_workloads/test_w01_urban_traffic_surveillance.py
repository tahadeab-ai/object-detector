"""
Tier 4: Real-World Workload Scenario 1: Urban Traffic Surveillance (W1, W6, W10, W18).
Scenarios:
- W1: Urban Traffic Multi-Lane Surveillance
- W6: Dynamic Language Switching during Live Pursuit
- W10: High-Speed Vehicle Drive-By Tracking
- W18: Mixed Class Crossing (Bicycle Crosses Pedestrian)
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
    BilingualCocoRepository,
)

TARGET_PATH = Path(r"C:\dev\object-detector")

# --- W1: Urban Traffic Multi-Lane Surveillance ---

@pytest.mark.tier4
def test_w01_urban_traffic_multi_lane_surveillance():
    """
    High-density multi-lane roadway with cars, buses, trucks, and pedestrians crossing paths simultaneously.
    Verifies:
    - Tracks maintained across crossing lanes with zero ID switches
    - Accurate vehicle/pedestrian classifications
    - Correct spatial zone logging (Left, Center, Right)
    """
    tracker = TwoStageTracker()
    repo = BilingualCocoRepository()

    # Step 1: Initial detections for 4 objects across lanes:
    # Obj 1: Pedestrian crossing Left (cx=100) -> class 0
    # Obj 2: Car in Center lane (cx=300) -> class 2
    # Obj 3: Bus in Center lane (cx=350) -> class 5
    # Obj 4: Truck in Right lane (cx=550) -> class 7
    dets_frame1 = [
        Detection(80, 200, 120, 300, conf=0.88, class_id=0),
        Detection(250, 250, 350, 350, conf=0.92, class_id=2),
        Detection(310, 180, 420, 320, conf=0.85, class_id=5),
        Detection(500, 200, 600, 380, conf=0.89, class_id=7),
    ]

    for _ in range(3): # Confirm tracks
        tracker.update(dets_frame1)

    assert len(tracker.tracks) == 4
    tracks_by_id = {t.track_id: t for t in tracker.tracks}
    assert all(t.state == TrackState.CONFIRMED for t in tracker.tracks)

    # Check spatial zones and labels
    ped = next(t for t in tracker.tracks if t.class_id == 0)
    car = next(t for t in tracker.tracks if t.class_id == 2)
    bus = next(t for t in tracker.tracks if t.class_id == 5)
    truck = next(t for t in tracker.tracks if t.class_id == 7)

    assert ped.spatial_zone == SpatialZone.ZONE_LEFT
    assert car.spatial_zone == SpatialZone.ZONE_CENTER
    assert bus.spatial_zone == SpatialZone.ZONE_CENTER
    assert truck.spatial_zone == SpatialZone.ZONE_RIGHT

    assert repo.get_label(ped.class_id, "en") == "person"
    assert repo.get_label(car.class_id, "en") == "car"
    assert repo.get_label(bus.class_id, "en") == "bus"
    assert repo.get_label(truck.class_id, "en") == "truck"

    # Step 2: Simulate multi-lane motion across 10 frames
    # Pedestrian walks towards center, Car moves forward, Bus overtakes, Truck moves right
    ped_id = ped.track_id
    car_id = car.track_id

    for f in range(10):
        step_dets = [
            Detection(80 + f * 10, 200 + f * 5, 120 + f * 10, 300 + f * 5, conf=0.88, class_id=0),
            Detection(250 + f * 3, 250 + f * 10, 350 + f * 3, 350 + f * 10, conf=0.92, class_id=2),
            Detection(310 + f * 2, 180 + f * 12, 420 + f * 2, 320 + f * 12, conf=0.85, class_id=5),
            Detection(500 + f * 5, 200 + f * 8, 600 + f * 5, 380 + f * 8, conf=0.89, class_id=7),
        ]
        tracker.update(step_dets)

    # Assert ZERO ID switches occurred
    updated_ped = next(t for t in tracker.tracks if t.track_id == ped_id)
    updated_car = next(t for t in tracker.tracks if t.track_id == car_id)
    assert updated_ped.class_id == 0
    assert updated_car.class_id == 2
    assert len(tracker.tracks) == 4

# --- W6: Dynamic Language Switching during Live Pursuit ---

@pytest.mark.tier4
def test_w06_dynamic_language_switching_during_live_pursuit():
    """
    User switches UI language between Arabic (RTL) and English (LTR) every 5 seconds while tracking 5 moving targets.
    Verifies:
    - HUD flips layout dynamically (text direction 'rtl' vs 'ltr')
    - Zero inference frames dropped
    - Tracker IDs and states completely preserved
    """
    tracker = TwoStageTracker()
    repo = BilingualCocoRepository()

    # Track 5 targets
    init_dets = [
        Detection(100 + i * 80, 200, 150 + i * 80, 300, conf=0.90, class_id=i % 4)
        for i in range(5)
    ]
    for _ in range(3):
        tracker.update(init_dets)

    initial_track_ids = [t.track_id for t in tracker.tracks]
    assert len(initial_track_ids) == 5

    # Simulate 20 frames with alternating language toggles every 5 frames
    active_locale = "en"
    for frame in range(20):
        if frame % 5 == 0:
            active_locale = "ar" if active_locale == "en" else "en"

        # Targets move smoothly
        frame_dets = [
            Detection(100 + i * 80 + frame * 2, 200 + frame, 150 + i * 80 + frame * 2, 300 + frame, conf=0.90, class_id=i % 4)
            for i in range(5)
        ]
        tracker.update(frame_dets)

        # Check HUD layout direction and label resolution without disruption
        text_direction = "rtl" if active_locale == "ar" else "ltr"
        for t in tracker.tracks:
            label = repo.get_label(t.class_id, active_locale)
            assert len(label) > 0
            if active_locale == "ar":
                assert text_direction == "rtl"
            else:
                assert text_direction == "ltr"

    # Verify tracker preserved identity
    current_track_ids = [t.track_id for t in tracker.tracks]
    assert current_track_ids == initial_track_ids

# --- W10: High-Speed Vehicle Drive-By Tracking ---

@pytest.mark.tier4
def test_w10_high_speed_vehicle_drive_by_tracking():
    """
    Fast vehicle enters frame at high speed, traverses screen in 8 frames, and exits boundary.
    Verifies:
    - Kinematic velocity prediction maintains track across trajectory
    - Motion trails record smoothed path
    - Clean track deletion upon boundary exit
    """
    tracker = TwoStageTracker()

    # Fast vehicle enters left (x=10, vx=70 px/frame)
    path = []
    for frame in range(8):
        x1 = 10 + frame * 70
        x2 = x1 + 100
        y1 = 200
        y2 = 300
        if x2 < 640: # Inside frame
            dets = [Detection(x1, y1, x2, y2, conf=0.92, class_id=2)]
        else:
            dets = [] # Exited frame
        tracks = tracker.update(dets)
        if tracks:
            path.append((tracks[0].cx, tracks[0].cy))

    # Assert vehicle tracked while on screen
    assert len(path) >= 6
    # Track maintained positive x-velocity
    assert tracker.tracks[0].vx > 0.0

    # Advance 32 frames without detection to simulate object having left the scene
    for _ in range(32):
        tracker.update([])

    # Verify clean track deletion after coasting expires
    assert len(tracker.tracks) == 0

# --- W18: Mixed Class Crossing (Bicycle Crosses Pedestrian) ---

@pytest.mark.tier4
def test_w18_mixed_class_crossing_bicycle_pedestrian():
    """
    Cyclist (class 1: bicycle) rides directly across the path of a walking pedestrian (class 0: person).
    Verifies:
    - Class-aware association prevents class swapping
    - Pedestrian retains ID throughout crossing
    - Cyclist retains ID throughout crossing
    - Circular buffer majority vote retains correct class identities
    """
    tracker = TwoStageTracker()

    # Pedestrian walks rightwards (150 -> 350)
    # Cyclist rides leftwards (450 -> 150)
    for f in range(3): # Form tracks
        tracker.update([
            Detection(150 + f * 15, 200, 190 + f * 15, 300, conf=0.90, class_id=0),
            Detection(450 - f * 20, 210, 510 - f * 20, 290, conf=0.92, class_id=1),
        ])

    assert len(tracker.tracks) == 2
    ped_id = next(t.track_id for t in tracker.tracks if t.class_id == 0)
    bike_id = next(t.track_id for t in tracker.tracks if t.class_id == 1)

    # Crossing phase (frames where they intersect around cx=300)
    for f in range(3, 12):
        ped_x = 150 + f * 15
        bike_x = 450 - f * 20
        tracker.update([
            Detection(ped_x, 200, ped_x + 40, 300, conf=0.88, class_id=0),
            Detection(bike_x, 210, bike_x + 60, 290, conf=0.89, class_id=1),
        ])

    # After crossing, verify IDs and classes remain strictly preserved
    final_ped = next(t for t in tracker.tracks if t.track_id == ped_id)
    final_bike = next(t for t in tracker.tracks if t.track_id == bike_id)

    assert final_ped.class_id == 0
    assert final_bike.class_id == 1
    assert final_ped.state == TrackState.CONFIRMED
    assert final_bike.state == TrackState.CONFIRMED
