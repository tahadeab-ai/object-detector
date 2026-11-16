//! Core types and C-ABI compatible data structures for YOLO NCNN Detector.

pub const YOLO_MAX_BOXES: usize = 100;

pub const ZONE_LEFT: i32 = 0;
pub const ZONE_CENTER: i32 = 1;
pub const ZONE_RIGHT: i32 = 2;

pub const PROXIMITY_FAR: i32 = 0;
pub const PROXIMITY_MEDIUM: i32 = 1;
pub const PROXIMITY_NEAR: i32 = 2;

pub const TRACK_TENTATIVE: i32 = 0;
pub const TRACK_CONFIRMED: i32 = 1;
pub const TRACK_COASTING: i32 = 2;
pub const TRACK_DELETED: i32 = 3;

/// Single detection / track bounding box representation (40 bytes, align 4).
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct YoloDetectionBox {
    pub x1: f32,
    pub y1: f32,
    pub x2: f32,
    pub y2: f32,
    pub confidence: f32,
    pub class_id: i32,
    pub track_id: i32,
    pub track_state: i32,
    pub spatial_zone: i32,
    pub proximity_tier: i32,
}

impl Default for YoloDetectionBox {
    fn default() -> Self {
        Self {
            x1: 0.0,
            y1: 0.0,
            x2: 0.0,
            y2: 0.0,
            confidence: 0.0,
            class_id: -1,
            track_id: -1,
            track_state: TRACK_TENTATIVE,
            spatial_zone: ZONE_CENTER,
            proximity_tier: PROXIMITY_FAR,
        }
    }
}

/// Unified frame inference and tracking result (4024 bytes, align 4).
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct YoloFrameResult {
    pub num_detections: i32,
    pub frame_id: u32,
    pub inference_time_ms: f32,
    pub tracker_time_ms: f32,
    pub active_backend: i32,
    pub status_code: i32,
    pub boxes: [YoloDetectionBox; YOLO_MAX_BOXES],
}

impl Default for YoloFrameResult {
    fn default() -> Self {
        Self {
            num_detections: 0,
            frame_id: 0,
            inference_time_ms: 0.0,
            tracker_time_ms: 0.0,
            active_backend: 0,
            status_code: 0,
            boxes: [YoloDetectionBox::default(); YOLO_MAX_BOXES],
        }
    }
}

// Compile-time layout verification
const _: () = {
    assert!(core::mem::size_of::<YoloDetectionBox>() == 40, "sizeof(YoloDetectionBox) must be 40");
    assert!(core::mem::align_of::<YoloDetectionBox>() == 4, "alignof(YoloDetectionBox) must be 4");
    assert!(core::mem::size_of::<YoloFrameResult>() == 4024, "sizeof(YoloFrameResult) must be 4024");
    assert!(core::mem::align_of::<YoloFrameResult>() == 4, "alignof(YoloFrameResult) must be 4");
};

/// Computes spatial zone: cx < 0.33 LEFT(0); 0.33 <= cx <= 0.66 CENTER(1); cx > 0.66 RIGHT(2).
#[inline]
pub fn compute_spatial_zone(x1: f32, x2: f32) -> i32 {
    let cx = (x1 + x2) * 0.5;
    if cx < 0.33 {
        ZONE_LEFT
    } else if cx <= 0.66 {
        ZONE_CENTER
    } else {
        ZONE_RIGHT
    }
}

/// Computes proximity tier:
/// area >= 0.18 || y2 >= 0.82 -> NEAR(2)
/// area >= 0.05 || y2 >= 0.55 -> MEDIUM(1)
/// else -> FAR(0)
#[inline]
pub fn compute_proximity_tier(x1: f32, y1: f32, x2: f32, y2: f32) -> i32 {
    let w = (x2 - x1).max(0.0);
    let h = (y2 - y1).max(0.0);
    let area = w * h;

    if area >= 0.18 || y2 >= 0.82 {
        PROXIMITY_NEAR
    } else if area >= 0.05 || y2 >= 0.55 {
        PROXIMITY_MEDIUM
    } else {
        PROXIMITY_FAR
    }
}

/// Computes standard Intersection over Union (IoU) between two bounding boxes.
#[inline]
pub fn box_iou(a: &YoloDetectionBox, b: &YoloDetectionBox) -> f32 {
    let inter_x1 = a.x1.max(b.x1);
    let inter_y1 = a.y1.max(b.y1);
    let inter_x2 = a.x2.min(b.x2);
    let inter_y2 = a.y2.min(b.y2);

    let inter_w = (inter_x2 - inter_x1).max(0.0);
    let inter_h = (inter_y2 - inter_y1).max(0.0);
    let inter_area = inter_w * inter_h;

    let area_a = (a.x2 - a.x1).max(0.0) * (a.y2 - a.y1).max(0.0);
    let area_b = (b.x2 - b.x1).max(0.0) * (b.y2 - b.y1).max(0.0);

    let union_area = area_a + area_b - inter_area;
    if union_area <= 1e-6 {
        0.0
    } else {
        inter_area / union_area
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_struct_layout_gate() {
        assert_eq!(core::mem::size_of::<YoloDetectionBox>(), 40);
        assert_eq!(core::mem::align_of::<YoloDetectionBox>(), 4);
        assert_eq!(core::mem::size_of::<YoloFrameResult>(), 4024);
        assert_eq!(core::mem::align_of::<YoloFrameResult>(), 4);
    }

    #[test]
    fn test_spatial_zone_logic() {
        assert_eq!(compute_spatial_zone(0.1, 0.2), ZONE_LEFT);     // cx = 0.15 < 0.33
        assert_eq!(compute_spatial_zone(0.4, 0.6), ZONE_CENTER);   // cx = 0.50
        assert_eq!(compute_spatial_zone(0.7, 0.9), ZONE_RIGHT);    // cx = 0.80 > 0.66
    }

    #[test]
    fn test_proximity_tier_logic() {
        // Near due to y2 >= 0.82
        assert_eq!(compute_proximity_tier(0.1, 0.7, 0.2, 0.85), PROXIMITY_NEAR);
        // Near due to area >= 0.18
        assert_eq!(compute_proximity_tier(0.0, 0.0, 0.5, 0.4), PROXIMITY_NEAR); // area = 0.20
        // Medium due to y2 >= 0.55
        assert_eq!(compute_proximity_tier(0.1, 0.4, 0.2, 0.60), PROXIMITY_MEDIUM);
        // Medium due to area >= 0.05
        assert_eq!(compute_proximity_tier(0.1, 0.1, 0.4, 0.3), PROXIMITY_MEDIUM); // area = 0.06
        // Far
        assert_eq!(compute_proximity_tier(0.1, 0.1, 0.2, 0.2), PROXIMITY_FAR); // area = 0.01, y2=0.2
    }
}
