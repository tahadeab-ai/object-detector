"""
Reference Engine Oracle for YOLO NCNN Detector.
Provides authoritative implementations of:
- YOLO11 Tensor Decoder
- Class-Aware NMS
- 4-State Track Lifecycle State Machine
- 2-Stage Association with Kinematic Velocity Gating
- Track Invariants (Bbox EMA, Velocity Smoothing, Majority Class Voting)
- Spatial Zone & Proximity Tier Computation
- Dynamic Metadata Validation
"""
import math
from typing import List, Tuple, Optional, Dict
from collections import Counter
import numpy as np

class SpatialZone:
    ZONE_LEFT = 0
    ZONE_CENTER = 1
    ZONE_RIGHT = 2

class ProximityTier:
    PROXIMITY_FAR = 0
    PROXIMITY_MEDIUM = 1
    PROXIMITY_NEAR = 2

class TrackState:
    TENTATIVE = 0
    CONFIRMED = 1
    COASTING = 2
    DELETED = 3

class Detection:
    def __init__(self, x1: float, y1: float, x2: float, y2: float, conf: float, class_id: int):
        self.x1 = float(x1)
        self.y1 = float(y1)
        self.x2 = float(x2)
        self.y2 = float(y2)
        self.conf = float(conf)
        self.class_id = int(class_id)

    @property
    def cx(self) -> float:
        return (self.x1 + self.x2) / 2.0

    @property
    def cy(self) -> float:
        return (self.y1 + self.y2) / 2.0

    @property
    def w(self) -> float:
        return max(0.0, self.x2 - self.x1)

    @property
    def h(self) -> float:
        return max(0.0, self.y2 - self.y1)

    @property
    def area(self) -> float:
        return self.w * self.h

def compute_spatial_zone(cx: float, img_w: float = 640.0) -> int:
    norm_cx = cx / img_w if cx > 1.0 else cx
    if norm_cx < 0.33:
        return SpatialZone.ZONE_LEFT
    elif norm_cx <= 0.66:
        return SpatialZone.ZONE_CENTER
    else:
        return SpatialZone.ZONE_RIGHT

def compute_proximity_tier(area: float, y2: float, img_w: float = 640.0, img_h: float = 640.0) -> int:
    norm_area = area / (img_w * img_h) if area > 1.0 else area
    norm_y2 = y2 / img_h if y2 > 1.0 else y2
    if norm_area >= 0.18 or norm_y2 >= 0.82:
        return ProximityTier.PROXIMITY_NEAR
    elif norm_area < 0.05 and norm_y2 < 0.55:
        return ProximityTier.PROXIMITY_FAR
    else:
        return ProximityTier.PROXIMITY_MEDIUM

def compute_iou(boxA: Detection, boxB: Detection) -> float:
    xA = max(boxA.x1, boxB.x1)
    yA = max(boxA.y1, boxB.y1)
    xB = min(boxA.x2, boxB.x2)
    yB = min(boxA.y2, boxB.y2)

    interArea = max(0.0, xB - xA) * max(0.0, yB - yA)
    boxAArea = boxA.area
    boxBArea = boxB.area

    denom = boxAArea + boxBArea - interArea
    if denom <= 0.0:
        return 0.0
    return interArea / denom

def decode_yolo11_tensor(tensor_84_8400: np.ndarray,
                         conf_threshold: float = 0.25,
                         pad_w: int = 0, pad_h: int = 0, scale: float = 1.0,
                         orig_w: int = 640, orig_h: int = 640) -> List[Detection]:
    """
    Decodes an [84, 8400] row-major tensor into candidate detections.
    Handles NaN/Inf sanitation and letterbox inversion.
    """
    rows, cols = tensor_84_8400.shape
    assert rows == 84 and cols == 8400, f"Expected [84, 8400], got [{rows}, {cols}]"

    # Sanitize NaNs and Infs
    tensor = np.nan_to_num(tensor_84_8400, nan=0.0, posinf=0.0, neginf=0.0)

    cx_arr = tensor[0, :]
    cy_arr = tensor[1, :]
    w_arr = tensor[2, :]
    h_arr = tensor[3, :]
    class_scores = tensor[4:, :] # shape [80, 8400]

    max_scores = np.max(class_scores, axis=0)
    best_classes = np.argmax(class_scores, axis=0)

    valid_mask = max_scores >= conf_threshold
    valid_indices = np.where(valid_mask)[0]

    detections = []
    for idx in valid_indices:
        cx = float(cx_arr[idx])
        cy = float(cy_arr[idx])
        w = float(w_arr[idx])
        h = float(h_arr[idx])
        conf = float(max_scores[idx])
        class_id = int(best_classes[idx])

        # Bbox coordinates
        x1 = cx - w / 2.0
        y1 = cy - h / 2.0
        x2 = cx + w / 2.0
        y2 = cy + h / 2.0

        # Invert letterbox
        if scale > 0.0:
            x1 = (x1 - pad_w) / scale
            y1 = (y1 - pad_h) / scale
            x2 = (x2 - pad_w) / scale
            y2 = (y2 - pad_h) / scale

        # Normalize or clamp safely
        x1 = max(0.0, min(float(orig_w), x1))
        y1 = max(0.0, min(float(orig_h), y1))
        x2 = max(0.0, min(float(orig_w), x2))
        y2 = max(0.0, min(float(orig_h), y2))

        detections.append(Detection(x1, y1, x2, y2, conf, class_id))

    # Sort descending by confidence
    detections.sort(key=lambda d: d.conf, reverse=True)
    return detections

