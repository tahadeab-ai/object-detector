import 'package:flutter/material.dart';
import '../../core/ffi/native_structs.dart';
import '../../core/models/model_profile.dart';
import '../../core/services/model_manager.dart';
import '../../core/theme/design_tokens.dart';

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
      VisionTask.obb,
    ];

    return Container(
      height: 38,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: AppTokens.surfaceGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTokens.hairline),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        itemCount: tasks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final task = tasks[index];
          final isSelected = task == activeTask;

          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isLoading ? null : () => onTaskSelected(task),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTokens.accent.withValues(alpha: 0.25)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? AppTokens.accent : Colors.transparent,
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getIcon(task),
                      size: 14,
                      color: isSelected ? AppTokens.accent : AppTokens.muted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isArabic ? task.labelAr : task.labelEn,
                      style: TextStyle(
                        fontFamily: AppTokens.fontCairo,
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? Colors.white : AppTokens.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _getIcon(VisionTask task) {
    switch (task) {
      case VisionTask.detection:
        return Icons.crop_free_rounded;
      case VisionTask.segmentation:
        return Icons.draw_rounded;
      case VisionTask.pose:
        return Icons.accessibility_new_rounded;
      case VisionTask.classification:
        return Icons.category_rounded;
      case VisionTask.obb:
        return Icons.transform_rounded;
    }
  }
}
