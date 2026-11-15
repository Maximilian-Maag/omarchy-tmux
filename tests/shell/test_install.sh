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

# a custom conf_path (OMARCHY_TMUX_CONFIG) is the file generated AND sourced
# (regression for #1: the installer must resolve conf_path from the config).
CUSTOM_CONF="$SANDBOX/custom.json"
printf '{ "conf_path": "tmux/custom-theme.conf" }\n' > "$CUSTOM_CONF"
rm -f "$XDG_CONFIG_HOME/tmux/custom-theme.conf"
echo "# fresh tmux.conf" > "$TMUX_DIR/tmux.conf"
OMARCHY_TMUX_CONFIG="$CUSTOM_CONF" bash "$INSTALL" >"$SANDBOX/install3.log" 2>&1
if [[ -f "$XDG_CONFIG_HOME/tmux/custom-theme.conf" ]]; then
  ok "install generated the overridden conf_path"
else
  bad "install ignored the overridden conf_path"; cat "$SANDBOX/install3.log"
fi
if grep -q "custom-theme.conf" "$TMUX_DIR/tmux.conf"; then
  ok "install sourced the overridden conf_path"
else
  bad "install wrote the wrong source-file line"; cat "$TMUX_DIR/tmux.conf"
fi

# #6 both directions: changing conf_path must REPLACE the stale source line (not
# keep it, and not append a duplicate). default -> custom -> default.
printf '# user config\n' > "$TMUX_DIR/tmux.conf"
bash "$INSTALL" >/dev/null 2>&1
if grep -qF "source-file $TMUX_DIR/omarchy-theme.conf" "$TMUX_DIR/tmux.conf"; then
  ok "default conf_path sourced"
else
  bad "default conf_path not sourced"; cat "$TMUX_DIR/tmux.conf"
fi
OMARCHY_TMUX_CONFIG="$CUSTOM_CONF" bash "$INSTALL" >/dev/null 2>&1
if grep -q "omarchy-theme.conf" "$TMUX_DIR/tmux.conf" && ! grep -q "custom-theme.conf" "$TMUX_DIR/tmux.conf"; then
  bad "conf_path change left the stale default line"; cat "$TMUX_DIR/tmux.conf"
else
  ok "conf_path change reconciled the stale default line"
fi
n="$(grep -c "omarchy-theme.conf" "$TMUX_DIR/tmux.conf")"
if (( n == 0 )); then ok "no duplicate default line after conf_path change"; else bad "stale default line kept ($n)"; fi
bash "$INSTALL" >/dev/null 2>&1
if grep -qF "source-file $TMUX_DIR/omarchy-theme.conf" "$TMUX_DIR/tmux.conf" && ! grep -q "custom-theme.conf" "$TMUX_DIR/tmux.conf"; then
  ok "conf_path reverted back to default"
else
  bad "reverting conf_path left the custom line"; cat "$TMUX_DIR/tmux.conf"
fi
n="$(grep -c "source-file" "$TMUX_DIR/tmux.conf")"
if (( n == 1 )); then ok "exactly one source-file line after two changes"; else bad "wrong source-file count ($n)"; cat "$TMUX_DIR/tmux.conf"; fi

# #10: the closing "reload" hint must point at the resolved conf_path, not the
# hardcoded default, so an override is not mis-reported.
OMARCHY_TMUX_CONFIG="$CUSTOM_CONF" bash "$INSTALL" >"$SANDBOX/install4.log" 2>&1
if grep -q "Reload tmux with:  tmux source-file $XDG_CONFIG_HOME/tmux/custom-theme.conf" "$SANDBOX/install4.log"; then
  ok "final hint uses the resolved conf_path"
else
  bad "final hint hardcoded a path"; grep "Reload tmux" "$SANDBOX/install4.log"
fi

# ── uninstall ─────────────────────────────────────────────────────────────────
# A dedicated, writable bin dir so the CLI symlink is exercised end to end without
# root: OMARCHY_TMUX_BIN points install and uninstall at it, and the sudo stub is
# made to actually run the command it is handed (the dir needs no privilege).
cat > "$BIN/sudo" <<'SUDO'
#!/bin/bash
exec "$@"
SUDO
chmod +x "$BIN/sudo"
export OMARCHY_TMUX_BIN="$SANDBOX/localbin"
mkdir -p "$OMARCHY_TMUX_BIN"

# The user's own tmux.conf and hyprland.lua (the latter with a require line they
# added by hand for a module that is not ours), plus a manually-placed theme-set
# hook — what `omarchy hook install` would have written.
printf '# my precious config\nset -g mouse on\n' > "$TMUX_DIR/tmux.conf"
printf -- '-- my own hyprland.lua\nhl.monitor({ output = "eDP-1" })\nrequire("hypr.my-own-module")\n' \
  > "$XDG_CONFIG_HOME/hypr/hyprland.lua"
mkdir -p "$XDG_CONFIG_HOME/omarchy/hooks/theme-set.d"
printf '#!/bin/bash\n' > "$XDG_CONFIG_HOME/omarchy/hooks/theme-set.d/tmux-theme-set"
before_tmux="$(sha256sum "$TMUX_DIR/tmux.conf" | cut -d' ' -f1)"
before_hypr="$(sha256sum "$XDG_CONFIG_HOME/hypr/hyprland.lua" | cut -d' ' -f1)"

