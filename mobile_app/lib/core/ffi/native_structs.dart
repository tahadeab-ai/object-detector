import 'dart:ffi';

/// Supported Vision Tasks
enum VisionTask {
  detection(0, 'Detection', 'كشف الكائنات'),
  segmentation(1, 'Segmentation', 'التقطيع المقطعي'),
  pose(2, 'Pose', 'تقدير الوضعية'),
  classification(3, 'Classification', 'تصنيف الصور'),
  obb(4, 'OBB', 'كشف الصناديق المائلة');

  final int id;
  final String labelEn;
  final String labelAr;
  const VisionTask(this.id, this.labelEn, this.labelAr);

  static VisionTask fromId(int id) {
    switch (id) {
      case 0:
        return VisionTask.detection;
      case 1:
        return VisionTask.segmentation;
      case 2:
        return VisionTask.pose;
      case 3:
        return VisionTask.classification;
      case 4:
        return VisionTask.obb;
      default:
        return VisionTask.detection;
    }
  }
}

/// Supported Execution Backends
enum InferenceBackend {
  cpu(0, 'CPU (NEON 4T)', 'المعالج (4 أنوية)'),
  vulkan(1, 'Vulkan GPU', 'معالج الرسوميات'),
  turnip(2, 'Mesa Turnip', 'محرّك تيرنب');

  final int id;
  final String labelEn;
  final String labelAr;
  const InferenceBackend(this.id, this.labelEn, this.labelAr);

  static InferenceBackend fromId(int id) {
    switch (id) {
      case 0:
        return InferenceBackend.cpu;
      case 1:
        return InferenceBackend.vulkan;
      case 2:
        return InferenceBackend.turnip;
      default:
        return InferenceBackend.cpu;
    }
  }
}

/// Maximum detection boxes per frame result (matches YOLO_MAX_BOXES = 100)
const int yoloMaxBoxes = 100;
const int maxSegObjects = 30;
const int maxContourPoints = 32;
const int maxPoseObjects = 20;
const int poseKeypointsCount = 17;
const int maxTopK = 5;
const int maxObbObjects = 50;

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

// =============================================================================
// Task A: Detection Structs (PRESERVED)
// =============================================================================

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
  external int activeBackend; // 0=CPU, 1=Vulkan, 2=Turnip

  @Int32()
  external int statusCode; // 0=Success

  @Array(yoloMaxBoxes)
  external Array<YoloDetectionBox> boxes;
}

// =============================================================================
// Multi-Task Common Header (sizeof == 28, alignof == 4)
// =============================================================================
final class MultiTaskHeader extends Struct {
  @Int32()
  external int taskId;

  @Uint32()
  external int frameId;

  @Float()
  external double preprocessingTimeMs;

  @Float()
  external double inferenceTimeMs;

  @Float()
  external double postprocessingTimeMs;

  @Int32()
  external int activeBackend;

  @Int32()
  external int statusCode;
}

// =============================================================================
// Task B: Instance Segmentation Structs
// =============================================================================
final class YoloSegmentationItem extends Struct {
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
  external int maskW;

  @Int32()
  external int maskH;

  @Int32()
  external int numContourPoints;

  @Array(maxContourPoints * 2)
  external Array<Float> contourPoints;
}

final class YoloSegmentationResult extends Struct {
  external MultiTaskHeader header;

  @Int32()
  external int numObjects;

  @Array(maxSegObjects)
  external Array<YoloSegmentationItem> objects;
}

// =============================================================================
// Task C: Pose Estimation Structs
// =============================================================================
final class YoloKeyPoint extends Struct {
  @Float()
  external double x;

  @Float()
  external double y;

  @Float()
  external double confidence;
}

final class YoloPoseItem extends Struct {
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

  @Array(poseKeypointsCount)
  external Array<YoloKeyPoint> keypoints;
}

final class YoloPoseResult extends Struct {
  external MultiTaskHeader header;

  @Int32()
  external int numObjects;

  @Array(maxPoseObjects)
  external Array<YoloPoseItem> objects;
}

// =============================================================================
// Task D: Image Classification Structs
// =============================================================================
final class YoloClassificationItem extends Struct {
  @Int32()
  external int classId;

  @Float()
  external double confidence;
}

final class YoloClassificationResult extends Struct {
  external MultiTaskHeader header;

  @Int32()
  external int numItems;

  @Array(maxTopK)
  external Array<YoloClassificationItem> items;
}

// =============================================================================
// Task E: Oriented Bounding Box (OBB) Structs
// =============================================================================
final class YoloObbItem extends Struct {
  @Float()
  external double cx;

  @Float()
  external double cy;

  @Float()
  external double width;

  @Float()
  external double height;

  @Float()
  external double angleRad;

  @Float()
  external double angleDeg;

  @Array(8)
  external Array<Float> corners;

  @Float()
  external double confidence;

  @Int32()
  external int classId;
}

final class YoloObbResult extends Struct {
  external MultiTaskHeader header;

  @Int32()
  external int numObjects;

  @Array(maxObbObjects)
  external Array<YoloObbItem> objects;
}

// =============================================================================
// HARD GATE: Validate exact C-ABI struct sizes at runtime
// =============================================================================
void enforceLayoutGate() {
  final boxSize = sizeOf<YoloDetectionBox>();
  final frameResultSize = sizeOf<YoloFrameResult>();
  final headerSize = sizeOf<MultiTaskHeader>();
  final segItemSize = sizeOf<YoloSegmentationItem>();
  final segResultSize = sizeOf<YoloSegmentationResult>();
  final poseItemSize = sizeOf<YoloPoseItem>();
  final poseResultSize = sizeOf<YoloPoseResult>();
  final clsResultSize = sizeOf<YoloClassificationResult>();
  final obbItemSize = sizeOf<YoloObbItem>();
  final obbResultSize = sizeOf<YoloObbResult>();

  if (boxSize != 40) {
    throw StateError('LAYOUT GATE: sizeof(YoloDetectionBox) == $boxSize, expected 40');
  }
  if (frameResultSize != 4024) {
    throw StateError('LAYOUT GATE: sizeof(YoloFrameResult) == $frameResultSize, expected 4024');
  }
  if (headerSize != 28) {
    throw StateError('LAYOUT GATE: sizeof(MultiTaskHeader) == $headerSize, expected 28');
  }
  if (segItemSize != 292) {
    throw StateError('LAYOUT GATE: sizeof(YoloSegmentationItem) == $segItemSize, expected 292');
  }
  if (segResultSize != 8792) {
    throw StateError('LAYOUT GATE: sizeof(YoloSegmentationResult) == $segResultSize, expected 8792');
  }
  if (poseItemSize != 228) {
    throw StateError('LAYOUT GATE: sizeof(YoloPoseItem) == $poseItemSize, expected 228');
  }
  if (poseResultSize != 4592) {
    throw StateError('LAYOUT GATE: sizeof(YoloPoseResult) == $poseResultSize, expected 4592');
  }
  if (clsResultSize != 72) {
    throw StateError('LAYOUT GATE: sizeof(YoloClassificationResult) == $clsResultSize, expected 72');
  }
  if (obbItemSize != 64) {
    throw StateError('LAYOUT GATE: sizeof(YoloObbItem) == $obbItemSize, expected 64');
  }
  if (obbResultSize != 3232) {
    throw StateError('LAYOUT GATE: sizeof(YoloObbResult) == $obbResultSize, expected 3232');
  }
}
