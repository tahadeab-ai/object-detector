import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';
import 'package:ffi/ffi.dart';
import '../ffi/native_structs.dart';
import '../ffi/yolo_ncnn_ffi.dart';
import '../models/detection_item.dart';
import '../models/multitask_results.dart';

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
  final int taskId; // 0=Det, 1=Seg, 2=Pose, 3=Cls, 4=Obb

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
    this.taskId = 0,
  });
}

class _SwitchModelMessage {
  final int taskId;
  final String paramPath;
  final String binPath;
  final int targetSize;
  final int backend;

  const _SwitchModelMessage({
    required this.taskId,
    required this.paramPath,
    required this.binPath,
    required this.targetSize,
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
  Completer<dynamic>? _currentTaskCompleter;
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
        _isBusy = false;
        if (_currentTaskCompleter != null && !_currentTaskCompleter!.isCompleted) {
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

  /// Switch model in the background isolate
  Future<bool> switchModelInIsolate({
    required int taskId,
    required String paramPath,
    required String binPath,
    required int targetSize,
    required int backend,
  }) async {
    if (_sendPort == null) return false;

    _isBusy = true;
    final comp = Completer<dynamic>();
    _currentTaskCompleter = comp;

    _sendPort!.send(_SwitchModelMessage(
      taskId: taskId,
      paramPath: paramPath,
      binPath: binPath,
      targetSize: targetSize,
      backend: backend,
    ));

    final res = await comp.future;
    return res == 0;
  }

  /// Single-Slot Latest-Frame Gate for Detection (Backward Compatible)
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
    final comp = Completer<dynamic>();
    _currentTaskCompleter = comp;

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
      taskId: 0,
    );

    try {
      _sendPort!.send(task);
      final res = await comp.future.timeout(const Duration(milliseconds: 1500));
      if (res is IsolateFrameResult) return res;
      return null;
    } catch (e) {
      return null;
    } finally {
      _isBusy = false;
      if (_currentTaskCompleter == comp) {
        _currentTaskCompleter = null;
      }
    }
  }

  /// Single-Slot Multi-Task Frame Processing
  Future<MultiTaskFrameResult?> processMultiTaskFrame({
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
    required VisionTask task,
  }) async {
    if (_isBusy || _sendPort == null) {
      return null;
    }

    _isBusy = true;
    final comp = Completer<dynamic>();
    _currentTaskCompleter = comp;

    final inferenceTask = _InferenceTask(
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
      taskId: task.id,
    );

    try {
      _sendPort!.send(inferenceTask);
      final res = await comp.future.timeout(const Duration(milliseconds: 1500));
      if (res is MultiTaskFrameResult) return res;
      return null;
    } catch (e) {
      return null;
    } finally {
      _isBusy = false;
      if (_currentTaskCompleter == comp) {
        _currentTaskCompleter = null;
      }
    }
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

    Pointer<Uint8> yPersistentPtr = nullptr;
    int yCap = 0;
    Pointer<Uint8> uPersistentPtr = nullptr;
    int uCap = 0;
    Pointer<Uint8> vPersistentPtr = nullptr;
    int vCap = 0;

    port.listen((message) {
      if (message is _SwitchModelMessage) {
        try {
          final ret = engine.initMultiTask(
            task: VisionTask.fromId(message.taskId),
            paramPath: message.paramPath,
            binPath: message.binPath,
            targetSize: message.targetSize,
            backend: message.backend,
          );
          replyPort.send(ret);
        } catch (_) {
          replyPort.send(-1);
        }
        return;
      }

      if (message is _InferenceTask) {
        try {
          engine.setBackend(backend: message.backend);

          final yLen = message.yBytes.length;
          if (yPersistentPtr == nullptr || yCap < yLen) {
            if (yPersistentPtr != nullptr) calloc.free(yPersistentPtr);
            yCap = yLen + 4096;
            yPersistentPtr = calloc<Uint8>(yCap);
          }
          yPersistentPtr.asTypedList(yLen).setAll(0, message.yBytes);

          final uLen = message.uBytes.length;
          if (uPersistentPtr == nullptr || uCap < uLen) {
            if (uPersistentPtr != nullptr) calloc.free(uPersistentPtr);
            uCap = uLen + 4096;
            uPersistentPtr = calloc<Uint8>(uCap);
          }
          uPersistentPtr.asTypedList(uLen).setAll(0, message.uBytes);

          final vLen = message.vBytes.length;
          if (vPersistentPtr == nullptr || vCap < vLen) {
            if (vPersistentPtr != nullptr) calloc.free(vPersistentPtr);
            vCap = vLen + 4096;
            vPersistentPtr = calloc<Uint8>(vCap);
          }
          vPersistentPtr.asTypedList(vLen).setAll(0, message.vBytes);

          final yPtr = yPersistentPtr;
          final uPtr = uPersistentPtr;
          final vPtr = vPersistentPtr;

          final task = VisionTask.fromId(message.taskId);

          if (task == VisionTask.detection) {
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

            if (ret == 0) {
              final res = outResult.ref;
              final boxes = <IsolateBoxData>[];
              final detItems = <DetectionItem>[];
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
                detItems.add(DetectionItem(
                  x1: b.x1,
                  y1: b.y1,
                  x2: b.x2,
                  y2: b.y2,
                  confidence: b.confidence,
                  classId: b.classId,
                  trackId: b.trackId,
                  trackState: TrackState.fromInt(b.trackState),
                  spatialZone: SpatialZone.fromInt(b.spatialZone),
                  proximityTier: ProximityTier.fromInt(b.proximityTier),
                ));
              }

              // Send MultiTaskFrameResult if multi-task or IsolateFrameResult
              replyPort.send(MultiTaskFrameResult(
                task: VisionTask.detection,
                frameId: res.frameId,
                prepTimeMs: 0.0,
                inferenceTimeMs: res.inferenceTimeMs.toDouble(),
                postTimeMs: res.trackerTimeMs.toDouble(),
                activeBackend: res.activeBackend,
                statusCode: res.statusCode,
                detections: detItems,
              ));
            } else {
              replyPort.send(MultiTaskFrameResult(
                task: VisionTask.detection,
                frameId: 0,
                prepTimeMs: 0,
                inferenceTimeMs: 0,
                postTimeMs: 0,
                activeBackend: 0,
                statusCode: ret,
              ));
            }
          } else if (task == VisionTask.segmentation) {
            final segBuffer = engine.persistentSegBuffer;
            final ret = engine.forwardTaskYuv420(
              yPlane: yPtr,
              uPlane: uPtr,
              vPlane: vPtr,
              width: message.width,
              height: message.height,
              yRowStride: message.yRowStride,
              uvRowStride: message.uvRowStride,
              uvPixelStride: message.uvPixelStride,
              sensorOrientation: message.sensorOrientation,
              outBuffer: segBuffer.cast(),
            );

            final res = segBuffer.ref;
            final segItems = <SegmentationItem>[];
            for (int i = 0; i < res.numObjects && i < maxSegObjects; i++) {
              final obj = res.objects[i];
              final pts = <Offset>[];
              for (int k = 0; k < obj.numContourPoints && k < maxContourPoints; k++) {
                pts.add(Offset(obj.contourPoints[k * 2], obj.contourPoints[k * 2 + 1]));
              }
              segItems.add(SegmentationItem(
                x1: obj.x1,
                y1: obj.y1,
                x2: obj.x2,
                y2: obj.y2,
                confidence: obj.confidence,
                classId: obj.classId,
                maskW: obj.maskW,
                maskH: obj.maskH,
                contourPoints: pts,
              ));
            }

            replyPort.send(MultiTaskFrameResult(
              task: VisionTask.segmentation,
              frameId: res.header.frameId,
              prepTimeMs: res.header.preprocessingTimeMs,
              inferenceTimeMs: res.header.inferenceTimeMs,
              postTimeMs: res.header.postprocessingTimeMs,
              activeBackend: res.header.activeBackend,
              statusCode: ret,
              segmentations: segItems,
            ));
          } else if (task == VisionTask.pose) {
            final poseBuffer = engine.persistentPoseBuffer;
            final ret = engine.forwardTaskYuv420(
              yPlane: yPtr,
              uPlane: uPtr,
              vPlane: vPtr,
              width: message.width,
              height: message.height,
              yRowStride: message.yRowStride,
              uvRowStride: message.uvRowStride,
              uvPixelStride: message.uvPixelStride,
              sensorOrientation: message.sensorOrientation,
              outBuffer: poseBuffer.cast(),
            );

            final res = poseBuffer.ref;
            final poseItems = <PoseItem>[];
            for (int i = 0; i < res.numObjects && i < maxPoseObjects; i++) {
              final obj = res.objects[i];
              final kps = <KeyPointData>[];
              for (int k = 0; k < poseKeypointsCount; k++) {
                kps.add(KeyPointData(
                  x: obj.keypoints[k].x,
                  y: obj.keypoints[k].y,
                  confidence: obj.keypoints[k].confidence,
                ));
              }
              poseItems.add(PoseItem(
                x1: obj.x1,
                y1: obj.y1,
                x2: obj.x2,
                y2: obj.y2,
                confidence: obj.confidence,
                classId: obj.classId,
                keypoints: kps,
              ));
            }

            replyPort.send(MultiTaskFrameResult(
              task: VisionTask.pose,
              frameId: res.header.frameId,
              prepTimeMs: res.header.preprocessingTimeMs,
              inferenceTimeMs: res.header.inferenceTimeMs,
              postTimeMs: res.header.postprocessingTimeMs,
              activeBackend: res.header.activeBackend,
              statusCode: ret,
              poses: poseItems,
            ));
          } else if (task == VisionTask.classification) {
            final clsBuffer = engine.persistentClsBuffer;
            final ret = engine.forwardTaskYuv420(
              yPlane: yPtr,
              uPlane: uPtr,
              vPlane: vPtr,
              width: message.width,
              height: message.height,
              yRowStride: message.yRowStride,
              uvRowStride: message.uvRowStride,
              uvPixelStride: message.uvPixelStride,
              sensorOrientation: message.sensorOrientation,
              outBuffer: clsBuffer.cast(),
            );

            final res = clsBuffer.ref;
            final clsItems = <ClassificationItem>[];
            for (int i = 0; i < res.numItems && i < maxTopK; i++) {
              clsItems.add(ClassificationItem(
                classId: res.items[i].classId,
                confidence: res.items[i].confidence,
              ));
            }

            replyPort.send(MultiTaskFrameResult(
              task: VisionTask.classification,
              frameId: res.header.frameId,
              prepTimeMs: res.header.preprocessingTimeMs,
              inferenceTimeMs: res.header.inferenceTimeMs,
              postTimeMs: res.header.postprocessingTimeMs,
              activeBackend: res.header.activeBackend,
              statusCode: ret,
              classifications: clsItems,
            ));
          } else if (task == VisionTask.obb) {
            final obbBuffer = engine.persistentObbBuffer;
            final ret = engine.forwardTaskYuv420(
              yPlane: yPtr,
              uPlane: uPtr,
              vPlane: vPtr,
              width: message.width,
              height: message.height,
              yRowStride: message.yRowStride,
              uvRowStride: message.uvRowStride,
              uvPixelStride: message.uvPixelStride,
              sensorOrientation: message.sensorOrientation,
              outBuffer: obbBuffer.cast(),
            );

            final res = obbBuffer.ref;
            final obbItems = <ObbItem>[];
            for (int i = 0; i < res.numObjects && i < maxObbObjects; i++) {
              final obj = res.objects[i];
              final corners = <Offset>[
                Offset(obj.corners[0], obj.corners[1]),
                Offset(obj.corners[2], obj.corners[3]),
                Offset(obj.corners[4], obj.corners[5]),
                Offset(obj.corners[6], obj.corners[7]),
              ];
              obbItems.add(ObbItem(
                cx: obj.cx,
                cy: obj.cy,
                width: obj.width,
                height: obj.height,
                angleRad: obj.angleRad,
                angleDeg: obj.angleDeg,
                corners: corners,
                confidence: obj.confidence,
                classId: obj.classId,
              ));
            }

            replyPort.send(MultiTaskFrameResult(
              task: VisionTask.obb,
              frameId: res.header.frameId,
              prepTimeMs: res.header.preprocessingTimeMs,
              inferenceTimeMs: res.header.inferenceTimeMs,
              postTimeMs: res.header.postprocessingTimeMs,
              activeBackend: res.header.activeBackend,
              statusCode: ret,
              obbs: obbItems,
            ));
          }
        } catch (_) {
          replyPort.send(MultiTaskFrameResult(
            task: VisionTask.fromId(message.taskId),
            frameId: 0,
            prepTimeMs: 0,
            inferenceTimeMs: 0,
            postTimeMs: 0,
            activeBackend: 0,
            statusCode: -999,
          ));
        }
      }
    });
  }
}
