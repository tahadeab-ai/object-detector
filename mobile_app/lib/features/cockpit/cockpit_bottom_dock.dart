import 'package:flutter/material.dart';
import '../../core/theme/design_tokens.dart';

/// Minimal Tactical Bottom Dock (height 48px).
/// Floating glassmorphic dock offering thumb-first one-handed access to essential actions:
/// Language (AR/EN), Sample Benchmark, Torch, Freeze, Settings, Diagnostics, Camera Flip.
class CockpitBottomDock extends StatelessWidget {
  final bool isArabic;
  final bool isTorchOn;
  final bool isFrozen;
  final VoidCallback onToggleLanguage;
  final VoidCallback onOpenSampleMode;
  final VoidCallback onToggleTorch;
  final VoidCallback onToggleFreeze;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenDiagnostics;
  final VoidCallback onSwitchCamera;

  const CockpitBottomDock({
    super.key,
    required this.isArabic,
    required this.isTorchOn,
    required this.isFrozen,
    required this.onToggleLanguage,
    required this.onOpenSampleMode,
    required this.onToggleTorch,
    required this.onToggleFreeze,
    required this.onOpenSettings,
    required this.onOpenDiagnostics,
    required this.onSwitchCamera,
  });

  Widget _buildDockButton({
    required IconData icon,
    required VoidCallback onTap,
    String? label,
    Color? color,
    bool isActive = false,
  }) {
    final activeColor = color ?? AppTokens.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          constraints: const BoxConstraints(
            minWidth: AppTokens.minTouchTarget,
            minHeight: AppTokens.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          child: label != null
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive ? activeColor.withValues(alpha: 0.2) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive ? activeColor : AppTokens.hairline,
                      width: 1.0,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: AppTokens.fontCairo,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isActive ? activeColor : AppTokens.text,
                    ),
                  ),
                )
              : Icon(
                  icon,
                  size: 20,
                  color: isActive ? activeColor : AppTokens.text,
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppTokens.surfaceGlass,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTokens.hairline, width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Language Toggle (AR / EN)
          _buildDockButton(
            icon: Icons.language_rounded,
            label: isArabic ? 'EN' : 'عربي',
            onTap: onToggleLanguage,
          ),

          // 2. Sample Mode Benchmark
          _buildDockButton(
            icon: Icons.photo_library_outlined,
            onTap: onOpenSampleMode,
            color: AppTokens.catFood,
          ),

          // 3. Torch Toggle
          _buildDockButton(
            icon: isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
            onTap: onToggleTorch,
            isActive: isTorchOn,
            color: AppTokens.warn,
          ),

          // 4. Freeze Frame Toggle
          _buildDockButton(
            icon: isFrozen ? Icons.pause_circle_filled_rounded : Icons.pause_circle_outline_rounded,
            onTap: onToggleFreeze,
            isActive: isFrozen,
            color: AppTokens.accent,
          ),

          // 5. Camera Flip
          _buildDockButton(
            icon: Icons.flip_camera_android_rounded,
            onTap: onSwitchCamera,
          ),

          // 6. Settings Bottom Sheet
          _buildDockButton(
            icon: Icons.tune_rounded,
            onTap: onOpenSettings,
          ),

          // 7. Diagnostics JSON Export
          _buildDockButton(
            icon: Icons.analytics_outlined,
            onTap: onOpenDiagnostics,
            color: AppTokens.ok,
          ),
        ],
      ),
    );
  }
}
