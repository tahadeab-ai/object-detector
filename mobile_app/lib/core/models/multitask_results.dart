import 'dart:ui';
import '../ffi/native_structs.dart';
import 'detection_item.dart';

class SegmentationItem {
  final double x1, y1, x2, y2;
  final double confidence;
  final int classId;
  final int maskW, maskH;
  final List<Offset> contourPoints;

  const SegmentationItem({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.confidence,
    required this.classId,
    required this.maskW,
    required this.maskH,
    required this.contourPoints,
  });
}

class KeyPointData {
  final double x;
  final double y;
  final double confidence;

  const KeyPointData({
    required this.x,
    required this.y,
    required this.confidence,
  });
}

class PoseItem {
  final double x1, y1, x2, y2;
  final double confidence;
  final int classId;
  final List<KeyPointData> keypoints;

  const PoseItem({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.confidence,
    required this.classId,
    required this.keypoints,
  });
}

class ClassificationItem {
  final int classId;
  final double confidence;

  const ClassificationItem({
    required this.classId,
    required this.confidence,
  });
}

class ObbItem {
  final double cx, cy;
  final double width, height;
  final double angleRad, angleDeg;
  final List<Offset> corners; // 4 corners
  final double confidence;
  final int classId;

  const ObbItem({
    required this.cx,
    required this.cy,
    required this.width,
    required this.height,
    required this.angleRad,
    required this.angleDeg,
    required this.corners,
    required this.confidence,
    required this.classId,
  });
}

class MultiTaskFrameResult {
  final VisionTask task;
  final int frameId;
  final double prepTimeMs;
  final double inferenceTimeMs;
  final double postTimeMs;
  final int activeBackend;
  final int statusCode;

  final List<DetectionItem> detections;
  final List<SegmentationItem> segmentations;
  final List<PoseItem> poses;
  final List<ClassificationItem> classifications;
  final List<ObbItem> obbs;

  const MultiTaskFrameResult({
    required this.task,
    required this.frameId,
    required this.prepTimeMs,
    required this.inferenceTimeMs,
    required this.postTimeMs,
    required this.activeBackend,
    required this.statusCode,
    this.detections = const [],
    this.segmentations = const [],
    this.poses = const [],
    this.classifications = const [],
    this.obbs = const [],
  });
}
