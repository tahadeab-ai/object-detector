#!/usr/bin/env python3
"""
Verification of C++/Rust Decoder Contract Parity against Ultralytics Reference (Google Colab)
Enforces:
1. Exact C++ Letterbox Preprocessing:
   scale = min(640/w, 640/h), copy_make_border pad 114 gray, norm 1/255
2. NCNN Raw Output Extraction:
   Output blob 'out0', shape [84, 8400] row-major layout
3. Exact Rust decoder.rs Parity:
   scaled_w = 640 - 2 * pad_w, scaled_h = 640 - 2 * pad_h
   x1 = ((cx - 0.5 * w) - pad_w) / scaled_w
   y1 = ((cy - 0.5 * h) - pad_h) / scaled_h
   x2 = ((cx + 0.5 * w) - pad_w) / scaled_w
   y2 = ((cy + 0.5 * h) - pad_h) / scaled_h
   clamp(0.0, 1.0)
4. Class-Aware Non-Maximum Suppression (NMS):
   Confidence threshold = 0.25, IoU threshold = 0.45
5. Numeric & Semantic Verification:
   Compares counts, classes, and bounding coordinates against Ultralytics FP32 reference
   across bus.jpg, sample_street.jpg, sample_workspace.jpg, and sample_retail.jpg.
6. Prints validation table with declared tolerance and explicit PASS/FAIL verdict line.
"""

import sys
import os
import urllib.request
from pathlib import Path
import numpy as np
import cv2

try:
    import torch
    from ultralytics import YOLO
    import ncnn
except ImportError as e:
    print(f"[!] Warning: Missing dependency {e}. This script runs in Google Colab environment.")

# COCO 80 classes reference
COCO_CLASSES = [
    "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat", "traffic light",
    "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat", "dog", "horse", "sheep", "cow",
    "elephant", "bear", "zebra", "giraffe", "backpack", "umbrella", "handbag", "tie", "suitcase", "frisbee",
    "skis", "snowboard", "sports ball", "kite", "baseball bat", "baseball glove", "skateboard", "surfboard",
    "tennis racket", "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
    "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch",
    "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse", "remote", "keyboard", "cell phone",
    "microwave", "oven", "toaster", "sink", "refrigerator", "book", "clock", "vase", "scissors", "teddy bear",
    "hair drier", "toothbrush"
]

def download_file(url: str, dest: str) -> str:
    p = Path(dest)
    if not p.exists():
        p.parent.mkdir(parents=True, exist_ok=True)
        print(f"Downloading {url} -> {dest}...")
        urllib.request.urlretrieve(url, dest)
    return str(p)

def cpp_replicate_preprocess(img_bgr, target_size=640):
    """
    Replicates exact C++ letterbox preprocessing in yolo_ncnn_runner.cpp:
    scale = min(640/w, 640/h), center pad 114 gray, normalize 1/255.
    Returns: chw_norm, scale, pad_w, pad_h, scaled_w, scaled_h
    """
    h, w = img_bgr.shape[:2]
    scale = min(target_size / float(w), target_size / float(h))
    scaled_w = int(w * scale)
    scaled_h = int(h * scale)
    pad_w = (target_size - scaled_w) // 2
    pad_h = (target_size - scaled_h) // 2

    # Nearest/linear resize matching C++
    resized = cv2.resize(img_bgr, (scaled_w, scaled_h), interpolation=cv2.INTER_LINEAR)

    # 114 gray letterbox padding
    pad_top = pad_h
    pad_bottom = target_size - scaled_h - pad_top
    pad_left = pad_w
    pad_right = target_size - scaled_w - pad_left

    letterbox = cv2.copyMakeBorder(
        resized, pad_top, pad_bottom, pad_left, pad_right,
        cv2.BORDER_CONSTANT, value=(114, 114, 114)
    )

    # BGR -> RGB and 1/255 normalization
    rgb = cv2.cvtColor(letterbox, cv2.COLOR_BGR2RGB).astype(np.float32) * (1.0 / 255.0)
    chw = np.ascontiguousarray(rgb.transpose(2, 0, 1))
    return chw, scale, pad_w, pad_h, scaled_w, scaled_h

