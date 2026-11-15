#!/bin/bash
# omarchy-tmux install script. Run once after cloning, or re-run to update:
#
#   ./install.sh                     install / update everything
#   ./install.sh --uninstall         remove what this script installed, and only that
#   OMARCHY_TMUX_BIN=~/.local/bin ./install.sh   where the CLI is symlinked
#
# The CLI goes into a bin directory (default /usr/local/bin, on PATH); the
# theme-set hook is an `omarchy hook install`; the keybinding module and its
# require block live in the Hyprland config dir, and one `source-file` line is
# added to tmux.conf. `--uninstall` reverses exactly those, and leaves the user's
# own config values and the generated theme conf (which the hook regenerates)
# alone.
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

BIN_DIR="${OMARCHY_TMUX_BIN:-/usr/local/bin}"
BIN_SRC="$PLUGIN_DIR/bin/omarchy-tmux"
BIN_DEST="$BIN_DIR/omarchy-tmux"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
HYPR_CONFIG_DIR="$CONFIG_DIR/hypr"
HYPR_MAIN="$HYPR_CONFIG_DIR/hyprland.lua"
BINDINGS="$HYPR_CONFIG_DIR/tmux-bindings.lua"
REQUIRE_LINE='require("hypr.tmux-bindings")'
BINDINGS_MARKER='-- omarchy-tmux keybindings'
TMUX_DIR="$CONFIG_DIR/tmux"
TMUX_CONF="$TMUX_DIR/tmux.conf"
TMUX_MARKER='# omarchy-tmux theme'
HOOK_DEST="$CONFIG_DIR/omarchy/hooks/theme-set.d/tmux-theme-set"

# ── helpers ───────────────────────────────────────────────────────────────────
remove_path() {  # remove_path <path> — remove a file we installed; sudo only if the dir needs it
  local path="$1"
  if (( EUID == 0 )) || [[ -w "$(dirname "$path")" ]]; then
    rm -f "$path"
  elif command -v sudo >/dev/null 2>&1; then
    sudo rm -f "$path"
  else
    return 1
  fi
}

unlink_ours() {  # unlink_ours <dest> <source it must point at>
  local dest="$1" source="$2"
  if [[ -L $dest ]] && [[ "$(readlink -f "$dest")" == "$(readlink -f "$source")" ]]; then
    remove_path "$dest" && echo "  Removed $dest."
  elif [[ -e $dest ]]; then
    echo "  WARNING: $dest is not a link into this checkout — left alone."
  fi
}

