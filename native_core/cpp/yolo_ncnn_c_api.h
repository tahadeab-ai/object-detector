#ifndef YOLO_NCNN_C_API_H
#define YOLO_NCNN_C_API_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
  #define YOLO_EXPORT __declspec(dllexport)
#else
  #define YOLO_EXPORT __attribute__((visibility("default")))
#endif

// =============================================================================
// 1. Task Definitions
// =============================================================================
#define YOLO_TASK_DETECTION      0
#define YOLO_TASK_SEGMENTATION   1
#define YOLO_TASK_POSE           2
#define YOLO_TASK_CLASSIFICATION 3
#define YOLO_TASK_OBB            4

// Maximum detections and tracks per frame (Fixed array, zero-heap per frame)
#define YOLO_MAX_BOXES 100

// Spatial Zones
typedef enum {
    YOLO_ZONE_LEFT = 0,
    YOLO_ZONE_CENTER = 1,
    YOLO_ZONE_RIGHT = 2
} YoloSpatialZone;

// Proximity Tiers
typedef enum {
    YOLO_PROXIMITY_FAR = 0,
    YOLO_PROXIMITY_MEDIUM = 1,
    YOLO_PROXIMITY_NEAR = 2
} YoloProximityTier;

// Track State
typedef enum {
    YOLO_TRACK_TENTATIVE = 0,
    YOLO_TRACK_CONFIRMED = 1,
    YOLO_TRACK_COASTING = 2,
    YOLO_TRACK_DELETED = 3
} YoloTrackState;

// =============================================================================
// 2. Task A: Object Detection Structs (PRESERVED)
// =============================================================================

// Detection Box Struct (Mandatory sizeof == 40, alignof == 4)
typedef struct {
    float x1;               // 0..4
    float y1;               // 4..8
    float x2;               // 8..12
    float y2;               // 12..16
    float confidence;       // 16..20
    int32_t class_id;       // 20..24
    int32_t track_id;       // 24..28
    int32_t track_state;    // 28..32 (YoloTrackState)
    int32_t spatial_zone;   // 32..36 (YoloSpatialZone)
    int32_t proximity_tier; // 36..40 (YoloProximityTier)
} YoloDetectionBox;

// Frame Result Struct (Mandatory sizeof == 4024, alignof == 4)
typedef struct {
    int32_t num_detections;       // 0..4
    uint32_t frame_id;            // 4..8
    float inference_time_ms;      // 8..12
    float tracker_time_ms;        // 12..16
    int32_t active_backend;       // 16..20 (0=CPU, 1=Vulkan, 2=Turnip)
    int32_t status_code;          // 20..24 (0=Success, non-zero=Error)
    YoloDetectionBox boxes[YOLO_MAX_BOXES]; // 24..4024 (100 * 40 = 4000 bytes)
} YoloFrameResult;

// =============================================================================
// 3. Multi-Task Common Telemetry Header (Mandatory sizeof == 28, alignof == 4)
// =============================================================================
typedef struct {
    int32_t task_id;                 // 0..4
    uint32_t frame_id;               // 4..8
    float preprocessing_time_ms;     // 8..12
    float inference_time_ms;         // 12..16
    float postprocessing_time_ms;    // 16..20
    int32_t active_backend;          // 20..24 (0=CPU, 1=Vulkan, 2=Turnip)
    int32_t status_code;             // 24..28
} MultiTaskHeader;

// =============================================================================
// 4. Task B: Instance Segmentation Structs (Mandatory sizeof == 8792, alignof == 4)
// =============================================================================
#define MAX_SEG_OBJECTS 30
#define MAX_CONTOUR_POINTS 32

typedef struct {
    float x1;                        // 0..4
    float y1;                        // 4..8
    float x2;                        // 8..12
    float y2;                        // 12..16
    float confidence;                // 16..20
    int32_t class_id;                // 20..24
    int32_t mask_w;                  // 24..28
    int32_t mask_h;                  // 28..32
    int32_t num_contour_points;      // 32..36 (up to 32)
    float contour_points[MAX_CONTOUR_POINTS * 2]; // 36..292 (32 * 2 * 4 = 256 bytes)
} YoloSegmentationItem;

typedef struct {
    MultiTaskHeader header;          // 0..28
    int32_t num_objects;             // 28..32
    YoloSegmentationItem objects[MAX_SEG_OBJECTS]; // 32..8792 (30 * 292 = 8760 bytes)
} YoloSegmentationResult;

// =============================================================================
// 5. Task C: Pose Estimation Structs (Mandatory sizeof == 4592, alignof == 4)
// =============================================================================
#define MAX_POSE_OBJECTS 20
#define POSE_KEYPOINTS_COUNT 17

typedef struct {
    float x;                         // 0..4
    float y;                         // 4..8
    float confidence;                // 8..12
} YoloKeyPoint;

typedef struct {
    float x1;                        // 0..4
    float y1;                        // 4..8
    float x2;                        // 8..12
    float y2;                        // 12..16
    float confidence;                // 16..20
    int32_t class_id;                // 20..24
    YoloKeyPoint keypoints[POSE_KEYPOINTS_COUNT]; // 24..228 (17 * 12 = 204 bytes)
} YoloPoseItem;

typedef struct {
    MultiTaskHeader header;          // 0..28
    int32_t num_objects;             // 28..32
    YoloPoseItem objects[MAX_POSE_OBJECTS]; // 32..4592 (20 * 228 = 4560 bytes)
} YoloPoseResult;

