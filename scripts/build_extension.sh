#!/usr/bin/env bash
# Builds the DevTools extension Flutter web app and copies the output into
# packages/perfect_flutter/extension/devtools/build/, which is what gets
# shipped to pub.dev. Invoked by `melos run build:extension`.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXT_PKG="$REPO_ROOT/packages/perfect_flutter_devtools_extension"
RUNTIME_DEVTOOLS="$REPO_ROOT/packages/perfect_flutter/extension/devtools"

echo "==> Building DevTools extension web app..."
cd "$EXT_PKG"
dart run devtools_extensions build_and_copy \
  --source="$EXT_PKG" \
  --dest="$RUNTIME_DEVTOOLS"

echo "==> Bundled into $RUNTIME_DEVTOOLS/build/"
