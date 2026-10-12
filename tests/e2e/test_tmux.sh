#!/bin/bash
# e2e: generate a tmux theme conf from a synthetic applied theme, then prove it
# is a VALID tmux config by loading it on a throwaway socket. The user's real
# tmux session is never touched (-L gives an isolated server).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$ROOT/bin/omarchy-tmux"
WORK="$(mktemp -d)"
trap 'tmux -L omarchy-test kill-server >/dev/null 2>&1; rm -rf "$WORK"' EXIT

export HOME="$WORK/home"
export XDG_STATE_HOME="$WORK/state"
export XDG_CONFIG_HOME="$WORK/config"
mkdir -p "$HOME"
mkdir -p "$XDG_STATE_HOME/omarchy/current/theme"
cat > "$XDG_STATE_HOME/omarchy/current/theme/colors.toml" <<'TOML'
mode = "dark"
accent = "#82FB9C"
selection = "#1f253a"
muted = "#2d3450"
background = "#0B0C16"
foreground = "#ddf7ff"
TOML

"$CLI" theme
CONF="$XDG_CONFIG_HOME/tmux/omarchy-theme.conf"
if [[ ! -f "$CONF" ]]; then
  echo "e2e: FAILED — conf not generated" >&2
  exit 1
fi

for colour in "#82FB9C" "#1f253a" "#0B0C16" "#ddf7ff"; do
  if ! grep -q "$colour" "$CONF"; then
    echo "e2e: FAILED — generated conf is missing theme colour $colour" >&2
    exit 1
  fi
done

# The real assertion: tmux accepts the generated file as a valid config.
tmux -L omarchy-test kill-server >/dev/null 2>&1
if tmux -f "$CONF" -L omarchy-test start-server; then
  echo "e2e: ok — generated conf loaded by tmux $(tmux -V)"
  exit 0
fi
echo "e2e: FAILED — tmux rejected the generated conf" >&2
exit 1
