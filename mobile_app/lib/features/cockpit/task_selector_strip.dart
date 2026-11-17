import 'package:flutter/material.dart';
import '../../core/ffi/native_structs.dart';
import '../../core/theme/design_tokens.dart';

/// Clean Tactical Task Selector Strip (height 38px).
/// Sits at top: 66px with zero overlap under the telemetry top bar.
/// Offers 1-tap switching between: Detection, Segmentation, Pose, Classification.
class TaskSelectorStrip extends StatelessWidget {
  final bool isArabic;
  final VisionTask activeTask;
  final bool isLoading;
  final ValueChanged<VisionTask> onTaskSelected;

  const TaskSelectorStrip({
    super.key,
    required this.isArabic,
    required this.activeTask,
    required this.isLoading,
    required this.onTaskSelected,
  });

  @override
  Widget build(BuildContext context) {
    const tasks = [
      VisionTask.detection,
      VisionTask.segmentation,
      VisionTask.pose,
      VisionTask.classification,
    ];

    return Container(
      height: 38,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: AppTokens.surfaceGlass,
        borderRadius: BorderRadius.circular(19),
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
        mainAxisSize: MainAxisSize.min,
        children: tasks.map((task) {
          final isSelected = activeTask == task;
          final label = isArabic ? task.labelAr : task.labelEn;

          IconData icon;
          switch (task) {
            case VisionTask.detection:
              icon = Icons.crop_free_rounded;
              break;
            case VisionTask.segmentation:
              icon = Icons.brush_rounded;
              break;
            case VisionTask.pose:
              icon = Icons.accessibility_new_rounded;
              break;
            case VisionTask.classification:
              icon = Icons.category_rounded;
              break;
            default:
              icon = Icons.auto_awesome_rounded;
          }

          return GestureDetector(
            onTap: isLoading ? null : () => onTaskSelected(task),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTokens.accent.withValues(alpha: 0.25)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: isSelected ? AppTokens.accent : Colors.transparent,
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: isSelected ? AppTokens.accent : AppTokens.muted,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: AppTokens.fontCairo,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? Colors.white : AppTokens.muted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
