import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../core/ffi/native_structs.dart';
import '../../core/l10n/coco_labels_repository.dart';
import '../../core/models/detection_item.dart';
import '../../core/models/engine_telemetry.dart';
import '../../core/services/camera_permission_service.dart';
import '../../core/services/detection_event_bus.dart';
import '../../core/services/diagnostics_service.dart';
import '../../core/services/inference_worker.dart';
import '../../core/services/telemetry_sync_client.dart';
import '../diagnostics/diagnostics_screen.dart';
import '../sample_mode/sample_benchmark_view.dart';
import '../settings/engine_settings_sheet.dart';
import 'bbox_hud_painter.dart';
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

  double _confThreshold = 0.25;
  double _iouThreshold = 0.45;
  int _activeBackend = 0; // 0=CPU, 1=Vulkan

  List<DetectionItem> _currentDetections = [];
  EngineTelemetry _currentTelemetry = const EngineTelemetry();

  StreamSubscription<FrameDetectionEvent>? _eventSub;
  late final TelemetrySyncClient _syncClient;
  final CocoLabelsRepository _labelsRepo = CocoLabelsRepository();
  final DiagnosticsService _diagService = DiagnosticsService();
  final InferenceWorker _inferenceWorker = InferenceWorker();

  int _frameCounter = 0;
  DateTime _lastFpsUpdate = DateTime.now();
  DateTime _lastInferenceTime = DateTime.now();
  DateTime _lastSyncDispatch = DateTime.now();

  // Watchdog: alert if no frames processed within 5 seconds of camera running
  Timer? _watchdogTimer;
  bool _watchdogFired = false;
  String? _cameraErrorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncClient = TelemetrySyncClient();
    _labelsRepo.load();
    _availableCameras = List.from(widget.cameras);

    _eventSub = DetectionEventBus().stream.listen((event) {
      if (!mounted) return;
      setState(() {
        _currentDetections = event.detections;
        _currentTelemetry = event.telemetry;
      });

      // Buffer telemetry every 2 seconds before dispatching asynchronously
      final now = DateTime.now();
      if (now.difference(_lastSyncDispatch).inSeconds >= 2) {
        _lastSyncDispatch = now;
        _syncClient.sendFrameTelemetry(
          frameId: event.frameId,
          detections: event.detections,
          telemetry: event.telemetry,
        );
      }
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

  int _selectedCameraIndex = 0;

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

  void _handleCameraFrame(CameraImage image) async {
    _diagService.recordFrameReceived();

    final now = DateTime.now();
    if (now.difference(_lastInferenceTime).inMilliseconds < 250) {
      return;
    }

    // Single-Slot Latest-Frame Gate:
    // Drop frame instantly if worker isolate or engine is currently busy
    if (_isProcessingFrame || _inferenceWorker.isBusy) {
      _diagService.recordFrameDropped();
      return;
    }

    _lastInferenceTime = now;
    _isProcessingFrame = true;
    _frameCounter++;
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

      // Delegate inference to dedicated worker isolate
      final result = await _inferenceWorker.processFrame(
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
      );

      if (result != null && result.statusCode == 0) {
        _resetWatchdog();
        _diagService.recordFrameProcessed();

        final detections = <DetectionItem>[];
        for (final b in result.boxes) {
          detections.add(DetectionItem(
            x1: b.x1.clamp(0.0, 1.0),
            y1: b.y1.clamp(0.0, 1.0),
            x2: b.x2.clamp(0.0, 1.0),
            y2: b.y2.clamp(0.0, 1.0),
            confidence: b.confidence,
            classId: b.classId,
            trackId: b.trackId,
            trackState: TrackState.fromInt(b.trackState),
            spatialZone: SpatialZone.fromInt(b.spatialZone),
            proximityTier: ProximityTier.fromInt(b.proximityTier),
          ));
        }

        DetectionEventBus().publish(
          FrameDetectionEvent(
            frameId: result.frameId,
            detections: detections,
            telemetry: _currentTelemetry.copyWith(
              inferenceTimeMs: result.inferenceTimeMs,
              trackerTimeMs: result.trackerTimeMs,
              totalLatencyMs: result.inferenceTimeMs + result.trackerTimeMs,
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

  Future<void> _switchCamera() async {
    if (_availableCameras.length < 2) return;
    try {
      _selectedCameraIndex =
          (_selectedCameraIndex + 1) % _availableCameras.length;
      final newCamera = _availableCameras[_selectedCameraIndex];
      debugPrint(
          '[CockpitScreen] _switchCamera to index: $_selectedCameraIndex (${newCamera.lensDirection})');
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
        initialTelemetrySync: _syncClient.isEnabled,
        isArabic: _isArabic,
        onConfChanged: (val) => setState(() => _confThreshold = val),
        onIouChanged: (val) => setState(() => _iouThreshold = val),
        onTelemetrySyncChanged: (val) =>
            setState(() => _syncClient.isEnabled = val),
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

  @override
  void dispose() {
    _stopWatchdog();
    WidgetsBinding.instance.removeObserver(this);
    _eventSub?.cancel();
    _cameraController?.dispose();
    _inferenceWorker.stop();
    _syncClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Viewfinder, Loading, Permission Rationale, or Fallback UI
          if (_isLoadingCamera)
            _buildLoadingState()
          else if (_isCameraInitialized && _cameraController != null)
            Center(child: CameraPreview(_cameraController!))
          else if (_isCameraPermissionDenied)
            _buildPermissionDeniedState()
          else if (_cameraErrorMessage != null)
            _buildErrorState(_cameraErrorMessage!)
          else
            _buildFallbackState(),

          // 2. Decoupled 60 FPS CustomPainter HUD inside RepaintBoundary
          RepaintBoundary(
            child: CustomPaint(
              size: size,
              painter: BBoxHudPainter(
                detections: _currentDetections,
                isArabic: _isArabic,
                showZones: true,
                showTrails: true,
                repo: _labelsRepo,
              ),
            ),
          ),

          // 3. Subtle Empty State HUD Watermark ("No objects in scene")
          if (_isCameraInitialized &&
              !_isLoadingCamera &&
              _currentDetections.isEmpty &&
              !_watchdogFired)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.radar_rounded,
                          size: 14, color: Colors.cyanAccent),
                      const SizedBox(width: 8),
                      Text(
                        _isArabic
                            ? 'لم يتم رصد أي أهداف في المشهد'
                            : 'No objects detected in scene',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 4. Watchdog Error Banner (if stalled >= 5s)
          if (_watchdogFired)
            Positioned(
              top: MediaQuery.of(context).padding.top + 90,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B1214),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 8),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.redAccent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isArabic
                                ? 'تنبيه الحارس: توقف تدفق الإطارات'
                                : 'Watchdog: Frame Stalled (>5s)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isArabic
                                ? 'لم تتم معالجة أي إطار خلال 5 ثوانٍ.'
                                : 'No frames processed within 5 seconds.',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _openDiagnostics,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.cyanAccent,
                      ),
                      child: Text(_isArabic ? 'التشخيص' : 'Diagnostics'),
                    ),
                  ],
                ),
              ),
            ),

          // 5. Top Glassmorphic Telemetry HUD
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: TelemetryTopBar(
              telemetry: _currentTelemetry,
              detections: _currentDetections,
              isArabic: _isArabic,
              onToggleLanguage: _toggleLanguage,
              onToggleBackend: _toggleBackend,
              onOpenSampleMode: _openSampleMode,
              onOpenSettings: _openSettings,
              onOpenDiagnostics: _openDiagnostics,
              onSwitchCamera: _switchCamera,
              repo: _labelsRepo,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      color: const Color(0xFF0D0D11),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.cyanAccent),
            const SizedBox(height: 16),
            Text(
              _isArabic
                  ? 'جاري تشغيل الكاميرا ومحرك NCNN...'
                  : 'Initializing Camera & NCNN Engine...',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionDeniedState() {
    return Container(
      color: const Color(0xFF16161D),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined,
                size: 64, color: Colors.amberAccent),
            const SizedBox(height: 16),
            Text(
              _isArabic
                  ? 'إذن استخدام الكاميرا مطلوب'
                  : 'Camera Permission Required',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _isArabic
                  ? 'يحتاج التطبيق لإذن الكاميرا لتشغيل الكشف المباشر عن الأهداف. يمكنك منح الإذن أو استخدام وضع الصور المرجعية.'
                  : 'Camera access is required for live real-time detection. You can grant access or run offline sample benchmark mode.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 24),
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
                  icon: const Icon(Icons.security_rounded, size: 18),
                  label: Text(
                    _isArabic ? 'منح الإذن / الإعدادات' : 'Grant / Settings',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _openSampleMode,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: Text(
                    _isArabic ? 'وضع الصور' : 'Sample Mode',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.cyanAccent,
                    side: const BorderSide(color: Colors.cyanAccent),
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
      color: const Color(0xFF161214),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 56, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              _isArabic ? 'خطأ في تشغيل الكاميرا' : 'Camera Hardware Error',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _requestPermissionAndInitCamera,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(_isArabic ? 'إعادة المحاولة' : 'Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _openDiagnostics,
                  icon: const Icon(Icons.analytics_outlined, size: 16),
                  label: Text(_isArabic ? 'التشخيص' : 'Diagnostics'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.cyanAccent,
                    side: const BorderSide(color: Colors.cyanAccent),
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
      color: const Color(0xFF0D0D11),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.camera_alt_outlined,
              size: 64,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 12),
            Text(
              _isArabic
                  ? 'بانتظار مستشعر الكاميرا أو وضع الصور المرجعية'
                  : 'Awaiting Camera Stream or Sample Benchmark Mode',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _openSampleMode,
              icon: const Icon(Icons.photo_library_outlined, size: 16),
              label: Text(
                _isArabic ? 'فتح وضع الصور المرجعية' : 'Launch Sample Benchmark',
                style: const TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.cyanAccent,
                side: const BorderSide(color: Colors.cyanAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
