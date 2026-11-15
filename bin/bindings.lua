-- Hyprland keybindings added by omarchy-tmux.
-- Sourced from hyprland.lua by install.sh (require("hypr.tmux-bindings")).
--
-- This is a TEMPLATE: `omarchy-tmux bindings` (and install.sh) substitute the
-- configured `keybinding` from config/tmux.json for the {{KEYBINDING}} token
-- below, so editing the config changes the installed binding. The file itself
-- is valid Lua (the token is just a string), but do not source it directly.
--
-- Opens (or re-attaches to) a tmux session in a floating terminal. The app-id
-- org.omarchy.* makes Omarchy auto-float the window.

hl.unbind("{{KEYBINDING}}")
o.bind("{{KEYBINDING}}", "Tmux session",
       "xdg-terminal-exec --app-id=org.omarchy.tmux --title='Tmux' -- "
       .. "tmux new-session -A -s main")
