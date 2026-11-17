import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'native_structs.dart';

// Native function typedefs for Legacy Detection Engine API
typedef _YoloEngineInitC = Int32 Function(
    Pointer<Utf8> paramPath, Pointer<Utf8> binPath, Int32 useVulkan);
typedef _YoloEngineInitDart = int Function(
    Pointer<Utf8> paramPath, Pointer<Utf8> binPath, int useVulkan);

typedef _YoloEngineForwardYuv420C = Int32 Function(
    Pointer<Uint8> yPlane,
    Pointer<Uint8> uPlane,
    Pointer<Uint8> vPlane,
    Int32 width,
    Int32 height,
    Int32 yRowStride,
    Int32 uvRowStride,
    Int32 uvPixelStride,
    Int32 sensorOrientation,
    Pointer<YoloFrameResult> outResult);
typedef _YoloEngineForwardYuv420Dart = int Function(
    Pointer<Uint8> yPlane,
    Pointer<Uint8> uPlane,
    Pointer<Uint8> vPlane,
    int width,
    int height,
    int yRowStride,
    int uvRowStride,
    int uvPixelStride,
    int sensorOrientation,
    Pointer<YoloFrameResult> outResult);

typedef _YoloEngineForwardRgbaC = Int32 Function(
    Pointer<Uint8> rgba,
    Int32 width,
    Int32 height,
    Int32 sensorOrientation,
    Pointer<YoloFrameResult> outResult);
typedef _YoloEngineForwardRgbaDart = int Function(
    Pointer<Uint8> rgba,
    int width,
    int height,
    int sensorOrientation,
    Pointer<YoloFrameResult> outResult);

// Native function typedefs for Modern Multi-Task Engine API
typedef _YoloMultiTaskInitC = Int32 Function(
    Int32 taskId,
    Pointer<Utf8> paramPath,
    Pointer<Utf8> binPath,
    Int32 targetSize,
    Int32 useBackend);
typedef _YoloMultiTaskInitDart = int Function(
    int taskId,
    Pointer<Utf8> paramPath,
    Pointer<Utf8> binPath,
    int targetSize,
    int useBackend);

typedef _YoloMultiTaskSetSizeC = Int32 Function(Int32 targetSize);
typedef _YoloMultiTaskSetSizeDart = int Function(int targetSize);

typedef _YoloMultiTaskSetBackendC = Int32 Function(Int32 backend);
typedef _YoloMultiTaskSetBackendDart = int Function(int backend);

typedef _YoloMultiTaskForwardYuv420C = Int32 Function(
    Pointer<Uint8> yPlane,
    Pointer<Uint8> uPlane,
    Pointer<Uint8> vPlane,
    Int32 width,
    Int32 height,
    Int32 yRowStride,
    Int32 uvRowStride,
    Int32 uvPixelStride,
    Int32 sensorOrientation,
    Pointer<Void> outResultBuffer);
typedef _YoloMultiTaskForwardYuv420Dart = int Function(
    Pointer<Uint8> yPlane,
    Pointer<Uint8> uPlane,
    Pointer<Uint8> vPlane,
    int width,
    int height,
    int yRowStride,
    int uvRowStride,
    int uvPixelStride,
    int sensorOrientation,
    Pointer<Void> outResultBuffer);

typedef _YoloMultiTaskForwardRgbaC = Int32 Function(
    Pointer<Uint8> rgba,
    Int32 width,
    Int32 height,
    Int32 sensorOrientation,
    Pointer<Void> outResultBuffer);
typedef _YoloMultiTaskForwardRgbaDart = int Function(
    Pointer<Uint8> rgba,
    int width,
    int height,
    int sensorOrientation,
    Pointer<Void> outResultBuffer);

typedef _YoloMultiTaskDestroyC = Void Function();
typedef _YoloMultiTaskDestroyDart = void Function();

/// Distinct error codes for fast failure
class YoloEngineErrors {
  static const int success = 0;
  static const int metadataValidationFailed = -101;
  static const int modelExtractionFailed = -102;
  static const int nativeInitFailed = -103;
  static const int libraryLoadFailed = -104;
}

/// Zero-allocation, high-performance Dart FFI wrapper around `libyolo_ncnn.so`
class YoloNcnnEngine {
  static YoloNcnnEngine? _instance;
  final DynamicLibrary _lib;

  // Legacy detection functions
  late final _YoloEngineInitDart _init;
  late final _YoloEngineForwardYuv420Dart _forwardYuv420;
  late final _YoloEngineForwardRgbaDart _forwardRgba;

  // Modern Multi-task functions
  late final _YoloMultiTaskInitDart _multiTaskInit;
  late final _YoloMultiTaskSetSizeDart _multiTaskSetSize;
  late final _YoloMultiTaskSetBackendDart _multiTaskSetBackend;
  late final _YoloMultiTaskForwardYuv420Dart _multiTaskForwardYuv420;
  late final _YoloMultiTaskForwardRgbaDart _multiTaskForwardRgba;
  late final _YoloMultiTaskDestroyDart _multiTaskDestroy;

