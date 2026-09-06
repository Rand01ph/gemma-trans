#!/bin/sh
# The public app remains independently buildable via GitHub CI and Xcode.
# Its old Xcode Cloud publisher must not replace the separately assembled App Store app.
set -eu
echo 'GemmaTrans 2.2 Xcode Cloud distribution must use the private repository.' >&2
exit 1