bash "$INSTALL" >"$SANDBOX/install-u.log" 2>&1
if [[ -L "$OMARCHY_TMUX_BIN/omarchy-tmux" ]] \
   && [[ "$(readlink -f "$OMARCHY_TMUX_BIN/omarchy-tmux")" == "$ROOT/bin/omarchy-tmux" ]]; then
  ok "install links the CLI into the override bin dir"
else
  bad "CLI not linked into the override bin dir"; cat "$SANDBOX/install-u.log"
fi

bash "$INSTALL" --uninstall >"$SANDBOX/uninstall.log" 2>&1
rc=$?
if (( rc == 0 )); then ok "uninstall exit 0"; else bad "uninstall exit $rc"; cat "$SANDBOX/uninstall.log"; fi

if [[ ! -e "$OMARCHY_TMUX_BIN/omarchy-tmux" ]]; then
  ok "the CLI symlink is removed"
else
  bad "CLI symlink survived the uninstall"
fi

if [[ "$(sha256sum "$XDG_CONFIG_HOME/hypr/hyprland.lua" | cut -d' ' -f1)" == "$before_hypr" ]]; then
  ok "install/uninstall round-trip leaves hyprland.lua byte-identical"
else
  bad "hyprland.lua changed across the round-trip"; cat "$XDG_CONFIG_HOME/hypr/hyprland.lua"
fi
if [[ "$(sha256sum "$TMUX_DIR/tmux.conf" | cut -d' ' -f1)" == "$before_tmux" ]]; then
  ok "install/uninstall round-trip leaves tmux.conf byte-identical"
else
  bad "tmux.conf changed across the round-trip"; cat "$TMUX_DIR/tmux.conf"
fi
n="$(grep -c -- '-- omarchy-tmux keybindings' "$XDG_CONFIG_HOME/hypr/hyprland.lua" || true)"
if (( n == 0 )); then ok "no keybindings marker is left behind"; else bad "marker left behind ($n)"; fi
if grep -q 'hypr.my-own-module' "$XDG_CONFIG_HOME/hypr/hyprland.lua"; then
  ok "a hand-added require line survives the uninstall"
else
  bad "the user's hand-added require line was removed"
fi
if grep -q 'my precious config' "$TMUX_DIR/tmux.conf" && ! grep -q 'source-file' "$TMUX_DIR/tmux.conf"; then
  ok "the user's own tmux.conf survives with our source line gone"
else
  bad "the user's tmux.conf was not restored"; cat "$TMUX_DIR/tmux.conf"
fi

if [[ ! -e "$XDG_CONFIG_HOME/hypr/tmux-bindings.lua" ]]; then
  ok "the rendered bindings module is removed"
else
  bad "bindings module survived the uninstall"
fi
if [[ ! -e "$XDG_CONFIG_HOME/omarchy/hooks/theme-set.d/tmux-theme-set" ]]; then
  ok "the theme-set hook is removed"
else
  bad "theme-set hook survived the uninstall"
fi

# The generated theme conf is NOT an install artifact to reverse — the theme-set
# hook regenerates it, so an uninstall must leave it where it is.
if [[ -f "$TMUX_DIR/omarchy-theme.conf" ]]; then
  bash "$INSTALL" >/dev/null 2>&1
  bash "$INSTALL" --uninstall >/dev/null 2>&1
  if [[ -f "$TMUX_DIR/omarchy-theme.conf" ]]; then
    ok "the generated theme conf is left alone by an uninstall"
  else
    bad "uninstall removed the generated theme conf"
  fi
fi

# A symlink that points somewhere else is not ours: the uninstall says so and leaves it.
ln -sfn /bin/true "$OMARCHY_TMUX_BIN/omarchy-tmux"
out="$(bash "$INSTALL" --uninstall 2>&1)"
if [[ "$(readlink "$OMARCHY_TMUX_BIN/omarchy-tmux")" == "/bin/true" ]]; then
  ok "a foreign symlink is left alone"
else
  bad "uninstall touched a foreign symlink"
fi
if [[ $out == *"not a link into this checkout"* ]]; then
  ok "and the refusal is reported"
else
  bad "uninstall did not say why it left the foreign symlink"; printf '%s\n' "$out"
fi
rm -f "$OMARCHY_TMUX_BIN/omarchy-tmux"

# A bare require line for OUR module, added by hand with no marker above it, is the
# user's own line — install never writes one without the marker — so it survives too,
# and the config comes back byte-identical.
printf -- '-- my own hyprland.lua\nrequire("hypr.tmux-bindings")\n' \
  > "$XDG_CONFIG_HOME/hypr/hyprland.lua"
before2="$(sha256sum "$XDG_CONFIG_HOME/hypr/hyprland.lua" | cut -d' ' -f1)"
bash "$INSTALL" >/dev/null 2>&1
bash "$INSTALL" --uninstall >/dev/null 2>&1
if [[ "$(sha256sum "$XDG_CONFIG_HOME/hypr/hyprland.lua" | cut -d' ' -f1)" == "$before2" ]]; then
  ok "a hand-added bare require line survives the round-trip too"
else
  bad "a hand-added bare require line was removed"; cat "$XDG_CONFIG_HOME/hypr/hyprland.lua"
fi

# Uninstalling when nothing is installed is not an error (idempotent teardown).
bash "$INSTALL" --uninstall >/dev/null 2>&1
if (( $? == 0 )); then ok "uninstalling nothing succeeds"; else bad "uninstalling nothing failed"; fi

echo
if (( fail == 0 )); then echo "shell: all $pass passed"; exit 0; else echo "shell: $fail failed"; exit 1; fi
