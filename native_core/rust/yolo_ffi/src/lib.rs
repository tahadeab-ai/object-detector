//! C-ABI Static Library Bridge for YOLO NCNN Detector.
//! Compiles strictly as a static library (libyolo_rust.a) to link into unified libyolo_ncnn.so.

use std::sync::Mutex;
use yolo_core::{
    class_aware_nms, decode_tensor, TwoStageTracker, YoloDetectionBox, YoloFrameResult,
    YOLO_MAX_BOXES,
};

// Global tracker state protected by a mutex
static TRACKER: Mutex<Option<TwoStageTracker>> = Mutex::new(None);

// Layout gate compile-time assertions
const _: () = {
    assert!(core::mem::size_of::<YoloDetectionBox>() == 40, "sizeof(YoloDetectionBox) must be 40");
    assert!(core::mem::align_of::<YoloDetectionBox>() == 4, "alignof(YoloDetectionBox) must be 4");
    assert!(core::mem::size_of::<YoloFrameResult>() == 4024, "sizeof(YoloFrameResult) must be 4024");
    assert!(core::mem::align_of::<YoloFrameResult>() == 4, "alignof(YoloFrameResult) must be 4");
};

#[no_mangle]
pub extern "C" fn yolo_rust_init() -> i32 {
    let mut lock = match TRACKER.lock() {
        Ok(guard) => guard,
        Err(_) => return -1,
    };
    *lock = Some(TwoStageTracker::new(0.25));
    0
}

#[no_mangle]
pub extern "C" fn yolo_rust_destroy() {
    if let Ok(mut lock) = TRACKER.lock() {
        *lock = None;
    }
}

#[no_mangle]
pub extern "C" fn yolo_engine_reset_tracker() -> i32 {
    let mut lock = match TRACKER.lock() {
        Ok(guard) => guard,
        Err(_) => return -1,
    };
    if let Some(ref mut tracker) = *lock {
        tracker.reset();
        0
    } else {
        -1
    }
}

#[no_mangle]
pub extern "C" fn yolo_rust_process_frame(
    raw_tensor: *const f32,
    scale: f32,
    pad_w: f32,
    pad_h: f32,
    frame_id: u32,
    out_result: *mut YoloFrameResult,
) -> i32 {
    if raw_tensor.is_null() || out_result.is_null() {
        return -1;
    }

    let mut lock = match TRACKER.lock() {
        Ok(guard) => guard,
        Err(_) => return -2,
    };
    let tracker = match *lock {
        Some(ref mut t) => t,
        None => return -3,
    };

    let tensor_slice = unsafe { std::slice::from_raw_parts(raw_tensor, 84 * 8400) };
    let result = unsafe { &mut *out_result };

    // Fixed array buffers to avoid per-frame heap allocations
    let mut decoded_boxes = [YoloDetectionBox::default(); YOLO_MAX_BOXES];
    let mut nms_boxes = [YoloDetectionBox::default(); YOLO_MAX_BOXES];

    // 1. Decode raw tensor [84, 8400]
    let decoded_count = decode_tensor(
        tensor_slice,
        scale,
        pad_w,
        pad_h,
        0.10, // low-conf threshold so Stage 2 can use 0.10 <= conf < 0.25 candidates
        &mut decoded_boxes,
    );

    // 2. Class-aware NMS
    let nms_count = class_aware_nms(
        &decoded_boxes[..decoded_count],
        0.45,
        &mut nms_boxes,
    );

    // 3. Multi-object tracker update
    let active_count = tracker.update(
        &nms_boxes[..nms_count],
        &mut result.boxes,
    );

    result.num_detections = active_count as i32;
    result.frame_id = frame_id;

    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_yolo_ffi_layout_and_init() {
        assert_eq!(yolo_rust_init(), 0);
        assert_eq!(yolo_engine_reset_tracker(), 0);
        yolo_rust_destroy();
    }
}
