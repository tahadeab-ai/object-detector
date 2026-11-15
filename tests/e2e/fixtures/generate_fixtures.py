"""
Generate test fixtures for YOLO NCNN E2E test suite.
"""
import json
import struct
import numpy as np
from pathlib import Path

FIXTURES_DIR = Path(r"C:\dev\object-detector\tests\e2e\fixtures")
TENSORS_DIR = FIXTURES_DIR / "tensors"
METADATA_DIR = FIXTURES_DIR / "metadata"
LABELS_DIR = FIXTURES_DIR / "labels"
IMAGES_DIR = FIXTURES_DIR / "images"

for d in [TENSORS_DIR, METADATA_DIR, LABELS_DIR, IMAGES_DIR]:
    d.mkdir(parents=True, exist_ok=True)

# 1. Tensors
# Shape [84, 8400] row-major FP32
# Rows 0: cx, 1: cy, 2: w, 3: h (in 0..640 or normalized)
# Rows 4..83: 80 class scores
np.random.seed(42)

# Valid tensor
valid_tensor = np.zeros((84, 8400), dtype=np.float32)
# Background noise
valid_tensor[4:, :] = np.random.uniform(0.0001, 0.05, size=(80, 8400)).astype(np.float32)

# Detection 1: Person (class 0) at col 100
valid_tensor[0, 100] = 320.0  # cx
valid_tensor[1, 100] = 320.0  # cy
valid_tensor[2, 100] = 120.0  # w
valid_tensor[3, 100] = 240.0  # h
valid_tensor[4 + 0, 100] = 0.92  # person score

# Detection 2: Car (class 2) at col 500
valid_tensor[0, 500] = 150.0  # cx
valid_tensor[1, 500] = 400.0  # cy
valid_tensor[2, 500] = 180.0  # w
valid_tensor[3, 500] = 100.0  # h
valid_tensor[4 + 2, 500] = 0.88  # car score

# Detection 3: Dog (class 16) at col 2000
valid_tensor[0, 2000] = 500.0
valid_tensor[1, 2000] = 450.0
valid_tensor[2, 2000] = 80.0
valid_tensor[3, 2000] = 70.0
valid_tensor[4 + 16, 2000] = 0.81  # dog score

# Save valid tensor
valid_tensor.tofile(TENSORS_DIR / "valid_output_1_84_8400.bin")

# Corrupted NaN/Inf tensor
corrupted_tensor = valid_tensor.copy()
corrupted_tensor[0, 10] = np.nan
corrupted_tensor[1, 20] = np.inf
corrupted_tensor[4, 30] = -np.inf
corrupted_tensor.tofile(TENSORS_DIR / "corrupted_nan_inf.bin")

# Empty zero tensor
zero_tensor = np.zeros((84, 8400), dtype=np.float32)
zero_tensor.tofile(TENSORS_DIR / "empty_zero_tensor.bin")

# Malformed shape [80, 8400]
malformed_tensor = np.zeros((80, 8400), dtype=np.float32)
malformed_tensor.tofile(TENSORS_DIR / "malformed_shape_80_8400.bin")

print(f"Generated tensors in {TENSORS_DIR}")

# 2. Metadata JSONs
valid_meta = {
    "model_name": "yolo11n",
    "format": "ncnn-fp16",
    "input": {
        "name": "in0",
        "shape": [1, 3, 640, 640],
        "dtype": "float32"
    },
    "output": {
        "name": "out0",
        "shape": [1, 84, 8400],
        "dtype": "float32",
        "layout": "row-major"
    },
    "classes": 80,
    "confidence_threshold": 0.25,
    "iou_threshold": 0.45,
    "export_platform": "colab-pnnx",
    "weights_sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
}

invalid_blob_meta = valid_meta.copy()
invalid_blob_meta["input"] = {"name": "input_blob", "shape": [1, 3, 640, 640], "dtype": "float32"}
invalid_blob_meta["output"] = {"name": "output_blob", "shape": [1, 84, 8400], "dtype": "float32", "layout": "row-major"}

corrupted_dims_meta = valid_meta.copy()
corrupted_dims_meta["input"] = {"name": "in0", "shape": [1, 3, 480, 640], "dtype": "float32"}
corrupted_dims_meta["output"] = {"name": "out0", "shape": [1, 80, 8400], "dtype": "float32", "layout": "row-major"}

with open(METADATA_DIR / "valid_model_metadata.json", "w", encoding="utf-8") as f:
    json.dump(valid_meta, f, indent=2)

with open(METADATA_DIR / "invalid_blob_metadata.json", "w", encoding="utf-8") as f:
    json.dump(invalid_blob_meta, f, indent=2)

with open(METADATA_DIR / "corrupted_dims_metadata.json", "w", encoding="utf-8") as f:
    json.dump(corrupted_dims_meta, f, indent=2)