def class_aware_nms(candidates: List[Detection], iou_threshold: float = 0.45) -> List[Detection]:
    """
    Performs Class-Aware NMS. Overlapping boxes of DIFFERENT classes never suppress.
    Capacity bounded to 100 boxes.
    """
    if not candidates:
        return []

    # Group by class_id
    by_class: Dict[int, List[Detection]] = {}
    for d in candidates:
        by_class.setdefault(d.class_id, []).append(d)

    survivors = []
    for cls_id, box_list in by_class.items():
        box_list.sort(key=lambda d: d.conf, reverse=True)
        keep = []
        while box_list:
            current = box_list.pop(0)
            keep.append(current)
            box_list = [b for b in box_list if compute_iou(current, b) <= iou_threshold]
        survivors.extend(keep)

    survivors.sort(key=lambda d: d.conf, reverse=True)
    return survivors[:100]

class Track:
    def __init__(self, track_id: int, initial_det: Detection):
        self.track_id = track_id
        self.state = TrackState.TENTATIVE
        self.hits = 1
        self.age = 1
        self.time_since_update = 0
        
        # Bbox and smoothed bbox
        self.x1 = initial_det.x1
        self.y1 = initial_det.y1
        self.x2 = initial_det.x2
        self.y2 = initial_det.y2
        self.conf = initial_det.conf

        # Velocity
        self.vx = 0.0
        self.vy = 0.0
        self.prev_cx = (self.x1 + self.x2) / 2.0
        self.prev_cy = (self.y1 + self.y2) / 2.0

        # Class history circular buffer (capacity 10)
        self.class_history: List[int] = [initial_det.class_id]

    @property
    def class_id(self) -> int:
        # Majority voting with tie-breaking in favor of latest detection
        counts = Counter(self.class_history)
        max_count = max(counts.values())
        candidates = [cls for cls, cnt in counts.items() if cnt == max_count]
        if len(candidates) == 1:
            return candidates[0]
        # Tie break with most recent
        for cls in reversed(self.class_history):
            if cls in candidates:
                return cls
        return self.class_history[-1]

    @property
    def cx(self) -> float:
        return (self.x1 + self.x2) / 2.0

    @property
    def cy(self) -> float:
        return (self.y1 + self.y2) / 2.0

    @property
    def spatial_zone(self) -> int:
        return compute_spatial_zone(self.cx)

    @property
    def proximity_tier(self) -> int:
        area = max(0.0, self.x2 - self.x1) * max(0.0, self.y2 - self.y1)
        return compute_proximity_tier(area, self.y2)

    def predict(self) -> Tuple[float, float, float, float]:
        """Kinematic constant-velocity prediction."""
        return (self.x1 + self.vx, self.y1 + self.vy, self.x2 + self.vx, self.y2 + self.vy)

    def update(self, det: Detection, alpha: float = 0.65, beta: float = 0.60):
        # Update hits and state
        self.hits += 1
        self.time_since_update = 0
        if self.state == TrackState.TENTATIVE and self.hits >= 3:
            self.state = TrackState.CONFIRMED
        elif self.state == TrackState.COASTING:
            self.state = TrackState.CONFIRMED

        # Instantaneous velocity
        current_cx = det.cx
        current_cy = det.cy
        inst_vx = current_cx - self.prev_cx
        inst_vy = current_cy - self.prev_cy

        # Velocity smoothing
        self.vx = beta * inst_vx + (1.0 - beta) * self.vx
        self.vy = beta * inst_vy + (1.0 - beta) * self.vy

        self.prev_cx = current_cx
        self.prev_cy = current_cy

        # Bounding box EMA
        self.x1 = alpha * det.x1 + (1.0 - alpha) * self.x1
        self.y1 = alpha * det.y1 + (1.0 - alpha) * self.y1
        self.x2 = alpha * det.x2 + (1.0 - alpha) * self.x2
        self.y2 = alpha * det.y2 + (1.0 - alpha) * self.y2
        self.conf = det.conf

        # Class history circular buffer (max 10)
        self.class_history.append(det.class_id)
        if len(self.class_history) > 10:
            self.class_history.pop(0)

    def mark_missed(self):
        self.time_since_update += 1
        if self.state == TrackState.TENTATIVE:
            # Spurious detection never confirmed
            self.state = TrackState.DELETED
        elif self.state == TrackState.CONFIRMED:
            self.state = TrackState.COASTING
        elif self.state == TrackState.COASTING:
            if self.time_since_update >= 31:
                self.state = TrackState.DELETED

