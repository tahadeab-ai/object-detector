import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../ffi/native_structs.dart';
import '../ffi/yolo_ncnn_ffi.dart';
import '../models/model_profile.dart';
import 'inference_worker.dart';

class ModelManagerState {
  final ModelProfile activeProfile;
  final int activeResolution;
  final int activeBackend; // 0=CPU, 1=Vulkan, 2=Turnip
  final bool isLoading;
  final String? errorMessage;

  const ModelManagerState({
    required this.activeProfile,
    required this.activeResolution,
    required this.activeBackend,
    this.isLoading = false,
    this.errorMessage,
  });

  ModelManagerState copyWith({
    ModelProfile? activeProfile,
    int? activeResolution,
    int? activeBackend,
    bool? isLoading,
    String? errorMessage,
  }) {
    return ModelManagerState(
      activeProfile: activeProfile ?? this.activeProfile,
      activeResolution: activeResolution ?? this.activeResolution,
      activeBackend: activeBackend ?? this.activeBackend,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class ModelManager extends ChangeNotifier {
  static final ModelManager _instance = ModelManager._internal();
  factory ModelManager() => _instance;
  ModelManager._internal();

  ModelManagerState _state = ModelManagerState(
    activeProfile: ModelProfile.catalog.first, // Original Detection
    activeResolution: ModelProfile.catalog.first.defaultResolution,
    activeBackend: 0, // CPU NEON 4-Thread default
  );

  ModelManagerState get state => _state;
  ModelProfile get activeProfile => _state.activeProfile;
  VisionTask get activeTask => _state.activeProfile.task;
  int get activeResolution => _state.activeResolution;
  int get activeBackend => _state.activeBackend;
  bool get isLoading => _state.isLoading;

  /// Switch model profile with memory-safe unload and re-init
  Future<bool> switchModel(
    ModelProfile newProfile, {
    int? resolution,
    int? backend,
  }) async {
    final targetRes = resolution ?? newProfile.defaultResolution;
    final targetBackend = backend ?? _state.activeBackend;

    _state = _state.copyWith(isLoading: true, errorMessage: null);
    notifyListeners();

    try {
      debugPrint('[ModelManager] Extracting assets for ${newProfile.nameEn}...');
      final paths = await _extractAssets(newProfile);

      debugPrint('[ModelManager] Initializing native engine for task: ${newProfile.task.labelEn} at ${targetRes}x$targetRes...');
      final worker = InferenceWorker();
      if (worker.isReady) {
        await worker.switchModelInIsolate(
          taskId: newProfile.task.id,
          paramPath: paths['param']!,
          binPath: paths['bin']!,
          targetSize: targetRes,
          backend: targetBackend,
        );
      }

      final engine = YoloNcnnEngine.getInstance();
      final ret = engine.initMultiTask(
        task: newProfile.task,
        paramPath: paths['param']!,
        binPath: paths['bin']!,
        targetSize: targetRes,
        backend: targetBackend,
      );

      if (ret != 0) {
        throw StateError('Native multi-task init failed with code $ret');
      }

      _state = _state.copyWith(
        activeProfile: newProfile,
        activeResolution: targetRes,
        activeBackend: targetBackend,
        isLoading: false,
      );
      notifyListeners();
      debugPrint('[ModelManager] Model switched successfully to ${newProfile.nameEn}');
      return true;
    } catch (e, stack) {
      debugPrint('[ModelManager] Error switching model: $e\n$stack');
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      notifyListeners();
      return false;
    }
  }

  /// Change active input resolution
  Future<void> setResolution(int resolution) async {
    if (!_state.activeProfile.supportedResolutions.contains(resolution)) {
      debugPrint('[ModelManager] Resolution $resolution not supported by active profile');
      return;
    }

    final engine = YoloNcnnEngine.getInstance();
    engine.setTargetSize(resolution);
    _state = _state.copyWith(activeResolution: resolution);
    notifyListeners();
  }

  /// Change active execution backend
  Future<void> setBackend(int backend) async {
    final engine = YoloNcnnEngine.getInstance();
    final actual = engine.setBackend(backend: backend);
    _state = _state.copyWith(activeBackend: actual);
    notifyListeners();
  }

  /// Extracts assets to temporary cache on demand
  Future<Map<String, String>> _extractAssets(ModelProfile profile) async {
    final tempDir = await getTemporaryDirectory();
    final modelsDir = Directory('${tempDir.path}/models');
    if (!modelsDir.existsSync()) {
      modelsDir.createSync(recursive: true);
    }

    final paramName = profile.paramAsset.split('/').last;
    final binName = profile.binAsset.split('/').last;

    final paramFile = File('${modelsDir.path}/$paramName');
    final binFile = File('${modelsDir.path}/$binName');

    final paramData = await rootBundle.load(profile.paramAsset);
    await paramFile.writeAsBytes(paramData.buffer.asUint8List(), flush: true);

    final binData = await rootBundle.load(profile.binAsset);
    await binFile.writeAsBytes(binData.buffer.asUint8List(), flush: true);

    return {
      'param': paramFile.path,
      'bin': binFile.path,
    };
  }
}
