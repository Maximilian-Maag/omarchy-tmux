#!/bin/bash
# omarchy-tmux install script. Run once after cloning, or re-run to update.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Optional config override, passed through to every CLI invocation. The shell
# tests use it to prove a custom config/tmux.json is honoured end to end; a
# normal user runs the installer bare and the plugin's own config/tmux.json is
# used.
CLI_ARGS=()
if [[ -n "${OMARCHY_TMUX_CONFIG:-}" ]]; then
  CLI_ARGS=(--config "$OMARCHY_TMUX_CONFIG")
fi

echo "omarchy-tmux: installing from $PLUGIN_DIR"

# ── 1. Validate the plugin ────────────────────────────────────────────────────
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$PLUGIN_DIR" && echo "  manifest OK."
fi

# ── 2. Put the CLI on PATH (symlink, so git pull keeps it current) ────────────
BIN_SRC="$PLUGIN_DIR/bin/omarchy-tmux"
BIN_DEST="/usr/local/bin/omarchy-tmux"
chmod +x "$BIN_SRC"
if [[ -L "$BIN_DEST" ]] && [[ "$(readlink -f "$BIN_DEST")" == "$(readlink -f "$BIN_SRC")" ]]; then
  echo "  omarchy-tmux already on PATH."
elif (( EUID == 0 )); then
  ln -sf "$BIN_SRC" "$BIN_DEST" && echo "  Installed $BIN_DEST."
elif command -v sudo >/dev/null 2>&1; then
  sudo ln -sf "$BIN_SRC" "$BIN_DEST" && echo "  Installed $BIN_DEST."
else
  echo "  WARNING: no sudo — add $BIN_SRC to PATH manually."
fi

# ── 3. Generate the theme conf now ────────────────────────────────────────────
"$BIN_SRC" "${CLI_ARGS[@]}" theme || echo "  WARNING: no applied theme yet — run 'omarchy-tmux theme' later."

# ── 4. Make the user's tmux.conf source our file (never clobber it) ───────────
# The path comes from the CLI (config/tmux.json's conf_path), so a custom
# conf_path is honoured rather than silently ignored. Nothing the user wrote is
# ever destroyed: the line is appended at most once, guarded against duplicates.
TMUX_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tmux"
TMUX_CONF="$TMUX_DIR/tmux.conf"
PATHS="$("$BIN_SRC" "${CLI_ARGS[@]}" paths 2>/dev/null || true)"
CONF_PATH="$(printf '%s\n' "$PATHS" | sed -n 's/^conf_path=//p')"
if [[ -z "$CONF_PATH" ]]; then
  echo "  WARNING: could not read conf_path from the CLI — using the built-in default."
  CONF_PATH="$TMUX_DIR/omarchy-theme.conf"
fi
SOURCE_LINE="source-file $CONF_PATH"
mkdir -p "$TMUX_DIR"
if [[ -f "$TMUX_CONF" ]]; then
  if grep -qF "$SOURCE_LINE" "$TMUX_CONF" || grep -q "omarchy-theme.conf" "$TMUX_CONF"; then
    echo "  tmux.conf already sources $CONF_PATH."
  else
    printf '\n# omarchy-tmux theme\n%s\n' "$SOURCE_LINE" >> "$TMUX_CONF"
    echo "  Added source-file to $TMUX_CONF (your config is otherwise untouched)."
  fi
else
  printf '# omarchy-tmux theme\n%s\n' "$SOURCE_LINE" > "$TMUX_CONF"
  echo "  Created $TMUX_CONF sourcing $CONF_PATH."
fi

# ── 5. Theme-set hook (uniquely named to avoid basename collisions) ───────────
chmod +x "$PLUGIN_DIR/hooks/tmux-theme-set"
if command -v omarchy >/dev/null 2>&1; then
  omarchy hook install theme-set "$PLUGIN_DIR/hooks/tmux-theme-set"
  echo "  Installed theme-set hook (as tmux-theme-set)."
fi

# ── 6. Wire OS keybindings into Hyprland ──────────────────────────────────────
HYPR_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
HYPR_MAIN="$HYPR_CONFIG_DIR/hyprland.lua"
if [[ -f "$HYPR_MAIN" ]]; then
  # The CLI renders bin/bindings.lua with the configured `keybinding`, so the
  # installed module always matches config/tmux.json.
  "$BIN_SRC" "${CLI_ARGS[@]}" bindings
else
  echo "  WARNING: $HYPR_MAIN not found — add: require(\"hypr.tmux-bindings\")"
fi

echo ""
echo "Done. Try:  omarchy-tmux theme   /   omarchy-tmux status"
echo "Reload tmux with:  tmux source-file ~/.config/tmux/omarchy-theme.conf"
