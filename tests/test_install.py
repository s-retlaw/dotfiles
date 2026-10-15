"""Installation regression checks; all writes are confined to temporary homes."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dotfiles-test-")
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.config = self.home / "config"
        self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.config),
                        OMARCHY_PATH="", XDG_DATA_HOME=str(self.home / "data"))
        self.rc = self.home / ".bashrc"
        self.rc.write_text("# original shell setup\nexport KEEP_ME=yes\n")

    def install(self, *args, ok=True):
        result = subprocess.run(["bash", str(REPO / "install.sh"), "--skip-packages", *args],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        return result

    def test_standalone_backups_and_rapid_copy_reinstalls(self):
        nvim = self.config / "nvim"
        nvim.mkdir(parents=True)
        (nvim / "original").write_text("original config")
        (self.home / ".tmux.conf").write_text("original tmux")
        herdr = self.config / "herdr"
        herdr.mkdir()
        (herdr / "session.json").write_text("runtime state")
        self.install("--standalone")
        self.assertEqual(nvim.resolve(), REPO / "nvim")
        self.install("--standalone")
        self.assertEqual(self.rc.read_text().count("# Personal dotfiles helpers"), 1)
        # Back-to-back runs previously collided at second-level timestamps.
        self.install("--standalone", "--copy")
        self.install("--standalone", "--copy")
        self.assertFalse(nvim.is_symlink())
        self.assertEqual((nvim / "init.lua").read_bytes(), (REPO / "nvim/init.lua").read_bytes())
        self.assertIn("KEEP_ME=yes", self.rc.read_text())
        self.assertEqual((herdr / "session.json").read_text(), "runtime state")
        self.assertEqual((herdr / "config.toml").read_bytes(), (REPO / "herdr/config.toml").read_bytes())
        self.assertTrue(list((self.home / ".dotfiles_backup").glob("*/item.*/nvim/original")))
        for target in (self.home / ".dotfiles_backup").glob("*/item.*/target.txt"):
            self.assertTrue(Path(target.read_text().strip()).is_absolute())

    def make_omarchy(self):
        nvim = self.config / "nvim"
        (nvim / "lua/config").mkdir(parents=True)
        (nvim / "lua/plugins").mkdir()
        (nvim / "init.lua").write_text('-- Omarchy bootstrap\nrequire("config.lazy")\n')
        (nvim / "lua/config/lazy.lua").write_text("-- Omarchy loader\n")
        (nvim / "lua/config/options.lua").write_text("-- existing options\n")
        (nvim / "lua/plugins/theme.lua").write_text("-- system theme\nreturn {}\n")
        (nvim / "lazyvim.json").write_text(json.dumps({"extras": ["existing.extra"], "version": 8}))
        return nvim

    def test_omarchy_preserves_base_and_merges_extras(self):
        nvim = self.make_omarchy()
        herdr = self.config / "herdr"
        herdr.mkdir()
        herdr_config = herdr / "config.toml"
        herdr_config.write_text('# Omarchy-owned config\n[keys]\nprefix = "ctrl+space"\n')
        original_herdr = herdr_config.read_bytes()
        originals = {p: p.read_bytes() for p in nvim.rglob("*.lua")}
        self.env["OMARCHY_PATH"] = str(self.home / "omarchy")
        for args in ((), ("--omarchy",), ("--copy",), ("--omarchy", "--copy")):
            self.install(*args)
            self.assertEqual(herdr_config.read_bytes(), original_herdr)
            self.assertFalse(herdr_config.is_symlink())
            for p, data in originals.items():
                self.assertEqual(p.read_bytes(), data)
            settings = json.loads((nvim / "lazyvim.json").read_text())
            self.assertEqual(settings["version"], 8)
            self.assertIn("existing.extra", settings["extras"])
            self.assertIn("lazyvim.plugins.extras.lang.python", settings["extras"])
            self.assertIn("lazyvim.plugins.extras.coding.mini-surround", settings["extras"])
            self.assertEqual(len(settings["extras"]), len(set(settings["extras"])))
        self.assertFalse((nvim / "lua/dotfiles").is_symlink())
        self.assertFalse((nvim / "lua/plugins/colorscheme.lua").exists())

    def test_invalid_inputs_do_not_modify_home(self):
        self.install("--typo", ok=False)
        self.install("--omarchy", ok=False)
        self.assertEqual(self.rc.read_text(), "# original shell setup\nexport KEEP_ME=yes\n")
        self.assertFalse((self.home / ".tmux.conf").exists())
        nvim = self.make_omarchy()
        (nvim / "lazyvim.json").write_text("invalid JSON")
        self.install("--omarchy", ok=False)
        self.assertFalse((self.home / ".tmux.conf").exists())

    def test_omarchy_rejects_overlay_onto_standalone(self):
        self.install("--standalone")
        self.install("--omarchy", ok=False)
        self.assertEqual((self.config / "nvim").resolve(), REPO / "nvim")

    def test_shell_symlink_is_preserved_in_backup(self):
        source = self.home / "external-rc"
        source.write_text("# original linked shell\n")
        self.rc.unlink()
        self.rc.symlink_to(source)
        self.install("--standalone")
        self.assertEqual(source.read_text(), "# original linked shell\n")
        self.assertFalse(self.rc.is_symlink())
        self.assertIn("# original linked shell", self.rc.read_text())

    def test_release_downloads_choose_architecture_and_libc(self):
        script = r'''source "$1" --skip-packages --standalone
command() {
    if [[ "$*" == "-v duckdb" ]]; then return 1; fi
    builtin command "$@"
}
curl() {
    printf '%s\n' "$2" > "$HOME/download-url"
    : > "$4"
}
unzip() {
    mkdir -p "$4"
    printf '#!/bin/sh\nexit 0\n' > "$4/duckdb"
}
for test_arch in x86_64 aarch64; do
    uname() { printf '%s\n' "$test_arch"; }
    case "$test_arch" in x86_64) asset=amd64 ;; aarch64) asset=arm64 ;; esac
    OS=arch
    install_duckdb_from_release
    [[ $(cat "$HOME/download-url") == *"duckdb_cli-linux-$asset.zip" ]]
    OS=alpine
    install_duckdb_from_release
    [[ $(cat "$HOME/download-url") == *"duckdb_cli-linux-$asset-musl.zip" ]]
done
'''
        result = subprocess.run(["bash", "-c", script, "test", str(REPO / "install.sh")],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.home / ".local/bin/duckdb").exists())

    def test_architecture_versions_and_root_without_sudo(self):
        script = '''source "$1" --skip-packages --standalone
version_gte 0.11.6 0.11.2
! version_gte 0.9.5 0.11.2
version_gte 0.12.0 0.11.2
uname() { printf '%s\\n' aarch64; }
[[ $(linux_arch) == arm64 ]]
uname() { printf '%s\\n' x86_64; }
[[ $(linux_arch) == x86_64 ]]
uname() { printf '%s\\n' riscv64; }
! linux_arch
# Shadow sudo so accidental use fails. Containers running as root need none.
sudo() { return 99; }
if [[ $EUID -eq 0 ]]; then as_root true; fi
'''
        result = subprocess.run(["bash", "-c", script, "test", str(REPO / "install.sh")],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
