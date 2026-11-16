import 'dart:ffi';

/// Maximum detection boxes per frame result (matches YOLO_MAX_BOXES = 100)
const int yoloMaxBoxes = 100;

/// Spatial zone of detection relative to camera frame
enum SpatialZone {
  left,
  center,
  right;

  static SpatialZone fromInt(int value) {
    switch (value) {
      case 0:
        return SpatialZone.left;
      case 1:
        return SpatialZone.center;
      case 2:
        return SpatialZone.right;
      default:
        return SpatialZone.center;
    }
  }
}

/// Proximity tier of detection based on area and vertical position
enum ProximityTier {
  far,
  medium,
  near;

  static ProximityTier fromInt(int value) {
    switch (value) {
      case 0:
        return ProximityTier.far;
      case 1:
        return ProximityTier.medium;
      case 2:
        return ProximityTier.near;
      default:
        return ProximityTier.far;
    }
  }
}

/// Tracking lifecycle states
enum TrackState {
  tentative,
  confirmed,
  coasting,
  deleted;

  static TrackState fromInt(int value) {
    switch (value) {
      case 0:
        return TrackState.tentative;
      case 1:
        return TrackState.confirmed;
      case 2:
        return TrackState.coasting;
      case 3:
        return TrackState.deleted;
      default:
        return TrackState.tentative;
    }
  }
}

/// Native Detection Box matching C `YoloDetectionBox` (sizeof == 40, alignof == 4)
final class YoloDetectionBox extends Struct {
  @Float()
  external double x1;

  @Float()
  external double y1;

  @Float()
  external double x2;

  @Float()
  external double y2;

  @Float()
  external double confidence;

  @Int32()
  external int classId;

  @Int32()
  external int trackId;

  @Int32()
  external int trackState;

  @Int32()
  external int spatialZone;

  @Int32()
  external int proximityTier;
}

/// Native Frame Result matching C `YoloFrameResult` (sizeof == 4024, alignof == 4)
final class YoloFrameResult extends Struct {
  @Int32()
  external int numDetections;

  @Uint32()
  external int frameId;

  @Float()
  external double inferenceTimeMs;

  @Float()
  external double trackerTimeMs;

  @Int32()
  external int activeBackend; // 0=CPU, 1=Vulkan

  @Int32()
  external int statusCode; // 0=Success

  @Array(yoloMaxBoxes)
  external Array<YoloDetectionBox> boxes;
}

/// HARD GATE: Validates exact C-ABI struct sizes at runtime.
/// Fails loudly with StateError on any struct layout drift.
void enforceLayoutGate() {
  final boxSize = sizeOf<YoloDetectionBox>();
  final frameResultSize = sizeOf<YoloFrameResult>();

  if (boxSize != 40) {
    throw StateError(
      'LAYOUT GATE FAILURE: sizeof(YoloDetectionBox) == $boxSize, expected 40 bytes',
    );
  }
  if (frameResultSize != 4024) {
    throw StateError(
      'LAYOUT GATE FAILURE: sizeof(YoloFrameResult) == $frameResultSize, expected 4024 bytes',
    );
  }
}
