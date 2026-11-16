import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
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

/// High-level Dart wrapper around the native `libyolo_ncnn.so` engine.
class YoloNcnnEngine {
  static YoloNcnnEngine? _instance;
  late final DynamicLibrary _lib;

  late final _YoloEngineInitDart _init;
  late final _YoloEngineSetBackendDart _setBackend;
  late final _YoloEngineForwardYuv420Dart _forwardYuv420;
  late final _YoloEngineForwardRgbaDart _forwardRgba;
  late final _YoloEngineDestroyDart _destroy;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  YoloNcnnEngine._(DynamicLibrary lib) : _lib = lib {
    _init = _lib.lookupFunction<_YoloEngineInitC, _YoloEngineInitDart>('yolo_engine_init');
    _setBackend = _lib.lookupFunction<_YoloEngineSetBackendC, _YoloEngineSetBackendDart>('yolo_engine_set_backend');
    _forwardYuv420 = _lib.lookupFunction<_YoloEngineForwardYuv420C, _YoloEngineForwardYuv420Dart>('yolo_engine_forward_yuv420');
    _forwardRgba = _lib.lookupFunction<_YoloEngineForwardRgbaC, _YoloEngineForwardRgbaDart>('yolo_engine_forward_rgba');
    _destroy = _lib.lookupFunction<_YoloEngineDestroyC, _YoloEngineDestroyDart>('yolo_engine_destroy');
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
      throw UnsupportedError('Platform not supported for native YOLO NCNN engine');
    }

    _instance = YoloNcnnEngine._(lib);
    return _instance!;
  }

  /// Initialize model network graph and weights
  bool initModel({
    required String paramPath,
    required String binPath,
    bool useVulkan = false,
  }) {
    final paramPathPtr = paramPath.toNativeUtf8();
    final binPathPtr = binPath.toNativeUtf8();

    try {
      final ret = _init(paramPathPtr, binPathPtr, useVulkan ? 1 : 0);
      _isInitialized = (ret == 0);
      return _isInitialized;
    } finally {
      calloc.free(paramPathPtr);
      calloc.free(binPathPtr);
    }
  }

  /// Switch backend dynamically between ARM NEON CPU (0) and Vulkan GPU (1)
  int setBackend({required bool useVulkan}) {
    return _setBackend(useVulkan ? 1 : 0);
  }

  /// Process YUV420/NV21 camera frame with zero heap allocation
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
    required Pointer<YoloFrameResult> outResult,
  }) {
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
      outResult,
    );
  }

  /// Process RGBA frame buffer (e.g., benchmark sample images)
  int forwardRgba({
    required Pointer<Uint8> rgba,
    required int width,
    required int height,
    required int sensorOrientation,
    required Pointer<YoloFrameResult> outResult,
  }) {
    return _forwardRgba(
      rgba,
      width,
      height,
      sensorOrientation,
      outResult,
    );
  }

  /// Free native engine and GPU resources
  void destroy() {
    if (_isInitialized) {
      _destroy();
      _isInitialized = false;
    }
  }
}
