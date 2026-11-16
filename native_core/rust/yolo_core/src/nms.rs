//! Class-Aware Non-Maximum Suppression (NMS).

use crate::types::{box_iou, YoloDetectionBox, YOLO_MAX_BOXES};

/// Performs class-aware Non-Maximum Suppression on decoded detection candidates.
/// Suppresses same-class boxes with IoU > iou_threshold.
/// Results are written to `out_boxes`, capped at YOLO_MAX_BOXES (100).
pub fn class_aware_nms(
    candidates: &[YoloDetectionBox],
    iou_threshold: f32,
    out_boxes: &mut [YoloDetectionBox],
) -> usize {
    if candidates.is_empty() {
        return 0;
    }

    let n = candidates.len().min(YOLO_MAX_BOXES);
    let mut indices: [usize; YOLO_MAX_BOXES] = [0; YOLO_MAX_BOXES];
    for i in 0..n {
        indices[i] = i;
    }

    // Sort candidate indices descending by confidence (insertion sort: fast on small N, zero alloc)
    for i in 1..n {
        let key = indices[i];
        let key_conf = candidates[key].confidence;
        let mut j = i;
        while j > 0 && candidates[indices[j - 1]].confidence < key_conf {
            indices[j] = indices[j - 1];
            j -= 1;
        }
        indices[j] = key;
    }

    let mut suppressed: [bool; YOLO_MAX_BOXES] = [false; YOLO_MAX_BOXES];
    let mut out_count = 0;

    for i in 0..n {
        let idx_a = indices[i];
        if suppressed[idx_a] {
            continue;
        }

        let box_a = &candidates[idx_a];
        out_boxes[out_count] = *box_a;
        out_count += 1;
        if out_count >= out_boxes.len() {
            break;
        }

        // Suppress remaining same-class overlapping candidates
        for j in (i + 1)..n {
            let idx_b = indices[j];
            if suppressed[idx_b] {
                continue;
            }

            let box_b = &candidates[idx_b];
            if box_a.class_id == box_b.class_id {
                let iou = box_iou(box_a, box_b);
                if iou > iou_threshold {
                    suppressed[idx_b] = true;
                }
            }
        }
    }

    out_count
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_nms_same_class_suppression_and_cross_class_retention() {
        let mut candidates = [YoloDetectionBox::default(); 3];

        // Box 0: person, conf 0.90, [0.1, 0.1, 0.3, 0.3]
        candidates[0] = YoloDetectionBox {
            x1: 0.1, y1: 0.1, x2: 0.3, y2: 0.3,
            confidence: 0.90, class_id: 0, ..Default::default()
        };

        // Box 1: person, conf 0.80, overlapping with Box 0 (IoU > 0.45)
        candidates[1] = YoloDetectionBox {
            x1: 0.12, y1: 0.12, x2: 0.30, y2: 0.30,
            confidence: 0.80, class_id: 0, ..Default::default()
        };

        // Box 2: bicycle, conf 0.85, same area as Box 0 but DIFFERENT class
        candidates[2] = YoloDetectionBox {
            x1: 0.10, y1: 0.10, x2: 0.30, y2: 0.30,
            confidence: 0.85, class_id: 1, ..Default::default()
        };

        let mut output = [YoloDetectionBox::default(); YOLO_MAX_BOXES];
        let kept = class_aware_nms(&candidates, 0.45, &mut output);

        // Box 0 (person 0.90) and Box 2 (bicycle 0.85) should be kept; Box 1 (person 0.80) suppressed
        assert_eq!(kept, 2);
        assert_eq!(output[0].class_id, 0);
        assert_eq!(output[0].confidence, 0.90);
        assert_eq!(output[1].class_id, 1);
        assert_eq!(output[1].confidence, 0.85);
    }
}
