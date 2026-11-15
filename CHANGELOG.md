# Changelog

All notable changes to omarchy-tmux are documented here. The newest heading must
equal `version` in `manifest.json` (enforced by the policy check).

## [0.2.0] - 2026-11-15

### Added

- `./install.sh --uninstall` — reverses exactly what the installer added: the
  `/usr/local/bin` symlink (only if it points back into this checkout), the
  `source-file` block in `tmux.conf`, the rendered keybinding module and its
  `require` block in `hyprland.lua`, and the theme-set hook. The user's own config
  values and the generated theme conf (which the theme-set hook regenerates) are
  left untouched, and a require line with no `-- omarchy-tmux keybindings` marker
  above it — added by hand — survives.
- `OMARCHY_TMUX_BIN` — overrides where the CLI is symlinked (default
  `/usr/local/bin`), so an install without root and the shell tests use a private
  bin dir.
- A shell round-trip test asserting that an install → uninstall cycle leaves the
  user's `hyprland.lua` and `tmux.conf` byte-identical (sha256) and leaves no
  marker or blank line behind.

## [0.1.0] - 2026-10-12

### Added

- `omarchy-tmux theme` — generates a tmux theme conf from the applied Omarchy
  theme, read live from
  `~/.local/state/omarchy/current/theme/colors.toml` (no baked-in palette).
  Themes the status bar, active/inactive window, copy-mode selection, pane
  borders and accent; supports `--stdout`.
- `omarchy-tmux bindings` — installs the Hyprland keybinding module and wires
  it into `hyprland.lua`.
- `omarchy-tmux status` — reports the applied theme, the generated conf and the
  tmux version.
- `hooks/tmux-theme-set` — uniquely named `theme-set` hook that regenerates the
  conf and reloads a running tmux server. Self-locating (an installed hook
  cannot find its plugin via `$(dirname "$BASH_SOURCE")/..`).
- `config/tmux.json` — the generated conf path and the keybinding, read by the
  CLI.
- Full test harness: unit, regression, integration, e2e and shell tests plus
  measured mutation testing, policy-as-code and CI.