// =============================================================================
// 6. Task D: Image Classification Structs (Mandatory sizeof == 72, alignof == 4)
// =============================================================================
#define MAX_TOPK 5

typedef struct {
    int32_t class_id;                // 0..4
    float confidence;                // 4..8
} YoloClassificationItem;

typedef struct {
    MultiTaskHeader header;          // 0..28
    int32_t num_items;               // 28..32
    YoloClassificationItem items[MAX_TOPK]; // 32..72 (5 * 8 = 40 bytes)
} YoloClassificationResult;

// =============================================================================
// 7. Task E: Oriented Bounding Box (OBB) Structs (Mandatory sizeof == 3232, alignof == 4)
// =============================================================================
#define MAX_OBB_OBJECTS 50

typedef struct {
    float cx;                        // 0..4
    float cy;                        // 4..8
    float width;                     // 8..12
    float height;                    // 12..16
    float angle_rad;                 // 16..20
    float angle_deg;                 // 20..24
    float corners[8];                // 24..56 (x0, y0, x1, y1, x2, y2, x3, y3)
    float confidence;                // 56..60
    int32_t class_id;                // 60..64
} YoloObbItem;

typedef struct {
    MultiTaskHeader header;          // 0..28
    int32_t num_objects;             // 28..32
    YoloObbItem objects[MAX_OBB_OBJECTS]; // 32..3232 (50 * 64 = 3200 bytes)
} YoloObbResult;

// Compile-time struct layout assertions
#ifdef __cplusplus
static_assert(sizeof(YoloDetectionBox) == 40, "sizeof(YoloDetectionBox) must be 40 bytes");
static_assert(alignof(YoloDetectionBox) == 4, "alignof(YoloDetectionBox) must be 4 bytes");
static_assert(sizeof(YoloFrameResult) == 4024, "sizeof(YoloFrameResult) must be 4024 bytes");
static_assert(alignof(YoloFrameResult) == 4, "alignof(YoloFrameResult) must be 4 bytes");

static_assert(sizeof(MultiTaskHeader) == 28, "sizeof(MultiTaskHeader) must be 28 bytes");
static_assert(alignof(MultiTaskHeader) == 4, "alignof(MultiTaskHeader) must be 4 bytes");
static_assert(sizeof(YoloSegmentationItem) == 292, "sizeof(YoloSegmentationItem) must be 292 bytes");
static_assert(sizeof(YoloSegmentationResult) == 8792, "sizeof(YoloSegmentationResult) must be 8792 bytes");
static_assert(sizeof(YoloPoseItem) == 228, "sizeof(YoloPoseItem) must be 228 bytes");
static_assert(sizeof(YoloPoseResult) == 4592, "sizeof(YoloPoseResult) must be 4592 bytes");
static_assert(sizeof(YoloClassificationResult) == 72, "sizeof(YoloClassificationResult) must be 72 bytes");
static_assert(sizeof(YoloObbItem) == 64, "sizeof(YoloObbItem) must be 64 bytes");
static_assert(sizeof(YoloObbResult) == 3232, "sizeof(YoloObbResult) must be 3232 bytes");
#endif

// =============================================================================
// 8. Legacy Engine API (100% Backward Compatible for Task A Detection)
// =============================================================================
YOLO_EXPORT int yolo_engine_init(const char* param_path, const char* bin_path, int use_vulkan);
YOLO_EXPORT int yolo_engine_set_backend(int use_vulkan);
YOLO_EXPORT int yolo_engine_forward_yuv420(
    const uint8_t* y_plane,
    const uint8_t* u_plane,
    const uint8_t* v_plane,
    int width,
    int height,
    int y_row_stride,
    int uv_row_stride,
    int uv_pixel_stride,
    int sensor_orientation,
    YoloFrameResult* out_result
);
YOLO_EXPORT int yolo_engine_forward_rgba(
    const uint8_t* rgba,
    int width,
    int height,
    int sensor_orientation,
    YoloFrameResult* out_result
);
YOLO_EXPORT void yolo_engine_destroy(void);

// =============================================================================
// 9. Modern Multi-Task Engine API
// =============================================================================
YOLO_EXPORT int yolo_multitask_init(
    int task_id,
    const char* param_path,
    const char* bin_path,
    int target_size,
    int use_backend // 0=CPU, 1=Vulkan, 2=Turnip
);

YOLO_EXPORT int yolo_multitask_set_target_size(int target_size);

YOLO_EXPORT int yolo_multitask_set_backend(int backend);

YOLO_EXPORT int yolo_multitask_get_active_task(void);

YOLO_EXPORT int yolo_multitask_forward_yuv420(
    const uint8_t* y_plane,
    const uint8_t* u_plane,
    const uint8_t* v_plane,
    int width,
    int height,
    int y_row_stride,
    int uv_row_stride,
    int uv_pixel_stride,
    int sensor_orientation,
    void* out_result_buffer
);

YOLO_EXPORT int yolo_multitask_forward_rgba(
    const uint8_t* rgba,
    int width,
    int height,
    int sensor_orientation,
    void* out_result_buffer
);

YOLO_EXPORT void yolo_multitask_destroy(void);

#ifdef __cplusplus
}
#endif

#endif // YOLO_NCNN_C_API_H
