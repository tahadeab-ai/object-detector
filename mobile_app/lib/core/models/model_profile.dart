import '../ffi/native_structs.dart';

enum ModelFamily {
  nano('Nano', 'نانو (فائق الخفة)'),
  small('Small', 'صغير (متوازن)'),
  medium('Medium', 'متوسط (دقة أعلى)');

  final String labelEn;
  final String labelAr;
  const ModelFamily(this.labelEn, this.labelAr);
}

class ModelProfile {
  final String id;
  final String nameEn;
  final String nameAr;
  final String descriptionEn;
  final String descriptionAr;
  final VisionTask task;
  final ModelFamily family;
  final List<int> supportedResolutions;
  final int defaultResolution;
  final String paramAsset;
  final String binAsset;
  final String labelsAsset;
  final int classesCount;
  final bool isOriginalModel;

  const ModelProfile({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.descriptionEn,
    required this.descriptionAr,
    required this.task,
    required this.family,
    required this.supportedResolutions,
    required this.defaultResolution,
    required this.paramAsset,
    required this.binAsset,
    required this.labelsAsset,
    required this.classesCount,
    this.isOriginalModel = false,
  });

  /// Built-in catalog of validated models
  static const List<ModelProfile> catalog = [
    // 1. Original Primary Detection Model (PRESERVED)
    ModelProfile(
      id: 'yolo11_orig_det',
      nameEn: 'YOLO11 Original Detection',
      nameAr: 'نموذج الكشف الأصلي (مدرّب مسبقاً)',
      descriptionEn: 'Preserved primary trained detection model with 2-stage tracking',
      descriptionAr: 'نموذج الكشف الأساسي المعتمد مع خوارزمية التعقب الحركي الثنائية',
      task: VisionTask.detection,
      family: ModelFamily.nano,
      supportedResolutions: [320, 640],
      defaultResolution: 320,
      paramAsset: 'assets/models/model.ncnn.param',
      binAsset: 'assets/models/model.ncnn.bin',
      labelsAsset: 'assets/models/coco80_labels_ar_en.json',
      classesCount: 80,
      isOriginalModel: true,
    ),

    // 2. YOLO11 Nano Dynamic Detection
    ModelProfile(
      id: 'yolo11n_det_dyn',
      nameEn: 'YOLO11 Nano Detection (Dynamic)',
      nameAr: 'كشف الكائنات نانو (متعدد الأبعاد)',
      descriptionEn: 'Dynamic resolution anchor-free detection across 320/480/640',
      descriptionAr: 'كشف فائق السرعة يدعم تبديل الأبعاد التكيفي 320 و 480 و 640',
      task: VisionTask.detection,
      family: ModelFamily.nano,
      supportedResolutions: [320, 480, 640],
      defaultResolution: 320,
      paramAsset: 'assets/models/yolo11n.ncnn.param',
      binAsset: 'assets/models/yolo11n.ncnn.bin',
      labelsAsset: 'assets/models/coco80_labels_ar_en.json',
      classesCount: 80,
    ),

    // 3. YOLO11 Nano Instance Segmentation
    ModelProfile(
      id: 'yolo11n_seg',
      nameEn: 'YOLO11 Nano Segmentation',
      nameAr: 'التقطيع المقطعي نانو (أقنعة الكائنات)',
      descriptionEn: 'Pixel-level instance masks with NCNN GEMM prototype decoding',
      descriptionAr: 'توليد أقنعة دقيقة للكائنات باستخدام ضرب المصفوفات السريع GEMM',
      task: VisionTask.segmentation,
      family: ModelFamily.nano,
      supportedResolutions: [320, 480, 640],
      defaultResolution: 320,
      paramAsset: 'assets/models/yolo11n_seg.ncnn.param',
      binAsset: 'assets/models/yolo11n_seg.ncnn.bin',
      labelsAsset: 'assets/models/coco80_labels_ar_en.json',
      classesCount: 80,
    ),

    // 4. YOLO11 Nano Pose Estimation
    ModelProfile(
      id: 'yolo11n_pose',
      nameEn: 'YOLO11 Nano Pose Estimation',
      nameAr: 'تقدير وضعية الجسم (17 نقطة هيكلية)',
      descriptionEn: 'Full-body 17 COCO keypoints and 19-bone skeletal topology',
      descriptionAr: 'تتبع 17 نقطة مفصلية و 19 رابطاً هيكلياً لحركات ووضعيات الإنسان',
      task: VisionTask.pose,
      family: ModelFamily.nano,
      supportedResolutions: [320, 480, 640],
      defaultResolution: 320,
      paramAsset: 'assets/models/yolo11n_pose.ncnn.param',
      binAsset: 'assets/models/yolo11n_pose.ncnn.bin',
      labelsAsset: 'assets/models/pose17_keypoints_ar_en.json',
      classesCount: 1, // Person
    ),

    // 5. YOLO11 Nano Image Classification
    ModelProfile(
      id: 'yolo11n_cls',
      nameEn: 'YOLO11 Nano Classification',
      nameAr: 'تصنيف المشاهد والصور (Top-5)',
      descriptionEn: 'High-throughput 60 FPS scene classification over 1000 ImageNet categories',
      descriptionAr: 'تصنيف مباشر عالي السرعة بمعدل 60 إطاراً على 1000 صنف من ImageNet',
      task: VisionTask.classification,
      family: ModelFamily.nano,
      supportedResolutions: [224],
      defaultResolution: 224,
      paramAsset: 'assets/models/yolo11n_cls.ncnn.param',
      binAsset: 'assets/models/yolo11n_cls.ncnn.bin',
      labelsAsset: '',
      classesCount: 1000,
    ),

    // 6. YOLO11 Nano Oriented Bounding Box (OBB)
    ModelProfile(
      id: 'yolo11n_obb',
      nameEn: 'YOLO11 Nano OBB (Rotated Boxes)',
      nameAr: 'كشف الكائنات ذات الزوايا المائلة (DOTA)',
      descriptionEn: 'Rotated rectangle detection preserving orientation angles and heading',
      descriptionAr: 'رصد الكائنات متغيرة الزوايا والاتجاه مع تقدير زاوية الدوران بدقة',
      task: VisionTask.obb,
      family: ModelFamily.nano,
      supportedResolutions: [320, 480, 640],
      defaultResolution: 320,
      paramAsset: 'assets/models/yolo11n_obb.ncnn.param',
      binAsset: 'assets/models/yolo11n_obb.ncnn.bin',
      labelsAsset: 'assets/models/dota15_labels_ar_en.json',
      classesCount: 15,
    ),
  ];
}
