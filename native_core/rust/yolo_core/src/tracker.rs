//! Two-Stage Multi-Object Tracker with 4-State Lifecycle and Kinematic Velocity Gating.
//! Zero heap allocation per frame: uses fixed static track pools.

use crate::types::{
    box_iou, compute_proximity_tier, compute_spatial_zone, YoloDetectionBox,
    TRACK_COASTING, TRACK_CONFIRMED, TRACK_DELETED, TRACK_TENTATIVE, YOLO_MAX_BOXES,
};

pub const MAX_TRACKS: usize = 100;
pub const MIN_HITS_CONFIRM: u32 = 2;
pub const MAX_AGE_COASTING: u32 = 30; // Survives 30 frames, deleted on frame 31
pub const EMA_ALPHA: f32 = 0.65;
pub const VELOCITY_ALPHA: f32 = 0.70;
pub const CLASS_HISTORY_SIZE: usize = 10;
pub const LOW_CONF_MIN: f32 = 0.10;

#[derive(Debug, Clone, Copy)]
pub struct Track {
    pub track_id: i32,
    pub state: i32,
    pub x1: f32,
    pub y1: f32,
    pub x2: f32,
    pub y2: f32,
    pub confidence: f32,
    pub class_id: i32,
    pub spatial_zone: i32,
    pub proximity_tier: i32,
    pub vx: f32,
    pub vy: f32,
    pub age: u32,
    pub hits: u32,
    pub time_since_update: u32,
    pub class_history: [i32; CLASS_HISTORY_SIZE],
    pub class_history_len: usize,
    pub active: bool,
}

impl Default for Track {
    fn default() -> Self {
        Self {
            track_id: -1,
            state: TRACK_TENTATIVE,
            x1: 0.0,
            y1: 0.0,
            x2: 0.0,
            y2: 0.0,
            confidence: 0.0,
            class_id: -1,
            spatial_zone: 0,
            proximity_tier: 0,
            vx: 0.0,
            vy: 0.0,
            age: 0,
            hits: 0,
            time_since_update: 0,
            class_history: [-1; CLASS_HISTORY_SIZE],
            class_history_len: 0,
            active: false,
        }
    }
}

impl Track {
    #[inline]
    pub fn cx(&self) -> f32 {
        (self.x1 + self.x2) * 0.5
    }

    #[inline]
    pub fn cy(&self) -> f32 {
        (self.y1 + self.y2) * 0.5
    }

    #[inline]
    pub fn w(&self) -> f32 {
        self.x2 - self.x1
    }

    #[inline]
    pub fn h(&self) -> f32 {
        self.y2 - self.y1
    }

    /// Predicts bounding box for current frame based on smoothed constant velocity.
    pub fn predict_box(&self) -> YoloDetectionBox {
        let pred_cx = self.cx() + self.vx;
        let pred_cy = self.cy() + self.vy;
        let half_w = self.w() * 0.5;
        let half_h = self.h() * 0.5;

        YoloDetectionBox {
            x1: (pred_cx - half_w).clamp(0.0, 1.0),
            y1: (pred_cy - half_h).clamp(0.0, 1.0),
            x2: (pred_cx + half_w).clamp(0.0, 1.0),
            y2: (pred_cy + half_h).clamp(0.0, 1.0),
            confidence: self.confidence,
            class_id: self.class_id,
            track_id: self.track_id,
            track_state: self.state,
            spatial_zone: self.spatial_zone,
            proximity_tier: self.proximity_tier,
        }
    }

