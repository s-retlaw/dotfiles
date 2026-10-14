"""Offline integration check using plugins already installed on this machine."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
plugins = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "nvim/lazy"
if not (plugins / "lazy.nvim").exists():
    raise SystemExit("Install the standalone Neovim plugins before running this optional check.")
for omarchy in (False, True):
    with tempfile.TemporaryDirectory(prefix="dotfiles-nvim-") as tmp:
        root = Path(tmp)
        config = root / "config/nvim"
        if omarchy:
            (config / "lua/config").mkdir(parents=True)
            (config / "lua/plugins").mkdir()
            (config / "init.lua").write_text('require("config.lazy")\n')
            (config / "lua/config/lazy.lua").write_text('''require("lazy").setup({
  spec = { { "LazyVim/LazyVim", import = "lazyvim.plugins" }, { import = "plugins" } },
})
''')
            (config / "lua/config/options.lua").write_text("vim.opt.shiftwidth = 4\n")
            (config / "lua/plugins/theme.lua").write_text('''return {
  { "LazyVim/LazyVim", opts = { colorscheme = "habamax" } },
}
''')
            settings = json.loads((repo / "nvim/lazyvim.json").read_text())
            (config / "lazyvim.json").write_text(json.dumps({"extras": settings["extras"]}))
            (config / "lua/dotfiles").symlink_to(repo / "nvim/lua/dotfiles")
            (config / "lua/plugins/walter.lua").symlink_to(repo / "nvim/lua/plugins/walter.lua")
        else:
            shutil.copytree(repo / "nvim", config)
        (config / "lazy-lock.json").write_bytes((repo / "nvim/lazy-lock.json").read_bytes())
        data = root / "data/nvim"
        data.mkdir(parents=True)
        (data / "lazy").symlink_to(plugins)
        env = dict(os.environ, HOME=tmp, XDG_CONFIG_HOME=str(root / "config"),
                   XDG_DATA_HOME=str(root / "data"), XDG_STATE_HOME=str(root / "state"),
                   XDG_CACHE_HOME=str(root / "cache"), NVIM_LOG_FILE=str(root / "nvim.log"),
                   DOTFILES_TEST_OMARCHY=str(int(omarchy)))
        result = subprocess.run(["nvim", "--headless", "-u", "NONE", "-l", str(repo / "tests/check_nvim.lua")],
                                env=env, cwd=tmp, capture_output=True, text=True, timeout=30)
        print("Omarchy overlay:" if omarchy else "Standalone:")
        print(result.stdout + result.stderr)
        if result.returncode:
            raise SystemExit(result.returncode)
