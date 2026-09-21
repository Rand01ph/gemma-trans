#!/bin/bash
# Shared Cloud validation. Native Cloud action additionally builds the MAS scheme.
set -euo pipefail
cd "$(dirname "$0")/.."
PACKAGE_CHECKSUM="$(sed -n 's/.*checksum: "\([0-9a-f]*\)".*/\1/p' Package.swift)"
RECORDED_CHECKSUM="$(sed -n 's/^SHA-256 \/ SwiftPM checksum: //p' Runtime/LlamaRuntime/CHECKSUMS.txt)"
test -n "$PACKAGE_CHECKSUM"
test "$PACKAGE_CHECKSUM" = "$RECORDED_CHECKSUM"
xcodebuild -version
xcrun --sdk macosx --show-sdk-version
swift test
# Older development snapshots do not yet include the UI contract.
if [ -f docs/ui/ui-contract.json ]; then
  python3 script/ui_contract.py
fi
if /usr/bin/grep -q '^  HunyuanModelTests:' App/project.yml; then
  xcodebuild -project App/GemmaTrans.xcodeproj -scheme HunyuanModelTests \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath App/build/cloud-validation \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -skipMacroValidation \
    -skipPackagePluginValidation test
fi
xcodebuild -project App/GemmaTrans.xcodeproj -scheme GemmaTrans \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath App/build/cloud-validation CODE_SIGNING_ALLOWED=NO \
  -skipMacroValidation -skipPackagePluginValidation build
