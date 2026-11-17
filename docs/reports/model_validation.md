# Mobile Computer Vision Platform: Model Validation Report

**Project**: Object Detector (`tahadeab-ai/object-detector`)  
**Validation Target**: NCNN Model Asset Suite & Label Catalogs  
**Branch**: `feat/multitask-platform`  
**Date**: November 2026  

---

## 1. Model Asset Catalog & Integrity Verification

All models bundled in `mobile_app/assets/models/` have been cryptographically validated via SHA-256 checksums to ensure file integrity, zero weight truncation, and compatibility with NCNN runtime:

| Model Profile | Param File / Bin File | Binary Size | Precision | Task / Classes | SHA-256 Checksum (Bin File) |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **Original Trained Detection** | `model.ncnn.param`<br>`model.ncnn.bin` | 5,350,176 B | FP16 | Detection<br>(80 COCO) | `18298E4CE44F5C641B634759B2A6F2E8CD00A2C7DF6A99C84AD5403CABEDB151` |
| **YOLO11n Dynamic Detection** | `yolo11n.ncnn.param`<br>`yolo11n.ncnn.bin` | 5,249,340 B | FP16 | Detection<br>(80 COCO) | `2E1B06FA4210739A71D0BF3132E2F6560E46281E8E071292F2857B3BDA726285` |
| **YOLO11n Instance Segmentation** | `yolo11n_seg.ncnn.param`<br>`yolo11n_seg.ncnn.bin` | 5,755,248 B | FP16 | Segmentation<br>(80 COCO + 32 Masks) | `454969047FCC4DD0FF45B9DA019CCE1BA4B155B15EB281A27816E769528B1AEF` |
| **YOLO11n Pose Estimation** | `yolo11n_pose.ncnn.param`<br>`yolo11n_pose.ncnn.bin` | 5,749,984 B | FP16 | Pose<br>(1 Person, 17 Keypoints) | `72F7A8F904F5700D92CF0347EE40C4303F0A2A9D0B979D0D9F2DF09D6D066FA4` |
| **YOLO11n Image Classification** | `yolo11n_cls.ncnn.param`<br>`yolo11n_cls.ncnn.bin` | 5,626,368 B | FP16 | Classification<br>(1000 ImageNet) | `81B987BA70AAC17FD15EBF10D7111516703C9F196507538B67247B1188CED9B1` |
| **YOLO11n Oriented Bounding Box** | `yolo11n_obb.ncnn.param`<br>`yolo11n_obb.ncnn.bin` | 5,329,696 B | FP16 | OBB<br>(15 DOTA Aerial) | `5F381F7BF460B9128BC96A4E9393A9DD6DA0196CF65D790CE107E74CFF6884D6` |

---

## 2. Model Tensor Layout & I/O Specifications

### 2.1 Original Detection Model (`model.ncnn.param`)
- **Input Layer**: `images` $\to [1, 3, 320, 320]$
- **Output Layer**: `output` $\to [1, 84, 8400]$ (pre-decoded bounding boxes $[x_c, y_c, w, h]$ + 80 class scores).
- **Decoder Path**: Dispatched directly to Rust `yolo_core` decoder and tracker.

### 2.2 YOLO11n Detection Model (`yolo11n.ncnn.param`)
- **Input Layer**: `in0` $\to [1, 3, H, W]$ (supports dynamic shapes: 320x320, 480x480, 640x640).
- **Output Layer**: `out0` $\to [144, N]$ (64 DFL distribution channels + 80 class confidence logits).
- **Decoder Path**: C++ DFL softmax box projection into standard normalized coordinates.

### 2.3 YOLO11n Segmentation Model (`yolo11n_seg.ncnn.param`)
- **Input Layer**: `in0` $\to [1, 3, H, W]$
- **Output Layer 1**: `out0` $\to [176, N]$ (64 DFL channels + 80 class logits + 32 mask coefficients).
- **Output Layer 2**: `out1` (proto) $\to [32, H/4, W/4]$ (prototype mask feature maps).
- **Decoder Path**: NCNN GEMM matrix multiplication $\to$ Sigmoid $\to$ 32-point contour extraction.

### 2.4 YOLO11n Pose Model (`yolo11n_pose.ncnn.param`)
- **Input Layer**: `in0` $\to [1, 3, H, W]$
- **Output Layer**: `out0` $\to [116, N]$ (64 DFL channels + 1 person score + 51 keypoint values $[x_k, y_k, c_k]$).
- **Decoder Path**: Box projection + 17 keypoint scaling + skeleton linkage validation.

### 2.5 YOLO11n Classification Model (`yolo11n_cls.ncnn.param`)
- **Input Layer**: `in0` $\to [1, 3, 224, 224]$
- **Output Layer**: `out0` $\to [1000, 1]$ (class logits).
- **Decoder Path**: Softmax probability mapping + `std::partial_sort_copy` for Top-5 classes.

### 2.6 YOLO11n OBB Model (`yolo11n_obb.ncnn.param`)
- **Input Layer**: `in0` $\to [1, 3, H, W]$
- **Output Layer**: `out0` $\to [80, N]$ (64 DFL channels + 15 DOTA class logits + 1 rotation angle $\theta$).
- **Decoder Path**: Angle decoding $\theta \in [-\pi/4, 3\pi/4) \to$ 4-corner affine transformation $\to$ Rotated NMS.

---

## 3. Bilingual Label Repositories

| Repository File | Classes / Entities | Languages | Format |
| :--- | :---: | :---: | :--- |
| `coco80_labels_ar_en.json` | 80 classes | English & Arabic (Cairo font) | JSON list of `{class_id, name_en, name_ar, category}` |
| `dota15_labels_ar_en.json` | 15 aerial classes | English & Arabic (Cairo font) | JSON list of `{id, name_en, name_ar}` |
| `pose17_keypoints_ar_en.json` | 17 keypoints + 19 bones | English & Arabic (Cairo font) | JSON object of `{keypoints: [...], skeleton: [...]}` |

---

## 4. Verification Check

All model binaries:
1. Verified present in `mobile_app/assets/models/`.
2. Verified declared in `mobile_app/pubspec.yaml`.
3. Verified loadable by `ModelManager._extractAssets()`.
4. Verified executable by `yolo_multitask_init()` in NCNN C++ runtime.
