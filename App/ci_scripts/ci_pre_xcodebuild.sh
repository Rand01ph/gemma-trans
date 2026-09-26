#!/bin/sh
set -eu
case "${CI_XCODEBUILD_ACTION:-}" in
  archive)
    if [ "${CI_BRANCH:-}" != main ] || [ "${CI_WORKFLOW:-}" != 'GemmaTrans Release' ] || [ -n "${CI_PULL_REQUEST_NUMBER:-}" ]; then
      echo 'Release archive requires the manual GemmaTrans Release workflow on main, outside a PR.' >&2
      exit 1
    fi
    case "${CI_BUILD_NUMBER:-}" in
      ''|*[!0-9]*|0) echo 'Missing valid Cloud build number.' >&2; exit 1 ;;
    esac
    # Cloud overrides CURRENT_PROJECT_VERSION; align the static plist with it.
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CI_BUILD_NUMBER" "$CI_PRIMARY_REPOSITORY_PATH/App/GemmaTrans/Info.plist"
    RELEASE_SOURCE_SHA=$(git -C "$CI_PRIMARY_REPOSITORY_PATH" rev-parse HEAD)
    echo "Release source: $RELEASE_SOURCE_SHA; Cloud build: $CI_BUILD_NUMBER"
    ;;
  build|test|analyze) ;;
  *) echo 'Missing or unsupported Cloud build action.' >&2; exit 1 ;;
esac
exec /bin/bash "$CI_PRIMARY_REPOSITORY_PATH/script/ci_validate.sh"
