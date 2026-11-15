"""Regression tests — one per real bug / design hazard this plugin must not regress.

Each test fails if the guard is removed, and names the hazard it pins.
"""

import importlib.machinery
import importlib.util
import contextlib
import io
import json
import os
import pathlib
import re
import tempfile
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
        self.assertIn("source-file", text)
        # Existing conf is appended to (>>), guarded by the grep above.
        self.assertIn('if [[ -f "$TMUX_CONF" ]]', text)
        self.assertIn('>> "$TMUX_CONF"', text)


class SourceFileGuardIsPathAware(unittest.TestCase):
    """HAZARD: the source-file guard matched the bare substring "omarchy-theme.conf"
    on ANY path, so after a conf_path change the stale line was kept (the custom
    path was never sourced) — and the reverse appended a duplicate. The guard must
    compare the resolved path and reconcile the line.
    """

    def setUp(self):
        self.text = (ROOT / "install.sh").read_text()

    def test_guard_compares_the_resolved_source_line(self):
        self.assertIn('grep -qF "$SOURCE_LINE"', self.text)

    def test_no_cross_path_substring_guard(self):
        # The blind substring match must be gone.
        self.assertNotIn('grep -q "omarchy-theme.conf"', self.text)

    def test_reconciles_a_previously_added_block(self):
        # A marker comment lets the installer find and replace its own block.
        self.assertIn("# omarchy-tmux theme", self.text)
        self.assertIn("awk", self.text)


class KeybindingDrivesTheBinding(unittest.TestCase):
    """HAZARD: config keybinding was printed by status only; the real binding
    was a literal in bin/bindings.lua, so editing the config changed nothing.
    The installed module must be rendered from the configured chord.
    """

    def test_bindings_template_carries_the_token(self):
        self.assertIn("{{KEYBINDING}}", (ROOT / "bin/bindings.lua").read_text())

    def test_render_uses_the_configured_chord(self):
        out = tmux.render_bindings({"keybinding": "SUPER + SHIFT + Z"},
                                   (ROOT / "bin/bindings.lua").read_text())
        self.assertIn('o.bind("SUPER + SHIFT + Z"', out)
        self.assertNotIn("{{KEYBINDING}}", out)


class KeybindingCannotInjectLua(unittest.TestCase):
    """HAZARD: the configured keybinding is substituted into a double-quoted Lua
    string literal in bin/bindings.lua. A value carrying a quote, backslash or
    newline would close the literal and inject Lua the compositor then executes.
    It must be refused, not rendered.
    """

    HOSTILE = [
        'D", dofile("/etc/passwd")\n--',
        "SUPER + \\ + T",
        "SUPER + T\nmalicious()",
        "SUPER + ' + T",
    ]

    def test_hostile_keybinding_is_refused(self):
        template = (ROOT / "bin/bindings.lua").read_text()
        for value in self.HOSTILE:
            with self.assertRaises(ValueError):
                tmux.render_bindings({"keybinding": value}, template)

    def test_validate_keybinding_is_the_guard(self):
        for value in self.HOSTILE:
            with self.assertRaises(ValueError):
                tmux.validate_keybinding(value)

    def test_hostile_value_never_reaches_the_module(self):
        template = (ROOT / "bin/bindings.lua").read_text()
        for value in self.HOSTILE:
            try:
                rendered = tmux.render_bindings({"keybinding": value}, template)
            except ValueError:
                continue
            self.fail("hostile keybinding was rendered: %r" % rendered)

    def test_clean_keybinding_still_renders(self):
        out = tmux.render_bindings({"keybinding": "SUPER + SHIFT + Z"},
                                   (ROOT / "bin/bindings.lua").read_text())
        self.assertIn('o.bind("SUPER + SHIFT + Z"', out)
        self.assertNotIn("{{KEYBINDING}}", out)


class ConfPathSingleSourceOfTruth(unittest.TestCase):
    """HAZARD: conf_path was honoured by the CLI but hardcoded in the hook and
    install.sh, so an override regenerated a file the hook then failed to
    source (a theme change silently did not reload tmux). Both must ask the CLI.
    """

    def test_hook_resolves_conf_path_from_the_cli(self):
        text = (ROOT / "hooks/tmux-theme-set").read_text()
        self.assertIn('"$CLI" "${CLI_ARGS[@]}" paths', text)
        self.assertIn("conf_path=", text)
        # The old hardcoded default path must be gone.
        self.assertNotIn("tmux/omarchy-theme.conf", text)

    def test_installer_derives_the_source_line_from_the_cli(self):
        text = (ROOT / "install.sh").read_text()
        self.assertIn('"$BIN_SRC" "${CLI_ARGS[@]}" paths', text)
        self.assertIn('PATHS=', text)


