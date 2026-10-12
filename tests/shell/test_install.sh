#!/bin/bash
# Shell tests for install.sh — hermetic (throwaway HOME/XDG, stubbed omarchy/sudo).
# The key guarantee: an existing user tmux.conf is never destroyed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="$ROOT/install.sh"
pass=0; fail=0
ok()  { echo "  ok: $*"; pass=$((pass+1)); }
bad() { echo "  FAIL: $*"; fail=$((fail+1)); }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
export XDG_STATE_HOME="$SANDBOX/state"
export XDG_CONFIG_HOME="$SANDBOX/config"
export XDG_DATA_HOME="$SANDBOX/data"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
mkdir -p "$XDG_STATE_HOME/omarchy/current/theme"
cat > "$XDG_STATE_HOME/omarchy/current/theme/colors.toml" <<'TOML'
mode = "dark"
accent = "#82FB9C"
selection = "#1f253a"
muted = "#2d3450"
background = "#0B0C16"
foreground = "#ddf7ff"
TOML

# stub omarchy + sudo, first on PATH
BIN="$SANDBOX/bin"; mkdir -p "$BIN"; export PATH="$BIN:$PATH"
printf '#!/bin/bash\nexit 0\n' > "$BIN/omarchy"
printf '#!/bin/bash\nexit 0\n' > "$BIN/sudo"
chmod +x "$BIN/omarchy" "$BIN/sudo"

# a pre-existing user config with a source line already? no — plain content
TMUX_DIR="$XDG_CONFIG_HOME/tmux"
mkdir -p "$TMUX_DIR"
printf '# my precious config\nset -g mouse on\n' > "$TMUX_DIR/tmux.conf"
mkdir -p "$XDG_CONFIG_HOME/hypr"
printf -- '-- main config\n' > "$XDG_CONFIG_HOME/hypr/hyprland.lua"

bash "$INSTALL" >"$SANDBOX/install.log" 2>&1
rc=$?

if (( rc == 0 )); then ok "install.sh exit 0"; else bad "install.sh exit $rc"; cat "$SANDBOX/install.log"; fi

if [[ -f "$TMUX_DIR/tmux.conf" ]] && grep -q "my precious config" "$TMUX_DIR/tmux.conf"; then
  ok "existing tmux.conf preserved"
else
  bad "user tmux.conf was destroyed"
fi
if grep -q "source-file" "$TMUX_DIR/tmux.conf"; then
  ok "source-file line appended"
else
  bad "no source-file line added"
fi
if [[ -f "$TMUX_DIR/omarchy-theme.conf" ]]; then
  ok "theme conf generated"
else
  bad "theme conf not generated"
fi
if [[ -f "$XDG_CONFIG_HOME/hypr/tmux-bindings.lua" ]]; then
  ok "hyprland bindings module installed"
else
  bad "bindings module missing"
fi
if grep -q "hypr.tmux-bindings" "$XDG_CONFIG_HOME/hypr/hyprland.lua"; then
  ok "keybindings wired into hyprland.lua"
else
  bad "keybindings not wired"
fi

# re-running must not duplicate the source line
bash "$INSTALL" >"$SANDBOX/install2.log" 2>&1
n="$(grep -c "source-file" "$TMUX_DIR/tmux.conf")"
if (( n == 1 )); then ok "idempotent: one source-file line"; else bad "duplicated source line ($n)"; fi

echo
if (( fail == 0 )); then echo "shell: all $pass passed"; exit 0; else echo "shell: $fail failed"; exit 1; fi
