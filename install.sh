#!/bin/bash
# omarchy-tmux install script. Run once after cloning, or re-run to update.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
"$BIN_SRC" theme || echo "  WARNING: no applied theme yet — run 'omarchy-tmux theme' later."

# ── 4. Make the user's tmux.conf source our file (never clobber it) ───────────
TMUX_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tmux"
TMUX_CONF="$TMUX_DIR/tmux.conf"
SOURCE_LINE="source-file ${XDG_CONFIG_HOME:-$HOME/.config}/tmux/omarchy-theme.conf"
mkdir -p "$TMUX_DIR"
if [[ -f "$TMUX_CONF" ]]; then
  if grep -q "omarchy-theme.conf" "$TMUX_CONF"; then
    echo "  tmux.conf already sources omarchy-theme.conf."
  else
    printf '\n# omarchy-tmux theme\n%s\n' "$SOURCE_LINE" >> "$TMUX_CONF"
    echo "  Added source-file to $TMUX_CONF (your config is otherwise untouched)."
  fi
else
  printf '# omarchy-tmux theme\n%s\n' "$SOURCE_LINE" > "$TMUX_CONF"
  echo "  Created $TMUX_CONF sourcing omarchy-theme.conf."
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
  cp "$PLUGIN_DIR/bin/bindings.lua" "$HYPR_CONFIG_DIR/tmux-bindings.lua"
  if ! grep -q "tmux-bindings" "$HYPR_MAIN"; then
    printf '\n-- omarchy-tmux keybindings\nrequire("hypr.tmux-bindings")\n' >> "$HYPR_MAIN"
    echo "  Wired keybindings into $HYPR_MAIN"
  else
    echo "  Keybindings already wired (updated)."
  fi
else
  echo "  WARNING: $HYPR_MAIN not found — add: require(\"hypr.tmux-bindings\")"
fi

echo ""
echo "Done. Try:  omarchy-tmux theme   /   omarchy-tmux status"
echo "Reload tmux with:  tmux source-file ~/.config/tmux/omarchy-theme.conf"
