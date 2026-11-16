import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/models/engine_telemetry.dart';

/// Glassmorphic top telemetry HUD bar displaying FPS, latencies, and backend controls
class TelemetryTopBar extends StatelessWidget {
  final EngineTelemetry telemetry;
  final bool isArabic;
  final VoidCallback onToggleLanguage;
  final VoidCallback onToggleBackend;
  final VoidCallback onOpenSampleMode;
  final VoidCallback onOpenSettings;

  const TelemetryTopBar({
    super.key,
    required this.telemetry,
    required this.isArabic,
    required this.onToggleLanguage,
    required this.onToggleBackend,
    required this.onOpenSampleMode,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Real-time FPS indicator
                  _buildMetricPill(
                    icon: Icons.speed_rounded,
                    label: '${telemetry.fps.toStringAsFixed(1)} FPS',
                    color: telemetry.fps >= 20.0
                        ? const Color(0xFF34C759)
                        : (telemetry.fps >= 10.0 ? const Color(0xFFFF9500) : const Color(0xFFFF3B30)),
                  ),

                  // NCNN Inference Latency
                  _buildMetricPill(
                    icon: Icons.memory_rounded,
                    label: '${telemetry.inferenceTimeMs.toStringAsFixed(1)} ms',
                    sublabel: 'NCNN',
                    color: Colors.cyanAccent,
                  ),

                  // Rust Tracker Latency
                  _buildMetricPill(
                    icon: Icons.alt_route_rounded,
                    label: '${telemetry.trackerTimeMs.toStringAsFixed(1)} ms',
                    sublabel: 'Track',
                    color: Colors.amberAccent,
                  ),

                  // Active Backend Badge / Button
                  GestureDetector(
                    onTap: onToggleBackend,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: telemetry.isVulkan
                            ? Colors.purpleAccent.withValues(alpha: 0.3)
                            : Colors.blueAccent.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: telemetry.isVulkan ? Colors.purpleAccent : Colors.blueAccent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            telemetry.isVulkan ? Icons.bolt_rounded : Icons.terminal_rounded,
                            size: 14,
                            color: telemetry.isVulkan ? Colors.purpleAccent : Colors.blueAccent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            telemetry.isVulkan ? 'Vulkan' : 'CPU',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: telemetry.isVulkan ? Colors.purpleAccent : Colors.blueAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Secondary controls row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Active & confirmed tracks count
                  Text(
                    isArabic
                        ? 'المسارات: ${telemetry.confirmedTracks} مؤكد / ${telemetry.activeTracks} إجمالي'
                        : 'Tracks: ${telemetry.confirmedTracks} conf / ${telemetry.activeTracks} total',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),

                  // Quick Action Buttons
                  Row(
                    children: [
                      // Language Switcher (AR / EN)
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
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
                        onPressed: onToggleLanguage,
                      ),
                      const SizedBox(width: 8),
                      // Sample Benchmark Mode Button
                      IconButton(
                        icon: const Icon(Icons.photo_library_outlined, size: 18, color: Colors.white),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: onOpenSampleMode,
                      ),
                      const SizedBox(width: 8),
                      // Settings Sheet Button
                      IconButton(
                        icon: const Icon(Icons.tune_rounded, size: 18, color: Colors.white),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: onOpenSettings,
                      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              if (sublabel != null)
                Text(
                  sublabel,
                  style: const TextStyle(color: Colors.white54, fontSize: 9),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
