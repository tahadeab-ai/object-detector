/// Live telemetry metrics from the native detection and tracking loop
class EngineTelemetry {
  final double fps;
  final double inferenceTimeMs;
  final double trackerTimeMs;
  final double totalLatencyMs;
  final int activeBackend; // 0=CPU, 1=Vulkan
  final int activeTracks;
  final int confirmedTracks;

  const EngineTelemetry({
    this.fps = 0.0,
    this.inferenceTimeMs = 0.0,
    this.trackerTimeMs = 0.0,
    this.totalLatencyMs = 0.0,
    this.activeBackend = 0,
    this.activeTracks = 0,
    this.confirmedTracks = 0,
  });

  bool get isVulkan => activeBackend == 1;
  String get backendLabel => isVulkan ? 'Vulkan Compute' : 'ARM NEON 4T';

  EngineTelemetry copyWith({
    double? fps,
    double? inferenceTimeMs,
    double? trackerTimeMs,
    double? totalLatencyMs,
    int? activeBackend,
    int? activeTracks,
    int? confirmedTracks,
  }) {
    return EngineTelemetry(
      fps: fps ?? this.fps,
      inferenceTimeMs: inferenceTimeMs ?? this.inferenceTimeMs,
      trackerTimeMs: trackerTimeMs ?? this.trackerTimeMs,
      totalLatencyMs: totalLatencyMs ?? this.totalLatencyMs,
      activeBackend: activeBackend ?? this.activeBackend,
      activeTracks: activeTracks ?? this.activeTracks,
      confirmedTracks: confirmedTracks ?? this.confirmedTracks,
    );
  }
}
