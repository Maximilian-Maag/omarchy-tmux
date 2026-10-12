"""Regression tests — one per real bug / design hazard this plugin must not regress.

Each test fails if the guard is removed, and names the hazard it pins.
"""

import importlib.machinery
import importlib.util
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
CLI = ROOT / "bin/omarchy-tmux"

_loader = importlib.machinery.SourceFileLoader("omarchy_tmux_reg", str(CLI))
_spec = importlib.util.spec_from_loader("omarchy_tmux_reg", _loader)
tmux = importlib.util.module_from_spec(_spec)
_loader.exec_module(tmux)


class HookFilenameHazard(unittest.TestCase):
    """HAZARD: `omarchy hook install theme-set <file>` installs the hook under
    its BASENAME, so a hook literally named `theme-set` silently clobbers every
    other plugin's theme-set hook. Ours must be uniquely named.
    """

    def test_hook_is_uniquely_named(self):
        hooks = sorted(p.name for p in (ROOT / "hooks").iterdir())
        self.assertIn("tmux-theme-set", hooks)
        self.assertNotIn("theme-set", hooks)

    def test_install_uses_the_unique_name(self):
        text = (ROOT / "install.sh").read_text()
        self.assertIn("hooks/tmux-theme-set", text)


class HookSelfLocates(unittest.TestCase):
    """HAZARD: an installed hook is copied to the hooks dir, so
    $(dirname "$BASH_SOURCE")/.. resolves to the hooks dir, not the plugin. The
    hook must self-locate instead.
    """

    def setUp(self):
        self.text = (ROOT / "hooks/tmux-theme-set").read_text()

    def test_does_not_assume_sibling_plugin_dir(self):
        # The dead pattern: dirname of the script, then '..'.
        self.assertNotIn('dirname "$BASH_SOURCE"', self.text)

    def test_searches_known_locations(self):
        self.assertIn("OMARCHY_TMUX_DIR", self.text)
        self.assertIn("Maximilian-Maag.tmux", self.text)
        self.assertIn("omarchy-tmux", self.text)


class NoBakedPalette(unittest.TestCase):
    """HAZARD: a plugin that "supports themes" with a hardcoded palette drifts
    from the applied theme. The CLI must read colours.toml at runtime and carry
    no hex literal of its own.
    """

    def test_source_contains_no_hex_colour_literal(self):
        text = CLI.read_text()
        matches = re.findall(r"#[0-9a-fA-F]{6}\b", text)
        self.assertEqual(matches, [], "hardcoded colours found: %s" % matches)

    def test_output_changes_with_the_theme(self):
        dark = tmux.build_conf({"mode": "dark", "accent": "#111111",
                                "selection": "#222222", "muted": "#333333",
                                "background": "#000000", "foreground": "#ffffff"})
        other = tmux.build_conf({"mode": "dark", "accent": "#aaaaaa",
                                 "selection": "#bbbbbb", "muted": "#cccccc",
                                 "background": "#010101", "foreground": "#eeeeee"})
        self.assertNotEqual(dark, other)
        self.assertIn("#111111", dark)
        self.assertIn("#aaaaaa", other)


class DedicatedConfPath(unittest.TestCase):
    """HAZARD: generating over the user's own ~/.config/tmux/tmux.conf would
    destroy their config. Ours goes to a dedicated file they source.
    """

    def test_default_path_is_dedicated(self):
        path = tmux.theme_conf_path({})
        self.assertEqual(path.name, "omarchy-theme.conf")
        self.assertNotEqual(path.name, "tmux.conf")

    def test_install_only_appends_a_source_line(self):
        text = (ROOT / "install.sh").read_text()
        self.assertIn('grep -q "omarchy-theme.conf"', text)
        self.assertIn("source-file", text)
        # Existing conf is appended to (>>), guarded by the grep above.
        self.assertIn('if [[ -f "$TMUX_CONF" ]]', text)
        self.assertIn('>> "$TMUX_CONF"', text)


class RuntimeThemeResolution(unittest.TestCase):
    """HAZARD: the applied theme is a COPY at .../current/theme/colors.toml, so
    its name is not in the path. Resolving by name (or defaulting to a fixed
    theme) shows the wrong colours; match the colours instead.
    """

    def test_theme_dir_name_is_literal_theme(self):
        path = tmux.theme_colors_path()
        self.assertEqual(path.parent.name, "theme")

    def test_resolution_uses_colour_match_not_a_fixed_default(self):
        src = CLI.read_text()
        self.assertIn("def resolve_theme_name", src)
        self.assertNotIn("catppuccin", src.lower())


class GradientColourSafety(unittest.TestCase):
    """HAZARD: an Omarchy colors.toml carries a Hyprland gradient
    (hyprland_active_border = "rgba(..) rgba(..) 45deg"). Feeding a raw
    rgba()/gradient string to tmux yields an invalid colour; normalise it.
    """

    def test_rgba_reduced(self):
        self.assertEqual(tmux.tmux_colour("rgba(26a269ee)"), "#26a269")

    def test_gradient_string_rejected_loudly(self):
        with self.assertRaises(ValueError):
            tmux.tmux_colour("rgba(26a269ee) rgba(2ec27eee) 45deg")


class ManifestContract(unittest.TestCase):
    """The policy check enforces this, but pin it here too so a rename fails
    loudly in the test suite as well.
    """

    def test_id_is_owner_namespaced(self):
        manifest = json.loads((ROOT / "manifest.json").read_text())
        self.assertEqual(manifest["id"], "Maximilian-Maag.tmux")
        self.assertFalse(manifest["id"].startswith("omarchy."))

    def test_version_matches_changelog(self):
        manifest = json.loads((ROOT / "manifest.json").read_text())
        text = (ROOT / "CHANGELOG.md").read_text()
        versions = re.findall(r"^##\s*\[?v?([0-9]+\.[0-9]+\.[0-9]+)", text, re.M)
        self.assertEqual(manifest["version"], versions[0])


if __name__ == "__main__":
    unittest.main()