  // Persistent native buffers (Allocated ONCE, zero heap allocation per frame)
  late final Pointer<YoloFrameResult> _persistentFrameResult;
  late final Pointer<YoloSegmentationResult> _persistentSegResult;
  late final Pointer<YoloPoseResult> _persistentPoseResult;
  late final Pointer<YoloClassificationResult> _persistentClsResult;
  late final Pointer<YoloObbResult> _persistentObbResult;
  late final Pointer<Float> _persistentOutputTensor;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  VisionTask _activeTask = VisionTask.detection;
  VisionTask get activeTask => _activeTask;

  Pointer<YoloFrameResult> get persistentResultBuffer => _persistentFrameResult;
  Pointer<YoloSegmentationResult> get persistentSegBuffer => _persistentSegResult;
  Pointer<YoloPoseResult> get persistentPoseBuffer => _persistentPoseResult;
  Pointer<YoloClassificationResult> get persistentClsBuffer => _persistentClsResult;
  Pointer<YoloObbResult> get persistentObbBuffer => _persistentObbResult;
  Pointer<Float> get persistentTensorBuffer => _persistentOutputTensor;

  YoloNcnnEngine._(DynamicLibrary lib) : _lib = lib {
    enforceLayoutGate();

    // Lookup Legacy symbols
    _init = _lib.lookupFunction<_YoloEngineInitC, _YoloEngineInitDart>('yolo_engine_init');
    _forwardYuv420 = _lib.lookupFunction<_YoloEngineForwardYuv420C, _YoloEngineForwardYuv420Dart>('yolo_engine_forward_yuv420');
    _forwardRgba = _lib.lookupFunction<_YoloEngineForwardRgbaC, _YoloEngineForwardRgbaDart>('yolo_engine_forward_rgba');

    // Lookup Multi-task symbols
    _multiTaskInit = _lib.lookupFunction<_YoloMultiTaskInitC, _YoloMultiTaskInitDart>('yolo_multitask_init');
    _multiTaskSetSize = _lib.lookupFunction<_YoloMultiTaskSetSizeC, _YoloMultiTaskSetSizeDart>('yolo_multitask_set_target_size');
    _multiTaskSetBackend = _lib.lookupFunction<_YoloMultiTaskSetBackendC, _YoloMultiTaskSetBackendDart>('yolo_multitask_set_backend');
    _multiTaskForwardYuv420 = _lib.lookupFunction<_YoloMultiTaskForwardYuv420C, _YoloMultiTaskForwardYuv420Dart>('yolo_multitask_forward_yuv420');
    _multiTaskForwardRgba = _lib.lookupFunction<_YoloMultiTaskForwardRgbaC, _YoloMultiTaskForwardRgbaDart>('yolo_multitask_forward_rgba');
    _multiTaskDestroy = _lib.lookupFunction<_YoloMultiTaskDestroyC, _YoloMultiTaskDestroyDart>('yolo_multitask_destroy');

    // Allocate persistent buffers once
    _persistentFrameResult = calloc<YoloFrameResult>();
    _persistentSegResult = calloc<YoloSegmentationResult>();
    _persistentPoseResult = calloc<YoloPoseResult>();
    _persistentClsResult = calloc<YoloClassificationResult>();
    _persistentObbResult = calloc<YoloObbResult>();
    _persistentOutputTensor = calloc<Float>(84 * 8400);
  }

  static YoloNcnnEngine getInstance({String? customLibPath}) {
    if (_instance != null) return _instance!;

    DynamicLibrary lib;
    if (Platform.isAndroid) {
      try {
        lib = DynamicLibrary.open(customLibPath ?? 'libyolo_ncnn.so');
      } catch (e) {
        throw StateError(
          'FATAL: Failed to load libyolo_ncnn.so. Ensure native library is packaged: $e',
        );
      }
    } else {
      throw UnsupportedError('YOLO NCNN Engine supports Android arm64-v8a only.');
    }

    _instance = YoloNcnnEngine._(lib);
    return _instance!;
  }

  /// Initialize Legacy Detection Engine
  Future<int> init({int useVulkan = 0}) async {
    final extractedPaths = await _extractModelFiles(
      paramAsset: 'assets/models/model.ncnn.param',
      binAsset: 'assets/models/model.ncnn.bin',
    );
    return initWithPaths(
      paramPath: extractedPaths['param']!,
      binPath: extractedPaths['bin']!,
      useVulkan: useVulkan,
    );
  }

  /// Initialize model with DiagnosticsService signature
  int initModel({
    required String paramPath,
    required String binPath,
    bool useVulkan = false,
  }) {
    return initWithPaths(
      paramPath: paramPath,
      binPath: binPath,
      useVulkan: useVulkan ? 1 : 0,
    );
  }