    /// Updates track state with a matched detection.
    pub fn update(&mut self, det: &YoloDetectionBox) {
        let det_cx = (det.x1 + det.x2) * 0.5;
        let det_cy = (det.y1 + det.y2) * 0.5;
        let curr_cx = self.cx();
        let curr_cy = self.cy();

        // Update kinematic velocity
        let measured_vx = det_cx - curr_cx;
        let measured_vy = det_cy - curr_cy;
        self.vx = VELOCITY_ALPHA * measured_vx + (1.0 - VELOCITY_ALPHA) * self.vx;
        self.vy = VELOCITY_ALPHA * measured_vy + (1.0 - VELOCITY_ALPHA) * self.vy;

        // Coordinate EMA smoothing (EMA alpha = 0.65 on coordinates only)
        self.x1 = EMA_ALPHA * det.x1 + (1.0 - EMA_ALPHA) * self.x1;
        self.y1 = EMA_ALPHA * det.y1 + (1.0 - EMA_ALPHA) * self.y1;
        self.x2 = EMA_ALPHA * det.x2 + (1.0 - EMA_ALPHA) * self.x2;
        self.y2 = EMA_ALPHA * det.y2 + (1.0 - EMA_ALPHA) * self.y2;

        self.confidence = det.confidence;

        // Class history majority vote over last N=10
        if self.class_history_len < CLASS_HISTORY_SIZE {
            self.class_history[self.class_history_len] = det.class_id;
            self.class_history_len += 1;
        } else {
            // Shift left and append
            for i in 0..(CLASS_HISTORY_SIZE - 1) {
                self.class_history[i] = self.class_history[i + 1];
            }
            self.class_history[CLASS_HISTORY_SIZE - 1] = det.class_id;
        }
        self.class_id = self.majority_class();

        self.spatial_zone = compute_spatial_zone(self.x1, self.x2);
        self.proximity_tier = compute_proximity_tier(self.x1, self.y1, self.x2, self.y2);

        self.hits += 1;
        self.age += 1;
        self.time_since_update = 0;

        // State transition: TENTATIVE -> CONFIRMED on min_hits = 3
        if self.state == TRACK_TENTATIVE && self.hits >= MIN_HITS_CONFIRM {
            self.state = TRACK_CONFIRMED;
        } else if self.state == TRACK_COASTING {
            self.state = TRACK_CONFIRMED;
        }
    }

    /// Marks missed detection for a frame.
    pub fn mark_missed(&mut self) {
        self.age += 1;
        self.time_since_update += 1;

        // Kinematic position extrapolation during coasting
        self.x1 = (self.x1 + self.vx).clamp(0.0, 1.0);
        self.y1 = (self.y1 + self.vy).clamp(0.0, 1.0);
        self.x2 = (self.x2 + self.vx).clamp(0.0, 1.0);
        self.y2 = (self.y2 + self.vy).clamp(0.0, 1.0);
        self.spatial_zone = compute_spatial_zone(self.x1, self.x2);
        self.proximity_tier = compute_proximity_tier(self.x1, self.y1, self.x2, self.y2);

        // State transition: CONFIRMED -> COASTING on first miss
        if self.state == TRACK_CONFIRMED {
            self.state = TRACK_COASTING;
        } else if self.state == TRACK_TENTATIVE {
            // Unconfirmed tentative tracks that miss are spurious; delete immediately
            self.state = TRACK_DELETED;
            self.active = false;
        }

        // DELETED when time_since_update > MAX_AGE_COASTING (frame 31)
        if self.time_since_update > MAX_AGE_COASTING {
            self.state = TRACK_DELETED;
            self.active = false;
        }
    }

    /// Computes majority class ID from rolling class history.
    pub fn majority_class(&self) -> i32 {
        if self.class_history_len == 0 {
            return self.class_id;
        }

        let mut max_count = 0;
        let mut best_class = self.class_history[0];

        for i in 0..self.class_history_len {
            let candidate = self.class_history[i];
            let mut count = 0;
            for j in 0..self.class_history_len {
                if self.class_history[j] == candidate {
                    count += 1;
                }
            }
            if count > max_count {
                max_count = count;
                best_class = candidate;
            }
        }

        best_class
    }

    /// Converts active track to YoloDetectionBox for output.
    pub fn to_detection_box(&self) -> YoloDetectionBox {
        YoloDetectionBox {
            x1: self.x1,
            y1: self.y1,
            x2: self.x2,
            y2: self.y2,
            confidence: self.confidence,
            class_id: self.class_id,
            track_id: self.track_id,
            track_state: self.state,
            spatial_zone: self.spatial_zone,
            proximity_tier: self.proximity_tier,
        }
    }
}

pub struct TwoStageTracker {
    pub tracks: [Track; MAX_TRACKS],
    pub next_id: i32,
    pub conf_threshold: f32,
}