print(f"Generated metadata in {METADATA_DIR}")

# 3. Bilingual COCO 80 Labels JSON
coco_labels = [
    {"id": 0, "name_en": "person", "name_ar": "شخص"},
    {"id": 1, "name_en": "bicycle", "name_ar": "دراجة هوائية"},
    {"id": 2, "name_en": "car", "name_ar": "سيارة"},
    {"id": 3, "name_en": "motorcycle", "name_ar": "دراجة نارية"},
    {"id": 4, "name_en": "airplane", "name_ar": "طائرة"},
    {"id": 5, "name_en": "bus", "name_ar": "حافلة"},
    {"id": 6, "name_en": "train", "name_ar": "قطار"},
    {"id": 7, "name_en": "truck", "name_ar": "شاحنة"},
    {"id": 8, "name_en": "boat", "name_ar": "قارب"},
    {"id": 9, "name_en": "traffic light", "name_ar": "إشارة مرور"},
    {"id": 10, "name_en": "fire hydrant", "name_ar": "صنبور إطفاء"},
    {"id": 11, "name_en": "stop sign", "name_ar": "علامة توقف"},
    {"id": 12, "name_en": "parking meter", "name_ar": "عداد مواقف"},
    {"id": 13, "name_en": "bench", "name_ar": "مقعد"},
    {"id": 14, "name_en": "bird", "name_ar": "طائر"},
    {"id": 15, "name_en": "cat", "name_ar": "قطة"},
    {"id": 16, "name_en": "dog", "name_ar": "كلب"},
    {"id": 17, "name_en": "horse", "name_ar": "حصان"},
    {"id": 18, "name_en": "sheep", "name_ar": "خروف"},
    {"id": 19, "name_en": "cow", "name_ar": "بقرة"},
    {"id": 20, "name_en": "elephant", "name_ar": "فيل"},
    {"id": 21, "name_en": "bear", "name_ar": "دب"},
    {"id": 22, "name_en": "zebra", "name_ar": "حمار وحشي"},
    {"id": 23, "name_en": "giraffe", "name_ar": "زرافة"},
    {"id": 24, "name_en": "backpack", "name_ar": "حقيبة ظهر"},
    {"id": 25, "name_en": "umbrella", "name_ar": "مظلة"},
    {"id": 26, "name_en": "handbag", "name_ar": "حقيبة يد"},
    {"id": 27, "name_en": "tie", "name_ar": "ربطة عنق"},
    {"id": 28, "name_en": "suitcase", "name_ar": "حقيبة سفر"},
    {"id": 29, "name_en": "frisbee", "name_ar": "قرص طائر"},
    {"id": 30, "name_en": "skis", "name_ar": "زلاجات"},
    {"id": 31, "name_en": "snowboard", "name_ar": "لوح تزلج"},
    {"id": 32, "name_en": "sports ball", "name_ar": "كرة رياضية"},
    {"id": 33, "name_en": "kite", "name_ar": "طائرة ورقية"},
    {"id": 34, "name_en": "baseball bat", "name_ar": "مضرب بيسبول"},
    {"id": 35, "name_en": "baseball glove", "name_ar": "قفاز بيسبول"},
    {"id": 36, "name_en": "skateboard", "name_ar": "لوح تزلج"},
    {"id": 37, "name_en": "surfboard", "name_ar": "لوح ركوب الأمواج"},
    {"id": 38, "name_en": "tennis racket", "name_ar": "مضرب تنس"},
    {"id": 39, "name_en": "bottle", "name_ar": "زجاجة"},
    {"id": 40, "name_en": "wine glass", "name_ar": "كأس"},
    {"id": 41, "name_en": "cup", "name_ar": "كوب"},
    {"id": 42, "name_en": "fork", "name_ar": "شوكة"},
    {"id": 43, "name_en": "knife", "name_ar": "سكين"},
    {"id": 44, "name_en": "spoon", "name_ar": "ملعقة"},
    {"id": 45, "name_en": "bowl", "name_ar": "وعاء"},
    {"id": 46, "name_en": "banana", "name_ar": "موز"},
    {"id": 47, "name_en": "apple", "name_ar": "تفاح"},
    {"id": 48, "name_en": "sandwich", "name_ar": "شطيرة"},
    {"id": 49, "name_en": "orange", "name_ar": "برتقال"},
    {"id": 50, "name_en": "broccoli", "name_ar": "بروكلي"},
    {"id": 51, "name_en": "carrot", "name_ar": "جزر"},
    {"id": 52, "name_en": "hot dog", "name_ar": "هوت دوغ"},
    {"id": 53, "name_en": "pizza", "name_ar": "بيتزا"},
    {"id": 54, "name_en": "donut", "name_ar": "دونات"},
    {"id": 55, "name_en": "cake", "name_ar": "كعكة"},
    {"id": 56, "name_en": "chair", "name_ar": "كرسي"},
    {"id": 57, "name_en": "couch", "name_ar": "أريكة"},
    {"id": 58, "name_en": "potted plant", "name_ar": "نبتة في وعاء"},
    {"id": 59, "name_en": "bed", "name_ar": "سرير"},
    {"id": 60, "name_en": "dining table", "name_ar": "طاولة طعام"},
    {"id": 61, "name_en": "toilet", "name_ar": "مرحاض"},
    {"id": 62, "name_en": "tv", "name_ar": "تلفزيون"},
    {"id": 63, "name_en": "laptop", "name_ar": "حاسوب محمول"},
    {"id": 64, "name_en": "mouse", "name_ar": "فأرة"},
    {"id": 65, "name_en": "remote", "name_ar": "جهاز تحكم"},
    {"id": 66, "name_en": "keyboard", "name_ar": "لوحة مفاتيح"},
    {"id": 67, "name_en": "cell phone", "name_ar": "هاتف محمول"},
    {"id": 68, "name_en": "microwave", "name_ar": "ميكروويف"},
    {"id": 69, "name_en": "oven", "name_ar": "فرن"},
    {"id": 70, "name_en": "toaster", "name_ar": "محمصة"},
    {"id": 71, "name_en": "sink", "name_ar": "مغسلة"},
    {"id": 72, "name_en": "refrigerator", "name_ar": "ثلاجة"},
    {"id": 73, "name_en": "book", "name_ar": "كتاب"},
    {"id": 74, "name_en": "clock", "name_ar": "ساعة"},
    {"id": 75, "name_en": "vase", "name_ar": "مزهرية"},
    {"id": 76, "name_en": "scissors", "name_ar": "مقص"},
    {"id": 77, "name_en": "teddy bear", "name_ar": "دب لعبة"},
    {"id": 78, "name_en": "hair drier", "name_ar": "مجفف شعر"},
    {"id": 79, "name_en": "toothbrush", "name_ar": "فرشاة أسنان"}
]

