#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
scratch="${SCRATCH_PATH:-.build}"
out="${APP_OUTPUT:-build/Tac.app}"
identity="${SIGNING_IDENTITY:--}"
args=(--scratch-path "$scratch" -c "$configuration")
if [[ "${UNIVERSAL:-0}" == 1 ]]; then args+=(--arch arm64 --arch x86_64); fi
swift build "${args[@]}"
bin=$(swift build "${args[@]}" --show-bin-path)
framework=$(find "$scratch/artifacts" -path '*/macos-arm64_x86_64/Sparkle.framework' -type d -print -quit)
[[ -n "$framework" ]] || { echo "Sparkle.framework not found" >&2; exit 1; }
[[ "$out" == build/*.app ]] || { echo "APP_OUTPUT must be a build/*.app path" >&2; exit 1; }
rm -rf "$out"
mkdir -p "$out/Contents/MacOS" "$out/Contents/Resources" "$out/Contents/Frameworks"
cp "$bin/Tac" "$out/Contents/MacOS/"
cp Resources/Info.plist "$out/Contents/"
cp Resources/AppIcon.icns "$out/Contents/Resources/"
cp LICENSE "$out/Contents/Resources/"
ditto "$framework" "$out/Contents/Frameworks/Sparkle.framework"
sparkle="$out/Contents/Frameworks/Sparkle.framework/Versions/B"
sign_args=(--force --sign "$identity")
if [[ "$identity" != - ]]; then sign_args+=(--options runtime --timestamp); fi
for component in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
    codesign "${sign_args[@]}" --preserve-metadata=entitlements "$sparkle/$component"
done
codesign "${sign_args[@]}" "$out/Contents/Frameworks/Sparkle.framework"
codesign "${sign_args[@]}" "$out"
codesign --verify --deep --strict "$out"
echo "Built $out"
