import 'package:flutter/services.dart';

enum NihuiTask {
  coco(0, 'Detection', 'كشف الكائنات'),
  seg(1, 'Segmentation', 'التقطيع المقطعي'),
  pose(2, 'Pose', 'تقدير الوضعية'),
  cls(3, 'Classification', 'تصنيف الصور'),
  obb(4, 'OBB', 'الصناديق المائلة');

  final int id;
  final String labelEn;
  final String labelAr;
  const NihuiTask(this.id, this.labelEn, this.labelAr);
}

enum NihuiModel {
  n320(0, 'n-320'),
  s320(1, 's-320'),
  m320(2, 'm-320'),
  n480(3, 'n-480'),
  s480(4, 's-480'),
  m480(5, 'm-480'),
  n640(6, 'n-640'),
  s640(7, 's-640'),
  m640(8, 'm-640');

  final int id;
  final String label;
  const NihuiModel(this.id, this.label);
}

enum NihuiBackend {
  cpu(0, 'CPU', 'معالج CPU'),
  gpu(1, 'GPU', 'معالج GPU'),
  turnip(2, 'Turnip', 'محرّك تيرنب');

  final int id;
  final String labelEn;
  final String labelAr;
  const NihuiBackend(this.id, this.labelEn, this.labelAr);
}

class NihuiNativeController {
  static const MethodChannel _channel = MethodChannel('com.taha.yoloncnn/nihui_control');

  static Future<bool> reloadModel({
    required int taskId,
    required int modelId,
    required int cpuGpu,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>('reloadModel', {
        'taskid': taskId,
        'modelid': modelId,
        'cpugpu': cpuGpu,
      });
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<int> switchCamera() async {
    try {
      final res = await _channel.invokeMethod<int>('switchCamera');
      return res ?? 1;
    } catch (e) {
      return 1;
    }
  }

  static Future<bool> setPaused(bool paused) async {
    try {
      final res = await _channel.invokeMethod<bool>('setPaused', {
        'paused': paused,
      });
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> setMediaMode(bool enabled) async {
    try {
      final res = await _channel.invokeMethod<bool>('setMediaMode', {
        'enabled': enabled,
      });
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> feedPhoto({
    required String path,
    required bool isAsset,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>('feedPhoto', {
        'path': path,
        'isAsset': isAsset,
      });
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> startVideo({
    required String path,
    required bool isAsset,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>('startVideo', {
        'path': path,
        'isAsset': isAsset,
      });
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> stopVideo() async {
    try {
      final res = await _channel.invokeMethod<bool>('stopVideo');
      return res ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> pickMedia(String type) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('pickMedia', {
        'type': type,
      });
      return res;
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getState() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getState');
      return res;
    } catch (e) {
      return null;
    }
  }
}
