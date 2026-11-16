import 'package:flutter/material.dart';

/// Modal bottom sheet for configuring detection thresholds and microservice sync
class EngineSettingsSheet extends StatefulWidget {
  final double initialConfThreshold;
  final double initialIouThreshold;
  final bool initialTelemetrySync;
  final ValueChanged<double> onConfChanged;
  final ValueChanged<double> onIouChanged;
  final ValueChanged<bool> onTelemetrySyncChanged;
  final bool isArabic;

  const EngineSettingsSheet({
    super.key,
    required this.initialConfThreshold,
    required this.initialIouThreshold,
    required this.initialTelemetrySync,
    required this.onConfChanged,
    required this.onIouChanged,
    required this.onTelemetrySyncChanged,
    required this.isArabic,
  });

  @override
  State<EngineSettingsSheet> createState() => _EngineSettingsSheetState();
}

class _EngineSettingsSheetState extends State<EngineSettingsSheet> {
  late double _conf;
  late double _iou;
  late bool _telemetrySync;

  @override
  void initState() {
    super.initState();
    _conf = widget.initialConfThreshold;
    _iou = widget.initialIouThreshold;
    _telemetrySync = widget.initialTelemetrySync;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E24),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.isArabic ? 'إعدادات المحرك' : 'Engine Settings',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Confidence threshold slider
          Text(
            widget.isArabic
                ? 'حد الثقة (Confidence): ${(_conf * 100).toStringAsFixed(0)}%'
                : 'Confidence Threshold: ${(_conf * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          Slider(
            value: _conf,
            min: 0.10,
            max: 0.90,
            divisions: 16,
            activeColor: Colors.cyanAccent,
            onChanged: (val) {
              setState(() => _conf = val);
              widget.onConfChanged(val);
            },
          ),
          const SizedBox(height: 8),

          // NMS IoU threshold slider
          Text(
            widget.isArabic
                ? 'حد تقاطع NMS IoU: ${(_iou * 100).toStringAsFixed(0)}%'
                : 'NMS IoU Threshold: ${(_iou * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          Slider(
            value: _iou,
            min: 0.20,
            max: 0.80,
            divisions: 12,
            activeColor: Colors.amberAccent,
            onChanged: (val) {
              setState(() => _iou = val);
              widget.onIouChanged(val);
            },
          ),
          const SizedBox(height: 12),

          // Go/Redis Telemetry Sync Switch
          SwitchListTile(
            title: Text(
              widget.isArabic ? 'مزامنة قياسات Go/Redis' : 'Go/Redis Telemetry Sync',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            subtitle: Text(
              widget.isArabic
                  ? 'إرسال بيانات التتبع عبر الشبكة (منفذ 8080)'
                  : 'Stream frame telemetry to microservice (:8080)',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            value: _telemetrySync,
            activeThumbColor: Colors.greenAccent,
            onChanged: (val) {
              setState(() => _telemetrySync = val);
              widget.onTelemetrySyncChanged(val);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