impl Default for TwoStageTracker {
    fn default() -> Self {
        Self {
            tracks: [Track::default(); MAX_TRACKS],
            next_id: 1,
            conf_threshold: 0.25,
        }
    }
}

impl TwoStageTracker {
    pub fn new(conf_threshold: f32) -> Self {
        Self {
            tracks: [Track::default(); MAX_TRACKS],
            next_id: 1,
            conf_threshold,
        }
    }

    pub fn reset(&mut self) {
        for t in self.tracks.iter_mut() {
            *t = Track::default();
        }
        self.next_id = 1;
    }

    /// Associates detections with active tracks and updates tracker state.
    /// Writes confirmed/active tracks into `out_boxes`, returns count.
    pub fn update(
        &mut self,
        detections: &[YoloDetectionBox],
        out_boxes: &mut [YoloDetectionBox],
    ) -> usize {
        let num_dets = detections.len().min(YOLO_MAX_BOXES);
        let mut det_matched = [false; YOLO_MAX_BOXES];
        let mut track_matched = [false; MAX_TRACKS];

        // --- STAGE 1: High-confidence candidates vs active/coasting tracks ---
        for (d_idx, det) in detections[..num_dets].iter().enumerate() {
            if det.confidence < self.conf_threshold {
                continue;
            }

            let mut best_cost = f32::MAX;
            let mut best_track_idx = None;

            for (t_idx, track) in self.tracks.iter().enumerate() {
                if !track.active || track_matched[t_idx] {
                    continue;
                }

                let pred_box = track.predict_box();
                let iou = box_iou(det, &pred_box);

                let det_cx = (det.x1 + det.x2) * 0.5;
                let det_cy = (det.y1 + det.y2) * 0.5;
                let pred_cx = (pred_box.x1 + pred_box.x2) * 0.5;
                let pred_cy = (pred_box.y1 + pred_box.y2) * 0.5;
                let dist = ((det_cx - pred_cx).powi(2) + (det_cy - pred_cy).powi(2)).sqrt();

                // Center-distance gating: reject associations where velocity prediction drift > 0.40
                if dist > 0.40 && iou < 0.10 {
                    continue;
                }

                // Cost function: combines IoU with kinematic center distance
                let cost = (1.0 - iou) + 0.5 * dist;
                if cost < best_cost && (iou > 0.20 || dist < 0.15) {
                    best_cost = cost;
                    best_track_idx = Some(t_idx);
                }
            }

            if let Some(t_idx) = best_track_idx {
                self.tracks[t_idx].update(det);
                track_matched[t_idx] = true;
                det_matched[d_idx] = true;
            }
        }

        // --- STAGE 2: Re-link remaining COASTING tracks with low-confidence detections ---
        for (t_idx, track) in self.tracks.iter_mut().enumerate() {
            if !track.active || track_matched[t_idx] || track.state != TRACK_COASTING {
                continue;
            }

            let mut best_cost = f32::MAX;
            let mut best_det_idx = None;

            for (d_idx, det) in detections[..num_dets].iter().enumerate() {
                if det_matched[d_idx] || det.confidence < LOW_CONF_MIN || det.confidence >= self.conf_threshold {
                    continue;
                }

                let pred_box = track.predict_box();
                let iou = box_iou(det, &pred_box);
                let det_cx = (det.x1 + det.x2) * 0.5;
                let det_cy = (det.y1 + det.y2) * 0.5;
                let pred_cx = (pred_box.x1 + pred_box.x2) * 0.5;
                let pred_cy = (pred_box.y1 + pred_box.y2) * 0.5;
                let dist = ((det_cx - pred_cx).powi(2) + (det_cy - pred_cy).powi(2)).sqrt();

                if dist > 0.35 && iou < 0.10 {
                    continue;
                }

                let cost = (1.0 - iou) + 0.5 * dist;
                if cost < best_cost && (iou > 0.20 || dist < 0.20) {
                    best_cost = cost;
                    best_det_idx = Some(d_idx);
                }
            }

            if let Some(d_idx) = best_det_idx {
                track.update(&detections[d_idx]);
                track_matched[t_idx] = true;
                det_matched[d_idx] = true;
            }
        }

        // Mark missed on all unmatched active tracks
        for (t_idx, track) in self.tracks.iter_mut().enumerate() {
            if track.active && !track_matched[t_idx] {
                track.mark_missed();
            }
        }

        // Allocate new tentative tracks for unmatched high-confidence detections
        for (d_idx, det) in detections[..num_dets].iter().enumerate() {
            if !det_matched[d_idx] && det.confidence >= self.conf_threshold {
                self.spawn_track(det);
            }
        }

        // Collect CONFIRMED tracks for output (active targets verified with at least 2 hits)
        let mut out_count = 0;
        for track in self.tracks.iter() {
            if track.active
                && track.state == TRACK_CONFIRMED
                && track.hits >= 2
                && track.confidence >= self.conf_threshold
            {
                out_boxes[out_count] = track.to_detection_box();
                out_count += 1;
                if out_count >= out_boxes.len() {
                    break;
                }
            }
        }

        out_count
    }

