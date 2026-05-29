#!/bin/bash
#
# Convert ONNX models to MNN format with FP16 quantization.
#
# Prerequisites:
#   - MNN converter available in PATH (MNNConvert or mnnconvert from the MNN Python package)
#   - ONNX models already exported via export_onnx.py
#
# Usage:
#   PATH="$PWD/.venv/bin:$PATH" bash scripts/convert_mnn.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL_DIR="${SCRIPT_DIR}/../assets/models"

if command -v MNNConvert >/dev/null 2>&1; then
    MNN_CONVERT="MNNConvert"
elif command -v mnnconvert >/dev/null 2>&1; then
    MNN_CONVERT="mnnconvert"
else
    echo "ERROR: MNN converter not found. Install the MNN Python package or add MNNConvert to PATH." >&2
    echo "       Example: uv pip install --python .venv/bin/python MNN" >&2
    exit 1
fi

echo "Converting ONNX models to MNN format with ${MNN_CONVERT}..."

# Convert image encoder
echo "[1/2] Converting image encoder..."
"${MNN_CONVERT}" \
    --framework ONNX \
    --modelFile "${MODEL_DIR}/mobileclip_s1_image_encoder.onnx" \
    --MNNModel "${MODEL_DIR}/mobileclip_s1_image_encoder.mnn" \
    --fp16

# Convert text encoder
echo "[2/2] Converting text encoder..."
"${MNN_CONVERT}" \
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
