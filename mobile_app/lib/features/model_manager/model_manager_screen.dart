import 'package:flutter/material.dart';
import '../../core/models/model_profile.dart';
import '../../core/services/model_manager.dart';
import '../../core/theme/design_tokens.dart';

class ModelManagerScreen extends StatefulWidget {
  final bool isArabic;

  const ModelManagerScreen({super.key, required this.isArabic});

  @override
  State<ModelManagerScreen> createState() => _ModelManagerScreenState();
}

class _ModelManagerScreenState extends State<ModelManagerScreen> {
  final ModelManager _modelManager = ModelManager();

  @override
  void initState() {
    super.initState();
    _modelManager.addListener(_onManagerUpdated);
  }

  @override
  void dispose() {
    _modelManager.removeListener(_onManagerUpdated);
    super.dispose();
  }

  void _onManagerUpdated() {
    if (mounted) setState(() {});
  }

  Future<void> _handleSwitchModel(ModelProfile profile) async {
    if (profile.id == _modelManager.activeProfile.id) return;

    final success = await _modelManager.switchModel(profile);
    if (!mounted) return;

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTokens.danger,
          content: Text(
            widget.isArabic
                ? 'فشل تبديل النموذج: ${_modelManager.state.errorMessage ?? "خطأ غير معروف"}'
                : 'Failed to switch model: ${_modelManager.state.errorMessage ?? "Unknown error"}',
            style: const TextStyle(fontFamily: AppTokens.fontCairo),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTokens.ok,
          content: Text(
            widget.isArabic
                ? 'تم تحميل النموذج بنجاح: ${profile.nameAr}'
                : 'Loaded model successfully: ${profile.nameEn}',
            style: const TextStyle(fontFamily: AppTokens.fontCairo),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isArabic;
    final state = _modelManager.state;
    final activeProfile = state.activeProfile;

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppTokens.bg,
        appBar: AppBar(
          backgroundColor: AppTokens.surface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTokens.text),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            isAr ? 'مدير النماذج والمهام' : 'Model & Task Manager',
            style: const TextStyle(
              fontFamily: AppTokens.fontCairo,
              color: AppTokens.text,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            if (state.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTokens.accent,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1. Runtime Backend Selector
            _buildBackendCard(state, isAr),
            const SizedBox(height: 16),

            // 2. Active Model Resolution Selector
            _buildResolutionCard(activeProfile, state, isAr),
            const SizedBox(height: 20),

            // 3. Catalog Section Header
            Text(
              isAr ? 'كتالوج النماذج المتاحة' : 'Available Models Catalog',
              style: const TextStyle(
                fontFamily: AppTokens.fontCairo,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTokens.text,
              ),
            ),
            const SizedBox(height: 12),

            // 4. Model Cards
            for (final profile in ModelProfile.catalog)
              _buildModelCard(
                profile: profile,
                isActive: profile.id == activeProfile.id,
                isLoading: state.isLoading && profile.id == activeProfile.id,
                isAr: isAr,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackendCard(ModelManagerState state, bool isAr) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.memory_rounded, size: 18, color: AppTokens.accent),
              const SizedBox(width: 8),
              Text(
                isAr ? 'محرك التنفيذ العتادي' : 'Hardware Execution Backend',
                style: const TextStyle(
                  fontFamily: AppTokens.fontCairo,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTokens.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildBackendChip(
                label: isAr ? 'معالج CPU (4T NEON)' : 'CPU NEON (4 Threads)',
                backendId: 0,
                selectedId: state.activeBackend,
                isRecommended: true,
              ),
              _buildBackendChip(
                label: 'Vulkan GPU (Adreno 640)',
                backendId: 1,
                selectedId: state.activeBackend,
              ),
              _buildBackendChip(
                label: 'Mesa Turnip Driver',
                backendId: 2,
                selectedId: state.activeBackend,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBackendChip({
    required String label,
    required int backendId,
    required int selectedId,
    bool isRecommended = false,
  }) {
    final isSelected = backendId == selectedId;
    return ChoiceChip(
      selected: isSelected,
      onSelected: (val) {
        if (val) _modelManager.setBackend(backendId);
      },
      backgroundColor: AppTokens.surfaceGlass,
      selectedColor: AppTokens.accent.withValues(alpha: 0.25),
      side: BorderSide(
        color: isSelected ? AppTokens.accent : AppTokens.hairline,
      ),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTokens.fontCairo,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? AppTokens.accent : AppTokens.text,
            ),
          ),
          if (isRecommended) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppTokens.ok.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '★',
                style: TextStyle(fontSize: 9, color: AppTokens.ok),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResolutionCard(ModelProfile profile, ModelManagerState state, bool isAr) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.aspect_ratio_rounded, size: 18, color: AppTokens.catIndoor),
              const SizedBox(width: 8),
              Text(
                isAr ? 'دقة الإدخال للنموذج النشط' : 'Active Model Input Resolution',
                style: const TextStyle(
                  fontFamily: AppTokens.fontCairo,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTokens.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: profile.supportedResolutions.map((res) {
              final isSelected = res == state.activeResolution;
              return ChoiceChip(
                selected: isSelected,
                onSelected: (val) {
                  if (val) _modelManager.setResolution(res);
                },
                backgroundColor: AppTokens.surfaceGlass,
                selectedColor: AppTokens.catIndoor.withValues(alpha: 0.25),
                side: BorderSide(
                  color: isSelected ? AppTokens.catIndoor : AppTokens.hairline,
                ),
                label: Text(
                  '${res}x$res',
                  style: TextStyle(
                    fontFamily: AppTokens.fontCairo,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? AppTokens.catIndoor : AppTokens.text,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildModelCard({
    required ModelProfile profile,
    required bool isActive,
    required bool isLoading,
    required bool isAr,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF1B2433) : AppTokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? AppTokens.accent : AppTokens.hairline,
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _handleSwitchModel(profile),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppTokens.accent.withValues(alpha: 0.2)
                        : AppTokens.surfaceGlass,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isActive ? AppTokens.accent : AppTokens.hairline,
                    ),
                  ),
                  child: Icon(
                    _getTaskIcon(profile.task),
                    size: 22,
                    color: isActive ? AppTokens.accent : AppTokens.muted,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              isAr ? profile.nameAr : profile.nameEn,
                              style: TextStyle(
                                fontFamily: AppTokens.fontCairo,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isActive ? Colors.white : AppTokens.text,
                              ),
                            ),
                          ),
                          if (isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTokens.ok.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTokens.ok),
                              ),
                              child: Text(
                                isAr ? 'نشط' : 'ACTIVE',
                                style: const TextStyle(
                                  fontFamily: AppTokens.fontCairo,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppTokens.ok,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isAr ? profile.descriptionAr : profile.descriptionEn,
                        style: const TextStyle(
                          fontFamily: AppTokens.fontCairo,
                          fontSize: 11,
                          color: AppTokens.muted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _buildTag(isAr ? profile.task.labelAr : profile.task.labelEn),
                          const SizedBox(width: 6),
                          _buildTag('${profile.classesCount} ${isAr ? "صنف" : "classes"}'),
                          const SizedBox(width: 6),
                          _buildTag('${profile.defaultResolution}p'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTokens.surfaceGlass,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTokens.hairline),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: AppTokens.fontCairo,
          fontSize: 9,
          color: AppTokens.muted,
        ),
      ),
    );
  }

  IconData _getTaskIcon(dynamic task) {
    switch (task.toString()) {
      case 'VisionTask.detection':
        return Icons.crop_free_rounded;
      case 'VisionTask.segmentation':
        return Icons.draw_rounded;
      case 'VisionTask.pose':
        return Icons.accessibility_new_rounded;
      case 'VisionTask.classification':
        return Icons.category_rounded;
      case 'VisionTask.obb':
        return Icons.transform_rounded;
      default:
        return Icons.visibility_rounded;
    }
  }
}
