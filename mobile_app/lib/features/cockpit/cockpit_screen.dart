import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../core/ffi/native_structs.dart';
import '../../core/l10n/coco_labels_repository.dart';
import '../../core/l10n/multitask_labels_repository.dart';
import '../../core/models/detection_item.dart';
import '../../core/models/engine_telemetry.dart';
import '../../core/models/model_profile.dart';
import '../../core/models/multitask_results.dart';
import '../../core/services/camera_permission_service.dart';
import '../../core/services/detection_event_bus.dart';
import '../../core/services/diagnostics_service.dart';
import '../../core/services/inference_worker.dart';
import '../../core/services/model_manager.dart';
import '../../core/theme/design_tokens.dart';
import '../dashboard/performance_dashboard_screen.dart';
import '../diagnostics/diagnostics_screen.dart';
import '../model_manager/model_manager_screen.dart';
import '../sample_mode/sample_benchmark_view.dart';
import '../settings/engine_settings_sheet.dart';
import 'bbox_hud_painter.dart';
import 'cockpit_bottom_dock.dart';
import 'multitask_hud_painter.dart';
import 'task_selector_strip.dart';
import 'telemetry_top_bar.dart';

class CockpitScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CockpitScreen({super.key, required this.cameras});

  @override
  State<CockpitScreen> createState() => _CockpitScreenState();
}

