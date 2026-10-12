-- Hyprland keybindings added by omarchy-tmux.
-- Sourced from hyprland.lua by install.sh (require("hypr.tmux-bindings")).
--
-- Opens (or re-attaches to) a tmux session in a floating terminal. The app-id
-- org.omarchy.* makes Omarchy auto-float the window.

hl.unbind("SUPER + SHIFT + ALT + T")
o.bind("SUPER + SHIFT + ALT + T", "Tmux session",
       "xdg-terminal-exec --app-id=org.omarchy.tmux --title='Tmux' -- "
       .. "tmux new-session -A -s main")
