#!/bin/bash
# =============================================================================
# GitHub Release Publisher from Google Colab Datacenter
# Enforces ISP Upload Limit < 16 MB (RESTORE-5 / A6, A18)
# Releases weights and metadata directly from Colab to GitHub Releases
# =============================================================================
set -euo pipefail

REPO="tahadeab-ai/object-detector"
TAG="model-v1"
MODEL_DIR="yolo11n_ncnn_model"

if [ -z "${GH_TOKEN:-}" ]; then
  echo "Error: GH_TOKEN environment variable is not set." >&2
  exit 1
fi

echo "Authenticating GitHub CLI with token..."
echo "$GH_TOKEN" | gh auth login --with-token

echo "Checking if release $TAG exists on $REPO..."
if gh release view "$TAG" --repo "$REPO" > /dev/null 2>&1; then
  echo "Uploading assets to existing release $TAG..."
  gh release upload "$TAG" \
    "$MODEL_DIR/model.ncnn.param" \
    "$MODEL_DIR/model.ncnn.bin" \
    "$MODEL_DIR/model_metadata.json" \
    --repo "$REPO" --clobber
else
  echo "Creating release $TAG..."
  gh release create "$TAG" \
    "$MODEL_DIR/model.ncnn.param" \
    "$MODEL_DIR/model.ncnn.bin" \
    "$MODEL_DIR/model_metadata.json" \
    --repo "$REPO" \
    --title "YOLO11n NCNN Model v1" \
    --notes "NCNN FP16 weights and metadata for YOLO11n exported on Google Colab via PNNX."
fi

echo "Release published successfully:"
gh release view "$TAG" --repo "$REPO" --json url -q .url
