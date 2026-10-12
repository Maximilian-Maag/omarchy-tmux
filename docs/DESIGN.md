# Design

## Goal

Make the installed tmux follow the **applied** Omarchy theme, without baking a
palette into the plugin and without touching the user's own tmux configuration.

## Why not a static theme?

A plugin that "supports themes" with a hardcoded palette drifts: a theme's
`colors.toml` is the source of truth, and hardcoded per-theme blocks go stale
(one real plugin had eight wrong colours in a "supported" theme). This plugin
therefore carries **no hex literal at all** — a regression test asserts that —
and derives every colour from the live file at runtime.

## Reading the applied theme

The applied theme is a **copy**:

```
~/.local/state/omarchy/current/theme/colors.toml
```

so the directory is always literally `theme` and the theme's *name* is not in
the path. To recover the name (for `status`), the plugin matches the colour set
against each directory under `/usr/share/omarchy/themes` and
`~/.config/omarchy/themes`. If nothing matches it says `(unknown)` rather than
defaulting to a fixed theme (which would show entirely unrelated colours).

## Output path

```
~/.config/tmux/omarchy-theme.conf
```

A **dedicated** file. The user's `~/.config/tmux/tmux.conf` is only ever
appended to, once, with:

```
source-file ~/.config/tmux/omarchy-theme.conf
```

The installer guards the append with a `grep`, so re-running it is idempotent.

## Colour mapping

| tmux element        | source colour(s)                          |
|---------------------|-------------------------------------------|
| `status-style`      | `background` bg, `foreground` fg          |
| `status-left`       | `accent` bg, `background` fg              |
| `window-status-format` (inactive) | `muted` fg, `background` bg  |
| `window-status-current-format` (active) | `accent` fg, `selection` bg, bold on dark themes |
| `mode-style` (copy-mode selection) | `selection` bg, `accent` fg |
| `message-style`     | `selection` bg, `accent` fg               |
| `pane-border-style` | `muted` fg                                |
| `pane-active-border-style` | `accent` fg                        |
| `clock-mode-colour` | `accent`                                  |

Fallbacks: `selection` → `lighter_background` → `background`; `muted` →
`dark_foreground` → `foreground`.

`tmux_colour()` normalises values: `#rrggbb` passes through; a Hyprland
gradient stop `rgba(rrggbbaa)` is reduced to `#rrggbb`; anything else raises,
because silently emitting an invalid colour leaves tmux on a fallback.

## Hook

`hooks/tmux-theme-set` is a `theme-set` hook. Two hazards drive its shape:

1. **Basename collision.** `omarchy hook install theme-set <file>` installs the
   hook under the file's **basename**, so a file literally named `theme-set`
   clobbers every other plugin's theme-set hook. Ours is `tmux-theme-set`.
2. **A copied hook cannot find its plugin.** Once installed, the hook lives in
   the hooks directory, so `$(dirname "$BASH_SOURCE")/..` is the hooks dir, not
   the plugin. The hook self-locates over `$OMARCHY_TMUX_DIR`, the Omarchy
   plugins directory and the dev checkout.

The hook regenerates the conf and, only if a tmux server is already running,
reloads it — it never starts a server.

## Keybinding

`bin/bindings.lua` adds `Super+Shift+Alt+T` → open/re-attach a tmux session in a
floating terminal (`org.omarchy.tmux` app-id makes Omarchy float it). It is
copied to `~/.config/hypr/tmux-bindings.lua` and required from `hyprland.lua`.
