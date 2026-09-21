#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANNEL="$(cat "$ROOT_DIR/script/default-channel")"
MODE=run
while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) CHANNEL="$2"; shift 2 ;;
    run|--verify|--build-only|--no-launch|--ui-test|--logs|--telemetry|--debug) MODE="$1"; shift ;;
    *) echo 'Usage: build_and_run.sh [--channel qa|dev|uitest] [--build-only|--verify|--ui-test|--logs|--telemetry|--debug]' >&2; exit 2 ;;
  esac
done
[[ "$MODE" != --ui-test ]] || CHANNEL=uitest
case "$CHANNEL" in qa) LABEL=QA ;; dev) LABEL=Dev ;; uitest) LABEL=UITest ;; *) exit 2 ;; esac
APP_NAME="GemmaTrans $LABEL"
BUNDLE_ID="com.gemmatrans.GemmaTrans.$CHANNEL"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DERIVED_DATA="${GEMMATRANS_DERIVED_DATA:-$ROOT_DIR/App/build/qa}"
PROJECT="$ROOT_DIR/App/build/channels/$CHANNEL/GemmaTrans.xcodeproj"
BUILD_APP="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
INSTALL_APP="$HOME/Applications/$APP_NAME.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
python3 "$ROOT_DIR/script/channel_project.py" "$CHANNEL"
ARGS=(-project "$PROJECT" -scheme GemmaTrans -configuration Debug -destination 'platform=macOS,arch=arm64'
  -derivedDataPath "$DERIVED_DATA" -clonedSourcePackagesDirPath "$ROOT_DIR/.build"
  -skipPackageUpdates -skipMacroValidation -skipPackagePluginValidation)
if [[ "${CODE_SIGNING_ALLOWED:-YES}" == NO ]]; then
  [[ "$MODE" == --build-only || "$MODE" == --no-launch ]] || { echo 'Installing/testing requires a stable Apple Development signature.' >&2; exit 1; }
  ARGS+=(CODE_SIGNING_ALLOWED=NO)
fi
if [[ "$MODE" == --ui-test ]]; then
  trap '"$LSREGISTER" -u "$BUILD_APP" >/dev/null 2>&1 || true' EXIT
  RESULT="${GEMMATRANS_TEST_RESULT:-$ROOT_DIR/App/build/ui-isolated-$(date +%Y%m%d-%H%M%S).xcresult}"
  xcodebuild "${ARGS[@]}" -resultBundlePath "$RESULT" test
  exit
fi
xcodebuild "${ARGS[@]}" build
"$LSREGISTER" -u "$BUILD_APP" >/dev/null 2>&1 || true
[[ "$MODE" != --build-only && "$MODE" != --no-launch ]] || exit 0
python3 "$ROOT_DIR/script/install_channel.py" "$BUILD_APP" "$INSTALL_APP" "$CHANNEL"
"$LSREGISTER" -u "$BUILD_APP" >/dev/null 2>&1 || true
# The installed, signature-verified copy is authoritative; do not leave a second
# launchable copy for Spotlight/LaunchServices to rediscover later.
python3 - "$BUILD_APP" "$BUNDLE_ID" <<'PYTHON'
import pathlib, plistlib, shutil, sys
p=pathlib.Path(sys.argv[1])
if plistlib.loads((p/'Contents/Info.plist').read_bytes())['CFBundleIdentifier'] != sys.argv[2]:
    raise SystemExit('Unexpected product identity; refusing cleanup')
shutil.rmtree(p)
PYTHON
"$LSREGISTER" -f "$INSTALL_APP"
open -n "$INSTALL_APP"
python3 "$ROOT_DIR/script/verify_channel.py" "$INSTALL_APP" "$CHANNEL"
case "$MODE" in
  --logs|--telemetry) /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
  --debug) lldb -n "$APP_NAME" ;;
esac
