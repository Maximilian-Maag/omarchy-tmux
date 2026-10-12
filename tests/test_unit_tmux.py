"""Unit tests for omarchy-tmux's pure logic.

The shipped CLI has no ``.py`` extension (it is installed as ``omarchy-tmux``),
so it is loaded with a SourceFileLoader rather than imported by name.
"""

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
CLI = ROOT / "bin/omarchy-tmux"

_loader = importlib.machinery.SourceFileLoader("omarchy_tmux", str(CLI))
_spec = importlib.util.spec_from_loader("omarchy_tmux", _loader)
tmux = importlib.util.module_from_spec(_spec)
_loader.exec_module(tmux)

SAMPLE = """\
mode = "dark"

# the accent
accent = "#82FB9C"
selection = "#1f253a"
muted = "#2d3450"

background = "#0B0C16"
foreground = "#ddf7ff"
hyprland_active_border = "rgba(26a269ee) rgba(2ec27eee) 45deg"
"""

COLORS = {
    "mode": "dark",
    "accent": "#82FB9C",
    "selection": "#1f253a",
    "muted": "#2d3450",
    "background": "#0B0C16",
    "foreground": "#ddf7ff",
}


class ParseColors(unittest.TestCase):
    def test_basic_keys_and_values(self):
        colors = tmux.parse_colors(SAMPLE)
        self.assertEqual(colors["accent"], "#82FB9C")
        self.assertEqual(colors["background"], "#0B0C16")
        self.assertEqual(colors["mode"], "dark")

    def test_comments_and_blanks_skipped(self):
        colors = tmux.parse_colors("# a comment\n\n   \naccent = \"#fff\"\n")
        self.assertEqual(colors, {"accent": "#fff"})

    def test_comment_containing_equals_is_not_parsed(self):
        # A comment with an '=' must not be parsed as a key.
        colors = tmux.parse_colors('# accent = "#fff"\naccent = "#000"\n')
        self.assertEqual(colors, {"accent": "#000"})

    def test_hex_colour_is_not_treated_as_a_comment(self):
        # A naive split on '#' would truncate the value.
        self.assertEqual(tmux.parse_colors("accent = \"#82FB9C\"\n")["accent"], "#82FB9C")

    def test_line_without_equals_is_skipped(self):
        self.assertEqual(tmux.parse_colors("garbage\naccent = \"#fff\"\n"),
                         {"accent": "#fff"})

    def test_empty_key_is_skipped(self):
        self.assertEqual(tmux.parse_colors("= nope\naccent = \"#fff\"\n"),
                         {"accent": "#fff"})

    def test_single_quotes_stripped(self):
        self.assertEqual(tmux.parse_colors("accent = '#fff'\n")["accent"], "#fff")

    def test_unquoted_value_kept(self):
        self.assertEqual(tmux.parse_colors("mode = dark\n")["mode"], "dark")


class NormalizeName(unittest.TestCase):
    def test_title_case_to_slug(self):
        self.assertEqual(tmux.normalize_name("Tokyo Night"), "tokyo-night")

    def test_strips_and_lowercases(self):
        self.assertEqual(tmux.normalize_name("  Hackerman  "), "hackerman")


class TmuxColour(unittest.TestCase):
    def test_hex_passthrough(self):
        self.assertEqual(tmux.tmux_colour("#82FB9C"), "#82FB9C")

    def test_rgba_reduced_to_hex(self):
        self.assertEqual(tmux.tmux_colour("rgba(26a269ee)"), "#26a269")

    def test_rgba_with_alpha_zero(self):
        self.assertEqual(tmux.tmux_colour("rgba(2ec27e00)"), "#2ec27e")

    def test_short_hex_rejected(self):
        with self.assertRaises(ValueError):
            tmux.tmux_colour("#fff")

    def test_garbage_rejected(self):
        with self.assertRaises(ValueError):
            tmux.tmux_colour("not-a-colour")

    def test_whitespace_stripped(self):
        self.assertEqual(tmux.tmux_colour("  #82FB9C  "), "#82FB9C")


class Style(unittest.TestCase):
    def test_fg_before_bg(self):
        self.assertEqual(tmux.style(fg="#fff", bg="#000"), "fg=#fff,bg=#000")

    def test_flags_appended(self):
        self.assertEqual(tmux.style(fg="#fff", bold=True), "fg=#fff,bold")

    def test_empty_parts_skipped(self):
        self.assertEqual(tmux.style(fg="#fff", bg="", bold=False), "fg=#fff")

    def test_all_empty(self):
        self.assertEqual(tmux.style(), "")

    def test_flag_alone(self):
        self.assertEqual(tmux.style(underscore=True), "underscore")


