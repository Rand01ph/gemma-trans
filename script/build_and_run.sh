#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="GemmaTrans"
BUNDLE_ID="com.gemmatrans.GemmaTrans"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/App"
PROJECT="$APP_DIR/GemmaTrans.xcodeproj"
DERIVED_DATA="$APP_DIR/build/codex"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
DEVELOPMENT_TEAM="G2XC9VU88M"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--no-launch]" >&2
}

stop_running_apps() {
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    kill "$pid" >/dev/null 2>&1 || true
  done < <(pgrep -f '/GemmaTrans\.app/Contents/MacOS/GemmaTrans$' || true)

  for _ in 1 2 3 4 5; do
    pgrep -f '/GemmaTrans\.app/Contents/MacOS/GemmaTrans$' >/dev/null || return 0
    sleep 0.2
  done
}

build_app() {
  local xcodebuild_args=(
    -project "$PROJECT"
    -scheme "$APP_NAME"
    -configuration Debug
    -destination 'platform=macOS,arch=arm64'
    -derivedDataPath "$DERIVED_DATA"
    -skipPackageUpdates
    -skipMacroValidation
    -skipPackagePluginValidation
  )
  [[ -d "$DEVELOPER_DIR" ]] || {
    echo "Xcode developer directory not found: $DEVELOPER_DIR" >&2
    exit 1
  }
  command -v xcodegen >/dev/null || {
    echo "xcodegen is required (expected /opt/homebrew/bin/xcodegen)." >&2
    exit 1
  }

  if [[ "${CODE_SIGNING_ALLOWED:-YES}" == "NO" ]]; then
    xcodebuild_args+=("CODE_SIGNING_ALLOWED=NO")
  elif ! /usr/bin/security find-identity -v -p codesigning 2>/dev/null | grep -q "$DEVELOPMENT_TEAM"; then
    echo "warning: no Mac Development identity for $DEVELOPMENT_TEAM; building unsigned." >&2
    echo "         Global shortcut and macOS Service validation require a signed build." >&2
    xcodebuild_args+=("CODE_SIGNING_ALLOWED=NO")
  fi

  (
    cd "$APP_DIR"
    xcodegen generate --use-cache
    /usr/bin/xcodebuild "${xcodebuild_args[@]}" build
  )
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_app() {
  local pid=""
  for _ in $(seq 1 30); do
    pid="$(pgrep -f "${APP_BINARY}$" | head -1 || true)"
    [[ -n "$pid" ]] && break
    sleep 0.2
  done
  [[ -n "$pid" ]] || {
    echo "$APP_NAME did not stay running." >&2
    exit 1
  }

  local command_path bundle_id listener_pid
  command_path="$(ps -p "$pid" -o command=)"
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")"
  [[ "$command_path" == "$APP_BINARY" ]] || {
    echo "Unexpected executable: $command_path" >&2
    exit 1
  }
  [[ "$bundle_id" == "$BUNDLE_ID" ]] || {
    echo "Unexpected bundle id: $bundle_id" >&2
    exit 1
  }

  listener_pid="$(lsof -nP -iTCP:8765 -sTCP:LISTEN -t 2>/dev/null | head -1 || true)"
  if [[ -n "$listener_pid" && "$listener_pid" != "$pid" ]]; then
    echo "Port 8765 belongs to pid $listener_pid, not fresh $APP_NAME pid $pid." >&2
    exit 1
  fi

  echo "Verified $APP_NAME pid $pid"
  echo "Executable: $command_path"
  echo "Bundle ID: $bundle_id"
  if [[ "$listener_pid" == "$pid" ]]; then
    echo "Port 8765: owned by fresh build"
  else
    echo "Port 8765: not listening (API may be disabled or engine still loading)"
  fi
}

case "$MODE" in
  run)
    stop_running_apps
    build_app
    open_app
    ;;
  --no-launch|no-launch)
    stop_running_apps
    build_app
    ;;
  --verify|verify)
    stop_running_apps
    build_app
    open_app
    verify_app
    ;;
  --debug|debug)
    stop_running_apps
    build_app
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    stop_running_apps
    build_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    stop_running_apps
    build_app
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  *)
    usage
    exit 2
    ;;
esac
