# Changelog

All notable changes to omarchy-tmux are documented here. The newest heading must
equal `version` in `manifest.json` (enforced by the policy check).

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
