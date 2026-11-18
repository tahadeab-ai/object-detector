import 'package:flutter/foundation.dart';
import '../ffi/native_structs.dart';
import '../models/model_profile.dart';
import 'nihui_native_controller.dart';

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
      int modelId = 0;
      if (newProfile.nameEn.toLowerCase().contains('s')) {
        modelId = targetRes == 640 ? 7 : (targetRes == 480 ? 4 : 1);
      } else if (newProfile.nameEn.toLowerCase().contains('m')) {
        modelId = targetRes == 640 ? 8 : (targetRes == 480 ? 5 : 2);
      } else {
        modelId = targetRes == 640 ? 6 : (targetRes == 480 ? 3 : 0);
      }

      await NihuiNativeController.reloadModel(
        taskId: newProfile.task.id,
        modelId: modelId,
        cpuGpu: targetBackend,
      );

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
    await switchModel(_state.activeProfile, resolution: resolution);
  }

  /// Change active execution backend
  Future<void> setBackend(int backend) async {
    await switchModel(_state.activeProfile, backend: backend);
  }

}
