import 'package:flutter/material.dart';
import '../../core/models/detection_item.dart';
import '../../core/models/engine_telemetry.dart';
import '../../core/theme/design_tokens.dart';

/// Minimal Tactical Top Telemetry HUD Pill (height <= 48px).
/// Zero BackdropFilter (D2 Performance Rule: simulated glass via 88% surface + hairline).
/// Monospace tabular figures for FPS and Latency to guarantee zero jitter.
class TelemetryTopBar extends StatelessWidget {
  final EngineTelemetry telemetry;
  final List<DetectionItem> detections;
  final bool isArabic;
  final VoidCallback onToggleBackend;

  const TelemetryTopBar({
    super.key,
    required this.telemetry,
    required this.detections,
    required this.isArabic,
    required this.onToggleBackend,
  });

  Color _getFpsColor(double fps) {
    if (fps >= 25.0) return AppTokens.ok; // Emerald Green >= 25
    if (fps >= 15.0) return AppTokens.warn; // Amber 15-24
    return AppTokens.danger; // Crimson Red < 15
  }

  @override
  Widget build(BuildContext context) {
    final confirmedCount = detections.where((d) => d.isConfirmed).length;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTokens.surfaceGlass,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTokens.hairline, width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 1. FPS Badge (Tabular Monospace)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _getFpsColor(telemetry.fps),
                  boxShadow: [
                    BoxShadow(
                      color: _getFpsColor(telemetry.fps).withValues(alpha: 0.6),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${telemetry.fps.toStringAsFixed(1)} FPS',
                style: AppTokens.telemetry12.copyWith(
                  color: _getFpsColor(telemetry.fps),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),

          // Divider
          Container(
            width: 1,
            height: 16,
            color: AppTokens.hairline,
          ),

          // 2. NCNN Inference Time
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.memory_rounded,
                size: 14,
                color: AppTokens.accent,
              ),
              const SizedBox(width: 4),
              Text(
                '${telemetry.inferenceTimeMs.toStringAsFixed(0)}ms',
                style: AppTokens.telemetry12.copyWith(
                  color: AppTokens.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          // Divider
          Container(
            width: 1,
            height: 16,
            color: AppTokens.hairline,
          ),

          // 3. Objects Count Badge
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.filter_center_focus_rounded,
                size: 14,
                color: AppTokens.text,
              ),
              const SizedBox(width: 4),
              Text(
                '$confirmedCount obj',
                style: AppTokens.telemetry12.copyWith(
                  color: AppTokens.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          // Divider
          Container(
            width: 1,
            height: 16,
            color: AppTokens.hairline,
          ),

          // 4. Backend Chip / Toggle Button (NEON 4T <-> Vulkan)
          GestureDetector(
            onTap: onToggleBackend,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: telemetry.isVulkan
                    ? const Color(0xFF8B5CF6).withValues(alpha: 0.25)
                    : AppTokens.accent.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: telemetry.isVulkan
                      ? const Color(0xFFA78BFA)
                      : AppTokens.accent,
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    telemetry.isVulkan
                        ? Icons.bolt_rounded
                        : Icons.layers_rounded,
                    size: 12,
                    color: telemetry.isVulkan
                        ? const Color(0xFFA78BFA)
                        : AppTokens.accent,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    telemetry.isVulkan ? 'Vulkan' : 'NEON 4T',
                    style: TextStyle(
                      fontFamily: AppTokens.fontCairo,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: telemetry.isVulkan
                          ? const Color(0xFFA78BFA)
                          : AppTokens.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
