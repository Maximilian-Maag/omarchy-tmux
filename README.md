# omarchy-tmux

Themes the installed **tmux** from the applied **Omarchy** theme, and wires a
Hyprland keybinding to open a tmux session.

- Reads the applied theme **live** from
  `~/.local/state/omarchy/current/theme/colors.toml` on every run — **no palette
  is baked in**, so every Omarchy theme (including one you wrote yourself) is
  themed correctly.
- Writes to a **dedicated file**, `~/.config/tmux/omarchy-theme.conf`, which your
  own `~/.config/tmux/tmux.conf` sources. Your config is never overwritten —
  install only appends one `source-file` line, guarded against duplicates.
- A uniquely-named `theme-set` hook (`hooks/tmux-theme-set`) regenerates and
  reloads the conf whenever you change theme.

Plugin id: `Maximilian-Maag.tmux`.

## Install

```bash
git clone <this repo> ~/Work/omarchy-tmux
cd ~/Work/omarchy-tmux
./install.sh
```

Or, as an Omarchy plugin:

```bash
omarchy plugin add <repo-url> --yes
```

`install.sh` symlinks the CLI into `/usr/local/bin`, generates the theme conf,
adds the `source-file` line to your tmux config, installs the hook and wires the
keybinding into `hyprland.lua`.

## Usage

```bash
omarchy-tmux theme            # generate ~/.config/tmux/omarchy-theme.conf
omarchy-tmux theme --stdout   # print it instead of writing
omarchy-tmux bindings         # (re)install the Hyprland keybinding module
omarchy-tmux status           # applied theme, generated file, tmux version
```

Reload a running tmux after a manual regenerate:

```bash
tmux source-file ~/.config/tmux/omarchy-theme.conf
```

## What gets themed

| tmux element        | Omarchy colour                  |
|---------------------|---------------------------------|
| status bar          | `background` / `foreground`     |
| status-left segment | `accent` on `background`        |
| inactive window     | `muted` on `background`         |
| active window       | `accent` on `selection` (bold)  |
| copy-mode selection | `selection` / `accent`          |
| pane borders        | `muted`                         |
| active pane border  | `accent`                        |
| clock / status-right| `accent`                        |

Values missing from a theme fall back sensibly (`selection` →
`lighter_background` → `background`; `muted` → `dark_foreground` →
`foreground`). A Hyprland gradient value such as `rgba(26a269ee)` is reduced to
its `#rrggbb`.

## Keybinding

`Super+Shift+Alt+T` opens (or re-attaches to) a tmux session in a floating
terminal. It lives in `bin/bindings.lua` and is copied to
`~/.config/hypr/tmux-bindings.lua`, required from `hyprland.lua`.

## Configuration

`config/tmux.json` (read by the CLI):

```json
{
  "conf_path": "~/.config/tmux/omarchy-theme.conf",
  "keybinding": "SUPER + SHIFT + ALT + T"
}
```

Override the config location with `omarchy-tmux --config <path> theme`.

## Development

```bash
make check     # policy + unit + regression (fast)
make test      # full suite incl. measured mutation testing (~10 min)
SKIP_MUTATION=1 tools/run_tests.sh   # everything but mutation
```

Every test kind is present: unit, regression, integration, e2e and shell, plus
policy-as-code and a **measured** mutation score. See `docs/` for the design and
the verification notes.
