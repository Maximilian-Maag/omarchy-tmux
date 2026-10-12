"""Integration tests — the shipped CLI driven as a subprocess against a synthetic
Omarchy theme directory (never the user's real one).
"""

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
CLI = ROOT / "bin/omarchy-tmux"

THEME = """\
mode = "dark"

accent = "#82FB9C"
selection = "#1f253a"
muted = "#2d3450"
background = "#0B0C16"
foreground = "#ddf7ff"
"""


class CliIntegration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = pathlib.Path(self.tmp.name)
        self.state = self.base / "state"
        self.config = self.base / "config"
        theme = self.state / "omarchy/current/theme"
        theme.mkdir(parents=True)
        (theme / "colors.toml").write_text(THEME)
        self.env = dict(os.environ)
        self.env["XDG_STATE_HOME"] = str(self.state)
        self.env["XDG_CONFIG_HOME"] = str(self.config)
        self.env["HOME"] = str(self.base / "home")
        (self.base / "home").mkdir()

    def run_cli(self, *args, **kwargs):
        return subprocess.run([sys.executable, str(CLI), *args],
                              capture_output=True, text=True, env=self.env, **kwargs)

    def test_bindings_reports_a_missing_bindings_file(self):
        # plugin_dir() is derived from the CLI's own path, so run a copy of the CLI
        # out of a temp checkout that has no bin/bindings.lua: it must fail (rc 1)
        # rather than silently claiming success.
        stray = self.base / "stray" / "bin"
        stray.mkdir(parents=True)
        copy = stray / "omarchy-tmux"
        copy.write_text(CLI.read_text())
        proc = subprocess.run([sys.executable, str(copy), "bindings"],
                              capture_output=True, text=True, env=self.env)
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("bindings.lua not found", proc.stderr)

    def test_theme_writes_dedicated_conf(self):
        proc = self.run_cli("theme")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        conf = self.config / "tmux/omarchy-theme.conf"
        self.assertTrue(conf.is_file())
        text = conf.read_text()
        self.assertIn("#0B0C16", text)
        self.assertIn("#82FB9C", text)
        self.assertIn("#1f253a", text)
        self.assertIn("status-style", text)

    def test_theme_is_idempotent(self):
        # Running twice must not fail on the already-created directory.
        self.assertEqual(self.run_cli("theme").returncode, 0)
        self.assertEqual(self.run_cli("theme").returncode, 0)

    def test_theme_does_not_touch_user_tmux_conf(self):
        user_conf = self.config / "tmux/tmux.conf"
        user_conf.parent.mkdir(parents=True)
        user_conf.write_text("# my precious config\nset -g mouse on\n")
        self.run_cli("theme")
        self.assertEqual(user_conf.read_text(), "# my precious config\nset -g mouse on\n")

    def test_theme_stdout_prints_conf(self):
        proc = self.run_cli("theme", "--stdout")
        self.assertEqual(proc.returncode, 0)
        self.assertIn("set -g status-style", proc.stdout)
        self.assertFalse((self.config / "tmux/omarchy-theme.conf").exists())

    def test_theme_without_applied_theme_fails(self):
        (self.state / "omarchy/current/theme/colors.toml").unlink()
        proc = self.run_cli("theme")
        self.assertEqual(proc.returncode, 1)
        self.assertIn("no applied theme", proc.stderr)

    def test_status_reports_applied_theme(self):
        proc = self.run_cli("status")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("Maximilian-Maag.tmux", proc.stdout)
        self.assertIn("applied theme", proc.stdout)
        self.assertIn("keybinding", proc.stdout)

    def test_bindings_wires_hyprland(self):
        hypr = self.config / "hypr"
        hypr.mkdir(parents=True)
        (hypr / "hyprland.lua").write_text("-- main config\n")
        proc = self.run_cli("bindings")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue((hypr / "tmux-bindings.lua").is_file())
        self.assertIn('require("hypr.tmux-bindings")', (hypr / "hyprland.lua").read_text())

    def test_bindings_idempotent(self):
        hypr = self.config / "hypr"
        hypr.mkdir(parents=True)
        (hypr / "hyprland.lua").write_text("-- main\n")
        self.run_cli("bindings")
        self.run_cli("bindings")
        text = (hypr / "hyprland.lua").read_text()
        self.assertEqual(text.count('require("hypr.tmux-bindings")'), 1)

    def test_config_json_overrides_conf_path(self):
        cfg = self.base / "tmux.json"
        cfg.write_text(json.dumps({"conf_path": str(self.base / "elsewhere/theme.conf")}))
        proc = self.run_cli("--config", str(cfg), "theme")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue((self.base / "elsewhere/theme.conf").is_file())

    def test_generated_conf_is_valid_tmux(self):
        self.run_cli("theme")
        conf = self.config / "tmux/omarchy-theme.conf"
        subprocess.run(["tmux", "-L", "omarchy-it", "kill-server"], capture_output=True)
        proc = subprocess.run(["tmux", "-f", str(conf), "-L", "omarchy-it", "start-server"],
                              capture_output=True, text=True)
        subprocess.run(["tmux", "-L", "omarchy-it", "kill-server"], capture_output=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)


if __name__ == "__main__":
    unittest.main()
