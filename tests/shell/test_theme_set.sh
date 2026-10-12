#!/bin/bash
# Shell tests for hooks/tmux-theme-set — hermetic (throwaway HOME/XDG, stub tmux).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/hooks/tmux-theme-set"
pass=0; fail=0
ok()  { echo "  ok: $*"; pass=$((pass+1)); }
bad() { echo "  FAIL: $*"; fail=$((fail+1)); }

setup() {
  SANDBOX="$(mktemp -d)"
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
  BIN="$SANDBOX/bin"
  mkdir -p "$BIN"
  export PATH="$BIN:$PATH"
  export TMUX_LOG="$SANDBOX/tmux.log"
  : > "$TMUX_LOG"
  cat > "$BIN/tmux" <<'TMUX'
#!/bin/bash
echo "tmux $*" >> "$TMUX_LOG"
case "${1:-}" in
  list-sessions) exit "${TMUX_RUNNING:-1}" ;;
  *) exit "${TMUX_SOURCE_RC:-0}" ;;
esac
TMUX
  chmod +x "$BIN/tmux"
}

teardown() { rm -rf "$SANDBOX"; }
CONF() { printf '%s\n' "$XDG_CONFIG_HOME/tmux/omarchy-theme.conf"; }

# 1. plugin found, tmux NOT running -> conf generated, nothing sourced
setup
export OMARCHY_TMUX_DIR="$ROOT"
bash "$HOOK" "Hackerman"; rc=$?
if [[ -f "$(CONF)" ]]; then ok "conf generated from the applied theme"; else bad "no conf written"; fi
if (( rc == 0 )); then ok "hook exit 0"; else bad "hook exit $rc"; fi
if grep -q "source-file" "$TMUX_LOG"; then bad "sourced tmux with no server running"; else ok "no source-file while tmux is down"; fi
if grep -q "list-sessions" "$TMUX_LOG"; then ok "checked whether a server runs"; else bad "never checked for a running server"; fi
teardown

# 2. tmux running -> the generated conf is sourced
setup
export OMARCHY_TMUX_DIR="$ROOT"
export TMUX_RUNNING=0
bash "$HOOK" "Hackerman"
if grep -q "source-file" "$TMUX_LOG"; then ok "sourced the conf into a running server"; else bad "did not reload a running server"; fi
if grep -q "omarchy-theme.conf" "$TMUX_LOG"; then ok "sourced the generated file"; else bad "sourced the wrong path"; fi
teardown

# 3. empty theme name -> no-op (kills the -z guard mutation)
setup
export OMARCHY_TMUX_DIR="$ROOT"
bash "$HOOK" ""; rc=$?
if [[ ! -e "$(CONF)" ]]; then ok "empty theme writes nothing"; else bad "empty theme generated a conf"; fi
if (( rc == 0 )); then ok "empty theme exit 0"; else bad "empty theme exit $rc"; fi
teardown

# 4. plugin not found -> graceful no-op
setup
export OMARCHY_TMUX_DIR="$SANDBOX/nope"
bash "$HOOK" "Hackerman"; rc=$?
if (( rc == 0 )); then ok "missing plugin exit 0"; else bad "missing plugin exit $rc"; fi
if [[ ! -e "$(CONF)" ]]; then ok "missing plugin writes nothing"; else bad "wrote without a plugin"; fi
teardown

# 5. self-location fallback (kills the && -> || mutation in find_plugin)
setup
mkdir -p "$HOME/Work"
ln -s "$ROOT" "$HOME/Work/omarchy-tmux"
export OMARCHY_TMUX_DIR="$SANDBOX/emptydir"
mkdir -p "$OMARCHY_TMUX_DIR"
bash "$HOOK" "Hackerman"
if [[ -f "$(CONF)" ]]; then ok "fell back to the dev checkout"; else bad "did not self-locate"; fi
teardown

# 6. a failing CLI must not abort the hook (kills the || -> && mutation)
setup
export OMARCHY_TMUX_DIR="$ROOT"
rm -f "$XDG_STATE_HOME/omarchy/current/theme/colors.toml"
bash "$HOOK" "Hackerman"; rc=$?
if (( rc == 0 )); then ok "hook survives a CLI failure"; else bad "CLI failure aborted the hook (exit $rc)"; fi
teardown

# 7. a failing source-file must not abort the hook (kills the || -> && mutation)
setup
export OMARCHY_TMUX_DIR="$ROOT"
export TMUX_RUNNING=0
export TMUX_SOURCE_RC=1
bash "$HOOK" "Hackerman"; rc=$?
if (( rc == 0 )); then ok "hook survives a source-file failure"; else bad "source-file failure aborted the hook (exit $rc)"; fi
teardown

echo
if (( fail == 0 )); then echo "shell: all $pass passed"; exit 0; else echo "shell: $fail failed"; exit 1; fi