  /// Initialize with explicit paths (Detection)
  int initWithPaths({
    required String paramPath,
    required String binPath,
    int useVulkan = 0,
  }) {
    final paramPtr = paramPath.toNativeUtf8();
    final binPtr = binPath.toNativeUtf8();

    try {
      final ret = _init(paramPtr, binPtr, useVulkan);
      _isInitialized = (ret == 0);
      _activeTask = VisionTask.detection;
      return ret;
    } finally {
      calloc.free(paramPtr);
      calloc.free(binPtr);
    }
  }

  /// Initialize Multi-Task Engine with explicit task, model files, resolution, and backend
  int initMultiTask({
    required VisionTask task,
    required String paramPath,
    required String binPath,
    int targetSize = 640,
    int backend = 0,
  }) {
    final paramPtr = paramPath.toNativeUtf8();
    final binPtr = binPath.toNativeUtf8();

    try {
      final ret = _multiTaskInit(task.id, paramPtr, binPtr, targetSize, backend);
      _isInitialized = (ret == 0);
      _activeTask = task;
      return ret;
    } finally {
      calloc.free(paramPtr);
      calloc.free(binPtr);
    }
  }

  int setBackend({int backend = 0, bool? useVulkan}) {
    if (!_isInitialized) return -1;
    final b = useVulkan != null ? (useVulkan ? 1 : 0) : backend;
    return _multiTaskSetBackend(b);
  }

  int setTargetSize(int targetSize) {
    if (!_isInitialized) return -1;
    return _multiTaskSetSize(targetSize);
  }

  /// Forward YUV420 frame through active task pipeline
  int forwardTaskYuv420({
    required Pointer<Uint8> yPlane,
    required Pointer<Uint8> uPlane,
    required Pointer<Uint8> vPlane,
    required int width,
    required int height,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required int sensorOrientation,
    required Pointer<Void> outBuffer,
  }) {
    if (!_isInitialized) return -1;
    return _multiTaskForwardYuv420(
      yPlane,
      uPlane,
      vPlane,
      width,
      height,
      yRowStride,
      uvRowStride,
      uvPixelStride,
      sensorOrientation,
      outBuffer,
    );
  }

  /// Forward RGBA frame through active task pipeline
  int forwardTaskRgba({
    required Pointer<Uint8> rgba,
    required int width,
    required int height,
    required int sensorOrientation,
    required Pointer<Void> outBuffer,
  }) {
    if (!_isInitialized) return -1;
    return _multiTaskForwardRgba(rgba, width, height, sensorOrientation, outBuffer);
  }

  /// Legacy forward YUV420 (for Detection)
  int forwardYuv420({
    required Pointer<Uint8> yPlane,
    required Pointer<Uint8> uPlane,
    required Pointer<Uint8> vPlane,
    required int width,
    required int height,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required int sensorOrientation,
    Pointer<YoloFrameResult>? outResult,
  }) {
    if (!_isInitialized) return -1;
    final dest = outResult ?? _persistentFrameResult;
    return _forwardYuv420(
      yPlane,
      uPlane,
      vPlane,
      width,
      height,
      yRowStride,
      uvRowStride,
      uvPixelStride,
      sensorOrientation,
      dest,
    );
  }

  /// Legacy forward RGBA (for Detection)
  int forwardRgba({
    required Pointer<Uint8> rgba,
    required int width,
    required int height,
    required int sensorOrientation,
    Pointer<YoloFrameResult>? outResult,
  }) {
    if (!_isInitialized) return -1;
    final dest = outResult ?? _persistentFrameResult;
    return _forwardRgba(rgba, width, height, sensorOrientation, dest);
  }

  void destroy() {
    if (_isInitialized) {
      _multiTaskDestroy();
      _isInitialized = false;
    }
    calloc.free(_persistentFrameResult);
    calloc.free(_persistentSegResult);
    calloc.free(_persistentPoseResult);
    calloc.free(_persistentClsResult);
    calloc.free(_persistentObbResult);
    calloc.free(_persistentOutputTensor);
    _instance = null;
  }

  static Future<Map<String, String>> _extractModelFiles({
    required String paramAsset,
    required String binAsset,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final modelsDir = Directory('${tempDir.path}/models');
    if (!modelsDir.existsSync()) {
      modelsDir.createSync(recursive: true);
    }

    final paramName = paramAsset.split('/').last;
    final binName = binAsset.split('/').last;

    final paramFile = File('${modelsDir.path}/$paramName');
    final binFile = File('${modelsDir.path}/$binName');

    if (!paramFile.existsSync()) {
      final paramData = await rootBundle.load(paramAsset);
      await paramFile.writeAsBytes(paramData.buffer.asUint8List(), flush: true);
    }

    if (!binFile.existsSync()) {
      final binData = await rootBundle.load(binAsset);
      await binFile.writeAsBytes(binData.buffer.asUint8List(), flush: true);
    }

    return {
      'param': paramFile.path,
      'bin': binFile.path,
    };
  }
}