class TmuxVersionCallIsBounded(unittest.TestCase):
    """HAZARD: tmux_version() ran a subprocess with no timeout, unlike docker's
    30s seam, so a wedged tmux could hang status/install forever.
    """

    def test_default_timeout_is_thirty_seconds(self):
        self.assertEqual(tmux.DEFAULT_TIMEOUT, 30)

    def test_version_call_passes_the_timeout(self):
        captured = {}

        def fake(argv, **kwargs):
            captured["argv"] = argv
            captured["kwargs"] = kwargs

            class Result:
                stdout = "tmux 3.4\n"
            return Result()

        real = tmux.subprocess.run
        tmux.subprocess.run = fake
        try:
            self.assertEqual(tmux.tmux_version(), "tmux 3.4")
        finally:
            tmux.subprocess.run = real
        self.assertEqual(captured["argv"], ["tmux", "-V"])
        self.assertEqual(captured["kwargs"].get("timeout"), tmux.DEFAULT_TIMEOUT)
        self.assertEqual(captured["kwargs"].get("timeout"), 30)

    def test_a_timed_out_call_is_reported_not_raised(self):
        def boom(argv, **kwargs):
            raise tmux.subprocess.TimeoutExpired(argv, kwargs.get("timeout"))

        real = tmux.subprocess.run
        tmux.subprocess.run = boom
        try:
            self.assertEqual(tmux.tmux_version(), "not installed")
        finally:
            tmux.subprocess.run = real


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


class MalformedColorsIsDiagnosed(unittest.TestCase):
    """HAZARD: build_conf indexes required colours directly, so a malformed
    colors.toml aborted `theme` with a raw KeyError traceback instead of the
    plugin's own diagnostic.
    """

    def setUp(self):
        self._state = tempfile.TemporaryDirectory()
        self.addCleanup(self._state.cleanup)
        self._old_state = os.environ.get("XDG_STATE_HOME")
        os.environ["XDG_STATE_HOME"] = self._state.name
        self.addCleanup(self._restore_state)
        self.theme_dir = pathlib.Path(self._state.name) / "omarchy/current/theme"
        self.theme_dir.mkdir(parents=True, exist_ok=True)

    def _restore_state(self):
        if self._old_state is None:
            os.environ.pop("XDG_STATE_HOME", None)
        else:
            os.environ["XDG_STATE_HOME"] = self._old_state

    def _run_theme(self):
        err = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(err):
            rc = tmux.main(["theme", "--stdout"])
        return rc, err.getvalue()

    def test_missing_key_is_named_not_a_traceback(self):
        (self.theme_dir / "colors.toml").write_text('mode = "dark"\naccent = "#82FB9C"\n')
        rc, err = self._run_theme()
        self.assertEqual(rc, 1)
        self.assertIn("omarchy-tmux:", err)
        self.assertIn("background", err)
        self.assertNotIn("Traceback", err)

    def test_unparseable_colour_is_diagnosed(self):
        (self.theme_dir / "colors.toml").write_text(
            'mode = "dark"\nbackground = "#0B0C16"\nforeground = "#ddf7ff"\n'
            'accent = "not-a-colour"\n')
        rc, err = self._run_theme()
        self.assertEqual(rc, 1)
        self.assertIn("omarchy-tmux:", err)
        self.assertNotIn("Traceback", err)


class AuthoritativeThemeName(unittest.TestCase):
    """HAZARD: the theme name was resolved only by whole-file colour equality,
    so a non-catalogued theme (or one differing in a key) showed '(unknown)'.
    Omarchy writes the applied name to current/theme.name — consult it first.
    """

    def test_resolver_consults_the_live_name_file(self):
        src = CLI.read_text()
        self.assertIn("theme.name", src)
        self.assertIn("def omarchy_theme_name", src)

    def test_non_catalogued_name_resolves_to_that_name(self):
        with tempfile.TemporaryDirectory() as t:
            state = pathlib.Path(t)
            (state / "omarchy/current").mkdir(parents=True)
            (state / "omarchy/current/theme.name").write_text("my-custom-theme\n")
            old = os.environ.get("XDG_STATE_HOME")
            os.environ["XDG_STATE_HOME"] = str(state)
            try:
                self.assertEqual(tmux.resolve_theme_name({}, []), "my-custom-theme")
            finally:
                os.environ.pop("XDG_STATE_HOME", None)
                if old is not None:
                    os.environ["XDG_STATE_HOME"] = old


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


class ReadmeMatchesShippedConfig(unittest.TestCase):
    """HAZARD: the README documented a conf_path (tilde) that differed from the
    shipped relative one, so copying it verbatim ignored a non-default
    $XDG_CONFIG_HOME.
    """

    def test_readme_conf_path_matches_the_shipped_config(self):
        cfg = json.loads((ROOT / "config/tmux.json").read_text())
        readme = (ROOT / "README.md").read_text()
        self.assertIn('"conf_path": "%s"' % cfg["conf_path"], readme)

    def test_readme_documents_no_tilde_conf_path(self):
        self.assertNotIn('"conf_path": "~', (ROOT / "README.md").read_text())


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
