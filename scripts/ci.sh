#!/usr/bin/env bash
# One-shot verification pipeline for pocketsearch.
# Runs: pub get → analyze → unit tests → Android debug + release → iOS release (no codesign).
# Skips: integration_test (requires a device — run manually on a connected device).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
echo "== project: ${ROOT}"

log() { printf "\n\033[1;34m▶ %s\033[0m\n" "$*"; }

log "flutter --version"
flutter --version

log "flutter pub get"
flutter pub get

log "check MobileCLIP model assets"
bash scripts/check_models.sh

log "flutter analyze"
flutter analyze

log "flutter test (unit + widget)"
flutter test

log "flutter build apk --debug"
flutter build apk --debug

log "flutter build apk --release"
flutter build apk --release

if [[ "$(uname -s)" == "Darwin" ]]; then
  if [[ ! -d ios/Runner.xcodeproj ]]; then
    log "flutter create iOS scaffold"
    flutter create --platforms=ios --org app --project-name pocketsearch .
  fi

  log "cd ios && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install"
  (cd ios && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install)

  log "LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter build ios --release --no-codesign"
  LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter build ios --release --no-codesign
else
  echo "(skipping iOS build on non-macOS host)"
fi

log "✅ All automated checks passed."
echo "Remaining manual steps:"
echo "  1. Connect a real Android device (with Developer Mode + USB debugging)"
echo "     or start an emulator, then run:"
echo "       flutter test integration_test/smoke_test.dart"
echo "  2. Install the release APK on device and cold-start once to verify:"
echo "       flutter install --release"
echo "  3. On iOS: open ios/Runner.xcworkspace in Xcode, sign with your team,"
echo "     then Product → Run on a real iPhone to verify cold start."
