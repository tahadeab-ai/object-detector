#!/usr/bin/env python3
"""
PyTorch vs Tencent NCNN Numeric Parity Verification (Google Colab)
Enforces:
- Static input [1, 3, 640, 640] (in0) and output [1, 84, 8400] row-major layout (out0) (A8, A16, F6)
- Mean absolute raw tensor diff < 0.05
- Score max diff <= 0.05, Coordinate max diff <= 10.0 px
- Detection-level count and class parity on bus.jpg at conf=0.25, IoU=0.45
- Outputs explicit PASS/FAIL verdict line
"""

import sys
import urllib.request
from pathlib import Path
import cv2
import numpy as np
import torch
from PIL import Image
from ultralytics import YOLO
from ultralytics.data.augment import LetterBox
import ncnn

def download_bus_image(dest="bus.jpg"):
    url = "https://raw.githubusercontent.com/ultralytics/ultralytics/main/ultralytics/assets/bus.jpg"
    p = Path(dest)
    if not p.exists():
        print(f"Downloading reference image {url} -> {dest}...")
        urllib.request.urlretrieve(url, dest)
    return str(p)

def run_parity_benchmark():
    img_path = download_bus_image("bus.jpg")

    # 1. Preprocess with official LetterBox 640x640, RGB, normalized [0, 1], contiguous CHW
    img = cv2.imread(img_path)
    letterbox = LetterBox(640, auto=False, stride=32)
    img_lb = letterbox(image=img)
    img_rgb = cv2.cvtColor(img_lb, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
    chw = np.ascontiguousarray(img_rgb.transpose(2, 0, 1))
    tensor_in = torch.from_numpy(chw).unsqueeze(0)

    # 2. PyTorch FP32 Reference Forward Pass
    pt_model = YOLO("yolo11n.pt")
    with torch.no_grad():
        pt_out = pt_model.model(tensor_in)[0].numpy().squeeze(0) # (84, 8400)
    pt_res = pt_model.predict(img_lb, conf=0.25, iou=0.45, verbose=False)[0]
    pt_classes = sorted(pt_res.boxes.cls.cpu().numpy().astype(int).tolist())

    # 3. Tencent NCNN FP16 Forward Pass
    net = ncnn.Net()
    net.opt.use_vulkan_compute = False
    net.opt.num_threads = 4
    net.load_param("yolo11n_ncnn_model/model.ncnn.param")
    net.load_model("yolo11n_ncnn_model/model.ncnn.bin")

    ex = net.create_extractor()
    mat_in = ncnn.Mat(chw)
    ex.input("in0", mat_in)
    ret, out0 = ex.extract("out0")
    if ret != 0:
        raise RuntimeError(f"NCNN extractor failed with code {ret}")
    ncnn_out = np.array(out0) # (84, 8400)

    # 4. Numeric Tensor Differences
    diff = np.abs(pt_out - ncnn_out)
    mean_diff = float(np.mean(diff))
    median_diff = float(np.median(diff))
    max_diff = float(np.max(diff))
    coord_max_diff = float(np.max(diff[0:4, :]))
    score_max_diff = float(np.max(diff[4:84, :]))

    # 5. Class-Aware NMS on NCNN Raw Tensor
    boxes = ncnn_out[0:4, :].T
    scores = ncnn_out[4:84, :].T
    max_scores = np.max(scores, axis=1)
    class_ids = np.argmax(scores, axis=1)
    conf_mask = max_scores >= 0.25
    cand_boxes = boxes[conf_mask]
    cand_scores = max_scores[conf_mask]
    cand_classes = class_ids[conf_mask]

    x1 = cand_boxes[:, 0] - cand_boxes[:, 2] / 2
    y1 = cand_boxes[:, 1] - cand_boxes[:, 3] / 2
    x2 = cand_boxes[:, 0] + cand_boxes[:, 2] / 2
    y2 = cand_boxes[:, 1] + cand_boxes[:, 3] / 2
    cand_xyxy = np.stack([x1, y1, x2, y2], axis=1)

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

    ncnn_classes = sorted(cand_classes[keep_indices].tolist())

    print("=== Colab benchmark_ncnn_colab.py Parity Output ===")
    print(f"Static Input Shape: [1, 3, 640, 640] (in0)")
    print(f"Static Output Shape: [1, 84, 8400] row-major (out0)")
    print(f"Declared Tolerance: mean_diff < 0.05, score_max_diff <= 0.05, coord_max_diff <= 10.0 px")
    print(f"Actual Mean Absolute Diff: {mean_diff:.6f}")
    print(f"Actual Median Absolute Diff: {median_diff:.6f}")
    print(f"Actual Max Absolute Diff: {max_diff:.6f} (coord: {coord_max_diff:.4f} px, score: {score_max_diff:.6f})")
    print(f"PyTorch Detections (conf=0.25, iou=0.45): count={len(pt_classes)}, classes={pt_classes}")
    print(f"NCNN Detections    (conf=0.25, iou=0.45): count={len(ncnn_classes)}, classes={ncnn_classes}")

    assert len(pt_classes) == len(ncnn_classes) == 5, f"Count mismatch: {len(pt_classes)} vs {len(ncnn_classes)}"
    assert pt_classes == ncnn_classes == [0, 0, 0, 0, 5], f"Classes mismatch: {pt_classes} vs {ncnn_classes}"
    assert mean_diff < 0.05, f"Mean diff {mean_diff} >= 0.05"
    assert score_max_diff <= 0.05, f"Score max diff {score_max_diff} > 0.05"
    assert coord_max_diff <= 10.0, f"Coord max diff {coord_max_diff} > 10.0"

    print("VERDICT: PASS")

if __name__ == "__main__":
    run_parity_benchmark()
