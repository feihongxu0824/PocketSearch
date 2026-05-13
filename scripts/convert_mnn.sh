#!/bin/bash
#
# Convert ONNX models to MNN format with FP16 quantization.
#
# Prerequisites:
#   - MNN toolkit installed (MNNConvert binary available in PATH)
#   - ONNX models already exported via export_onnx.py
#
# Usage:
#   bash scripts/convert_mnn.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL_DIR="${SCRIPT_DIR}/../assets/models"

echo "Converting ONNX models to MNN format..."

# Convert image encoder
echo "[1/2] Converting image encoder..."
MNNConvert \
    --framework ONNX \
    --modelFile "${MODEL_DIR}/mobileclip_s1_image_encoder.onnx" \
    --MNNModel "${MODEL_DIR}/mobileclip_s1_image_encoder.mnn" \
    --fp16

# Convert text encoder
echo "[2/2] Converting text encoder..."
MNNConvert \
    --framework ONNX \
    --modelFile "${MODEL_DIR}/mobileclip_s1_text_encoder.onnx" \
    --MNNModel "${MODEL_DIR}/mobileclip_s1_text_encoder.mnn" \
    --fp16

echo ""
echo "Done! MNN models saved to:"
echo "  ${MODEL_DIR}/mobileclip_s1_image_encoder.mnn"
echo "  ${MODEL_DIR}/mobileclip_s1_text_encoder.mnn"
echo ""
ls -lh "${MODEL_DIR}"/*.mnn 2>/dev/null || echo "(no .mnn files found)"
