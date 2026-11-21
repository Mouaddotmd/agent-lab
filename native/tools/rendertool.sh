#!/bin/zsh
# Builds one tool against the app's sources (without App.swift), quicker than ./build.sh.
#   tools/rendertool.sh chatrender      → build/chatrender
set -euo pipefail
cd "${0:A:h}/.."
name=$1
files=()
for f in Sources/*.swift; do [[ "$f" == "Sources/App.swift" ]] || files+=("$f"); done
xcrun swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx15.0 $files "tools/$name.swift" -o "build/$name"
echo "built build/$name"
