import 'dart:async';
import '../models/detection_item.dart';
import '../models/engine_telemetry.dart';

/// Event payload containing frame detection results and engine performance metrics
class FrameDetectionEvent {
  final int frameId;
  final List<DetectionItem> detections;
  final EngineTelemetry telemetry;

  const FrameDetectionEvent({
    required this.frameId,
    required this.detections,
    required this.telemetry,
  });
}

/// Centralized event bus for distributing detection updates across UI and services
class DetectionEventBus {
  static final DetectionEventBus _instance = DetectionEventBus._internal();
  factory DetectionEventBus() => _instance;
  DetectionEventBus._internal();

  final _controller = StreamController<FrameDetectionEvent>.broadcast();

  Stream<FrameDetectionEvent> get stream => _controller.stream;

  void publish(FrameDetectionEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  void dispose() {
    _controller.close();
  }
}
