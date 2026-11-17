import 'package:flutter/material.dart';
import '../../core/theme/design_tokens.dart';

/// Clean Tactical Bottom Dock (height 52px).
/// 5 well-spaced buttons:
/// 1. Language toggle (عربي / EN)
/// 2. Sample Benchmark Mode (Icons.photo_library_outlined)
/// 3. Freeze / Pause (Icons.pause_rounded / Icons.play_arrow_rounded)
/// 4. Flip Camera (Icons.flip_camera_ios_outlined)
/// 5. Settings & Diagnostics Sheet (Icons.tune_rounded)
class CockpitBottomDock extends StatelessWidget {
  final bool isArabic;
  final bool isFrozen;
  final VoidCallback onToggleLanguage;
  final VoidCallback onOpenSampleMode;
  final VoidCallback onToggleFreeze;
  final VoidCallback onSwitchCamera;
  final VoidCallback onOpenSettings;

  const CockpitBottomDock({
    super.key,
    required this.isArabic,
    required this.isFrozen,
    required this.onToggleLanguage,
    required this.onOpenSampleMode,
    required this.onToggleFreeze,
    required this.onSwitchCamera,
    required this.onOpenSettings,
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
        borderRadius: BorderRadius.circular(24),
        child: Container(
          constraints: const BoxConstraints(
            minWidth: 52,
            minHeight: 48,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          alignment: Alignment.center,
          child: label != null
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive ? activeColor.withValues(alpha: 0.2) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isActive ? activeColor : AppTokens.hairline,
                      width: 1.0,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: AppTokens.fontCairo,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isActive ? activeColor : AppTokens.text,
                    ),
                  ),
                )
              : Icon(
                  icon,
                  size: 22,
                  color: isActive ? activeColor : AppTokens.text,
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTokens.surfaceGlass,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppTokens.hairline, width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 1. Language Toggle (AR / EN)
          _buildDockButton(
            icon: Icons.language_rounded,
            label: isArabic ? 'EN' : 'عربي',
            onTap: onToggleLanguage,
          ),
          const SizedBox(width: 4),

          // 2. Sample Mode Benchmark
          _buildDockButton(
            icon: Icons.photo_library_outlined,
            onTap: onOpenSampleMode,
            color: AppTokens.catFood,
          ),
          const SizedBox(width: 4),

          // 3. Freeze Frame Toggle
          _buildDockButton(
            icon: isFrozen ? Icons.play_arrow_rounded : Icons.pause_rounded,
            onTap: onToggleFreeze,
            isActive: isFrozen,
            color: isFrozen ? AppTokens.warn : AppTokens.accent,
          ),
          const SizedBox(width: 4),

          // 4. Camera Flip
          _buildDockButton(
            icon: Icons.flip_camera_ios_outlined,
            onTap: onSwitchCamera,
          ),
          const SizedBox(width: 4),

          // 5. Settings Bottom Sheet
          _buildDockButton(
            icon: Icons.tune_rounded,
            onTap: onOpenSettings,
            color: AppTokens.accent,
          ),
        ],
      ),
    );
  }
}
