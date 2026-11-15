#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include <stddef.h>

typedef enum { ZONE_LEFT = 0, ZONE_CENTER = 1, ZONE_RIGHT = 2 } SpatialZone;
typedef enum { PROXIMITY_FAR = 0, PROXIMITY_MEDIUM = 1, PROXIMITY_NEAR = 2 } ProximityTier;

typedef struct {
    int32_t track_id;        // 0
    int32_t class_id;        // 4
    float confidence;        // 8
    float x1, y1, x2, y2;    // 12, 16, 20, 24
    int32_t spatial_zone;    // 28
    int32_t proximity_tier;  // 32
} YoloDetectionBox;          // size: 36

typedef struct {
    int32_t count;               // 0
    float preprocess_ms;         // 4
    float inference_ms;          // 8
    float postprocess_ms;        // 12
    float total_fps;             // 16
    int32_t active_backend;      // 20
    YoloDetectionBox boxes[100]; // 24 (size 3600)
} YoloFrameResult;               // size: 3624

int main(void) {
    assert(sizeof(YoloDetectionBox) == 36);
    assert(offsetof(YoloDetectionBox, track_id) == 0);
    assert(offsetof(YoloDetectionBox, class_id) == 4);
    assert(offsetof(YoloDetectionBox, confidence) == 8);
    assert(offsetof(YoloDetectionBox, x1) == 12);
    assert(offsetof(YoloDetectionBox, spatial_zone) == 28);
    assert(offsetof(YoloDetectionBox, proximity_tier) == 32);

    assert(sizeof(YoloFrameResult) == 3624);
    assert(offsetof(YoloFrameResult, count) == 0);
    assert(offsetof(YoloFrameResult, preprocess_ms) == 4);
    assert(offsetof(YoloFrameResult, inference_ms) == 8);
    assert(offsetof(YoloFrameResult, active_backend) == 20);
    assert(offsetof(YoloFrameResult, boxes) == 24);

    printf("C-ABI structure offsets and sizes verified successfully.\n");
    return 0;
}
