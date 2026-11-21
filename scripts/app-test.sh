#!/bin/zsh
# Walks the real native app through every screen with a real Claude Code agent, on a throwaway data folder and repo.
# Screenshots go to $1 (default: a temp folder).
set -euo pipefail
cd "${0:A:h}/.."
out="${1:-$(mktemp -d)}"; mkdir -p "$out"
data="$(mktemp -d)"; repo="$(mktemp -d)"
git -C "$repo" init -q -b main; echo "# test" > "$repo/README.md"
git -C "$repo" add .; git -C "$repo" -c user.name=T -c user.email=t@t commit -qm init
AGENT_LAB_SNAPSHOT="$out" AGENT_LAB_DATA="$data" AGENT_LAB_TEST_REPO="$repo" "./Agent Lab.app/Contents/MacOS/AgentLab" && rc=0 || rc=$?
rm -rf "$data" "$repo"
echo "screenshots: $out"
exit $rc
