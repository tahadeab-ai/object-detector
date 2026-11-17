import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../ffi/native_structs.dart';

class LabelItem {
  final int id;
  final String nameEn;
  final String nameAr;
  final String category;

  const LabelItem({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    this.category = 'general',
  });
}

class KeypointInfo {
  final int id;
  final String nameEn;
  final String nameAr;

  const KeypointInfo({
    required this.id,
    required this.nameEn,
    required this.nameAr,
  });
}

class SkeletonBone {
  final int startJoint;
  final int endJoint;

  const SkeletonBone(this.startJoint, this.endJoint);
}

class MultiTaskLabelsRepository {
  static final MultiTaskLabelsRepository _instance =
      MultiTaskLabelsRepository._internal();
  factory MultiTaskLabelsRepository() => _instance;
  MultiTaskLabelsRepository._internal();

  final Map<int, LabelItem> _cocoClasses = {};
  final Map<int, LabelItem> _dotaClasses = {};
  final Map<int, KeypointInfo> _keypoints = {};
  final List<SkeletonBone> _skeleton = [];

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  List<SkeletonBone> get skeleton => List.unmodifiable(_skeleton);

  Future<void> load() async {
    if (_isLoaded) return;

    // 1. Load COCO 80
    try {
      final jsonString =
          await rootBundle.loadString('assets/models/coco80_labels_ar_en.json');
      final List<dynamic> list = json.decode(jsonString) as List<dynamic>;
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        _cocoClasses[map['class_id'] as int] = LabelItem(
          id: map['class_id'] as int,
          nameEn: map['name_en'] as String,
          nameAr: map['name_ar'] as String,
          category: (map['category'] as String?) ?? 'general',
        );
      }
    } catch (_) {
      for (int i = 0; i < 80; i++) {
        _cocoClasses[i] = LabelItem(
          id: i,
          nameEn: 'object_$i',
          nameAr: 'هدف_$i',
        );
      }
    }

    // 2. Load DOTA 15
    try {
      final jsonString =
          await rootBundle.loadString('assets/models/dota15_labels_ar_en.json');
      final List<dynamic> list = json.decode(jsonString) as List<dynamic>;
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        _dotaClasses[map['id'] as int] = LabelItem(
          id: map['id'] as int,
          nameEn: map['name_en'] as String,
          nameAr: map['name_ar'] as String,
          category: 'aerial',
        );
      }
    } catch (_) {
      for (int i = 0; i < 15; i++) {
        _dotaClasses[i] = LabelItem(
          id: i,
          nameEn: 'dota_$i',
          nameAr: 'هدف_دوران_$i',
        );
      }
    }

    // 3. Load Pose 17 Keypoints and Skeleton
    try {
      final jsonString = await rootBundle
          .loadString('assets/models/pose17_keypoints_ar_en.json');
      final Map<String, dynamic> data =
          json.decode(jsonString) as Map<String, dynamic>;
      final kps = data['keypoints'] as List<dynamic>;
      for (final k in kps) {
        final map = k as Map<String, dynamic>;
        _keypoints[map['id'] as int] = KeypointInfo(
          id: map['id'] as int,
          nameEn: map['name_en'] as String,
          nameAr: map['name_ar'] as String,
        );
      }
      final sk = data['skeleton'] as List<dynamic>;
      _skeleton.clear();
      for (final pair in sk) {
        final p = pair as List<dynamic>;
        _skeleton.add(SkeletonBone(p[0] as int, p[1] as int));
      }
    } catch (_) {
      _skeleton.clear();
      _skeleton.addAll(const [
        SkeletonBone(15, 13),
        SkeletonBone(13, 11),
        SkeletonBone(16, 14),
        SkeletonBone(14, 12),
        SkeletonBone(11, 12),
        SkeletonBone(5, 11),
        SkeletonBone(6, 12),
        SkeletonBone(5, 6),
        SkeletonBone(5, 7),
        SkeletonBone(6, 8),
        SkeletonBone(7, 9),
        SkeletonBone(8, 10),
        SkeletonBone(1, 2),
        SkeletonBone(0, 1),
        SkeletonBone(0, 2),
        SkeletonBone(1, 3),
        SkeletonBone(2, 4),
        SkeletonBone(3, 5),
        SkeletonBone(4, 6),
      ]);
    }

    _isLoaded = true;
  }

  String getLabelForTask({
    required VisionTask task,
    required int classId,
    required bool isArabic,
  }) {
    switch (task) {
      case VisionTask.detection:
      case VisionTask.segmentation:
        final info = _cocoClasses[classId];
        if (info != null) return isArabic ? info.nameAr : info.nameEn;
        return isArabic ? 'صنف $classId' : 'Class $classId';

      case VisionTask.pose:
        return isArabic ? 'شخص' : 'person';

      case VisionTask.obb:
        final info = _dotaClasses[classId];
        if (info != null) return isArabic ? info.nameAr : info.nameEn;
        return isArabic ? 'هدف $classId' : 'Target $classId';

      case VisionTask.classification:
        return isArabic ? 'فئة #$classId' : 'Class #$classId';
    }
  }

  String getKeypointLabel(int jointId, {required bool isArabic}) {
    final kp = _keypoints[jointId];
    if (kp != null) return isArabic ? kp.nameAr : kp.nameEn;
    return isArabic ? 'مفصل $jointId' : 'Joint $jointId';
  }
}
