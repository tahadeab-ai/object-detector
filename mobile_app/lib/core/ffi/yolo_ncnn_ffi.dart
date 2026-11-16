import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'native_structs.dart';

// Native function typedefs
typedef _YoloEngineInitC = Int32 Function(
    Pointer<Utf8> paramPath, Pointer<Utf8> binPath, Int32 useVulkan);
typedef _YoloEngineInitDart = int Function(
    Pointer<Utf8> paramPath, Pointer<Utf8> binPath, int useVulkan);

typedef _YoloEngineSetBackendC = Int32 Function(Int32 useVulkan);
typedef _YoloEngineSetBackendDart = int Function(int useVulkan);

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

typedef _YoloEngineDestroyC = Void Function();
typedef _YoloEngineDestroyDart = void Function();

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
  late final DynamicLibrary _lib;

  late final _YoloEngineInitDart _init;
  late final _YoloEngineSetBackendDart _setBackend;
  late final _YoloEngineForwardYuv420Dart _forwardYuv420;
  late final _YoloEngineForwardRgbaDart _forwardRgba;
  late final _YoloEngineDestroyDart _destroy;

  // Persistent native frame result buffer (Allocated ONCE, zero heap allocation per frame)
  late final Pointer<YoloFrameResult> _persistentFrameResult;
  // Persistent output tensor buffer for 84 * 8400 floats = 705,600 floats (2,822,400 bytes)
  late final Pointer<Float> _persistentOutputTensor;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Pointer<YoloFrameResult> get persistentResultBuffer => _persistentFrameResult;
  Pointer<Float> get persistentTensorBuffer => _persistentOutputTensor;

  YoloNcnnEngine._(DynamicLibrary lib) : _lib = lib {
    enforceLayoutGate();

    _init = _lib.lookupFunction<_YoloEngineInitC, _YoloEngineInitDart>(
        'yolo_engine_init');
    _setBackend =
        _lib.lookupFunction<_YoloEngineSetBackendC, _YoloEngineSetBackendDart>(
            'yolo_engine_set_backend');
    _forwardYuv420 = _lib.lookupFunction<_YoloEngineForwardYuv420C,
        _YoloEngineForwardYuv420Dart>('yolo_engine_forward_yuv420');
    _forwardRgba = _lib.lookupFunction<_YoloEngineForwardRgbaC,
        _YoloEngineForwardRgbaDart>('yolo_engine_forward_rgba');
    _destroy = _lib.lookupFunction<_YoloEngineDestroyC, _YoloEngineDestroyDart>(
        'yolo_engine_destroy');

    // Allocate persistent buffers once
    _persistentFrameResult = calloc<YoloFrameResult>();
    _persistentOutputTensor = calloc<Float>(84 * 8400);
  }

  /// Singleton access or custom factory
  static YoloNcnnEngine getInstance({String? customLibPath}) {
    if (_instance != null) return _instance!;

    final DynamicLibrary lib;
    if (customLibPath != null) {
      lib = DynamicLibrary.open(customLibPath);
    } else if (Platform.isAndroid) {
      lib = DynamicLibrary.open('libyolo_ncnn.so');
    } else if (Platform.isWindows) {
      lib = DynamicLibrary.open('yolo_ncnn.dll');
    } else if (Platform.isLinux) {
      lib = DynamicLibrary.open('libyolo_ncnn.so');
    } else {
      throw UnsupportedError(
          'Platform not supported for native YOLO NCNN engine');
    }

    _instance = YoloNcnnEngine._(lib);
    return _instance!;
  }

  /// Extracts model assets from bundle to disk and validates metadata contract
  static Future<int> setupAndValidateModelAssets({
    required Function(String paramPath, String binPath) onReady,
  }) async {
    try {
      // 1. Validate metadata contract
      final metadataStr =
          await rootBundle.loadString('assets/models/model_metadata.json');
      final Map<String, dynamic> metadata =
          json.decode(metadataStr) as Map<String, dynamic>;

      final input = metadata['input'] as Map<String, dynamic>?;
      final output = metadata['output'] as Map<String, dynamic>?;

      if (input == null ||
          input['name'] != 'in0' ||
          input['shape']?[2] != 640 ||
          input['shape']?[3] != 640) {
        return YoloEngineErrors.metadataValidationFailed;
      }

      if (output == null ||
          output['name'] != 'out0' ||
          output['shape']?[1] != 84 ||
          output['shape']?[2] != 8400) {
        return YoloEngineErrors.metadataValidationFailed;
      }

      // 2. Extract model files to Application Support Directory
      final supportDir = await getApplicationSupportDirectory();
      final paramFile = File('${supportDir.path}/model.ncnn.param');
      final binFile = File('${supportDir.path}/model.ncnn.bin');

      if (!await paramFile.exists()) {
        final paramBytes =
            await rootBundle.load('assets/models/model.ncnn.param');
        await paramFile.writeAsBytes(paramBytes.buffer.asUint8List(),
            flush: true);
      }

      if (!await binFile.exists()) {
        final binBytes = await rootBundle.load('assets/models/model.ncnn.bin');
        await binFile.writeAsBytes(binBytes.buffer.asUint8List(), flush: true);
      }

      onReady(paramFile.path, binFile.path);
      return YoloEngineErrors.success;
    } catch (_) {
      return YoloEngineErrors.modelExtractionFailed;
    }
  }

  /// Initialize model network graph and weights
  int initModel({
    required String paramPath,
    required String binPath,
    bool useVulkan = false,
  }) {
    final paramPathPtr = paramPath.toNativeUtf8();
    final binPathPtr = binPath.toNativeUtf8();

    try {
      final ret = _init(paramPathPtr, binPathPtr, useVulkan ? 1 : 0);
      _isInitialized = (ret == 0);
      return _isInitialized
          ? YoloEngineErrors.success
          : YoloEngineErrors.nativeInitFailed;
    } finally {
      calloc.free(paramPathPtr);
      calloc.free(binPathPtr);
    }
  }

  /// Switch backend dynamically between ARM NEON CPU (0) and Vulkan GPU (1)
  int setBackend({required bool useVulkan}) {
    return _setBackend(useVulkan ? 1 : 0);
  }

  /// Process YUV420/NV21 camera frame with zero heap allocation per frame
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
    final targetResult = outResult ?? _persistentFrameResult;
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
      targetResult,
    );
  }

  /// Process RGBA frame buffer (e.g., benchmark sample images) with zero heap allocation
  int forwardRgba({
    required Pointer<Uint8> rgba,
    required int width,
    required int height,
    required int sensorOrientation,
    Pointer<YoloFrameResult>? outResult,
  }) {
    final targetResult = outResult ?? _persistentFrameResult;
    return _forwardRgba(
      rgba,
      width,
      height,
      sensorOrientation,
      targetResult,
    );
  }

  /// Free native engine, persistent buffers, and GPU resources
  void destroy() {
    if (_isInitialized) {
      _destroy();
      _isInitialized = false;
    }
    calloc.free(_persistentFrameResult);
    calloc.free(_persistentOutputTensor);
  }
}
