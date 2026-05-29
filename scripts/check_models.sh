#!/usr/bin/env bash
#
# Verify that the MobileCLIP MNN model assets required at runtime exist.
#
# Usage:
#   bash scripts/check_models.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_DIR="${ROOT_DIR}/assets/models"

required=(
  "mobileclip_s1_image_encoder.mnn"
  "mobileclip_s1_text_encoder.mnn"
)

missing=0
for name in "${required[@]}"; do
  path="${MODEL_DIR}/${name}"
  if [[ ! -s "${path}" ]]; then
    echo "ERROR: missing required model asset: assets/models/${name}" >&2
    missing=1
  fi
done

if [[ "${missing}" -ne 0 ]]; then
  cat >&2 <<'EOF'

PocketSearch cannot run without the MobileCLIP MNN model files.

Prepare them before building:
  1. Download MobileCLIP-S1 checkpoint to /tmp/mobileclip_s1.pt
  2. Run: .venv/bin/python scripts/export_onnx.py
  3. Run: PATH="$PWD/.venv/bin:$PATH" bash scripts/convert_mnn.sh
  4. Run: bash scripts/check_models.sh

Expected outputs:
  assets/models/mobileclip_s1_image_encoder.mnn
  assets/models/mobileclip_s1_text_encoder.mnn
EOF
  exit 1
fi

echo "==> Required model assets found:"
for name in "${required[@]}"; do
  ls -lh "${MODEL_DIR}/${name}"
done
