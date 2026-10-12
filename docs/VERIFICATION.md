# Verification notes

What was actually run and observed while building this plugin, plus what could
not be verified.

## Machine

- Arch Linux, Hyprland/Omarchy, user `mmaag`.
- `tmux 3.7c` at `/usr/bin/tmux`.
- Applied theme: **Hackerman** (`omarchy theme current`), colours read from
  `~/.local/state/omarchy/current/theme/colors.toml`
  (`accent = #82FB9C`, `background = #0B0C16`, `selection = #1f253a`,
  `muted = #2d3450`, `foreground = #ddf7ff`).

## Existing user config (not destroyed)

`~/.config/tmux/tmux.conf` already existed (4185 bytes). There was no
`~/.tmux.conf`. This plugin never writes `tmux.conf`; it writes the dedicated
`~/.config/tmux/omarchy-theme.conf` and only appends a single guarded
`source-file` line to the user's config.

## Generated conf validity

The e2e test loads the generated conf on a **throwaway socket**:

```
tmux -f <generated> -L omarchy-test start-server \; kill-server
```

The user's real tmux server is untouched (`-L` isolates the socket).

## What was NOT verified

- The Hyprland keybinding was **not** loaded into a live compositor during this
  build: that requires editing `~/.config/hypr/hyprland.lua` and reloading the
  user's session, which this task explicitly leaves to the user. The Lua module
  is static-checked (its `hl.unbind` + `o.bind` shape) and installed by the
  shell test into a throwaway `XDG_CONFIG_HOME`.
- The installed `theme-set` hook was not registered with a real
  `omarchy hook install` (that mutates the user's `~/.config/omarchy/hooks`).
  The hook is exercised hermetically with a stub `tmux` and a throwaway HOME.
