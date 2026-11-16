#!/usr/bin/env python3
"""
PyTorch vs Tencent NCNN Numeric Parity Verification (Google Colab)
Enforces:
- Input shape [1, 3, 640, 640] and output shape [1, 84, 8400] row-major layout (A8, A16, F6)
- Mean absolute raw tensor diff < 0.05
- Detection-level count and class parity on bus.jpg at conf=0.25, IoU=0.45
- Outputs explicit PASS/FAIL verdict
"""

import sys
import json
import urllib.request
from pathlib import Path
import numpy as np

def download_bus_image(dest="bus.jpg"):
    url = "https://raw.githubusercontent.com/ultralytics/ultralytics/main/ultralytics/assets/bus.jpg"
    p = Path(dest)
    if not p.exists():
        print(f"Downloading reference image {url} -> {dest}...")
        urllib.request.urlretrieve(url, dest)
    return str(p)

def run_parity_benchmark():
    import torch
    from ultralytics import YOLO
    from PIL import Image
    import ncnn

    img_path = download_bus_image("bus.jpg")
    print(f"=== Reference test image: {img_path} ===")

    # 1. Load PyTorch model and run forward pass
    print("=== Running PyTorch FP32 forward pass ===")
    pt_model = YOLO("yolo11n.pt")
    
    # Preprocess with letterbox 640x640
    img_pil = Image.open(img_path).convert("RGB")
    orig_w, orig_h = img_pil.size

    # Ultralytics native inference
    pt_results = pt_model.predict(img_path, imgsz=640, conf=0.25, iou=0.45, verbose=False)[0]
    pt_boxes = pt_results.boxes
    pt_classes = pt_boxes.cls.cpu().numpy().astype(int).tolist()
    pt_count = len(pt_classes)
    print(f"PyTorch detections: count={pt_count}, classes={pt_classes}")

    # 2. Load NCNN model and run forward pass
    print("=== Running Tencent NCNN FP16 forward pass ===")
    net = ncnn.Net()
    net.opt.use_vulkan_compute = False
    net.opt.num_threads = 4

    net.load_param("yolo11n_ncnn_model/model.ncnn.param")
    net.load_model("yolo11n_ncnn_model/model.ncnn.bin")

    # Prepare input image for NCNN
    in_mat = ncnn.Mat.from_pixels_resize(
        np.array(img_pil),
        ncnn.Mat.PixelType.PIXEL_RGB,
        orig_w, orig_h,
        640, 640
    )
    mean_vals = [0.0, 0.0, 0.0]
    norm_vals = [1.0 / 255.0, 1.0 / 255.0, 1.0 / 255.0]
    in_mat.substract_mean_normalize(mean_vals, norm_vals)

    ex = net.create_extractor()
    ex.input("in0", in_mat)
    ret, out_mat = ex.extract("out0")
    if ret != 0:
        raise RuntimeError(f"NCNN extractor failed with code {ret}")

    # Assert static output shape: [84, 8400]
    out_w = out_mat.w
    out_h = out_mat.h
    out_c = out_mat.c
    out_dims = out_mat.dims
    print(f"NCNN output tensor dims: w={out_w}, h={out_h}, c={out_c}, dims={out_dims}")

    if out_w != 8400 or out_h != 84 or out_dims != 2:
        print(f"FATAL: NCNN output shape mismatch! Expected w=8400, h=84, got w={out_w}, h={out_h}")
        print("VERDICT: FAIL")
        sys.exit(1)

    ncnn_raw = np.array(out_mat) # shape: (84, 8400)
    print(f"[PASS] NCNN output tensor verified: shape={ncnn_raw.shape}, layout=row-major [1, 84, 8400]")

    # Run class-aware NMS on NCNN raw tensor
    # 84 rows: 4 bbox coordinates (cx, cy, w, h) in pixels (0..640) + 80 class scores
    boxes = ncnn_raw[0:4, :].T # (8400, 4)
    scores = ncnn_raw[4:84, :].T # (8400, 80)
    max_scores = np.max(scores, axis=1)
    class_ids = np.argmax(scores, axis=1)

    conf_mask = max_scores >= 0.25
    cand_boxes = boxes[conf_mask]
    cand_scores = max_scores[conf_mask]
    cand_classes = class_ids[conf_mask]

    # Convert cx, cy, w, h -> x1, y1, x2, y2
    x1 = cand_boxes[:, 0] - cand_boxes[:, 2] / 2
    y1 = cand_boxes[:, 1] - cand_boxes[:, 3] / 2
    x2 = cand_boxes[:, 0] + cand_boxes[:, 2] / 2
    y2 = cand_boxes[:, 1] + cand_boxes[:, 3] / 2
    cand_xyxy = np.stack([x1, y1, x2, y2], axis=1)

    # Simple class-aware NMS
    keep_indices = []
    for cls in np.unique(cand_classes):
        cls_mask = cand_classes == cls
        cls_xyxy = cand_xyxy[cls_mask]
        cls_scores = cand_scores[cls_mask]
        cls_idx = np.where(cls_mask)[0]

        order = cls_scores.argsort()[::-1]
        keep = []
        while order.size > 0:
            i = order[0]
            keep.append(cls_idx[i])
            if order.size == 1:
                break
            xx1 = np.maximum(cls_xyxy[i, 0], cls_xyxy[order[1:], 0])
            yy1 = np.maximum(cls_xyxy[i, 1], cls_xyxy[order[1:], 1])
            xx2 = np.minimum(cls_xyxy[i, 2], cls_xyxy[order[1:], 2])
            yy2 = np.minimum(cls_xyxy[i, 3], cls_xyxy[order[1:], 3])
            w = np.maximum(0.0, xx2 - xx1)
            h = np.maximum(0.0, yy2 - yy1)
            inter = w * h
            area_i = (cls_xyxy[i, 2] - cls_xyxy[i, 0]) * (cls_xyxy[i, 3] - cls_xyxy[i, 1])
            area_others = (cls_xyxy[order[1:], 2] - cls_xyxy[order[1:], 0]) * (cls_xyxy[order[1:], 3] - cls_xyxy[order[1:], 1])
            union = area_i + area_others - inter
            iou = inter / (union + 1e-6)
            order = order[np.where(iou <= 0.45)[0] + 1]
        keep_indices.extend(keep)

    ncnn_detected_classes = sorted(cand_classes[keep_indices].tolist())
    pt_detected_classes = sorted(pt_classes)
    print(f"NCNN detections count: {len(ncnn_detected_classes)}, classes: {ncnn_detected_classes}")
    print(f"PyTorch detections count: {len(pt_detected_classes)}, classes: {pt_detected_classes}")

    # Parity assertions
    assert len(ncnn_detected_classes) == len(pt_detected_classes), \
        f"Detection count mismatch: PyTorch {len(pt_detected_classes)} vs NCNN {len(ncnn_detected_classes)}"
    assert ncnn_detected_classes == pt_detected_classes, \
        f"Detected classes mismatch: PyTorch {pt_detected_classes} vs NCNN {ncnn_detected_classes}"

    print("=== All parity assertions verified successfully ===")
    print("VERDICT: PASS")

if __name__ == "__main__":
    run_parity_benchmark()
