#!/bin/zsh
# Builds "Agent Lab Native.app", the 1:1 SwiftUI version of the web app.
#   ./native/build.sh          build
#   ./native/build.sh run      build, then open it
set -euo pipefail
cd "${0:A:h}"
# The MAVIS system (docs/mavis-system.md): no view may add a raw colour or measurement. The count only goes down.
python3 tools/systemlint.py
node scripts/gen-icons.mjs >/dev/null
app="build/Agent Lab Native.app"
rm -rf "$app"; mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Agent Lab</string>
  <key>CFBundleIdentifier</key><string>dev.agentlab.native</string>
  <key>CFBundleExecutable</key><string>AgentLabNative</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Agent Lab listens while you hold the mic, to write what you say into the message box.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Agent Lab turns what you say into text in the message box.</string>
  <!-- The Browser tab opens plain http pages too (local servers, older sites); the app's own connections stay https. -->
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoadsInWebContent</key><true/><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
# The account service (Account.swift): your Supabase project and Google key, from native/accounts.env (kept out of
# git; see docs/accounts.md). Without it the build has no accounts and the welcome skips signing in.
if [[ -f accounts.env ]]; then
  source accounts.env
  for pair in "AgentLabAuthURL:$AGENTLAB_AUTH_URL" "AgentLabAuthKey:$AGENTLAB_AUTH_KEY" "AgentLabGoogleClientID:$AGENTLAB_GOOGLE_CLIENT_ID" \
              "AgentLabGoogleClientSecret:$AGENTLAB_GOOGLE_CLIENT_SECRET" "AgentLabPrivacyURL:$AGENTLAB_PRIVACY_URL"; do
    key=${pair%%:*}; value=${pair#*:}
    [[ -n "$value" ]] && /usr/libexec/PlistBuddy -c "Add :$key string $value" "$app/Contents/Info.plist"
  done
  echo "accounts: on"
fi
cp ../src/renderer/fonts/*.otf "$app/Contents/Resources/"
cp Assets/operators/*.png "$app/Contents/Resources/"      # operator logos: claude-code.png, codex.png
# The Terminal tab's screen (TerminalTab.swift): xterm.js and its fit and links add-ons, pinned in package.json, read
# from inside the app so nothing loads from the network.
mkdir -p "$app/Contents/Resources/terminal"
cp ../node_modules/@xterm/xterm/lib/xterm.js ../node_modules/@xterm/xterm/css/xterm.css \
   ../node_modules/@xterm/addon-fit/lib/addon-fit.js ../node_modules/@xterm/addon-web-links/lib/addon-web-links.js "$app/Contents/Resources/terminal/"
xcrun swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx15.0 Sources/*.swift -o "$app/Contents/MacOS/AgentLabNative"
# The engine lives inside the app (Resources/engine + only the packages it needs), so starting it never reads the
# Desktop: macOS has nothing to ask about before your agents show (17 Nov: "would like to access your Desktop folder"
# on every launch, with "No agents yet" until you allowed it). Copies are APFS clones: instant, no extra space.
res="$app/Contents/Resources"
mkdir -p "$res/engine"
cp ../engine/*.js "$res/engine/"
print '{"type":"module"}' > "$res/package.json"
for dep in ${(f)"$(node scripts/engine-deps.mjs)"}; do mkdir -p "$res/${dep:h}"; cp -Rc "../$dep" "$res/${dep:h}/"; done
# Signed with your Apple Development certificate when there is one: macOS then knows it's the same app after every
# rebuild and keeps whatever you allowed. Without one it falls back to ad-hoc (macOS forgets on each build).
identity=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')
codesign --force --sign "${identity:--}" "$app" >/dev/null
[[ -n "$identity" ]] && echo "built $app (signed with your Apple Development certificate)" || echo "built $app (signed ad-hoc)"
# Moved to ~/Applications, outside the Desktop, and opened from there (no second copy left here to open by mistake).
installed="$HOME/Applications/Agent Lab Native.app"
# Updated in place, never deleted and replaced: it stays the same app (same Dock icon, same place, same permissions),
# just with the new build inside. rsync only rewrites what changed; --delete drops files the new build no longer has.
mkdir -p "$installed"
rsync -a --delete "$app/" "$installed/"
rm -rf "$app"
echo "updated $installed"
[[ "${1:-}" == run ]] && open "$installed" || true
# Tools for the pixel diff (no window): snapshot and diff.
srcs=(${(f)"$(ls Sources/*.swift | grep -v App.swift)"})
xcrun swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx15.0 $srcs tools/snapshot.swift -o build/snapshot
xcrun swiftc -O -swift-version 5 tools/diff.swift -o build/diff
xcrun swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx15.0 $srcs tools/chatrender.swift -o build/chatrender
xcrun swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx15.0 $srcs tools/enginetest.swift -o build/enginetest
xcrun swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx15.0 Sources/ChatCore.swift Sources/ChatTurns.swift Sources/Engine.swift tools/chattest.swift -o build/chattest
xcrun swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx15.0 $srcs tools/navtest.swift -o build/navtest
# Performance: opening, switching and resizing chats on real messages. build/chatperf <messages.json> [copies]
xcrun swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx15.0 $srcs tools/chatperf.swift -o build/chatperf
# The message box, driven with real keys in an offscreen window: build/boxtest <folder>
xcrun swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx15.0 $srcs tools/boxtest.swift -o build/boxtest
xcrun swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx15.0 $srcs tools/menushot.swift -o build/menushot
# Floating menus take clicks, Esc and outside clicks: build/menuclick
xcrun swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx15.0 $srcs tools/menuclick.swift -o build/menuclick
# The chat never goes black while the window or side panel changes its width: build/resizetest
xcrun swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx15.0 $srcs tools/resizetest.swift -o build/resizetest
# The side panel's slide in and out, quick clicks included: build/paneltest
xcrun swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx15.0 $srcs tools/paneltest.swift -o build/paneltest
# Icon buttons' labels: the pause, the side, centred, on screen, the next at once, a click hides: AL_TIP_TEST=1 build/tiptest
xcrun swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx15.0 $srcs tools/tiptest.swift -o build/tiptest
echo "built tools"
