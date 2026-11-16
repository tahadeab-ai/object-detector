//! YOLO11 Tensor Decoder for [1, 84, 8400] row-major tensor layout.

use crate::types::{compute_proximity_tier, compute_spatial_zone, YoloDetectionBox};

pub const NUM_ANCHORS: usize = 8400;
pub const NUM_ROWS: usize = 84;
pub const NUM_CLASSES: usize = 80;

/// Decodes raw YOLO11 tensor [84, 8400] into candidate detection boxes.
///
/// Layout: row-major, index = row * 8400 + anchor.
/// Rows 0..3: cx, cy, w, h in 640x640 letterbox space.
/// Rows 4..83: 80 class probabilities.
pub fn decode_tensor(
    raw_tensor: &[f32],
    scale: f32,
    pad_w: f32,
    pad_h: f32,
    conf_threshold: f32,
    out_boxes: &mut [YoloDetectionBox],
) -> usize {
    if raw_tensor.len() < NUM_ROWS * NUM_ANCHORS || scale <= 0.0 {
        return 0;
    }

    let inv_scale = 1.0 / scale;
    let mut count = 0;

    for anchor in 0..NUM_ANCHORS {
        // Fast early-skip: find max class score and class_id
        let mut max_score = 0.0f32;
        let mut best_class = 0i32;

        for c in 0..NUM_CLASSES {
            let score = raw_tensor[(4 + c) * NUM_ANCHORS + anchor];
            if score > max_score {
                max_score = score;
                best_class = c as i32;
            }
        }

        // Filter by confidence threshold
        if max_score < conf_threshold {
            continue;
        }

        let cx = raw_tensor[0 * NUM_ANCHORS + anchor];
        let cy = raw_tensor[1 * NUM_ANCHORS + anchor];
        let w = raw_tensor[2 * NUM_ANCHORS + anchor];
        let h = raw_tensor[3 * NUM_ANCHORS + anchor];

        // Convert center/size to letterbox corners
        let lb_x1 = cx - w * 0.5;
        let lb_y1 = cy - h * 0.5;
        let lb_x2 = cx + w * 0.5;
        let lb_y2 = cy + h * 0.5;

        // Unpad and scale to normalized [0, 1] frame coordinates
        let x1 = ((lb_x1 - pad_w) * inv_scale).clamp(0.0, 1.0);
        let y1 = ((lb_y1 - pad_h) * inv_scale).clamp(0.0, 1.0);
        let x2 = ((lb_x2 - pad_w) * inv_scale).clamp(0.0, 1.0);
        let y2 = ((lb_y2 - pad_h) * inv_scale).clamp(0.0, 1.0);

        if x2 <= x1 || y2 <= y1 {
            continue;
        }

        let spatial_zone = compute_spatial_zone(x1, x2);
        let proximity_tier = compute_proximity_tier(x1, y1, x2, y2);

        out_boxes[count] = YoloDetectionBox {
            x1,
            y1,
            x2,
            y2,
            confidence: max_score,
            class_id: best_class,
            track_id: -1,
            track_state: 0,
            spatial_zone,
            proximity_tier,
        };

        count += 1;
        if count >= out_boxes.len() {
            break;
        }
    }

    count
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::YOLO_MAX_BOXES;

    #[test]
    fn test_decoder_synthetic_tensor() {
        let mut raw = vec![0.0f32; NUM_ROWS * NUM_ANCHORS];

        // Anchor 100: person (class 0) at center [320, 320, 100, 200]
        raw[0 * NUM_ANCHORS + 100] = 320.0; // cx
        raw[1 * NUM_ANCHORS + 100] = 320.0; // cy
        raw[2 * NUM_ANCHORS + 100] = 100.0; // w
        raw[3 * NUM_ANCHORS + 100] = 200.0; // h
        raw[4 * NUM_ANCHORS + 100] = 0.85;  // class 0 score

        // Anchor 200: car (class 2) below threshold (0.15)
        raw[0 * NUM_ANCHORS + 200] = 100.0;
        raw[1 * NUM_ANCHORS + 200] = 100.0;
        raw[2 * NUM_ANCHORS + 200] = 50.0;
        raw[3 * NUM_ANCHORS + 200] = 50.0;
        raw[6 * NUM_ANCHORS + 200] = 0.15; // class 2 score

        let mut boxes = [YoloDetectionBox::default(); YOLO_MAX_BOXES];
        // Test scale=1.0, pad=0.0 (already 640x640 normalized to width=640, height=640)
        let count = decode_tensor(&raw, 640.0, 0.0, 0.0, 0.25, &mut boxes);

        assert_eq!(count, 1);
        let b = &boxes[0];
        assert_eq!(b.class_id, 0);
        assert!((b.confidence - 0.85).abs() < 1e-5);
        // x1 = (320 - 50)/640 = 270/640 = 0.421875
        // x2 = (320 + 50)/640 = 370/640 = 0.578125
        assert!((b.x1 - 270.0 / 640.0).abs() < 1e-4);
        assert!((b.x2 - 370.0 / 640.0).abs() < 1e-4);
        assert_eq!(b.spatial_zone, crate::types::ZONE_CENTER);
    }
}
