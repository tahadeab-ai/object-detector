import 'package:flutter/material.dart';
import '../../core/theme/design_tokens.dart';

/// Modal bottom sheet for configuring on-device edge detection thresholds.
/// Pure 100% On-Device: zero network, zero backend sync.
class EngineSettingsSheet extends StatefulWidget {
  final double initialConfThreshold;
  final double initialIouThreshold;
  final ValueChanged<double> onConfChanged;
  final ValueChanged<double> onIouChanged;
  final bool isArabic;

  const EngineSettingsSheet({
    super.key,
    required this.initialConfThreshold,
    required this.initialIouThreshold,
    required this.onConfChanged,
    required this.onIouChanged,
    required this.isArabic,
  });

  @override
  State<EngineSettingsSheet> createState() => _EngineSettingsSheetState();
}

class _EngineSettingsSheetState extends State<EngineSettingsSheet> {
  late double _conf;
  late double _iou;

  @override
  void initState() {
    super.initState();
    _conf = widget.initialConfThreshold;
    _iou = widget.initialIouThreshold;
  }

  void _applyPreset(double conf, double iou) {
    setState(() {
      _conf = conf;
      _iou = iou;
    });
    widget.onConfChanged(conf);
    widget.onIouChanged(iou);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppTokens.hairline, width: 1.0),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.isArabic ? 'إعدادات الكشف والمحرك' : 'Engine & Detection Settings',
                style: const TextStyle(
                  fontFamily: AppTokens.fontCairo,
                  color: AppTokens.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppTokens.muted),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Presets Row (Balanced, Sensitive, Precise)
          Text(
            widget.isArabic ? 'الإعدادات المسبقة' : 'Presets',
            style: const TextStyle(
              fontFamily: AppTokens.fontCairo,
              color: AppTokens.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildPresetChip(
                label: widget.isArabic ? 'متوازن' : 'Balanced',
                sublabel: '45% / 45%',
                isSelected: (_conf - 0.45).abs() < 0.02 && (_iou - 0.45).abs() < 0.02,
                onTap: () => _applyPreset(0.45, 0.45),
              ),
              const SizedBox(width: 8),
              _buildPresetChip(
                label: widget.isArabic ? 'حساس' : 'Sensitive',
                sublabel: '35% / 40%',
                isSelected: (_conf - 0.35).abs() < 0.02 && (_iou - 0.40).abs() < 0.02,
                onTap: () => _applyPreset(0.35, 0.40),
              ),
              const SizedBox(width: 8),
              _buildPresetChip(
                label: widget.isArabic ? 'دقيق' : 'Precise',
                sublabel: '60% / 50%',
                isSelected: (_conf - 0.60).abs() < 0.02 && (_iou - 0.50).abs() < 0.02,
                onTap: () => _applyPreset(0.60, 0.50),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Confidence threshold slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.isArabic ? 'حد الثقة (Confidence)' : 'Confidence Threshold',
                style: const TextStyle(
                  fontFamily: AppTokens.fontCairo,
                  color: AppTokens.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${(_conf * 100).toStringAsFixed(0)}%',
                style: AppTokens.telemetry14.copyWith(color: AppTokens.accent),
              ),
            ],
          ),
          Slider(
            value: _conf,
            min: 0.10,
            max: 0.90,
            divisions: 16,
            activeColor: AppTokens.accent,
            inactiveColor: AppTokens.hairline,
            onChanged: (val) {
              setState(() => _conf = val);
              widget.onConfChanged(val);
            },
          ),
          const SizedBox(height: 8),

          // NMS IoU threshold slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.isArabic ? 'حد تداخل NMS IoU' : 'NMS IoU Threshold',
                style: const TextStyle(
                  fontFamily: AppTokens.fontCairo,
                  color: AppTokens.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${(_iou * 100).toStringAsFixed(0)}%',
                style: AppTokens.telemetry14.copyWith(color: AppTokens.warn),
              ),
            ],
          ),
          Slider(
            value: _iou,
            min: 0.20,
            max: 0.80,
            divisions: 12,
            activeColor: AppTokens.warn,
            inactiveColor: AppTokens.hairline,
            onChanged: (val) {
              setState(() => _iou = val);
              widget.onIouChanged(val);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPresetChip({
    required String label,
    required String sublabel,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? AppTokens.accent.withValues(alpha: 0.2) : AppTokens.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppTokens.accent : AppTokens.hairline,
              width: 1.0,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppTokens.fontCairo,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? AppTokens.accent : AppTokens.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sublabel,
                style: AppTokens.telemetry12.copyWith(
                  fontSize: 10,
                  color: isSelected ? AppTokens.accent : AppTokens.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
