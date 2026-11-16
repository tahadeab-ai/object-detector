import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class CocoClassInfo {
  final int classId;
  final String nameEn;
  final String nameAr;
  final String category;

  const CocoClassInfo({
    required this.classId,
    required this.nameEn,
    required this.nameAr,
    required this.category,
  });

  factory CocoClassInfo.fromJson(Map<String, dynamic> json) {
    return CocoClassInfo(
      classId: json['class_id'] as int,
      nameEn: json['name_en'] as String,
      nameAr: json['name_ar'] as String,
      category: (json['category'] as String?) ?? 'general',
    );
  }
}

class CocoLabelsRepository {
  static final CocoLabelsRepository _instance = CocoLabelsRepository._internal();
  factory CocoLabelsRepository() => _instance;
  CocoLabelsRepository._internal();

  final Map<int, CocoClassInfo> _classes = {};
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    if (_isLoaded) return;
    try {
      final jsonString =
          await rootBundle.loadString('assets/models/coco80_labels_ar_en.json');
      final List<dynamic> list = json.decode(jsonString) as List<dynamic>;
      for (final item in list) {
        final info = CocoClassInfo.fromJson(item as Map<String, dynamic>);
        _classes[info.classId] = info;
      }
      _isLoaded = true;
    } catch (e) {
      // Fallback default English label mapping if asset load fails
      for (int i = 0; i < 80; i++) {
        _classes[i] = CocoClassInfo(
          classId: i,
          nameEn: 'class_$i',
          nameAr: 'صنف_$i',
          category: 'general',
        );
      }
      _isLoaded = true;
    }
  }

  String getLabel(int classId, {required bool isArabic}) {
    final info = _classes[classId];
    if (info == null) {
      return isArabic ? 'غير معروف' : 'Unknown';
    }
    return isArabic ? info.nameAr : info.nameEn;
  }

  CocoClassInfo? getInfo(int classId) => _classes[classId];

  List<CocoClassInfo> getAllClasses() => _classes.values.toList();
}
