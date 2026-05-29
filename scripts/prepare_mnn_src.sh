#!/usr/bin/env bash
#
# prepare_mnn_src.sh — fetch the MNN 3.5.0 source tree expected by the
# `mnn` Dart package's CMake hook.
#
# The `mnn-0.1.3` package's `src/CMakeLists.txt` hardcodes:
#     set(MNN_SOURCE_DIR "/tmp/mnn_src/MNN-3.5.0")
# macOS clears /tmp on reboot. To avoid re-downloading 89 MB every time,
# this script stores the source in ~/.cache/mnn_src/ (persistent) and
# creates a symlink at /tmp/mnn_src → ~/.cache/mnn_src/.
#
# Idempotent: skips download if already cached; recreates symlink if needed.
#
# Usage:
#   bash scripts/prepare_mnn_src.sh
set -euo pipefail

MNN_VERSION="3.5.0"
CACHE_DIR="${HOME}/.cache/mnn_src"
MNN_DIR="${CACHE_DIR}/MNN-${MNN_VERSION}"
SYMLINK_TARGET="/tmp/mnn_src"

# Multiple mirrors for regions where github.com is slow/blocked.
MNN_MIRRORS=(
  "https://github.com/alibaba/MNN/archive/refs/tags/${MNN_VERSION}.tar.gz"
  "https://gh-proxy.com/https://github.com/alibaba/MNN/archive/refs/tags/${MNN_VERSION}.tar.gz"
  "https://ghfast.top/https://github.com/alibaba/MNN/archive/refs/tags/${MNN_VERSION}.tar.gz"
)

# --- Step 1: Ensure symlink /tmp/mnn_src → ~/.cache/mnn_src/ ---
if [[ -L "${SYMLINK_TARGET}" ]]; then
  # Symlink exists, check it points to the right place
  if [[ "$(readlink "${SYMLINK_TARGET}")" != "${CACHE_DIR}" ]]; then
    rm -f "${SYMLINK_TARGET}"
    ln -s "${CACHE_DIR}" "${SYMLINK_TARGET}"
  fi
elif [[ -d "${SYMLINK_TARGET}" ]]; then
  # Real directory exists (from old script); migrate contents
  if [[ -d "${SYMLINK_TARGET}/MNN-${MNN_VERSION}" ]]; then
    mkdir -p "${CACHE_DIR}"
    mv "${SYMLINK_TARGET}/MNN-${MNN_VERSION}" "${CACHE_DIR}/"
  fi
  rm -rf "${SYMLINK_TARGET}"
  ln -s "${CACHE_DIR}" "${SYMLINK_TARGET}"
else
  mkdir -p "${CACHE_DIR}"
  ln -s "${CACHE_DIR}" "${SYMLINK_TARGET}"
fi

# --- Step 2: Download if not cached ---
if [[ -f "${MNN_DIR}/CMakeLists.txt" ]]; then
  echo "==> MNN ${MNN_VERSION} ready at ${MNN_DIR}"
  echo "    Symlink: ${SYMLINK_TARGET} → ${CACHE_DIR}"
  exit 0
fi

mkdir -p "${CACHE_DIR}"
MNN_TARBALL="${CACHE_DIR}/MNN-${MNN_VERSION}.tar.gz"

download_succeeded=0
for url in "${MNN_MIRRORS[@]}"; do
  echo "==> Downloading MNN ${MNN_VERSION} from: ${url}"
  if command -v curl >/dev/null 2>&1; then
    if curl -fL --connect-timeout 15 --max-time 600 \
            -o "${MNN_TARBALL}" "${url}"; then
      download_succeeded=1
      break
    fi
  elif command -v wget >/dev/null 2>&1; then
    if wget --connect-timeout=15 --tries=1 \
            -O "${MNN_TARBALL}" "${url}"; then
      download_succeeded=1
      break
    fi
  else
    echo "ERROR: neither curl nor wget is available" >&2
    exit 1
  fi
  echo "==> Mirror failed, trying next…"
  rm -f "${MNN_TARBALL}"
done

if [[ "${download_succeeded}" -ne 1 ]]; then
  echo "ERROR: all mirrors failed. Download manually:" >&2
  echo "       ${MNN_MIRRORS[0]}" >&2
  echo "       extract to ${CACHE_DIR}/  (yields ${MNN_DIR}/)" >&2
  exit 1
fi

echo "==> Extracting…"
tar -xzf "${MNN_TARBALL}" -C "${CACHE_DIR}/"
rm -f "${MNN_TARBALL}"

if [[ ! -f "${MNN_DIR}/CMakeLists.txt" ]]; then
  echo "ERROR: extraction failed — ${MNN_DIR}/CMakeLists.txt not found" >&2
  exit 1
fi

echo "==> Done. MNN ${MNN_VERSION} cached at ${MNN_DIR}"
echo "    Symlink: ${SYMLINK_TARGET} → ${CACHE_DIR}"
