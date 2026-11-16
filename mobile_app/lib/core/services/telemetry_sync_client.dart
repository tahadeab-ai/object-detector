import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/detection_item.dart';
import '../models/engine_telemetry.dart';

/// Non-blocking telemetry sync client to forward detection data to backend Go/Redis service
class TelemetrySyncClient {
  final String backendUrl;
  bool isEnabled;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(milliseconds: 1500);

  TelemetrySyncClient({
    this.backendUrl = 'http://127.0.0.1:8080/api/telemetry',
    this.isEnabled = false,
  });

  Future<void> sendFrameTelemetry({
    required int frameId,
    required List<DetectionItem> detections,
    required EngineTelemetry telemetry,
  }) async {
    if (!isEnabled) return;

    final payload = {
      'frame_id': frameId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'fps': telemetry.fps,
      'inference_ms': telemetry.inferenceTimeMs,
      'tracker_ms': telemetry.trackerTimeMs,
      'total_latency_ms': telemetry.totalLatencyMs,
      'backend': telemetry.backendLabel,
      'tracks_count': detections.length,
      'detections': detections
          .map((d) => {
                'track_id': d.trackId,
                'class_id': d.classId,
                'confidence': d.confidence,
                'state': d.trackState.name,
                'zone': d.spatialZone.name,
                'proximity': d.proximityTier.name,
                'bbox': [d.x1, d.y1, d.x2, d.y2],
              })
          .toList(),
    };

    try {
      final uri = Uri.parse(backendUrl);
      final request = await _client
          .postUrl(uri)
          .timeout(const Duration(milliseconds: 1500));
      request.headers.contentType = ContentType.json;
      request.write(json.encode(payload));
      final response =
          await request.close().timeout(const Duration(milliseconds: 1500));
      await response.drain<void>();
    } catch (_) {
      // Non-blocking fire-and-forget: ignore network drops or absent backend
    }
  }

  void close() {
    _client.close(force: true);
  }
}
