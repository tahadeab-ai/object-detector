import '../ffi/native_structs.dart';

/// Clean Dart representation of a tracked detection item
class DetectionItem {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double confidence;
  final int classId;
  final int trackId;
  final TrackState trackState;
  final SpatialZone spatialZone;
  final ProximityTier proximityTier;

  const DetectionItem({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.confidence,
    required this.classId,
    required this.trackId,
    required this.trackState,
    required this.spatialZone,
    required this.proximityTier,
  });

  factory DetectionItem.fromNative(YoloDetectionBox box) {
    return DetectionItem(
      x1: box.x1.clamp(0.0, 1.0),
      y1: box.y1.clamp(0.0, 1.0),
      x2: box.x2.clamp(0.0, 1.0),
      y2: box.y2.clamp(0.0, 1.0),
      confidence: box.confidence,
      classId: box.classId,
      trackId: box.trackId,
      trackState: TrackState.fromInt(box.trackState),
      spatialZone: SpatialZone.fromInt(box.spatialZone),
      proximityTier: ProximityTier.fromInt(box.proximityTier),
    );
  }

  double get width => (x2 - x1).clamp(0.0, 1.0);
  double get height => (y2 - y1).clamp(0.0, 1.0);
  double get cx => (x1 + x2) / 2.0;
  double get cy => (y1 + y2) / 2.0;
  double get area => width * height;
  bool get isConfirmed => trackState == TrackState.confirmed;
}
