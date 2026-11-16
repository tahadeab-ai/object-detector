import 'dart:async';
import 'dart:ffi';
import 'package:camera/camera.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import '../../core/ffi/native_structs.dart';
import '../../core/ffi/yolo_ncnn_ffi.dart';
import '../../core/l10n/coco_labels_repository.dart';
import '../../core/models/detection_item.dart';
import '../../core/models/engine_telemetry.dart';
import '../../core/services/detection_event_bus.dart';
import '../../core/services/telemetry_sync_client.dart';
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
  bool _isCameraInitialized = false;
  bool _isCameraPermissionDenied = false;
  bool _isProcessingFrame = false;
  bool _isArabic = false;

  double _confThreshold = 0.25;
  double _iouThreshold = 0.45;

  List<DetectionItem> _currentDetections = [];
  EngineTelemetry _currentTelemetry = const EngineTelemetry();

  StreamSubscription<FrameDetectionEvent>? _eventSub;
  late final TelemetrySyncClient _syncClient;
  final CocoLabelsRepository _labelsRepo = CocoLabelsRepository();

  int _frameCounter = 0;
  DateTime _lastFpsUpdate = DateTime.now();
  DateTime _lastSyncDispatch = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncClient = TelemetrySyncClient();
    _labelsRepo.load();

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

    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // Stop stream on inactive/paused to save battery and GPU
      _cameraController?.stopImageStream();
    } else if (state == AppLifecycleState.resumed) {
      // Restart camera stream on resume
      if (!_cameraController!.value.isStreamingImages) {
        _cameraController?.startImageStream(_handleCameraFrame);
      }
    }
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      setState(() => _isCameraPermissionDenied = false);
      return;
    }

    try {
      final camera = widget.cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => widget.cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();
      if (!mounted) return;

      await controller.startImageStream(_handleCameraFrame);

      setState(() {
        _cameraController = controller;
        _isCameraInitialized = true;
        _isCameraPermissionDenied = false;
      });
    } on CameraException catch (e) {
      if (e.code == 'CameraAccessDenied' ||
          e.code == 'CameraAccessDeniedWithoutPrompt') {
        setState(() => _isCameraPermissionDenied = true);
      }
    } catch (_) {
      // Handled cleanly in device-absent mode
    }
  }

  void _handleCameraFrame(CameraImage image) {
    // Single-Slot Latest-Frame Gate:
    // Drop frame instantly if worker isolate or engine is currently busy
    if (_isProcessingFrame) {
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
      // Detect NV21 (VU-interleaved) vs I420 from plane count and pixel strides
      final isNv21 = image.planes.length == 2 ||
          (image.planes.length > 1 &&
              (image.planes[1].bytesPerPixel ?? 1) == 2);

      final yPlane = image.planes[0];
      final uPlane = image.planes.length > 1 ? image.planes[1] : yPlane;
      final vPlane = image.planes.length > 2 ? image.planes[2] : uPlane;

      final uvPixelStride = isNv21 ? 2 : (uPlane.bytesPerPixel ?? 1);
      final sensorOrientation =
          _cameraController?.description.sensorOrientation ?? 90;

      // When running on device with native library loaded:
      try {
        final engine = YoloNcnnEngine.getInstance();
        if (engine.isInitialized) {
          final yPtr = calloc<Uint8>(yPlane.bytes.length);
          yPtr.asTypedList(yPlane.bytes.length).setAll(0, yPlane.bytes);

          final uPtr = calloc<Uint8>(uPlane.bytes.length);
          uPtr.asTypedList(uPlane.bytes.length).setAll(0, uPlane.bytes);

          final vPtr = calloc<Uint8>(vPlane.bytes.length);
          vPtr.asTypedList(vPlane.bytes.length).setAll(0, vPlane.bytes);

          final outResult = engine.persistentResultBuffer;
          final ret = engine.forwardYuv420(
            yPlane: yPtr,
            uPlane: uPtr,
            vPlane: vPtr,
            width: image.width,
            height: image.height,
            yRowStride: yPlane.bytesPerRow,
            uvRowStride: uPlane.bytesPerRow,
            uvPixelStride: uvPixelStride,
            sensorOrientation: sensorOrientation,
            outResult: outResult,
          );

          calloc.free(yPtr);
          calloc.free(uPtr);
          calloc.free(vPtr);

          if (ret == 0) {
            final res = outResult.ref;
            final detections = <DetectionItem>[];
            for (int k = 0; k < res.numDetections && k < yoloMaxBoxes; k++) {
              detections.add(DetectionItem.fromNative(res.boxes[k]));
            }

            DetectionEventBus().publish(
              FrameDetectionEvent(
                frameId: res.frameId,
                detections: detections,
                telemetry: _currentTelemetry.copyWith(
                  inferenceTimeMs: res.inferenceTimeMs.toDouble(),
                  trackerTimeMs: res.trackerTimeMs.toDouble(),
                  totalLatencyMs: res.inferenceTimeMs + res.trackerTimeMs,
                  activeBackend: res.activeBackend,
                  activeTracks: res.numDetections,
                  confirmedTracks:
                      detections.where((d) => d.isConfirmed).length,
                ),
              ),
            );
          }
        }
      } catch (_) {
        // Native library unavailable in host unit testing
      }
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _toggleLanguage() {
    setState(() => _isArabic = !_isArabic);
  }

  void _toggleBackend() {
    final nextBackend = _currentTelemetry.isVulkan ? 0 : 1;
    setState(() {
      _currentTelemetry =
          _currentTelemetry.copyWith(activeBackend: nextBackend);
    });
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

  void _openSampleMode() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SampleBenchmarkView(isArabic: _isArabic),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eventSub?.cancel();
    _cameraController?.dispose();
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
          // 1. Camera Viewfinder or Fallback UI
          if (_isCameraInitialized && _cameraController != null)
            Center(
              child: CameraPreview(_cameraController!),
            )
          else if (_isCameraPermissionDenied)
            Container(
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
                          ? 'يرجى تفعيل إذن الكاميرا من إعدادات الجهاز لمتابعة البث الحي'
                          : 'Please grant camera access in system settings to run real-time inference.',
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
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
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _openSampleMode,
                      icon: const Icon(Icons.photo_library_outlined, size: 16),
                      label: Text(
                        _isArabic
                            ? 'فتح وضع الصور المرجعية'
                            : 'Launch Sample Benchmark',
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
            ),

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

          // 3. Top Glassmorphic Telemetry HUD
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
              repo: _labelsRepo,
            ),
          ),
        ],
      ),
    );
  }
}
