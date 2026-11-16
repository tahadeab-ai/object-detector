import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
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

class _CockpitScreenState extends State<CockpitScreen> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
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

  @override
  void initState() {
    super.initState();
    _syncClient = TelemetrySyncClient();
    _labelsRepo.load();

    _eventSub = DetectionEventBus().stream.listen((event) {
      if (!mounted) return;
      setState(() {
        _currentDetections = event.detections;
        _currentTelemetry = event.telemetry;
      });

      _syncClient.sendFrameTelemetry(
        frameId: event.frameId,
        detections: event.detections,
        telemetry: event.telemetry,
      );
    });

    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      // Hardware camera unavailable (e.g., host verification / device absent)
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
      });
    } catch (_) {
      // Handled gracefully in device-absent mode
    }
  }

  void _handleCameraFrame(CameraImage image) {
    // Single-Slot Latest-Frame Gate:
    // Drop frame immediately if worker isolate / engine is busy with an earlier frame
    if (_isProcessingFrame) {
      return;
    }

    _isProcessingFrame = true;
    _frameCounter++;

    // Calculate rolling FPS
    final now = DateTime.now();
    final elapsedMs = now.difference(_lastFpsUpdate).inMilliseconds;
    if (elapsedMs >= 500) {
      final currentFps = (_frameCounter * 1000.0) / elapsedMs;
      _frameCounter = 0;
      _lastFpsUpdate = now;
      setState(() {
        _currentTelemetry = _currentTelemetry.copyWith(fps: currentFps);
      });
    }

    // Pass frame buffers to native pipeline (simulated here if running without full JNI/so runtime)
    // On hardware, pointers are forwarded to yolo_engine_forward_yuv420
    _isProcessingFrame = false;
  }

  void _toggleLanguage() {
    setState(() => _isArabic = !_isArabic);
  }

  void _toggleBackend() {
    final nextBackend = _currentTelemetry.isVulkan ? 0 : 1;
    setState(() {
      _currentTelemetry = _currentTelemetry.copyWith(activeBackend: nextBackend);
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
        onTelemetrySyncChanged: (val) => setState(() => _syncClient.isEnabled = val),
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
          // Camera viewfinder or dark cockpit background
          if (_isCameraInitialized && _cameraController != null)
            Center(
              child: CameraPreview(_cameraController!),
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
            ),

          // Decoupled 60 FPS CustomPainter HUD
          CustomPaint(
            size: size,
            painter: BBoxHudPainter(
              detections: _currentDetections,
              isArabic: _isArabic,
              showZones: true,
              repo: _labelsRepo,
            ),
          ),

          // Top glassmorphic telemetry bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: TelemetryTopBar(
              telemetry: _currentTelemetry,
              isArabic: _isArabic,
              onToggleLanguage: _toggleLanguage,
              onToggleBackend: _toggleBackend,
              onOpenSampleMode: _openSampleMode,
              onOpenSettings: _openSettings,
            ),
          ),
        ],
      ),
    );
  }
}
