#!/bin/zsh
# Builds "Agent Lab.app" (native SwiftUI) from this folder.
#   ./build.sh        build
#   ./build.sh run    build, then open it
set -euo pipefail
cd "${0:A:h}"
[[ -d node_modules/@anthropic-ai/claude-agent-sdk ]] || npm install --silent

app="Agent Lab.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# The app runs the engine from this folder, so its path is written into Info.plist.
sed "s|__ENGINE__|${PWD}/engine|" app/Info.plist > "$app/Contents/Info.plist"

# Icon: drawn once by app/draw-icon.swift.
[[ -f app/AppIcon.png ]] || xcrun swift app/draw-icon.swift app/AppIcon.png
iconset="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s app/AppIcon.png --out "$iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) app/AppIcon.png --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
cp app/Fonts/*.ttf "$app/Contents/Resources/"
# The engine and its packages go inside the app (not Electron, not the SDK's fallback binary: agents use your own claude).
mkdir -p "$app/Contents/Resources/engine"
cp engine/*.js package.json "$app/Contents/Resources/engine/"
rsync -a --exclude electron --exclude '@electron*' --exclude 'claude-agent-sdk-darwin-*' node_modules "$app/Contents/Resources/engine/"

xcrun swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx26.0 \
  $(find app/Sources -name '*.swift' | sort) -o "$app/Contents/MacOS/AgentLab"
codesign --force --sign - "$app" >/dev/null
echo "built $app"
if [[ "${1:-}" == run || "${1:-}" == install ]]; then
  pkill -x AgentLab 2>/dev/null && sleep 0.5 || true
  # Installed outside Desktop, so macOS doesn't ask for Desktop access to run it.
  mkdir -p ~/Applications && rm -rf ~/Applications/"$app" && cp -R "$app" ~/Applications/
  echo "installed ~/Applications/$app"
  [[ "${1:-}" == run ]] && open ~/Applications/"$app"
fi