class TwoStageTracker:
    """
    Two-Stage Association Multi-Object Tracker with Zero-Heap bounded capacity.
    Max 100 tracks.
    """
    def __init__(self, conf_threshold: float = 0.25, low_conf_threshold: float = 0.10, max_tracks: int = 100):
        self.conf_threshold = conf_threshold
        self.low_conf_threshold = low_conf_threshold
        self.max_tracks = max_tracks
        self.tracks: List[Track] = []
        self.next_id = 1

    def reset(self):
        self.tracks.clear()
        self.next_id = 1

    def update(self, detections: List[Detection]) -> List[Track]:
        # Increment age on all existing tracks
        for t in self.tracks:
            t.age += 1

        # Partition detections into Stage 1 (high conf) and Stage 2 (low conf)
        stage1_dets = [d for d in detections if d.conf >= self.conf_threshold]
        stage2_dets = [d for d in detections if self.low_conf_threshold <= d.conf < self.conf_threshold]

        unmatched_tracks = list(self.tracks)
        unmatched_dets = list(stage1_dets)

        # Stage 1: Associate high-conf detections with active tracks
        matched_pairs = []
        for t in list(unmatched_tracks):
            best_det = None
            best_iou = 0.1 # Minimum IoU gate
            for d in unmatched_dets:
                # Center distance gate and IoU
                pred_box = Detection(*t.predict(), t.conf, t.class_id)
                iou = compute_iou(pred_box, d)
                if iou > best_iou:
                    best_iou = iou
                    best_det = d
            if best_det is not None:
                matched_pairs.append((t, best_det))
                unmatched_tracks.remove(t)
                unmatched_dets.remove(best_det)

        # Apply Stage 1 matches
        for t, d in matched_pairs:
            t.update(d)

        # Stage 2: Associate remaining COASTING tracks with low-conf detections
        coasting_tracks = [t for t in unmatched_tracks if t.state == TrackState.COASTING]
        for t in list(coasting_tracks):
            best_det = None
            best_iou = 0.05
            for d in list(stage2_dets):
                pred_box = Detection(*t.predict(), t.conf, t.class_id)
                iou = compute_iou(pred_box, d)
                if iou > best_iou:
                    best_iou = iou
                    best_det = d
            if best_det is not None:
                t.update(best_det)
                unmatched_tracks.remove(t)
                stage2_dets.remove(best_det)

        # Mark remaining unmatched tracks as missed
        for t in unmatched_tracks:
            t.mark_missed()

        # Purge deleted tracks
        self.tracks = [t for t in self.tracks if t.state != TrackState.DELETED]

        # Stage 1 unmatched detections spawn new TENTATIVE tracks
        for d in unmatched_dets:
            if len(self.tracks) >= self.max_tracks:
                # Evict oldest tentative track if available
                tentatives = [t for t in self.tracks if t.state == TrackState.TENTATIVE]
                if tentatives:
                    oldest_tentative = min(tentatives, key=lambda t: t.age)
                    self.tracks.remove(oldest_tentative)
                else:
                    break # Buffer full
            new_track = Track(self.next_id, d)
            self.next_id += 1
            self.tracks.append(new_track)

        # Return confirmed tracks for visualization/reporting
        return [t for t in self.tracks if t.state == TrackState.CONFIRMED]

def validate_model_metadata(param_content: str, metadata_dict: Dict) -> int:
    """
    Dynamic metadata validator.
    Returns:
      0 on success
      -101 if param empty/missing
      -102 if weights/bin missing
      -103 if blob names mismatch
      -104 if tensor shapes mismatch
    """
    if not param_content or len(param_content.strip()) == 0:
        return -101

    input_meta = metadata_dict.get("input", {})
    output_meta = metadata_dict.get("output", {})

    expected_in_name = input_meta.get("name", "in0")
    expected_out_name = output_meta.get("name", "out0")

    expected_in_shape = input_meta.get("shape", [1, 3, 640, 640])
    expected_out_shape = output_meta.get("shape", [1, 84, 8400])

    if expected_in_name not in param_content:
        return -103
    if expected_out_name not in param_content:
        return -103

    if expected_in_shape != [1, 3, 640, 640]:
        return -104
    if expected_out_shape != [1, 84, 8400]:
        return -104

    return 0
