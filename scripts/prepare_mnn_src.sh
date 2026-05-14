#!/usr/bin/env bash
#
# prepare_mnn_src.sh — fetch the MNN 3.5.0 source tree expected by the
# `mnn` Dart package's CMake hook.
#
# The `mnn-0.1.3` package's `src/CMakeLists.txt` does:
#     set(MNN_SOURCE_DIR "/tmp/mnn_src/MNN-3.5.0")
#     add_subdirectory(${MNN_SOURCE_DIR} ...)
# i.e. it does NOT use FetchContent — it expects the source to already
# exist at that path. macOS clears /tmp on reboot, so `flutter test`
# will fail with `add_subdirectory given source ".../MNN-3.5.0" which
# is not an existing directory` until you re-run this script.
#
# Idempotent: skips download if /tmp/mnn_src/MNN-3.5.0/CMakeLists.txt
# already exists.
#
# Usage:
#   bash scripts/prepare_mnn_src.sh
set -euo pipefail

MNN_VERSION="3.5.0"
MNN_DIR="/tmp/mnn_src/MNN-${MNN_VERSION}"
MNN_TARBALL="/tmp/mnn_src/MNN-${MNN_VERSION}.tar.gz"

# Multiple mirrors so the script also works in regions where direct
# github.com downloads are slow or blocked. The first reachable
# mirror with non-trivial throughput wins; later ones are fallbacks.
MNN_MIRRORS=(
  "https://github.com/alibaba/MNN/archive/refs/tags/${MNN_VERSION}.tar.gz"
  "https://gh-proxy.com/https://github.com/alibaba/MNN/archive/refs/tags/${MNN_VERSION}.tar.gz"
  "https://ghfast.top/https://github.com/alibaba/MNN/archive/refs/tags/${MNN_VERSION}.tar.gz"
)

if [[ -f "${MNN_DIR}/CMakeLists.txt" ]]; then
  echo "==> MNN ${MNN_VERSION} already prepared at ${MNN_DIR}"
  exit 0
fi

mkdir -p /tmp/mnn_src

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
  echo "ERROR: every mirror failed. Check your network or download manually:" >&2
  echo "       ${MNN_MIRRORS[0]}" >&2
  echo "       extract to /tmp/mnn_src/  (yields /tmp/mnn_src/MNN-${MNN_VERSION}/)" >&2
  exit 1
fi

echo "==> Extracting to /tmp/mnn_src/…"
tar -xzf "${MNN_TARBALL}" -C /tmp/mnn_src/
rm -f "${MNN_TARBALL}"

if [[ ! -f "${MNN_DIR}/CMakeLists.txt" ]]; then
  echo "ERROR: extraction did not produce ${MNN_DIR}/CMakeLists.txt" >&2
  exit 1
fi

echo "==> Done. ${MNN_DIR} is ready."
echo "    You can now run: flutter test test/"
