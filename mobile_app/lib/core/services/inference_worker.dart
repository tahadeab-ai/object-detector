import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../ffi/native_structs.dart';
import '../ffi/yolo_ncnn_ffi.dart';

class IsolateBoxData {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double confidence;
  final int classId;
  final int trackId;
  final int trackState;
  final int spatialZone;
  final int proximityTier;

  const IsolateBoxData({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.confidence,
    required this.classId,
    required this.trackId,
    required this.trackState,
    required this.spatialZone,
    required this.proximityTier,
  });
}

class IsolateFrameResult {
  final int frameId;
  final double inferenceTimeMs;
  final double trackerTimeMs;
  final int activeBackend;
  final int statusCode;
  final List<IsolateBoxData> boxes;

  const IsolateFrameResult({
    required this.frameId,
    required this.inferenceTimeMs,
    required this.trackerTimeMs,
    required this.activeBackend,
    required this.statusCode,
    required this.boxes,
  });
}

class _InferenceTask {
  final Uint8List yBytes;
  final Uint8List uBytes;
  final Uint8List vBytes;
  final int width;
  final int height;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
  final int sensorOrientation;
  final int backend;

  const _InferenceTask({
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
    required this.width,
    required this.height,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.sensorOrientation,
    required this.backend,
  });
}

/// Dedicated Background Worker Isolate for zero UI-thread contention
class InferenceWorker {
  static final InferenceWorker _instance = InferenceWorker._internal();
  factory InferenceWorker() => _instance;
  InferenceWorker._internal();

  Isolate? _isolate;
  SendPort? _sendPort;
  Completer<void>? _initCompleter;
  Completer<IsolateFrameResult>? _currentTaskCompleter;
  bool _isBusy = false;

  bool get isBusy => _isBusy;
  bool get isReady => _sendPort != null;

  Future<void> start() async {
    if (_sendPort != null) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();
    final receivePort = ReceivePort();

    try {
      _isolate = await Isolate.spawn(_isolateEntryPoint, receivePort.sendPort);
      final events = receivePort.asBroadcastStream();
      _sendPort = await events.first as SendPort;

      events.listen((message) {
        if (message is IsolateFrameResult) {
          _isBusy = false;
          _currentTaskCompleter?.complete(message);
          _currentTaskCompleter = null;
        }
      });

      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.completeError(e);
      rethrow;
    }
  }

  /// Single-Slot Latest-Frame Gate:
  /// Submits a frame for processing. Returns null if worker is currently busy.
  Future<IsolateFrameResult?> processFrame({
    required Uint8List yBytes,
    required Uint8List uBytes,
    required Uint8List vBytes,
    required int width,
    required int height,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required int sensorOrientation,
    required int backend,
  }) async {
    if (_isBusy || _sendPort == null) {
      return null;
    }

    _isBusy = true;
    _currentTaskCompleter = Completer<IsolateFrameResult>();

    final task = _InferenceTask(
      yBytes: yBytes,
      uBytes: uBytes,
      vBytes: vBytes,
      width: width,
      height: height,
      yRowStride: yRowStride,
      uvRowStride: uvRowStride,
      uvPixelStride: uvPixelStride,
      sensorOrientation: sensorOrientation,
      backend: backend,
    );

    _sendPort!.send(task);
    return _currentTaskCompleter!.future;
  }

  void stop() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _initCompleter = null;
    _isBusy = false;
  }

  static void _isolateEntryPoint(SendPort replyPort) {
    final port = ReceivePort();
    replyPort.send(port.sendPort);

    final engine = YoloNcnnEngine.getInstance();

    port.listen((message) {
      if (message is _InferenceTask) {
        try {
          engine.setBackend(useVulkan: message.backend == 1);

          final yPtr = calloc<Uint8>(message.yBytes.length);
          yPtr.asTypedList(message.yBytes.length).setAll(0, message.yBytes);

          final uPtr = calloc<Uint8>(message.uBytes.length);
          uPtr.asTypedList(message.uBytes.length).setAll(0, message.uBytes);

          final vPtr = calloc<Uint8>(message.vBytes.length);
          vPtr.asTypedList(message.vBytes.length).setAll(0, message.vBytes);

          final outResult = engine.persistentResultBuffer;
          final ret = engine.forwardYuv420(
            yPlane: yPtr,
            uPlane: uPtr,
            vPlane: vPtr,
            width: message.width,
            height: message.height,
            yRowStride: message.yRowStride,
            uvRowStride: message.uvRowStride,
            uvPixelStride: message.uvPixelStride,
            sensorOrientation: message.sensorOrientation,
            outResult: outResult,
          );

          calloc.free(yPtr);
          calloc.free(uPtr);
          calloc.free(vPtr);

          if (ret == 0) {
            final res = outResult.ref;
            final boxes = <IsolateBoxData>[];
            for (int k = 0; k < res.numDetections && k < yoloMaxBoxes; k++) {
              final b = res.boxes[k];
              boxes.add(IsolateBoxData(
                x1: b.x1,
                y1: b.y1,
                x2: b.x2,
                y2: b.y2,
                confidence: b.confidence,
                classId: b.classId,
                trackId: b.trackId,
                trackState: b.trackState,
                spatialZone: b.spatialZone,
                proximityTier: b.proximityTier,
              ));
            }

            replyPort.send(IsolateFrameResult(
              frameId: res.frameId,
              inferenceTimeMs: res.inferenceTimeMs.toDouble(),
              trackerTimeMs: res.trackerTimeMs.toDouble(),
              activeBackend: res.activeBackend,
              statusCode: res.statusCode,
              boxes: boxes,
            ));
          } else {
            replyPort.send(IsolateFrameResult(
              frameId: 0,
              inferenceTimeMs: 0,
              trackerTimeMs: 0,
              activeBackend: 0,
              statusCode: ret,
              boxes: const [],
            ));
          }
        } catch (_) {
          replyPort.send(const IsolateFrameResult(
            frameId: 0,
            inferenceTimeMs: 0,
            trackerTimeMs: 0,
            activeBackend: 0,
            statusCode: -999,
            boxes: [],
          ));
        }
      }
    });
  }
}
