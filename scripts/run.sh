#!/usr/bin/env bash
# Builds, then opens the app.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh
open .build/xcode/Build/Products/Debug/Kortex.app