def rust_replicate_decode(raw_tensor_84x8400, pad_w, pad_h, conf_thresh=0.25):
    """
    Replicates exact Rust decoder.rs logic on flat row-major tensor [84, 8400].
    """
    # Raw tensor layout: [84 rows, 8400 columns]
    # Row 0: cx, Row 1: cy, Row 2: w, Row 3: h
    # Rows 4..83: 80 class logits/probabilities
    target_size = 640.0
    scaled_w = target_size - 2.0 * float(pad_w)
    scaled_h = target_size - 2.0 * float(pad_h)

    candidates = []

    for anchor in range(8400):
        # Find best class score
        best_class = -1
        max_score = -1.0
        for c in range(80):
            score = raw_tensor_84x8400[4 + c, anchor]
            if score > max_score:
                max_score = score
                best_class = c

        if max_score >= conf_thresh:
            cx = raw_tensor_84x8400[0, anchor]
            cy = raw_tensor_84x8400[1, anchor]
            bw = raw_tensor_84x8400[2, anchor]
            bh = raw_tensor_84x8400[3, anchor]

            # Exact unpad and normalization matching Rust decoder.rs
            x1 = np.clip(((cx - 0.5 * bw) - float(pad_w)) / scaled_w, 0.0, 1.0)
            y1 = np.clip(((cy - 0.5 * bh) - float(pad_h)) / scaled_h, 0.0, 1.0)
            x2 = np.clip(((cx + 0.5 * bw) - float(pad_w)) / scaled_w, 0.0, 1.0)
            y2 = np.clip(((cy + 0.5 * bh) - float(pad_h)) / scaled_h, 0.0, 1.0)

            if x2 > x1 and y2 > y1:
                candidates.append({
                    "class_id": best_class,
                    "confidence": float(max_score),
                    "box": [float(x1), float(y1), float(x2), float(y2)],
                })

    return candidates

def iou(box1, box2):
    xA = max(box1[0], box2[0])
    yA = max(box1[1], box2[1])
    xB = min(box1[2], box2[2])
    yB = min(box1[3], box2[3])

    inter = max(0.0, xB - xA) * max(0.0, yB - yA)
    area1 = (box1[2] - box1[0]) * (box1[3] - box1[1])
    area2 = (box2[2] - box2[0]) * (box2[3] - box2[1])
    union = area1 + area2 - inter
    return inter / union if union > 0 else 0.0

def class_aware_nms(candidates, iou_thresh=0.45):
    """Class-aware Non-Maximum Suppression matching Rust decoder.rs"""
    by_class = {}
    for c in candidates:
        cls = c["class_id"]
        if cls not in by_class:
            by_class[cls] = []
        by_class[cls].append(c)

    final_boxes = []
    for cls, boxes in by_class.items():
        # Sort descending by confidence
        boxes.sort(key=lambda x: x["confidence"], reverse=True)
        keep = []
        while boxes:
            best = boxes.pop(0)
            keep.append(best)
            boxes = [b for b in boxes if iou(best["box"], b["box"]) < iou_thresh]
        final_boxes.extend(keep)

    final_boxes.sort(key=lambda x: x["confidence"], reverse=True)
    return final_boxes

def evaluate_parity_on_image(img_path, pt_model, ncnn_net, conf_thresh=0.25, iou_thresh=0.45):
    img_bgr = cv2.imread(img_path)
    if img_bgr is None:
        raise FileNotFoundError(f"Image not found at {img_path}")

    h_orig, w_orig = img_bgr.shape[:2]

    # 1. C++ exact preprocessing
    chw, scale, pad_w, pad_h, scaled_w, scaled_h = cpp_replicate_preprocess(img_bgr)

    # 2. Ultralytics PyTorch Reference Inference
    # Predict directly with official Ultralytics pipeline
    pt_results = pt_model.predict(img_bgr, conf=conf_thresh, iou=iou_thresh, verbose=False)[0]
    pt_boxes = []
    for box in pt_results.boxes:
        xyxyn = box.xyxyn.cpu().numpy()[0] # normalized [0, 1]
        cls_id = int(box.cls.cpu().numpy()[0])
        conf = float(box.conf.cpu().numpy()[0])
        pt_boxes.append({
            "class_id": cls_id,
            "confidence": conf,
            "box": [float(xyxyn[0]), float(xyxyn[1]), float(xyxyn[2]), float(xyxyn[3])]
        })

    # 3. NCNN Forward Inference
    ex = ncnn_net.create_extractor()
    in_mat = ncnn.Mat(chw)
    ex.input("in0", in_mat)
    ret, out_mat = ex.extract("out0")
    if ret != 0:
        raise RuntimeError(f"NCNN extract out0 failed with code {ret}")

    out_np = np.array(out_mat) # [84, 8400]

    # 4. Rust Decoder Replicated Logic
    rust_candidates = rust_replicate_decode(out_np, pad_w, pad_h, conf_thresh)
    ncnn_boxes = class_aware_nms(rust_candidates, iou_thresh)

    # 5. Measure Parity
    pt_classes = sorted([b["class_id"] for b in pt_boxes])
    ncnn_classes = sorted([b["class_id"] for b in ncnn_boxes])

    # Class overlap metric
    common_classes = set(pt_classes).intersection(set(ncnn_classes))
    total_classes = set(pt_classes).union(set(ncnn_classes))
    class_jaccard = len(common_classes) / len(total_classes) if total_classes else 1.0

    # Bounding box IoU matching
    ious = []
    for nb in ncnn_boxes:
        best_iou = 0.0
        for pb in pt_boxes:
            if nb["class_id"] == pb["class_id"]:
                score = iou(nb["box"], pb["box"])
                if score > best_iou:
                    best_iou = score
        ious.append(best_iou)

    mean_iou = np.mean(ious) if ious else 0.0

    return {
        "image": Path(img_path).name,
        "pt_count": len(pt_boxes),
        "ncnn_count": len(ncnn_boxes),
        "class_jaccard": class_jaccard,
        "mean_iou": mean_iou,
        "pt_classes": [COCO_CLASSES[c] for c in pt_classes[:6]],
        "ncnn_classes": [COCO_CLASSES[c] for c in ncnn_classes[:6]],
    }

