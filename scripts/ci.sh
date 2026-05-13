#!/usr/bin/env bash
# One-shot verification pipeline for zvec_photo_search.
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

log "flutter analyze"
flutter analyze

log "flutter test (unit + widget)"
flutter test

log "flutter build apk --debug"
flutter build apk --debug

log "flutter build apk --release"
flutter build apk --release

if [[ "$(uname -s)" == "Darwin" ]]; then
  log "cd ios && pod install"
  (cd ios && pod install)

  log "flutter build ios --release --no-codesign"
  flutter build ios --release --no-codesign
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
