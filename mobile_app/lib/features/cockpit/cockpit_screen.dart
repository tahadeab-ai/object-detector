import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/camera_permission_service.dart';
import '../../core/services/nihui_native_controller.dart';
import '../../core/theme/design_tokens.dart';

class CockpitScreen extends StatefulWidget {
  const CockpitScreen({super.key});

  @override
  State<CockpitScreen> createState() => _CockpitScreenState();
}

class _CockpitScreenState extends State<CockpitScreen> with WidgetsBindingObserver {
  bool _hasPermission = false;
  bool _isCheckingPermission = true;
  bool _isArabic = false;
  bool _isPaused = false;
  bool _isLoadingModel = false;

  NihuiTask _selectedTask = NihuiTask.coco;
  NihuiModel _selectedModel = NihuiModel.n320;
  NihuiBackend _selectedBackend = NihuiBackend.cpu;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAndRequestCameraPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_isPaused && _hasPermission) {
        NihuiNativeController.setPaused(false);
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      NihuiNativeController.setPaused(true);
    }
  }

  Future<void> _checkAndRequestCameraPermission() async {
    setState(() => _isCheckingPermission = true);
    final granted = await CameraPermissionService.checkPermission();
    if (granted) {
      setState(() {
        _hasPermission = true;
        _isCheckingPermission = false;
      });
    } else {
      final req = await CameraPermissionService.requestPermission();
      setState(() {
        _hasPermission = req;
        _isCheckingPermission = false;
      });
    }
  }

  Future<void> _onTaskChanged(NihuiTask task) async {
    if (_selectedTask == task || _isLoadingModel) return;
    setState(() {
      _selectedTask = task;
      _isLoadingModel = true;
    });
    await NihuiNativeController.reloadModel(
      taskId: _selectedTask.id,
      modelId: _selectedModel.id,
      cpuGpu: _selectedBackend.id,
    );
    if (mounted) {
      setState(() => _isLoadingModel = false);
    }
  }

  Future<void> _onModelChanged(NihuiModel model) async {
    if (_selectedModel == model || _isLoadingModel) return;
    setState(() {
      _selectedModel = model;
      _isLoadingModel = true;
    });
    await NihuiNativeController.reloadModel(
      taskId: _selectedTask.id,
      modelId: _selectedModel.id,
      cpuGpu: _selectedBackend.id,
    );
    if (mounted) {
      setState(() => _isLoadingModel = false);
    }
  }

  Future<void> _onBackendChanged(NihuiBackend backend) async {
    if (_selectedBackend == backend || _isLoadingModel) return;
    setState(() {
      _selectedBackend = backend;
      _isLoadingModel = true;
    });
    await NihuiNativeController.reloadModel(
      taskId: _selectedTask.id,
      modelId: _selectedModel.id,
      cpuGpu: _selectedBackend.id,
    );
    if (mounted) {
      setState(() => _isLoadingModel = false);
    }
  }

  Future<void> _onFlipCamera() async {
    await NihuiNativeController.switchCamera();
  }

  Future<void> _onTogglePause() async {
    final next = !_isPaused;
    setState(() => _isPaused = next);
    await NihuiNativeController.setPaused(next);
  }

  void _onToggleLanguage() {
    setState(() => _isArabic = !_isArabic);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Native NCNN Camera SurfaceView
          if (_hasPermission)
            const SizedBox.expand(
              child: AndroidView(
                viewType: 'nihui_camera_surface',
                creationParamsCodec: StandardMessageCodec(),
              ),
            )
          else if (_isCheckingPermission)
            _buildLoadingView()
          else
            _buildPermissionPromptView(),

          // 2. Glassmorphic Top Controls
          if (_hasPermission)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              right: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTopControlStrip(),
                  const SizedBox(height: 8),
                  _buildTaskSelectorStrip(),
                ],
              ),
            ),

          // 3. Floating Bottom Dock
          if (_hasPermission)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 12,
              left: 20,
              right: 20,
              child: _buildBottomDock(),
            ),

          // Loading overlay indicator when switching heavy models
          if (_isLoadingModel)
            Positioned(
              top: MediaQuery.of(context).padding.top + 120,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTokens.accent, width: 1.0),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTokens.accent),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isArabic ? 'جاري تحميل النموذج...' : 'Switching Model...',
                        style: const TextStyle(
                          fontFamily: AppTokens.fontCairo,
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopControlStrip() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTokens.surfaceGlass,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTokens.hairline, width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Model Selector Dropdown/Pill
          PopupMenuButton<NihuiModel>(
            tooltip: _isArabic ? 'اختيار النموذج' : 'Select Model',
            color: const Color(0xFF161922),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppTokens.hairline),
            ),
            initialValue: _selectedModel,
            onSelected: _onModelChanged,
            itemBuilder: (context) {
              return NihuiModel.values.map((model) {
                final isSelected = model == _selectedModel;
                return PopupMenuItem<NihuiModel>(
                  value: model,
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                        size: 16,
                        color: isSelected ? AppTokens.accent : AppTokens.muted,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        model.label,
                        style: TextStyle(
                          fontFamily: AppTokens.fontMono,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? AppTokens.accent : AppTokens.text,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTokens.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTokens.accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.memory_rounded, size: 15, color: AppTokens.accent),
                  const SizedBox(width: 6),
                  Text(
                    _selectedModel.label,
                    style: const TextStyle(
                      fontFamily: AppTokens.fontMono,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTokens.accent,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, size: 16, color: AppTokens.accent),
                ],
              ),
            ),
          ),

          // Backend Switcher Chips (CPU / GPU / Turnip)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: NihuiBackend.values.map((b) {
              final isSelected = b == _selectedBackend;
              return GestureDetector(
                onTap: () => _onBackendChanged(b),
                child: Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTokens.ok.withValues(alpha: 0.25) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? AppTokens.ok : AppTokens.hairline,
                      width: 1.0,
                    ),
                  ),
                  child: Text(
                    b.labelEn,
                    style: TextStyle(
                      fontFamily: AppTokens.fontMono,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? AppTokens.ok : AppTokens.muted,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskSelectorStrip() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: AppTokens.surfaceGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTokens.hairline, width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: NihuiTask.values.map((task) {
            final isSelected = task == _selectedTask;
            final label = _isArabic ? task.labelAr : task.labelEn;

            IconData icon;
            switch (task) {
              case NihuiTask.coco:
                icon = Icons.crop_free_rounded;
                break;
              case NihuiTask.seg:
                icon = Icons.brush_rounded;
                break;
              case NihuiTask.pose:
                icon = Icons.accessibility_new_rounded;
                break;
              case NihuiTask.cls:
                icon = Icons.category_rounded;
                break;
              case NihuiTask.obb:
                icon = Icons.rotate_90_degrees_ccw_rounded;
                break;
            }

            return GestureDetector(
              onTap: () => _onTaskChanged(task),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected ? AppTokens.accent.withValues(alpha: 0.25) : Colors.transparent,
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
                      icon,
                      size: 15,
                      color: isSelected ? AppTokens.accent : AppTokens.muted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: AppTokens.fontCairo,
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? AppTokens.accent : AppTokens.text,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBottomDock() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTokens.surfaceGlass,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppTokens.hairline, width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Language Toggle
          IconButton(
            tooltip: _isArabic ? 'English' : 'عربي',
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: AppTokens.hairline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _isArabic ? 'EN' : 'عربي',
                style: const TextStyle(
                  fontFamily: AppTokens.fontCairo,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTokens.accent,
                ),
              ),
            ),
            onPressed: _onToggleLanguage,
          ),

          // Flip Camera
          IconButton(
            tooltip: _isArabic ? 'تبديل الكاميرا' : 'Flip Camera',
            icon: const Icon(Icons.flip_camera_ios_outlined, color: AppTokens.text, size: 22),
            onPressed: _onFlipCamera,
          ),

          // Pause / Play Stream
          IconButton(
            tooltip: _isPaused
                ? (_isArabic ? 'استئناف' : 'Resume')
                : (_isArabic ? 'إيقاف مؤقت' : 'Pause'),
            icon: Icon(
              _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: _isPaused ? AppTokens.warn : AppTokens.accent,
              size: 26,
            ),
            onPressed: _onTogglePause,
          ),

          // Info
          IconButton(
            tooltip: _isArabic ? 'معلومات المحرك' : 'Engine Info',
            icon: const Icon(Icons.info_outline_rounded, color: AppTokens.text, size: 22),
            onPressed: _showInfoDialog,
          ),
        ],
      ),
    );
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161922),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTokens.hairline),
          ),
          title: Text(
            _isArabic ? 'معلومات محرك YOLO11 NCNN' : 'YOLO11 NCNN Engine Info',
            style: const TextStyle(
              fontFamily: AppTokens.fontCairo,
              color: AppTokens.accent,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(_isArabic ? 'المهمة الحالية:' : 'Active Task:', _selectedTask.labelEn),
              _infoRow(_isArabic ? 'النموذج النشط:' : 'Active Model:', _selectedModel.label),
              _infoRow(_isArabic ? 'المعالج:' : 'Backend:', _selectedBackend.labelEn),
              const Divider(color: AppTokens.hairline, height: 20),
              Text(
                _isArabic
                    ? 'محرك NCNN الأصلي (nihui) متصل مباشرة بـ SurfaceView عبر NdkCamera بدون أي نسخ وسيط.'
                    : 'Native nihui NCNN engine connected directly to SurfaceView via NdkCamera with zero buffer copy.',
                style: const TextStyle(
                  fontFamily: AppTokens.fontCairo,
                  color: AppTokens.muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                _isArabic ? 'إغلاق' : 'Close',
                style: const TextStyle(
                  fontFamily: AppTokens.fontCairo,
                  color: AppTokens.accent,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontFamily: AppTokens.fontCairo, color: AppTokens.muted, fontSize: 12)),
          Text(value, style: const TextStyle(fontFamily: AppTokens.fontMono, color: AppTokens.text, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildLoadingView() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTokens.accent),
            const SizedBox(height: 16),
            Text(
              _isArabic ? 'جاري التحقق من الصلاحيات...' : 'Checking camera permission...',
              style: const TextStyle(
                fontFamily: AppTokens.fontCairo,
                color: AppTokens.muted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionPromptView() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined, size: 64, color: AppTokens.warn),
            const SizedBox(height: 16),
            Text(
              _isArabic ? 'إذن الكاميرا مطلوب' : 'Camera Permission Required',
              style: const TextStyle(
                fontFamily: AppTokens.fontCairo,
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isArabic
                  ? 'يتطلب التطبيق الوصول إلى الكاميرا لتشغيل الكشف الحي والمباشر.'
                  : 'The app requires camera access for live real-time YOLO detection.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTokens.fontCairo,
                color: AppTokens.muted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _checkAndRequestCameraPermission,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text(
                _isArabic ? 'منح الإذن' : 'Grant Permission',
                style: const TextStyle(fontFamily: AppTokens.fontCairo, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTokens.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