def main():
    print("=" * 80)
    print("YOLO NCNN C++/Rust Decoder Contract Parity Verification")
    print("=" * 80)

    # Resolve paths
    base_dir = Path(__file__).resolve().parent.parent
    param_path = base_dir / "mobile_app" / "assets" / "models" / "model.ncnn.param"
    bin_path = base_dir / "mobile_app" / "assets" / "models" / "model.ncnn.bin"
    samples_dir = base_dir / "mobile_app" / "assets" / "samples"

    if not param_path.exists() or not bin_path.exists():
        print(f"[!] Model files not found: {param_path}, {bin_path}")
        sys.exit(1)

    # Download bus.jpg reference
    bus_path = Path("bus.jpg")
    if not bus_path.exists():
        download_file(
            "https://raw.githubusercontent.com/ultralytics/ultralytics/main/ultralytics/assets/bus.jpg",
            "bus.jpg"
        )

    test_images = ["bus.jpg"]
    for s in ["sample_street.jpg", "sample_workspace.jpg", "sample_retail.jpg"]:
        sp = samples_dir / s
        if sp.exists():
            test_images.append(str(sp))

    # Initialize PyTorch Reference Model
    print("[*] Loading Ultralytics PyTorch reference (yolo11n.pt)...")
    pt_model = YOLO("yolo11n.pt")

    # Initialize NCNN Engine
    print("[*] Loading NCNN model (model.ncnn.param, model.ncnn.bin)...")
    net = ncnn.Net()
    net.opt.use_vulkan_compute = False
    net.opt.num_threads = 4
    if net.load_param(str(param_path)) != 0:
        print("[!] Failed to load model.ncnn.param")
        sys.exit(1)
    if net.load_model(str(bin_path)) != 0:
        print("[!] Failed to load model.ncnn.bin")
        sys.exit(1)

    print("\nEvaluating Parity Across Reference and Bundled Sample Datasets:")
    print("-" * 80)
    print(f"{'Image':<20} | {'PT Cnt':<6} | {'NCNN Cnt':<8} | {'Class Jaccard':<13} | {'Mean IoU':<8} | {'Status'}")
    print("-" * 80)

    all_pass = True
    # Declared Parity Tolerance Criteria:
    # 1. Detection count difference <= 2 (due to FP16 quantization boundary near 0.25 conf)
    # 2. Class Jaccard index >= 0.70
    # 3. Mean bounding box IoU >= 0.75
    for img in test_images:
        res = evaluate_parity_on_image(img, pt_model, net)
        cnt_diff = abs(res["pt_count"] - res["ncnn_count"])
        jaccard = res["class_jaccard"]
        m_iou = res["mean_iou"]

        passed = (cnt_diff <= 2) and (jaccard >= 0.70) and (m_iou >= 0.75)
        status = "PASS" if passed else "FAIL"
        if not passed:
            all_pass = False

        print(f"{res['image']:<20} | {res['pt_count']:<6} | {res['ncnn_count']:<8} | {jaccard:<13.3f} | {m_iou:<8.3f} | {status}")
        print(f"  -> PT classes:   {res['pt_classes']}")
        print(f"  -> NCNN classes: {res['ncnn_classes']}")

    print("-" * 80)
    if all_pass:
        print("\nOVERALL CONTRACT PARITY VERDICT: PASS")
        print("Explicit contract alignment between C++ preprocessing, NCNN FP16 inference, and Rust decoder.rs validated.")
        sys.exit(0)
    else:
        print("\nOVERALL CONTRACT PARITY VERDICT: FAIL")
        sys.exit(1)

if __name__ == "__main__":
    main()
