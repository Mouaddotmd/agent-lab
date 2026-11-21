#!/bin/zsh
# Screenshots every screen and state of the native app (no window), at full width and two narrower widths, into one
# folder with a gallery page, so a redesign is reviewed on every screen at once instead of found broken one by one.
#   tools/shotall.sh [label]     → build/shots/<date>-<label>/index.html
# Needs build/snapshot (built by build.sh). SNAP_ENGINE=1 loads your real agents first.
set -euo pipefail
cd "${0:A:h}/.."
[[ -x build/snapshot ]] || { echo "build/snapshot is missing: run ./build.sh first"; exit 1; }
out="build/shots/$(date +%Y%m%d-%H%M)-${1:-now}"
mkdir -p "$out"
views=(agents discover reviews messages team memory usage connections profile)
states=(settings history search newagent workspace)
widths=(1392 1100 900)
shots=()
shot() { # name, then env assignments, then snapshot args
  local name=$1; shift
  if env "$@" >/dev/null 2>&1; then shots+=("$name"); else echo "  failed: $name"; fi
}
for w in $widths; do
  for v in $views; do shot "$v-$w" SNAP_W=$w build/snapshot "$out/$v-$w.png" $v; done
  for s in $states; do shot "agents+$s-$w" SNAP_W=$w build/snapshot "$out/agents+$s-$w.png" agents $s; done
  shot "chat-$w" SNAP_W=$w SNAP_OPEN=1 build/snapshot "$out/chat-$w.png" agents
  shot "chat-folded-$w" SNAP_W=$w SNAP_OPEN=1 SNAP_FOLD=1 build/snapshot "$out/chat-folded-$w.png" agents
done
for p in account claude ready; do shot "welcome-$p" SNAP_WELCOME=$p build/snapshot "$out/welcome-$p.png"; done
{
  print '<!doctype html><meta charset=utf-8><title>Agent Lab screens</title>'
  print '<style>body{margin:0;background:#111;color:#bbb;font:13px -apple-system,sans-serif;padding:24px}figure{margin:0 0 32px}img{max-width:100%;border-radius:8px;display:block}figcaption{margin:6px 0 0}</style>'
  for s in $shots; do print "<figure><img src=\"$s.png\" loading=lazy><figcaption>$s</figcaption></figure>"; done
} > "$out/index.html"
echo "${#shots} screens → $out/index.html"