class ResolveThemeName(unittest.TestCase):
    def _theme(self, root, name, body):
        d = root / name
        d.mkdir()
        (d / "colors.toml").write_text(body)
        return d

    def test_matches_colour_set(self):
        with tempfile.TemporaryDirectory() as t:
            root = pathlib.Path(t)
            self._theme(root, "nord", "accent = \"#88c0d0\"\nbackground = \"#2e3440\"\n")
            self._theme(root, "gruvbox", "accent = \"#d79921\"\nbackground = \"#282828\"\n")
            colors = {"accent": "#d79921", "background": "#282828"}
            self.assertEqual(tmux.resolve_theme_name(colors, [root / "nord", root / "gruvbox"]),
                             "gruvbox")

    def test_no_match_returns_empty(self):
        with tempfile.TemporaryDirectory() as t:
            root = pathlib.Path(t)
            self._theme(root, "nord", "accent = \"#88c0d0\"\n")
            self.assertEqual(tmux.resolve_theme_name({"accent": "#000000"}, [root / "nord"]), "")

    def test_missing_colors_file_skipped(self):
        with tempfile.TemporaryDirectory() as t:
            root = pathlib.Path(t)
            (root / "empty").mkdir()
            self.assertEqual(tmux.resolve_theme_name({"a": "b"}, [root / "empty"]), "")


class BuildConf(unittest.TestCase):
    def test_uses_theme_colours(self):
        conf = tmux.build_conf(dict(COLORS))
        self.assertIn("#0B0C16", conf)   # background
        self.assertIn("#ddf7ff", conf)   # foreground
        self.assertIn("#82FB9C", conf)   # accent
        self.assertIn("#1f253a", conf)   # selection

    def test_status_bar_uses_background_and_foreground(self):
        conf = tmux.build_conf(dict(COLORS))
        self.assertIn('set -g status-style "fg=#ddf7ff,bg=#0B0C16"', conf)

    def test_active_window_uses_accent_and_selection(self):
        conf = tmux.build_conf(dict(COLORS))
        self.assertIn('set -g window-status-current-format "#[fg=#82FB9C,bg=#1f253a,bold]',
                      conf)

    def test_inactive_window_uses_muted(self):
        conf = tmux.build_conf(dict(COLORS))
        self.assertIn('set -g window-status-format "#[fg=#2d3450,bg=#0B0C16]', conf)

    def test_selection_used_by_mode_style(self):
        conf = tmux.build_conf(dict(COLORS))
        self.assertIn('set -g mode-style "fg=#82FB9C,bg=#1f253a"', conf)

    def test_accent_used_by_pane_border_and_clock(self):
        conf = tmux.build_conf(dict(COLORS))
        self.assertIn('set -g pane-active-border-style "fg=#82FB9C"', conf)
        self.assertIn("setw -g clock-mode-colour #82FB9C", conf)

    def test_light_mode_is_not_bold(self):
        colors = dict(COLORS, mode="light")
        conf = tmux.build_conf(colors)
        self.assertIn('set -g window-status-current-format "#[fg=#82FB9C,bg=#1f253a]', conf)
        self.assertNotIn("bold]", conf.split("window-status-current-format")[1].splitlines()[0])

    def test_selection_falls_back_to_lighter_background(self):
        colors = {k: v for k, v in COLORS.items() if k != "selection"}
        colors["lighter_background"] = "#151828"
        conf = tmux.build_conf(colors)
        self.assertIn('set -g mode-style "fg=#82FB9C,bg=#151828"', conf)

    def test_selection_falls_back_to_background(self):
        colors = {k: v for k, v in COLORS.items() if k != "selection"}
        conf = tmux.build_conf(colors)
        self.assertIn('set -g mode-style "fg=#82FB9C,bg=#0B0C16"', conf)

    def test_muted_falls_back_to_dark_foreground(self):
        colors = {k: v for k, v in COLORS.items() if k != "muted"}
        colors["dark_foreground"] = "#6a6e95"
        conf = tmux.build_conf(colors)
        self.assertIn('set -g window-status-format "#[fg=#6a6e95,bg=#0B0C16]', conf)

    def test_muted_falls_back_to_foreground(self):
        colors = {k: v for k, v in COLORS.items() if k != "muted"}
        conf = tmux.build_conf(colors)
        self.assertIn('set -g window-status-format "#[fg=#ddf7ff,bg=#0B0C16]', conf)

    def test_hyprland_gradient_colour_accepted(self):
        colors = dict(COLORS, accent="rgba(26a269ee)")
        conf = tmux.build_conf(colors)
        self.assertIn("#26a269", conf)

    def test_ends_with_newline(self):
        self.assertTrue(tmux.build_conf(dict(COLORS)).endswith("\n"))

    def test_header_mentions_source_file(self):
        self.assertIn("source-file", tmux.build_conf(dict(COLORS)))


