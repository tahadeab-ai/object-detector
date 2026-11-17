import 'package:flutter/material.dart';
import '../../core/theme/design_tokens.dart';

/// Modal bottom sheet for configuring on-device edge detection thresholds & engine settings.
/// Pure 100% On-Device: zero network, zero backend sync.
class EngineSettingsSheet extends StatefulWidget {
  final double initialConfThreshold;
  final double initialIouThreshold;
  final ValueChanged<double> onConfChanged;
  final ValueChanged<double> onIouChanged;
  final bool isArabic;
  final int currentResolution;
  final ValueChanged<int> onResolutionChanged;
  final bool isTorchOn;
  final VoidCallback onToggleTorch;
  final VoidCallback onOpenDiagnostics;

  const EngineSettingsSheet({
    super.key,
    required this.initialConfThreshold,
    required this.initialIouThreshold,
    required this.onConfChanged,
    required this.onIouChanged,
    required this.isArabic,
    required this.currentResolution,
    required this.onResolutionChanged,
    required this.isTorchOn,
    required this.onToggleTorch,
    required this.onOpenDiagnostics,
  });

  @override
  State<EngineSettingsSheet> createState() => _EngineSettingsSheetState();
}

class _EngineSettingsSheetState extends State<EngineSettingsSheet> {
  late double _conf;
  late int _resolution;
  late bool _torch;

  @override
  void initState() {
    super.initState();
    _conf = widget.initialConfThreshold;
    _resolution = widget.currentResolution;
    _torch = widget.isTorchOn;
  }

  void _applyResolution(int res) {
    setState(() => _resolution = res);
    widget.onResolutionChanged(res);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                widget.isArabic ? 'إعدادات الكشف والمحرك' : 'Detection & Engine Settings',
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

          // 1. Input Size Selector (320 Turbo / 480 Fast / 640 HD)
          Text(
            widget.isArabic ? 'دقة الإدخال وحجم الصورة' : 'Input Resolution (Dynamic Stride-32)',
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
              _buildResChip(
                label: '320 Turbo',
                sublabel: '45-60 FPS',
                res: 320,
              ),
              const SizedBox(width: 8),
              _buildResChip(
                label: '480 Fast',
                sublabel: '35-45 FPS',
                res: 480,
              ),
              const SizedBox(width: 8),
              _buildResChip(
                label: '640 HD',
                sublabel: '20-30 FPS',
                res: 640,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Confidence Threshold Slider
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
            min: 0.15,
            max: 0.85,
            divisions: 14,
            activeColor: AppTokens.accent,
            inactiveColor: AppTokens.hairline,
            onChanged: (val) {
              setState(() => _conf = val);
              widget.onConfChanged(val);
            },
          ),
          const SizedBox(height: 12),

          // 3. Quick Actions: Torch & Diagnostics
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _torch = !_torch);
                    widget.onToggleTorch();
                  },
                  icon: Icon(
                    _torch ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    color: _torch ? AppTokens.warn : AppTokens.text,
                    size: 18,
                  ),
                  label: Text(
                    widget.isArabic ? (_torch ? 'إطفاء الكشاف' : 'تشغيل الكشاف') : (_torch ? 'Torch On' : 'Torch Off'),
                    style: TextStyle(
                      fontFamily: AppTokens.fontCairo,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _torch ? AppTokens.warn : AppTokens.text,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _torch ? AppTokens.warn : AppTokens.hairline),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onOpenDiagnostics();
                  },
                  icon: const Icon(Icons.analytics_outlined, size: 18, color: Colors.white),
                  label: Text(
                    widget.isArabic ? 'تقرير التشخيص' : 'Diagnostics',
                    style: const TextStyle(
                      fontFamily: AppTokens.fontCairo,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTokens.surfaceAlt,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildResChip({
    required String label,
    required String sublabel,
    required int res,
  }) {
    final isSelected = _resolution == res;
    return Expanded(
      child: GestureDetector(
        onTap: () => _applyResolution(res),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? AppTokens.accent.withValues(alpha: 0.2) : AppTokens.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
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
