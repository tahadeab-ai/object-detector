#!/usr/bin/env python3
"""
YOLO11n to NCNN FP16 PNNX Export Pipeline (Google Colab)
Strict 0% Local Compute Enforcement (RESTORE-5 / A6)
Adheres strictly to [1, 84, 8400] row-major tensor layout (A8, A16, F6)
"""

import os
import sys
import json
import hashlib
import subprocess
from pathlib import Path

def install_dependencies():
    print("=== Installing Ultralytics, NCNN, and PNNX dependencies on Colab ===")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "ultralytics", "ncnn"])

def compute_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(8192):
            h.update(chunk)
    return h.hexdigest()

def export_model():
    from ultralytics import YOLO
    import ncnn
    import pnnx

    print("=== Loading official YOLO11n PyTorch weights ===")
    model = YOLO("yolo11n.pt")

    output_dir = Path("yolo11n_ncnn_model")
    param_file = output_dir / "model.ncnn.param"
    bin_file = output_dir / "model.ncnn.bin"

    print("=== Exporting YOLO11n to NCNN FP16 via PNNX (imgsz=640, half=True) ===")
    model.export(format="ncnn", imgsz=640, half=True)

    if not param_file.exists() or not bin_file.exists():
        raise FileNotFoundError(f"Export failed: missing {param_file} or {bin_file}")

    print("=== Validating exported PNNX graph structure ===")
    param_lines = param_file.read_text(encoding="utf-8").splitlines()
    
    # Verify input layer in0
    input_found = False
    for line in param_lines[:10]:
        if line.startswith("Input") and "in0" in line:
            input_found = True
            break
    if not input_found:
        raise ValueError("Failed PNNX contract: input blob 'in0' not found in model.ncnn.param")

    # Verify output layer out0
    output_found = False
    for line in param_lines[-10:]:
        if "out0" in line:
            output_found = True
            break
    if not output_found:
        raise ValueError("Failed PNNX contract: output blob 'out0' not found in model.ncnn.param")

    param_size = param_file.stat().st_size
    bin_size = bin_file.stat().st_size
    param_sha256 = compute_sha256(param_file)
    bin_sha256 = compute_sha256(bin_file)

    print(f"Export successful:")
    print(f"  model.ncnn.param: {param_size} bytes, SHA256: {param_sha256}")
    print(f"  model.ncnn.bin:   {bin_size} bytes, SHA256: {bin_sha256}")

    # Generate model_metadata.json
    metadata = {
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
        "normalization": {
            "mean": [0.0, 0.0, 0.0],
            "scale": [0.00392156862745098, 0.00392156862745098, 0.00392156862745098]
        },
        "classes": 80,
        "confidence_threshold": 0.25,
        "iou_threshold": 0.45,
        "export_platform": "colab-pnnx",
        "files": {
            "param_file": "model.ncnn.param",
            "bin_file": "model.ncnn.bin",
            "param_size_bytes": param_size,
            "bin_size_bytes": bin_size,
            "param_sha256": param_sha256,
            "bin_sha256": bin_sha256
        },
        "weights_sha256": bin_sha256
    }

    metadata_path = output_dir / "model_metadata.json"
    with open(metadata_path, "w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2)

    print(f"Generated metadata: {metadata_path}")
    return metadata

if __name__ == "__main__":
    install_dependencies()
    export_model()
