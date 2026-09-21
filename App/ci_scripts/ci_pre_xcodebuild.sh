#!/bin/sh
# Cloud validates PR/develop builds; distribution remains blocked on this line.
set -eu
if [ "${CI_XCODEBUILD_ACTION:-}" = archive ]; then
  echo 'Archive is blocked until the main release-source migration is reviewed.' >&2
  exit 1
fi
case "${CI_XCODEBUILD_ACTION:-}" in
  build|test|analyze) ;;
  *) echo 'Missing or unsupported Cloud build action.' >&2; exit 1 ;;
esac
exec /bin/bash "$CI_PRIMARY_REPOSITORY_PATH/script/ci_validate.sh"