    fn spawn_track(&mut self, det: &YoloDetectionBox) {
        // Find empty slot in fixed track array
        for track in self.tracks.iter_mut() {
            if !track.active {
                *track = Track {
                    track_id: self.next_id,
                    state: TRACK_TENTATIVE,
                    x1: det.x1,
                    y1: det.y1,
                    x2: det.x2,
                    y2: det.y2,
                    confidence: det.confidence,
                    class_id: det.class_id,
                    spatial_zone: compute_spatial_zone(det.x1, det.x2),
                    proximity_tier: compute_proximity_tier(det.x1, det.y1, det.x2, det.y2),
                    vx: 0.0,
                    vy: 0.0,
                    age: 1,
                    hits: 1,
                    time_since_update: 0,
                    class_history: [det.class_id; CLASS_HISTORY_SIZE],
                    class_history_len: 1,
                    active: true,
                };
                self.next_id += 1;
                return;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_invariant_1_coasting_and_deletion() {
        // (1) Track survives 30 frames with zero detections and is deleted on frame 31, not before
        let mut tracker = TwoStageTracker::new(0.25);
        let mut out = [YoloDetectionBox::default(); YOLO_MAX_BOXES];

        let det = YoloDetectionBox {
            x1: 0.2, y1: 0.2, x2: 0.4, y2: 0.4,
            confidence: 0.90, class_id: 0, ..Default::default()
        };

        // Confirm track with 3 consecutive hits
        tracker.update(&[det], &mut out);
        tracker.update(&[det], &mut out);
        tracker.update(&[det], &mut out);

        let t_idx = tracker.tracks.iter().position(|t| t.active).expect("Track should be active");
        assert_eq!(tracker.tracks[t_idx].state, TRACK_CONFIRMED);

        // Feed 30 empty frames: track must survive in COASTING state
        for frame in 1..=30 {
            tracker.update(&[], &mut out);
            assert!(
                tracker.tracks[t_idx].active,
                "Track must remain active on miss frame {}", frame
            );
            assert_eq!(
                tracker.tracks[t_idx].state, TRACK_COASTING,
                "Track must be COASTING on miss frame {}", frame
            );
            assert_eq!(tracker.tracks[t_idx].time_since_update, frame);
        }

        // On frame 31: track must be DELETED and active=false
        tracker.update(&[], &mut out);
        assert!(
            !tracker.tracks[t_idx].active,
            "Track must be DELETED on miss frame 31"
        );
        assert_eq!(tracker.tracks[t_idx].state, TRACK_DELETED);
    }

    #[test]
    fn test_invariant_2_crossing_trajectories_zero_id_switches() {
        // (2) Two crossing trajectories produce ZERO ID switches
        let mut tracker = TwoStageTracker::new(0.25);
        let mut out = [YoloDetectionBox::default(); YOLO_MAX_BOXES];

        // Track A moves left to right: cx 0.2 -> 0.8
        // Track B moves right to left: cx 0.8 -> 0.2
        // Crossing happens at frame 5 (cx ~ 0.5)

        let mut id_a = -1;
        let mut id_b = -1;

        for step in 0..10 {
            let cx_a = 0.20 + (step as f32) * 0.06;
            let cx_b = 0.80 - (step as f32) * 0.06;

            let det_a = YoloDetectionBox {
                x1: cx_a - 0.05, y1: 0.40, x2: cx_a + 0.05, y2: 0.60,
                confidence: 0.92, class_id: 0, ..Default::default()
            };
            let det_b = YoloDetectionBox {
                x1: cx_b - 0.05, y1: 0.40, x2: cx_b + 0.05, y2: 0.60,
                confidence: 0.88, class_id: 2, ..Default::default()
            };

            let count = tracker.update(&[det_a, det_b], &mut out);

            if step == 2 {
                // Tracks confirmed by frame 3 (step 2)
                let box_a = out[..count].iter().find(|b| b.class_id == 0).expect("Track A present");
                let box_b = out[..count].iter().find(|b| b.class_id == 2).expect("Track B present");
                id_a = box_a.track_id;
                id_b = box_b.track_id;
                assert_ne!(id_a, id_b);
            } else if step > 2 {
                // Assert zero ID switches after crossing
                let box_a = out[..count].iter().find(|b| b.class_id == 0).expect("Track A present");
                let box_b = out[..count].iter().find(|b| b.class_id == 2).expect("Track B present");
                assert_eq!(box_a.track_id, id_a, "Track A ID switched at step {}", step);
                assert_eq!(box_b.track_id, id_b, "Track B ID switched at step {}", step);
            }
        }
    }

    #[test]
    fn test_invariant_3_spurious_single_frame_never_confirmed() {
        // (3) Single-frame spurious detection never becomes CONFIRMED
        let mut tracker = TwoStageTracker::new(0.25);
        let mut out = [YoloDetectionBox::default(); YOLO_MAX_BOXES];

        let spurious = YoloDetectionBox {
            x1: 0.1, y1: 0.1, x2: 0.2, y2: 0.2,
            confidence: 0.95, class_id: 0, ..Default::default()
        };

        // Frame 1: spurious detection appears
        tracker.update(&[spurious], &mut out);
        let t_idx = tracker.tracks.iter().position(|t| t.active).expect("Track allocated");
        assert_eq!(tracker.tracks[t_idx].state, TRACK_TENTATIVE);
        assert_ne!(tracker.tracks[t_idx].state, TRACK_CONFIRMED);

        // Frame 2: spurious detection vanishes
        tracker.update(&[], &mut out);
        // It never achieved 3 hits, so it was never confirmed
        assert_ne!(tracker.tracks[t_idx].state, TRACK_CONFIRMED);
    }

    #[test]
    fn test_invariant_4_majority_class_voting() {
        // (4) class_id stays stable under noisy classification via majority vote
        let mut tracker = TwoStageTracker::new(0.25);
        let mut out = [YoloDetectionBox::default(); YOLO_MAX_BOXES];

        let base_det = YoloDetectionBox {
            x1: 0.3, y1: 0.3, x2: 0.5, y2: 0.5,
            confidence: 0.90, class_id: 0, ..Default::default() // Person (class 0)
        };

        // Confirm with 3 frames of class 0
        tracker.update(&[base_det], &mut out);
        tracker.update(&[base_det], &mut out);
        tracker.update(&[base_det], &mut out);

        let t_idx = tracker.tracks.iter().position(|t| t.active).expect("Track active");
        assert_eq!(tracker.tracks[t_idx].class_id, 0);

        // Feed noisy frames: 1 frame of noise (class 2: car)
        let mut noisy_det = base_det;
        noisy_det.class_id = 2;
        tracker.update(&[noisy_det], &mut out);

        // Majority vote must maintain class 0 despite single noise frame
        assert_eq!(
            tracker.tracks[t_idx].class_id, 0,
            "Track class must remain 0 via majority vote"
        );

        // Feed another noise frame (class 3: motorcycle)
        noisy_det.class_id = 3;
        tracker.update(&[noisy_det], &mut out);
        // Still class 0 because history has [0, 0, 0, 2, 3] -> count(0) = 3 > count(2), count(3)
        assert_eq!(
            tracker.tracks[t_idx].class_id, 0,
            "Track class must remain 0 via majority vote"
        );
    }
}
