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

  // Mode: Live Camera vs Media Studio
  bool _isMediaStudio = false;
  int _selectedSampleIndex = 0;
  String _activeMediaName = 'sample_street.jpg';

  final List<Map<String, String>> _samples = [
    {
      'name': 'Street',
      'nameAr': 'الشارع',
      'path': 'assets/samples/sample_street.jpg',
      'type': 'image',
    },
    {
      'name': 'Workspace',
      'nameAr': 'المكتب',
      'path': 'assets/samples/sample_workspace.jpg',
      'type': 'image',
    },
    {
      'name': 'Retail',
      'nameAr': 'المتجر',
      'path': 'assets/samples/sample_retail.jpg',
      'type': 'image',
    },
  ];

  NihuiTask _selectedTask = NihuiTask.coco;
  NihuiModel _selectedModel = NihuiModel.n320; // Default to n-320
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
      if (!_isPaused && (_hasPermission || _isMediaStudio)) {
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

  Future<void> _onSwitchMode(bool toMediaStudio) async {
    if (_isMediaStudio == toMediaStudio) return;
    setState(() {
      _isMediaStudio = toMediaStudio;
    });

    if (toMediaStudio) {
      await NihuiNativeController.setMediaMode(true);
      // Automatically load current sample photo into Media Studio
      await _loadSamplePhoto(_selectedSampleIndex);
    } else {
      await NihuiNativeController.setMediaMode(false);
    }
  }

  Future<void> _loadSamplePhoto(int index) async {
    _selectedSampleIndex = index;
    final sample = _samples[index];
    setState(() {
      _activeMediaName = _isArabic ? sample['nameAr']! : sample['name']!;
    });
    await NihuiNativeController.feedPhoto(
      path: sample['path']!,
      isAsset: true,
    );
  }

  Future<void> _pickGalleryMedia(String type) async {
    final res = await NihuiNativeController.pickMedia(type);
    if (res != null && res.containsKey('path')) {
      final path = res['path'] as String;
      final mediaType = res['type'] as String? ?? type;
      setState(() {
        _activeMediaName = path.split('/').last.split('\\').last;
      });

      if (mediaType == 'video') {
        await NihuiNativeController.startVideo(path: path, isAsset: false);
      } else {
        await NihuiNativeController.feedPhoto(path: path, isAsset: false);
      }
    }
  }

  Future<void> _onFlipCamera() async {
    if (!_isMediaStudio) {
      await NihuiNativeController.switchCamera();
    } else {
      _showMediaPickerMenu();
    }
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
      body: SafeArea(
        child: Column(
          children: [
            // ==========================================
            // ZONE 1: TOP CONTROL HEADER (Fixed Height)
            // ==========================================
            _buildTopControlHeader(),

            // ==========================================
            // ZONE 2: CENTER 3:4 VIEWPORT CARD (Expanded)
            // ==========================================
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: AspectRatio(
                    aspectRatio: 3.0 / 4.0,
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0C10),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppTokens.hairline.withValues(alpha: 0.7),
                          width: 1.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black87,
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Native SurfaceView platform view
                          if (_hasPermission || _isMediaStudio)
                            const AndroidView(
                              viewType: 'nihui_camera_surface',
                              creationParamsCodec: StandardMessageCodec(),
                            )
                          else if (_isCheckingPermission)
                            _buildLoadingView()
                          else
                            _buildPermissionPromptView(),

                          // Model Loading Indicator
                          if (_isLoadingModel)
                            _buildModelLoadingOverlay(),

                          // Active Media Mode Badge
                          if (_isMediaStudio)
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black87.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTokens.accent.withValues(alpha: 0.6)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.photo_library_rounded, size: 12, color: AppTokens.accent),
                                    const SizedBox(width: 4),
                                    Text(
                                      _activeMediaName,
                                      style: const TextStyle(
                                        fontFamily: AppTokens.fontMono,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppTokens.accent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ==========================================
            // ZONE 3: BOTTOM STUDIO BAR (Fixed Height)
            // ==========================================
            _buildBottomStudioBar(),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // ZONE 1: TOP CONTROL HEADER
  // -------------------------------------------------------------
  Widget _buildTopControlHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Model Selector (n-320 default) + Backend Selector
          Row(
            children: [
              // Model Selector Dropdown/Pill
              Expanded(
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTokens.surfaceGlass,
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(color: AppTokens.hairline),
                  ),
                  child: PopupMenuButton<NihuiModel>(
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.memory_rounded, size: 16, color: AppTokens.accent),
                          const SizedBox(width: 6),
                          Text(
                            _selectedModel.label,
                            style: const TextStyle(
                              fontFamily: AppTokens.fontMono,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTokens.accent,
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.arrow_drop_down_rounded, size: 20, color: AppTokens.muted),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Backend Selector Segment
              Container(
                height: 38,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppTokens.surfaceGlass,
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: AppTokens.hairline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: NihuiBackend.values.map((b) {
                    final isSelected = b == _selectedBackend;
                    return GestureDetector(
                      onTap: () => _onBackendChanged(b),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTokens.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          b.labelEn,
                          style: TextStyle(
                            fontFamily: AppTokens.fontMono,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.black : AppTokens.muted,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Row 2: All 5 Task Chips (0: Detection, 1: Segmentation, 2: Pose, 3: Classification, 4: OBB)
          Container(
            height: 34,
            decoration: BoxDecoration(
              color: AppTokens.surfaceGlass,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: AppTokens.hairline),
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
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTokens.accent.withValues(alpha: 0.25) : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? AppTokens.accent : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            icon,
                            size: 13,
                            color: isSelected ? AppTokens.accent : AppTokens.muted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${task.id}: $label',
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
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // ZONE 3: BOTTOM STUDIO BAR
  // -------------------------------------------------------------
  Widget _buildBottomStudioBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sub-row 1: Mode Switcher Tabs
          Container(
            height: 36,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: AppTokens.surfaceGlass,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTokens.hairline),
            ),
            child: Row(
              children: [
                // Live Camera Tab
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _onSwitchMode(false),
                    child: Container(
                      decoration: BoxDecoration(
                        color: !_isMediaStudio ? AppTokens.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.videocam_rounded,
                            size: 16,
                            color: !_isMediaStudio ? Colors.black : AppTokens.muted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isArabic ? 'الكاميرا الحية' : 'Live Camera',
                            style: TextStyle(
                              fontFamily: AppTokens.fontCairo,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: !_isMediaStudio ? Colors.black : AppTokens.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Media Studio Tab
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _onSwitchMode(true),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _isMediaStudio ? AppTokens.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.auto_awesome_motion_rounded,
                            size: 16,
                            color: _isMediaStudio ? Colors.black : AppTokens.muted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isArabic ? 'مختبر الصور والفيديو' : 'Media Studio',
                            style: TextStyle(
                              fontFamily: AppTokens.fontCairo,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _isMediaStudio ? Colors.black : AppTokens.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Sub-row 1b (Media Studio Sample & Source Strip)
          if (_isMediaStudio) ...[
            const SizedBox(height: 5),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    ...List.generate(_samples.length, (i) {
                      final sample = _samples[i];
                      final isSel = i == _selectedSampleIndex;
                      final name = _isArabic ? sample['nameAr']! : sample['name']!;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _loadSamplePhoto(i),
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isSel ? AppTokens.accent.withValues(alpha: 0.3) : const Color(0xFF161922),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSel ? AppTokens.accent : AppTokens.hairline,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.image_outlined, size: 12, color: isSel ? AppTokens.accent : AppTokens.muted),
                              const SizedBox(width: 4),
                              Text(
                                name,
                                style: TextStyle(
                                  fontFamily: AppTokens.fontCairo,
                                  fontSize: 11,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                  color: isSel ? AppTokens.accent : AppTokens.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _pickGalleryMedia('image'),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161922),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTokens.hairline),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_photo_alternate_outlined, size: 12, color: AppTokens.accent),
                            const SizedBox(width: 4),
                            Text(
                              _isArabic ? 'صورة من المعرض' : 'Gallery Photo',
                              style: const TextStyle(
                                fontFamily: AppTokens.fontCairo,
                                fontSize: 11,
                                color: AppTokens.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _pickGalleryMedia('video'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161922),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTokens.hairline),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.video_library_outlined, size: 12, color: AppTokens.accent),
                            const SizedBox(width: 4),
                            Text(
                              _isArabic ? 'فيديو من المعرض' : 'Gallery Video',
                              style: const TextStyle(
                                fontFamily: AppTokens.fontCairo,
                                fontSize: 11,
                                color: AppTokens.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 5),

          // Sub-row 2: Context Controls (Language, Flip/Pick, Pause/Resume, Info)
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppTokens.surfaceGlass,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppTokens.hairline),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Language Toggle
                IconButton(
                  tooltip: _isArabic ? 'English' : 'عربي',
                  icon: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTokens.hairline),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _isArabic ? 'EN' : 'عربي',
                      style: const TextStyle(
                        fontFamily: AppTokens.fontCairo,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTokens.accent,
                      ),
                    ),
                  ),
                  onPressed: _onToggleLanguage,
                ),

                // Flip Camera (Live) OR Pick Media (Studio)
                IconButton(
                  tooltip: _isMediaStudio
                      ? (_isArabic ? 'اختيار وسائط' : 'Pick Media')
                      : (_isArabic ? 'تبديل الكاميرا' : 'Flip Camera'),
                  icon: Icon(
                    _isMediaStudio ? Icons.add_photo_alternate_rounded : Icons.flip_camera_ios_outlined,
                    color: AppTokens.text,
                    size: 20,
                  ),
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
                    size: 24,
                  ),
                  onPressed: _onTogglePause,
                ),

                // Info Dialog
                IconButton(
                  tooltip: _isArabic ? 'معلومات واختبارات' : 'Info & Benchmarks',
                  icon: const Icon(Icons.info_outline_rounded, color: AppTokens.text, size: 20),
                  onPressed: _showInfoDialog,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMediaPickerMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161922),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: AppTokens.accent),
                title: Text(
                  _isArabic ? 'اختيار صورة من المعرض' : 'Pick Photo from Gallery',
                  style: const TextStyle(fontFamily: AppTokens.fontCairo, color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickGalleryMedia('image');
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library_rounded, color: AppTokens.accent),
                title: Text(
                  _isArabic ? 'اختيار فيديو من المعرض' : 'Pick Video from Gallery',
                  style: const TextStyle(fontFamily: AppTokens.fontCairo, color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickGalleryMedia('video');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModelLoadingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
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
              _infoRow(_isArabic ? 'الوضع النشط:' : 'Active Mode:', _isMediaStudio ? 'Media Studio Lab' : 'Live Camera'),
              _infoRow(_isArabic ? 'المهمة الحالية:' : 'Active Task:', '${_selectedTask.id}: ${_selectedTask.labelEn}'),
              _infoRow(_isArabic ? 'النموذج النشط:' : 'Active Model:', _selectedModel.label),
              _infoRow(_isArabic ? 'المعالج:' : 'Backend:', _selectedBackend.labelEn),
              const Divider(color: AppTokens.hairline, height: 20),
              Text(
                _isArabic
                    ? 'محرك NCNN الأصلي (nihui) متصل مباشرة بـ SurfaceView عبر NdkCamera بنسبة 3:4 مع الحفاظ على الأبعاد الحقيقية بدون أي تشوه أو تقاطع.'
                    : 'Native nihui NCNN engine connected directly to 3:4 SurfaceView with zero stretch, zero status-bar overlap, and direct photo/video lab.',
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