class ConfigAndPaths(unittest.TestCase):
    def test_default_conf_path(self):
        self.assertEqual(tmux.theme_conf_path({}),
                         tmux.config_home() / "tmux/omarchy-theme.conf")

    def test_conf_path_override_tilde(self):
        cfg = {"conf_path": "~/.config/tmux/custom.conf"}
        self.assertEqual(tmux.theme_conf_path(cfg),
                         pathlib.Path(os.path.expanduser("~/.config/tmux/custom.conf")))

    def test_conf_path_override_absolute(self):
        cfg = {"conf_path": "/tmp/omarchy-tmux-test/theme.conf"}
        self.assertEqual(tmux.theme_conf_path(cfg),
                         pathlib.Path("/tmp/omarchy-tmux-test/theme.conf"))

    def test_load_config_reads_file(self):
        with tempfile.TemporaryDirectory() as t:
            p = pathlib.Path(t) / "tmux.json"
            p.write_text(json.dumps({"keybinding": "SUPER + X"}))
            cfg = tmux.load_config(p)
            self.assertEqual(cfg["keybinding"], "SUPER + X")
            self.assertIn("conf_path", cfg)          # default preserved

    def test_load_config_missing_file_uses_defaults(self):
        cfg = tmux.load_config(pathlib.Path("/nonexistent/tmux.json"))
        self.assertEqual(cfg["conf_path"], tmux.DEFAULT_CONFIG["conf_path"])

    def test_load_config_invalid_json_uses_defaults(self):
        with tempfile.TemporaryDirectory() as t:
            p = pathlib.Path(t) / "tmux.json"
            p.write_text("{ not json")
            self.assertEqual(tmux.load_config(p)["keybinding"],
                             tmux.DEFAULT_CONFIG["keybinding"])

    def test_state_home_env(self):
        old = os.environ.get("XDG_STATE_HOME")
        os.environ["XDG_STATE_HOME"] = "/tmp/state-xyz"
        try:
            self.assertEqual(tmux.state_home(), pathlib.Path("/tmp/state-xyz"))
        finally:
            os.environ.pop("XDG_STATE_HOME", None)
            if old is not None:
                os.environ["XDG_STATE_HOME"] = old

    def test_config_home_env(self):
        old = os.environ.get("XDG_CONFIG_HOME")
        os.environ["XDG_CONFIG_HOME"] = "/tmp/config-xyz"
        try:
            self.assertEqual(tmux.config_home(), pathlib.Path("/tmp/config-xyz"))
        finally:
            os.environ.pop("XDG_CONFIG_HOME", None)
            if old is not None:
                os.environ["XDG_CONFIG_HOME"] = old

    def test_colors_path_under_state_home(self):
        old = os.environ.get("XDG_STATE_HOME")
        os.environ["XDG_STATE_HOME"] = "/tmp/state-xyz"
        try:
            self.assertEqual(tmux.theme_colors_path(),
                             pathlib.Path("/tmp/state-xyz/omarchy/current/theme/colors.toml"))
        finally:
            os.environ.pop("XDG_STATE_HOME", None)
            if old is not None:
                os.environ["XDG_STATE_HOME"] = old

    def test_plugin_dir_is_repo_root(self):
        self.assertEqual(tmux.plugin_dir(), ROOT)


class Commands(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = pathlib.Path(self.tmp.name)
        self.state = base / "state"
        self.config = base / "config"
        theme = self.state / "omarchy/current/theme"
        theme.mkdir(parents=True)
        (theme / "colors.toml").write_text(SAMPLE)
        self._env = {k: os.environ.get(k) for k in ("XDG_STATE_HOME", "XDG_CONFIG_HOME")}
        os.environ["XDG_STATE_HOME"] = str(self.state)
        os.environ["XDG_CONFIG_HOME"] = str(self.config)
        self.addCleanup(self._restore)

    def _restore(self):
        for k, v in self._env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def run_cli(self, *argv):
        """Run a subcommand, swallowing its console output."""
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
            return tmux.main(list(argv))

    def test_theme_writes_conf(self):
        rc = self.run_cli("theme")
        self.assertEqual(rc, 0)
        out = tmux.theme_conf_path()
        self.assertTrue(out.is_file())
        self.assertIn("#82FB9C", out.read_text())

    def test_theme_stdout_does_not_write(self):
        rc = self.run_cli("theme", "--stdout")
        self.assertEqual(rc, 0)
        self.assertFalse(tmux.theme_conf_path().exists())

    def test_theme_missing_theme_returns_1(self):
        (self.state / "omarchy/current/theme/colors.toml").unlink()
        self.assertEqual(self.run_cli("theme"), 1)

    def test_status_runs(self):
        self.assertEqual(self.run_cli("status"), 0)

    def test_bindings_installs_module(self):
        rc = self.run_cli("bindings")
        self.assertEqual(rc, 0)
        dest = self.config / "hypr/tmux-bindings.lua"
        self.assertTrue(dest.is_file())
        self.assertIn("o.bind", dest.read_text())


class TmuxVersion(unittest.TestCase):
    def test_returns_a_string(self):
        self.assertIsInstance(tmux.tmux_version(), str)


if __name__ == "__main__":
    unittest.main()