with open(LABELS_DIR / "valid_coco80_labels.json", "w", encoding="utf-8") as f:
    json.dump(coco_labels, f, ensure_ascii=False, indent=2)

print(f"Generated {len(coco_labels)} labels in {LABELS_DIR}")

# 4. Authentic JPEG files
# Minimal valid 1x1 or small JPEG byte sequence
# Standard JPEG structure: SOI (FF D8), DQT (FF DB), SOF0 (FF C0), DHT (FF C4), SOS (FF DA), data, EOI (FF D9)
def create_valid_jpeg(filename, width=640, height=480):
    # A genuine valid baseline JPEG binary representation
    # 1x1 pixel red JPEG baseline stream
    raw_jpeg = bytes.fromhex(
        "ffd8ffe000104a46494600010101004800480000ffdb00430008060607060508070707"
        "0909080a0c140d0c0b0b0c1912130f141d1a1f1e1d1a1c1c20242e2720222c231c1c28"
        "37292c30313434341f27393d38323c2e333432ffdb0043010909090c0b0c180d0d1832"
        "211c213232323232323232323232323232323232323232323232323232323232323232"
        "32323232323232323232323232323232323232ffc00011080001000103012200021101"
        "031101ffc4001f0000010501010101010100000000000000000102030405060708090a"
        "0bffc400b5100002010303020403050504040000017d01020300041105122131410613"
        "516107227114328191a1082342b1c11552d1f02433627282090a161718191a25262728"
        "292a3435363738393a434445464748494a535455565758595a636465666768696a7374"
        "75767778797a838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4"
        "b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae1e2e3e4e5e6e7e8e9eaf1"
        "f2f3f4f5f6f7f8f9faffc4001f01000301010101010101010100000000000001020304"
        "05060708090a0bffc400b5110002010204040304070504040001027700010203110405"
        "2131061241510761711322328108144291a1b1c109233352f0156272d10a162434e125"
        "f11718191a262728292a35363738393a434445464748494a535455565758595a636465"
        "666768696a737475767778797a82838485868788898a92939495969798999aa2a3a4a5"
        "a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9cad2d3d4d5d6d7d8d9dae2e3e4"
        "e5e6e7e8e9eaf2f3f4f5f6f7f8f9faffda000c03010002110311003f00bf7fd9"
    )
    with open(filename, "wb") as f:
        f.write(raw_jpeg)

create_valid_jpeg(IMAGES_DIR / "test_street.jpg")
create_valid_jpeg(IMAGES_DIR / "test_workspace.jpg")
create_valid_jpeg(IMAGES_DIR / "test_retail.jpg")

print(f"Generated images in {IMAGES_DIR}")
