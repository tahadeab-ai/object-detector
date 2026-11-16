import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/l10n/coco_labels_repository.dart';
import '../../core/models/detection_item.dart';
import '../../core/models/engine_telemetry.dart';

/// Glassmorphic top telemetry HUD bar with grouped object summary and latency breakdown
class TelemetryTopBar extends StatelessWidget {
  final EngineTelemetry telemetry;
  final List<DetectionItem> detections;
  final bool isArabic;
  final VoidCallback onToggleLanguage;
  final VoidCallback onToggleBackend;
  final VoidCallback onOpenSampleMode;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenDiagnostics;
  final VoidCallback? onSwitchCamera;
  final CocoLabelsRepository labelsRepo;

  TelemetryTopBar({
    super.key,
    required this.telemetry,
    required this.detections,
    required this.isArabic,
    required this.onToggleLanguage,
    required this.onToggleBackend,
    required this.onOpenSampleMode,
    required this.onOpenSettings,
    this.onOpenDiagnostics,
    this.onSwitchCamera,
    CocoLabelsRepository? repo,
  }) : labelsRepo = repo ?? CocoLabelsRepository();

  Color _getFpsColor(double fps) {
    if (fps >= 25.0) return const Color(0xFF34C759); // Green >= 25
    if (fps >= 15.0) return const Color(0xFFFF9500); // Amber 15-24
    return const Color(0xFFFF3B30); // Red < 15
  }

  Map<int, int> _getGroupedCounts() {
    final map = <int, int>{};
    for (final item in detections) {
      if (item.isConfirmed) {
        map[item.classId] = (map[item.classId] ?? 0) + 1;
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _getGroupedCounts();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Primary Metrics Row: FPS + Latencies (Pre / NCNN / Track) + Backend
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // FPS Badge (color-coded)
                  _buildMetricPill(
                    icon: Icons.speed_rounded,
                    label: '${telemetry.fps.toStringAsFixed(1)} FPS',
                    color: _getFpsColor(telemetry.fps),
                  ),

                  // Preprocess Latency
                  _buildMetricPill(
                    icon: Icons.aspect_ratio_rounded,
                    label:
                        '${telemetry.preProcessTimeMs.toStringAsFixed(1)} ms',
                    sublabel: 'Pre',
                    color: Colors.blueAccent,
                  ),

                  // NCNN Inference Latency
                  _buildMetricPill(
                    icon: Icons.memory_rounded,
                    label: '${telemetry.inferenceTimeMs.toStringAsFixed(1)} ms',
                    sublabel: 'NCNN',
                    color: Colors.cyanAccent,
                  ),

                  // NMS + Track Latency
                  _buildMetricPill(
                    icon: Icons.alt_route_rounded,
                    label: '${telemetry.trackerTimeMs.toStringAsFixed(1)} ms',
                    sublabel: 'Track',
                    color: Colors.amberAccent,
                  ),

                  // CPU / Vulkan Backend Switch Pill
                  GestureDetector(
                    onTap: onToggleBackend,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: telemetry.isVulkan
                            ? Colors.purpleAccent.withValues(alpha: 0.3)
                            : Colors.blueAccent.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: telemetry.isVulkan
                              ? Colors.purpleAccent
                              : Colors.blueAccent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            telemetry.isVulkan
                                ? Icons.bolt_rounded
                                : Icons.terminal_rounded,
                            size: 14,
                            color: telemetry.isVulkan
                                ? Colors.purpleAccent
                                : Colors.blueAccent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            telemetry.isVulkan ? 'Vulkan' : 'NEON 4T',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: telemetry.isVulkan
                                  ? Colors.purpleAccent
                                  : Colors.blueAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // 2. Real-time Grouped Object Summary Strip
              if (grouped.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: grouped.entries.map((entry) {
                        final label =
                            labelsRepo.getLabel(entry.key, isArabic: isArabic);
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '$label: ${entry.value}',
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

              // 3. Secondary Navigation & Action Row
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isArabic
                          ? 'المسارات: ${telemetry.confirmedTracks} مؤكد / ${telemetry.activeTracks} نشط'
                          : 'Tracks: ${telemetry.confirmedTracks} conf / ${telemetry.activeTracks} act',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Language Toggle
                      IconButton(
                        icon: Text(
                          isArabic ? 'EN' : 'عربي',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 26, minHeight: 28),
                        onPressed: onToggleLanguage,
                      ),
                      const SizedBox(width: 4),
                      // Sample Benchmark Mode
                      IconButton(
                        icon: const Icon(Icons.photo_library_outlined,
                            size: 18, color: Colors.white),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 26, minHeight: 28),
                        onPressed: onOpenSampleMode,
                      ),
                      const SizedBox(width: 4),
                      // Settings Sheet
                      IconButton(
                        icon: const Icon(Icons.tune_rounded,
                            size: 18, color: Colors.white),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 26, minHeight: 28),
                        onPressed: onOpenSettings,
                      ),
                      if (onOpenDiagnostics != null) ...[
                        const SizedBox(width: 4),
                        // Diagnostics Screen
                        IconButton(
                          icon: const Icon(Icons.analytics_outlined,
                              size: 18, color: Colors.cyanAccent),
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 26, minHeight: 28),
                          onPressed: onOpenDiagnostics,
                        ),
                      ],
                      if (onSwitchCamera != null) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.flip_camera_android_rounded,
                              size: 18, color: Colors.white),
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 26, minHeight: 28),
                          onPressed: onSwitchCamera,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricPill({
    required IconData icon,
    required String label,
    String? sublabel,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
              if (sublabel != null)
                Text(
                  sublabel,
                  style: const TextStyle(color: Colors.white54, fontSize: 8),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