uninstall() {
  echo "omarchy-tmux: uninstalling from $PLUGIN_DIR"

  # 1. The CLI symlink, and only if it points back into this checkout.
  unlink_ours "$BIN_DEST" "$BIN_SRC"

  # 2. The `source-file` block install appended to tmux.conf — our marker comment
  #    and the line directly after it, plus the blank line that preceded the
  #    marker. Removed one line at a time, never `sed -i`, so the user's config is
  #    only ever rewritten smaller and everything they wrote is left as it was.
  if [[ -f $TMUX_CONF ]] && grep -qF "$TMUX_MARKER" "$TMUX_CONF"; then
    mapfile -t lines < "$TMUX_CONF"
    out=()
    skip_next=0
    for line in "${lines[@]}"; do
      if (( skip_next )); then
        skip_next=0
        continue                       # the source-file line that followed the marker
      fi
      if [[ $line == "$TMUX_MARKER" ]]; then
        skip_next=1
        if (( ${#out[@]} )) && [[ -z ${out[-1]} ]]; then
          unset 'out[-1]'              # the blank line install put above the marker
        fi
        continue
      fi
      out+=("$line")
    done
    kept="$(mktemp)"
    for line in ${out[@]+"${out[@]}"}; do
      printf '%s\n' "$line"
    done > "$kept"
    mv "$kept" "$TMUX_CONF"
    echo "  Took the source-file line back out of $TMUX_CONF."
  fi

  # 3. The Hyprland keybinding module install rendered into the config dir.
  if [[ -f $BINDINGS ]]; then
    rm -f "$BINDINGS"
    echo "  Removed $BINDINGS."
  fi

  # 4. The require block install appended to hyprland.lua. Removed by exact line —
  #    never `sed -i` — so the user's config is only ever rewritten one line
  #    smaller. install writes the block as a blank line, a `-- omarchy-tmux
  #    keybindings` marker, then the require line, so the whole block comes back
  #    out: leaving the marker (and its blank line) behind would stack another
  #    marker on the file at every install/uninstall cycle. A require line with no
  #    marker above it was added by hand, so it is the user's and it survives.
  if [[ -f $HYPR_MAIN ]] && grep -qF "$REQUIRE_LINE" "$HYPR_MAIN"; then
    mapfile -t lines < "$HYPR_MAIN"
    out=()
    removed=0
    for line in "${lines[@]}"; do
      if [[ $line == "$REQUIRE_LINE" ]] && (( ${#out[@]} )) && [[ ${out[-1]} == "$BINDINGS_MARKER" ]]; then
        unset 'out[-1]'
        if (( ${#out[@]} )) && [[ -z ${out[-1]} ]]; then
          unset 'out[-1]'
        fi
        removed=1
        continue
      fi
      out+=("$line")
    done
    if (( removed )); then
      kept="$(mktemp)"
      for line in ${out[@]+"${out[@]}"}; do
        printf '%s\n' "$line"
      done > "$kept"
      mv "$kept" "$HYPR_MAIN"
      echo "  Took the require line back out of $HYPR_MAIN."
    fi
  fi

  # 5. The theme-set hook, if `omarchy hook install` put one there.
  if [[ -f $HOOK_DEST ]]; then
    rm -f "$HOOK_DEST"
    echo "  Removed the theme-set hook."
  fi

  echo ""
  echo "Done. The generated theme conf and your config values were left as they are."
  echo "Reload Hyprland config:  hyprctl reload"
}

if [[ ${1:-} == --uninstall ]]; then
  uninstall
  exit 0
fi

echo "omarchy-tmux: installing from $PLUGIN_DIR"

# ── 1. Validate the plugin ────────────────────────────────────────────────────
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate "$PLUGIN_DIR" && echo "  manifest OK."
fi

# ── 2. Put the CLI on PATH (symlink, so git pull keeps it current) ────────────
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
PATHS="$("$BIN_SRC" "${CLI_ARGS[@]}" paths 2>/dev/null || true)"
CONF_PATH="$(printf '%s\n' "$PATHS" | sed -n 's/^conf_path=//p')"
if [[ -z "$CONF_PATH" ]]; then
  echo "  WARNING: could not read conf_path from the CLI — using the built-in default."
  CONF_PATH="$TMUX_DIR/omarchy-theme.conf"
fi
SOURCE_LINE="source-file $CONF_PATH"
mkdir -p "$TMUX_DIR"
if [[ -f "$TMUX_CONF" ]]; then
  # Reconcile, don't just guard: drop any block WE previously added — our marker
  # comment and the source-file line directly after it — so a conf_path change
  # replaces the stale line instead of leaving tmux sourcing the old path (or
  # appending a duplicate). A source-file line the user wrote themselves carries
  # no marker and is left untouched.
  tmp="$(mktemp)"
  awk '
    /^# omarchy-tmux theme$/ { skip=1; next }
    skip { skip=0; next }
    { print }
  ' "$TMUX_CONF" > "$tmp"
  mv "$tmp" "$TMUX_CONF"
  if grep -qF "$SOURCE_LINE" "$TMUX_CONF"; then
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
if [[ -f "$HYPR_MAIN" ]]; then
  # The CLI renders bin/bindings.lua with the configured `keybinding`, so the
  # installed module always matches config/tmux.json.
  "$BIN_SRC" "${CLI_ARGS[@]}" bindings
else
  echo "  WARNING: $HYPR_MAIN not found — add: require(\"hypr.tmux-bindings\")"
fi

echo ""
echo "Done. Try:  omarchy-tmux theme   /   omarchy-tmux status"
echo "Reload tmux with:  tmux source-file $CONF_PATH"
