#!/bin/bash
# Syncs Mactrix/Localizable.xcstrings with the strings used in the Swift package sources.
#
# The UI lives in Swift package targets, but translations are looked up in the app's main
# bundle, so all strings are kept in a single catalog in the app target. Xcode only syncs a
# catalog with the strings of its own target, so run this after adding or changing strings.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "${1:-}" != "--no-build" ]]; then
  xcodebuild build -quiet \
    -workspace Mactrix.xcworkspace \
    -scheme Mactrix \
    -destination 'platform=macOS,arch=arm64'
fi

objroot=$(xcodebuild -workspace Mactrix.xcworkspace -scheme Mactrix -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/^ *OBJROOT = / { print $2; exit }')
build_dir="$objroot/Mactrix.build/Debug"

targets=(Mactrix MactrixApp-t MactrixUI-t ContactLinking-t MatrixIntegration-t MatrixProtocols-t
  MessageFormatting-t Utils-t)
stringsdata=()
for target in "${targets[@]}"; do
  for file in "$build_dir/$target.build"/Objects-normal/arm64/*.stringsdata; do
    case "$(basename "$file")" in
      ExtractedAppShortcutsMetadata.stringsdata | GeneratedAssetSymbols.stringsdata) ;;
      *) [[ -f "$file" ]] && stringsdata+=(--stringsdata "$file") ;;
    esac
  done
done

xcrun xcstringstool sync Mactrix/Localizable.xcstrings "${stringsdata[@]}"
echo "Synced $((${#stringsdata[@]} / 2)) source files into Mactrix/Localizable.xcstrings"
