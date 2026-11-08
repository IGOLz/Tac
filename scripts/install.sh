#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Alexandru Ciprian Craciun (884UZN5CH3)}" scripts/build.sh
pkill -x -f /Applications/Tac.app/Contents/MacOS/Tac || true
ditto build/Tac.app /Applications/Tac.app
open /Applications/Tac.app