class _CockpitScreenState extends State<CockpitScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = [];
  bool _isCameraInitialized = false;
  bool _isCameraPermissionDenied = false;
  bool _isLoadingCamera = false;
  bool _isProcessingFrame = false;
  bool _isArabic = false;
  bool _isTorchOn = false;
  bool _isFrozen = false;

  double _confThreshold = 0.45;
  double _iouThreshold = 0.45;
  int _activeBackend = 0; // 0=CPU (NEON 4T), 1=Vulkan

  List<DetectionItem> _currentDetections = [];
  List<SegmentationItem> _currentSegmentations = [];
  List<PoseItem> _currentPoses = [];
  List<ClassificationItem> _currentClassifications = [];
  List<ObbItem> _currentObbs = [];

  EngineTelemetry _currentTelemetry = const EngineTelemetry();

  StreamSubscription<FrameDetectionEvent>? _eventSub;
  final CocoLabelsRepository _labelsRepo = CocoLabelsRepository();
  final MultiTaskLabelsRepository _multiTaskRepo = MultiTaskLabelsRepository();
  final DiagnosticsService _diagService = DiagnosticsService();
  final InferenceWorker _inferenceWorker = InferenceWorker();
  final ModelManager _modelManager = ModelManager();

  int _frameCounter = 0;
  DateTime _lastFpsUpdate = DateTime.now();

  // Watchdog: alert if no frames processed within 5 seconds of camera running
  Timer? _watchdogTimer;
  bool _watchdogFired = false;
  String? _cameraErrorMessage;
  int _selectedCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _labelsRepo.load();
    _multiTaskRepo.load();
    _modelManager.addListener(_onModelManagerChanged);
    _availableCameras = List.from(widget.cameras);

    _eventSub = DetectionEventBus().stream.listen((event) {
      if (!mounted) return;
      setState(() {
        _currentDetections = event.detections;
        _currentTelemetry = event.telemetry;
      });
    });

    _inferenceWorker.start().catchError((e) {
      _diagService.recordError('InferenceWorker start failed: $e');
    });

    _requestPermissionAndInitCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopWatchdog();
      _cameraController?.stopImageStream();
    } else if (state == AppLifecycleState.resumed) {
      if (!_cameraController!.value.isStreamingImages) {
        _startCameraStream();
      }
    }
  }

  Future<void> _requestPermissionAndInitCamera() async {
    setState(() {
      _isLoadingCamera = true;
      _cameraErrorMessage = null;
    });

    final hasPermission = await CameraPermissionService.checkPermission();
    if (hasPermission) {
      await _initializeCamera();
    } else {
      final granted = await CameraPermissionService.requestPermission();
      if (granted) {
        await _initializeCamera();
      } else {
        if (!mounted) return;
        setState(() {
          _isCameraPermissionDenied = true;
          _isLoadingCamera = false;
        });
      }
    }
  }

  Future<void> _initializeCamera() async {
    try {
      if (_availableCameras.isEmpty) {
        _availableCameras = await availableCameras();
      }

      if (_availableCameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isCameraInitialized = false;
          _isCameraPermissionDenied = false;
          _isLoadingCamera = false;
          _cameraErrorMessage = 'No camera hardware found on this device.';
        });
        return;
      }

      int initialIdx = _availableCameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (initialIdx < 0) initialIdx = 0;
      _selectedCameraIndex = initialIdx;
      final camera = _availableCameras[_selectedCameraIndex];

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();
      if (!mounted) return;

      _cameraController = controller;
      await _startCameraStream();

      setState(() {
        _isCameraInitialized = true;
        _isCameraPermissionDenied = false;
        _isLoadingCamera = false;
        _cameraErrorMessage = null;
      });
    } on CameraException catch (e) {
      _diagService.recordError('CameraException: ${e.code} - ${e.description}');
      if (e.code == 'CameraAccessDenied' ||
          e.code == 'CameraAccessDeniedWithoutPrompt') {
        setState(() {
          _isCameraPermissionDenied = true;
          _isLoadingCamera = false;
        });
      } else {
        setState(() {
          _cameraErrorMessage = 'Camera Error: ${e.description ?? e.code}';
          _isLoadingCamera = false;
        });
      }
    } catch (e) {
      _diagService.recordError('Camera init error: $e');
      setState(() {
        _cameraErrorMessage = 'Failed to initialize camera: $e';
        _isLoadingCamera = false;
      });
    }
  }

  Future<void> _startCameraStream() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (_cameraController!.value.isStreamingImages) return;

    await _cameraController!.startImageStream(_handleCameraFrame);
    _resetWatchdog();
  }

  void _resetWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogFired = false;
    _watchdogTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      if (_isCameraInitialized && (_cameraController?.value.isStreamingImages ?? false)) {
        setState(() {
          _watchdogFired = true;
        });
      }
    });
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  /// Lock-free single-slot latest-frame gate:
  /// Never blocks the camera stream, drops frame instantly if isolate is busy or UI is frozen.
  void _handleCameraFrame(CameraImage image) async {
    _diagService.recordFrameReceived();

    if (_isProcessingFrame || _inferenceWorker.isBusy || _isFrozen) {
      _diagService.recordFrameDropped();
      return;
    }

    _isProcessingFrame = true;
    _frameCounter++;
    final now = DateTime.now();
    final elapsedMs = now.difference(_lastFpsUpdate).inMilliseconds;
    if (elapsedMs >= 500) {
      final currentFps = (_frameCounter * 1000.0) / elapsedMs;
      _frameCounter = 0;
      _lastFpsUpdate = now;
      if (mounted) {
        setState(() {
          _currentTelemetry = _currentTelemetry.copyWith(fps: currentFps);
        });
      }
    }

    try {
      final isNv21 = image.planes.length == 2 ||
          (image.planes.length > 1 &&
              (image.planes[1].bytesPerPixel ?? 1) == 2);

      final yPlane = image.planes[0];
      final uPlane = image.planes.length > 1 ? image.planes[1] : yPlane;
      final vPlane = image.planes.length > 2 ? image.planes[2] : uPlane;

      final uvPixelStride = isNv21 ? 2 : (uPlane.bytesPerPixel ?? 1);
      final sensorOrientation =
          _cameraController?.description.sensorOrientation ?? 90;

      final activeTask = _modelManager.activeTask;

      // Delegate multi-task inference to dedicated background isolate
      final result = await _inferenceWorker.processMultiTaskFrame(
        yBytes: yPlane.bytes,
        uBytes: uPlane.bytes,
        vBytes: vPlane.bytes,
        width: image.width,
        height: image.height,
        yRowStride: yPlane.bytesPerRow,
        uvRowStride: uPlane.bytesPerRow,
        uvPixelStride: uvPixelStride,
        sensorOrientation: sensorOrientation,
        backend: _activeBackend,
        task: activeTask,
      );

      if (result != null && result.statusCode == 0) {
        _resetWatchdog();
        _diagService.recordFrameProcessed();

        final detections = <DetectionItem>[];
        for (final item in result.detections) {
          if (item.confidence >= _confThreshold) {
            detections.add(item);
          }
        }

        if (mounted) {
          setState(() {
            _currentDetections = detections;
            _currentSegmentations = result.segmentations;
            _currentPoses = result.poses;
            _currentClassifications = result.classifications;
            _currentObbs = result.obbs;
          });
        }

        DetectionEventBus().publish(
          FrameDetectionEvent(
            frameId: result.frameId,
            detections: detections,
            telemetry: _currentTelemetry.copyWith(
              inferenceTimeMs: result.inferenceTimeMs,
              trackerTimeMs: result.postTimeMs,
              totalLatencyMs:
                  result.prepTimeMs + result.inferenceTimeMs + result.postTimeMs,
              activeBackend: result.activeBackend,
              activeTracks: detections.length,
              confirmedTracks:
                  detections.where((d) => d.isConfirmed).length,
            ),
          ),
        );
      }
    } catch (e) {
      _diagService.recordError('Frame error: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _toggleLanguage() {
    setState(() => _isArabic = !_isArabic);
  }

  void _toggleBackend() {
    final nextBackend = _activeBackend == 1 ? 0 : 1;
    setState(() {
      _activeBackend = nextBackend;
      _currentTelemetry =
          _currentTelemetry.copyWith(activeBackend: nextBackend);
    });
    _diagService.setBackend(nextBackend);
  }

  Future<void> _toggleTorch() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    try {
      final nextTorch = !_isTorchOn;
      await _cameraController!.setFlashMode(nextTorch ? FlashMode.torch : FlashMode.off);
      setState(() => _isTorchOn = nextTorch);
    } catch (_) {}
  }

  void _toggleFreeze() {
    setState(() => _isFrozen = !_isFrozen);
  }

  Future<void> _switchCamera() async {
    if (_availableCameras.length < 2) return;
    try {
      _selectedCameraIndex =
          (_selectedCameraIndex + 1) % _availableCameras.length;
      final newCamera = _availableCameras[_selectedCameraIndex];
      _stopWatchdog();
      if (_cameraController?.value.isStreamingImages ?? false) {
        await _cameraController?.stopImageStream();
      }
      await _cameraController?.dispose();
      final controller = CameraController(
        newCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) return;
      _cameraController = controller;
      _isTorchOn = false;
      await _startCameraStream();
      setState(() {});
    } catch (e) {
      debugPrint('Error switching camera: $e');
    }
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EngineSettingsSheet(
        initialConfThreshold: _confThreshold,
        initialIouThreshold: _iouThreshold,
        isArabic: _isArabic,
        onConfChanged: (val) => setState(() => _confThreshold = val),
        onIouChanged: (val) => setState(() => _iouThreshold = val),
      ),
    );
  }

  void _openDiagnostics() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiagnosticsScreen(isArabic: _isArabic),
      ),
    );
  }

  void _openSampleMode() async {
    _stopWatchdog();
    if (_cameraController != null && _cameraController!.value.isStreamingImages) {
      await _cameraController?.stopImageStream();
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SampleBenchmarkView(isArabic: _isArabic),
      ),
    );

    // Resume camera stream on return
    if (_cameraController != null &&
        _cameraController!.value.isInitialized &&
        !_cameraController!.value.isStreamingImages) {
      await _startCameraStream();
    }
  }

  void _onModelManagerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _onTaskChanged(VisionTask task) async {
    if (_modelManager.activeTask == task) return;

    final targetProfile = ModelProfile.catalog.firstWhere(
      (p) => p.task == task,
      orElse: () => ModelProfile.catalog.first,
    );

    final success = await _modelManager.switchModel(targetProfile);
    if (mounted && !success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTokens.danger,
          content: Text(
            _isArabic ? 'فشل تبديل المهمة' : 'Failed to switch task',
            style: const TextStyle(fontFamily: AppTokens.fontCairo),
          ),
        ),
      );
    }
  }

  void _openModelManager() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ModelManagerScreen(isArabic: _isArabic),
      ),
    );
  }

  void _openPerformanceDashboard() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PerformanceDashboardScreen(isArabic: _isArabic),
      ),
    );
  }

  @override
  void dispose() {
    _stopWatchdog();
    WidgetsBinding.instance.removeObserver(this);
    _eventSub?.cancel();
    _modelManager.removeListener(_onModelManagerChanged);
    _cameraController?.dispose();
    _inferenceWorker.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppTokens.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Full-Bleed Camera Preview & 1:1 Co-located HUD CustomPaint (Zero Black Bars)
          if (_isLoadingCamera)
            _buildLoadingState()
          else if (_isCameraInitialized && _cameraController != null)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  // Swap width & height for upright portrait display
                  width: _cameraController!.value.previewSize?.height ?? size.width,
                  height: _cameraController!.value.previewSize?.width ?? size.height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_cameraController!),
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: MultiTaskHudPainter(
                            task: _modelManager.activeTask,
                            isArabic: _isArabic,
                            showTrails: true,
                            detections: _currentDetections,
                            segmentations: _currentSegmentations,
                            poses: _currentPoses,
                            classifications: _currentClassifications,
                            obbs: _currentObbs,
                            multiTaskRepo: _multiTaskRepo,
                            cocoLabelsRepo: _labelsRepo,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_isCameraPermissionDenied)
            _buildPermissionDeniedState()
          else if (_cameraErrorMessage != null)
            _buildErrorState(_cameraErrorMessage!)
          else
            _buildFallbackState(),

          // 2. Subtle Watermark when Scene is Empty
          if (_isCameraInitialized &&
              !_isLoadingCamera &&
              _currentDetections.isEmpty &&
              !_watchdogFired)
            Positioned(
              bottom: 80,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTokens.surfaceGlass,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTokens.hairline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.radar_rounded,
                          size: 14, color: AppTokens.accent),
                      const SizedBox(width: 6),
                      Text(
                        _isArabic
                            ? 'بانتظار رصد أهداف في المشهد'
                            : 'Scanning scene for objects...',
                        style: const TextStyle(
                          fontFamily: AppTokens.fontCairo,
                          color: AppTokens.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 3. Watchdog Error Banner (if stalled >= 5s)
          if (_watchdogFired)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B1214),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTokens.danger),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 8),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppTokens.danger, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isArabic
                                ? 'تنبيه: توقف تدفق الإطارات'
                                : 'Watchdog: Frame Stream Stalled',
                            style: const TextStyle(
                              fontFamily: AppTokens.fontCairo,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _isArabic
                                ? 'لم تتم معالجة أي إطار خلال 5 ثوانٍ.'
                                : 'No frames processed within 5 seconds.',
                            style: const TextStyle(
                              fontFamily: AppTokens.fontCairo,
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _openDiagnostics,
                      child: Text(
                        _isArabic ? 'التشخيص' : 'Diagnostics',
                        style: const TextStyle(
                          fontFamily: AppTokens.fontCairo,
                          color: AppTokens.accent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 4. Minimal Glassmorphic Top Pill HUD (height <= 48px)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Center(
              child: TelemetryTopBar(
                telemetry: _currentTelemetry,
                detections: _currentDetections,
                isArabic: _isArabic,
                onToggleBackend: _toggleBackend,
              ),
            ),
          ),

          // 5. Tactical Task Navigation Strip (Detection, Seg, Pose, Cls, OBB)
          Positioned(
            top: MediaQuery.of(context).padding.top + 62,
            left: 0,
            right: 0,
            child: Center(
              child: TaskSelectorStrip(
                isArabic: _isArabic,
                activeTask: _modelManager.activeTask,
                isLoading: _modelManager.isLoading,
                onTaskSelected: _onTaskChanged,
              ),
            ),
          ),

          // 6. Minimal Tactical Floating Bottom Dock
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 12,
            left: 16,
            right: 16,
            child: Center(
              child: CockpitBottomDock(
                isArabic: _isArabic,
                isTorchOn: _isTorchOn,
                isFrozen: _isFrozen,
                onToggleLanguage: _toggleLanguage,
                onOpenSampleMode: _openSampleMode,
                onToggleTorch: _toggleTorch,
                onToggleFreeze: _toggleFreeze,
                onOpenSettings: _openSettings,
                onOpenDiagnostics: _openDiagnostics,
                onSwitchCamera: _switchCamera,
                onOpenModelManager: _openModelManager,
                onOpenPerformanceDashboard: _openPerformanceDashboard,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      color: AppTokens.bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTokens.accent),
            const SizedBox(height: 16),
            Text(
              _isArabic
                  ? 'جاري تهيئة الكاميرا ومحرك NCNN...'
                  : 'Initializing Camera & NCNN Engine...',
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

  Widget _buildPermissionDeniedState() {
    return Container(
      color: AppTokens.surface,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined,
                size: 56, color: AppTokens.warn),
            const SizedBox(height: 16),
            Text(
              _isArabic
                  ? 'إذن استخدام الكاميرا مطلوب'
                  : 'Camera Permission Required',
              style: const TextStyle(
                fontFamily: AppTokens.fontCairo,
                color: AppTokens.text,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isArabic
                  ? 'يحتاج التطبيق لإذن الكاميرا لتشغيل الكشف المباشر عن الأهداف.'
                  : 'Camera access is required for live real-time detection.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTokens.fontCairo,
                color: AppTokens.muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    final granted =
                        await CameraPermissionService.requestPermission();
                    if (granted) {
                      await _initializeCamera();
                    } else {
                      await CameraPermissionService.openAppSettings();
                    }
                  },
                  icon: const Icon(Icons.security_rounded, size: 16),
                  label: Text(
                    _isArabic ? 'منح الإذن' : 'Grant Permission',
                    style: const TextStyle(fontFamily: AppTokens.fontCairo),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTokens.accent,
                    foregroundColor: Colors.black,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _openSampleMode,
                  icon: const Icon(Icons.photo_library_outlined, size: 16),
                  label: Text(
                    _isArabic ? 'وضع الصور' : 'Sample Mode',
                    style: const TextStyle(fontFamily: AppTokens.fontCairo),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTokens.accent,
                    side: const BorderSide(color: AppTokens.accent),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Container(
      color: AppTokens.bg,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 56, color: AppTokens.danger),
            const SizedBox(height: 16),
            Text(
              _isArabic ? 'خطأ في تشغيل الكاميرا' : 'Camera Hardware Error',
              style: const TextStyle(
                fontFamily: AppTokens.fontCairo,
                color: AppTokens.text,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTokens.fontCairo,
                color: AppTokens.muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _requestPermissionAndInitCamera,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(
                    _isArabic ? 'إعادة المحاولة' : 'Retry',
                    style: const TextStyle(fontFamily: AppTokens.fontCairo),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTokens.accent,
                    foregroundColor: Colors.black,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _openDiagnostics,
                  icon: const Icon(Icons.analytics_outlined, size: 16),
                  label: Text(
                    _isArabic ? 'التشخيص' : 'Diagnostics',
                    style: const TextStyle(fontFamily: AppTokens.fontCairo),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTokens.accent,
                    side: const BorderSide(color: AppTokens.accent),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackState() {
    return Container(
      color: AppTokens.bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.camera_alt_outlined,
              size: 56,
              color: AppTokens.muted.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              _isArabic
                  ? 'بانتظار مستشعر الكاميرا أو وضع الصور المرجعية'
                  : 'Awaiting Camera Stream or Sample Benchmark',
              style: const TextStyle(
                fontFamily: AppTokens.fontCairo,
                color: AppTokens.muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _openSampleMode,
              icon: const Icon(Icons.photo_library_outlined, size: 16),
              label: Text(
                _isArabic ? 'فتح وضع الصور المرجعية' : 'Launch Sample Benchmark',
                style: const TextStyle(
                  fontFamily: AppTokens.fontCairo,
                  fontSize: 12,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTokens.accent,
                side: const BorderSide(color: AppTokens.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
