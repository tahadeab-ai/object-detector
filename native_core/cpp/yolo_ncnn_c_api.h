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
    int32_t active_backend;       // 16..20 (0=CPU, 1=Vulkan)
    int32_t status_code;          // 20..24 (0=Success, non-zero=Error)
    YoloDetectionBox boxes[YOLO_MAX_BOXES]; // 24..4024 (100 * 40 = 4000 bytes)
} YoloFrameResult;

#ifdef __cplusplus
static_assert(sizeof(YoloDetectionBox) == 40, "sizeof(YoloDetectionBox) must be exactly 40 bytes");
static_assert(alignof(YoloDetectionBox) == 4, "alignof(YoloDetectionBox) must be exactly 4 bytes");
static_assert(sizeof(YoloFrameResult) == 4024, "sizeof(YoloFrameResult) must be exactly 4024 bytes");
static_assert(alignof(YoloFrameResult) == 4, "alignof(YoloFrameResult) must be exactly 4 bytes");
#endif

// Engine API Functions
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

#ifdef __cplusplus
}
#endif

#endif // YOLO_NCNN_C_API_H
