import json
import os

assets_models = os.path.join("mobile_app", "assets", "models")

# 1. DOTA 15 classes for OBB
dota15 = [
    {"id": 0, "name_en": "plane", "name_ar": "طائرة"},
    {"id": 1, "name_en": "baseball diamond", "name_ar": "ملعب بيسبول"},
    {"id": 2, "name_en": "bridge", "name_ar": "جسر"},
    {"id": 3, "name_en": "ground track field", "name_ar": "مضمار سباق"},
    {"id": 4, "name_en": "small vehicle", "name_ar": "مركبة صغيرة"},
    {"id": 5, "name_en": "large vehicle", "name_ar": "مركبة كبيرة"},
    {"id": 6, "name_en": "ship", "name_ar": "سفينة"},
    {"id": 7, "name_en": "tennis court", "name_ar": "ملعب تنس"},
    {"id": 8, "name_en": "basketball court", "name_ar": "ملعب كرة سلة"},
    {"id": 9, "name_en": "storage tank", "name_ar": "خزان تخزين"},
    {"id": 10, "name_en": "soccer ball field", "name_ar": "ملعب كرة قدم"},
    {"id": 11, "name_en": "roundabout", "name_ar": "دوار مروري"},
    {"id": 12, "name_en": "harbor", "name_ar": "ميناء"},
    {"id": 13, "name_en": "swimming pool", "name_ar": "مسبح"},
    {"id": 14, "name_en": "helicopter", "name_ar": "مروحية"},
]

with open(os.path.join(assets_models, "dota15_labels_ar_en.json"), "w", encoding="utf-8") as f:
    json.dump(dota15, f, ensure_ascii=False, indent=2)

# 2. Pose 17 Keypoints and Skeleton Connections
pose17 = {
    "keypoints": [
        {"id": 0, "name_en": "nose", "name_ar": "الأنف"},
        {"id": 1, "name_en": "left eye", "name_ar": "العين اليسرى"},
        {"id": 2, "name_en": "right eye", "name_ar": "العين اليمنى"},
        {"id": 3, "name_en": "left ear", "name_ar": "الأذن اليسرى"},
        {"id": 4, "name_en": "right ear", "name_ar": "الأذن اليمنى"},
        {"id": 5, "name_en": "left shoulder", "name_ar": "الكتف الأيسر"},
        {"id": 6, "name_en": "right shoulder", "name_ar": "الكتف الأيمن"},
        {"id": 7, "name_en": "left elbow", "name_ar": "المرفق الأيسر"},
        {"id": 8, "name_en": "right elbow", "name_ar": "المرفق الأيمن"},
        {"id": 9, "name_en": "left wrist", "name_ar": "المعصم الأيسر"},
        {"id": 10, "name_en": "right wrist", "name_ar": "المعصم الأيمن"},
        {"id": 11, "name_en": "left hip", "name_ar": "الورك الأيسر"},
        {"id": 12, "name_en": "right hip", "name_ar": "الورك الأيمن"},
        {"id": 13, "name_en": "left knee", "name_ar": "الركبة اليسرى"},
        {"id": 14, "name_en": "right knee", "name_ar": "الركبة اليمنى"},
        {"id": 15, "name_en": "left ankle", "name_ar": "الكاحل الأيسر"},
        {"id": 16, "name_en": "right ankle", "name_ar": "الكاحل الأيمن"}
    ],
    "skeleton": [
        [15, 13], [13, 11], [16, 14], [14, 12], [11, 12],
        [5, 11], [6, 12], [5, 6], [5, 7], [6, 8],
        [7, 9], [8, 10], [1, 2], [0, 1], [0, 2],
        [1, 3], [2, 4], [3, 5], [4, 6]
    ]
}

with open(os.path.join(assets_models, "pose17_keypoints_ar_en.json"), "w", encoding="utf-8") as f:
    json.dump(pose17, f, ensure_ascii=False, indent=2)

print("Created DOTA 15 and Pose 17 label files successfully.")
