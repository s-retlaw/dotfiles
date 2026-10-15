# Dotfiles

Personal Bash helpers, tmux, herdr, and LazyVim configuration. The installer
backs up existing files before linking them to this checkout. Keep the checkout
in place when using symlinks.

## Install

Run as your normal user; package-manager operations use `sudo` when needed.
Root containers run those operations directly without requiring `sudo`.

```bash
./install.sh
source ~/.bashrc
```

Options:

| Option | Behavior |
| --- | --- |
| `--skip-packages` | Only install configuration; skip all package and release downloads. |
| `--copy` | Copy configurations instead of linking them, useful for containers. |
| `--omarchy` | Add overrides to an existing Omarchy LazyVim setup. |
| `--standalone` | Install the full Neovim configuration, bypassing Omarchy detection. |
| `--help` | Print usage. Unknown arguments fail before installation. |

Package installation has branches for Debian/Ubuntu, Fedora, Arch/Omarchy,
Alpine, and macOS/Homebrew. It includes compiler tools on Linux, search tools,
GitHub CLI, and Linux clipboard utilities. Neovim must be at least 0.11.2.
On Debian/Ubuntu, a sufficiently recent installed Neovim is reused; otherwise
a release is installed under the user's data directory. Linux release downloads
select x86-64 or ARM64; DuckDB also selects musl builds on Alpine. Herdr uses its
[official installer](https://herdr.dev/install.sh) only when missing; an existing
installation is not upgraded. On Alpine, install herdr separately.

User-installed binaries go in `~/.local/bin`; the shell helpers add that to PATH.
The installer respects `XDG_CONFIG_HOME` and `XDG_DATA_HOME`.

## Omarchy

Omarchy is detected from its installed directory, command, or `OMARCHY_PATH`.
You can also select this mode explicitly:

```bash
./install.sh --omarchy
```

This keeps Omarchy's `init.lua`, `lua/config/lazy.lua`, existing options, plugins,
and theme integration. It installs only:

- `lua/dotfiles/`: shared editor options and plugin customizations.
- `lua/plugins/walter.lua`: entry point that loads those customizations.
- Additional language/coding extras merged into `lazyvim.json`; existing extras
  and other settings are preserved.

Python 3 is required to merge the JSON. Omarchy's LazyVim setup must already
exist. Your shared preferences override corresponding editor defaults; other
Omarchy settings remain in effect. The standalone TokyoNight theme is not
installed in this mode. Launch the editor normally with `nvim`.

These overrides use [LazyVim's plugin customization mechanism](https://www.lazyvim.org/configuration/plugins)
and follow [Omarchy's guidance to customize user configs](https://omarchy.org/manual/dotfiles/).
Do not run `--standalone` on Omarchy unless you intend to replace its entire
Neovim configuration with the repo's standalone setup.

## Configuration

| Repo path | Installed location / purpose |
| --- | --- |
| `.bashrc` | Shell helper snippet at `~/.config/dotfiles/bashrc`, sourced once from your existing `~/.bashrc`. |
| `tmux/tmux.conf` | `~/.tmux.conf`. |
| `herdr/config.toml` | `~/.config/herdr/config.toml` on non-Omarchy installs; Omarchy mode leaves it untouched. Session data, sockets, and logs are left in place. |
| `nvim/` | `~/.config/nvim` on standalone machines; selected overrides on Omarchy. |

The snippet supplies `resize` / `rs`, container detection, PATH setup, and
Debian command aliases. It is not a replacement for your complete `.bashrc`.
The resize helper queries the current pane's terminal, times out after two
seconds, and restores terminal settings on exit.

Herdr uses the Omarchy baseline imported from Walter's Omarchy desktop on
October 15, 2026: `Ctrl+Space` prefix, terminal colors, `Alt+Up/Down` workspace
switching, and `Alt+Left/Right` tab switching. Close confirmations and pane
scrollbars are disabled, matching that baseline. `Alt+j/k` remain available to
LazyVim rather than being captured by Herdr.

In Omarchy mode, the installer neither creates nor replaces Herdr's config.
Keep Omarchy's own defaults there. On other computers, this repository is the
source of truth. Compare newer Omarchy configs against `herdr/config.toml`,
review changes, and update this copy manually as Omarchy develops. Copy-mode
installs need redeployment after changes; symlink installs see repo edits.
Keep a backup before deploying and verify settings against the installed
Herdr version. A new default can be imported with LocalSend; do not automatically
synchronize over Omarchy's config.
See the [herdr configuration docs](https://herdr.dev/docs/configuration/).
The installer does not restart or reload a running herdr session. To apply
settings yourself, use `herdr server reload-config` or the in-app reload action.

Tmux uses `Ctrl-a` on a host and `Ctrl-b` inside containers or herdr, with mouse
support, Vim-style pane navigation, and clipboard support when available.
Reload with prefix + `r`. Prefix detection occurs in the tmux server environment;
a server started outside herdr retains that context when attached inside it.

Neovim bootstraps lazy.nvim and installs plugins on first launch. Shared features:

- Two-space indentation, relative line numbers, persistent undo.
- Surround mappings: `ys`, `ds`, `cs`, `yss`, and visual `S`.
- Function/class/parameter text objects: `af`/`if`, `ac`/`ic`, `aa`/`ia`.
- LazyVim code motions, including `]f`/`[f` and `]c`/`[c`.
- Parameter swaps: `<leader>a` and `<leader>A`.
- Docker, Go, Helm, Markdown, Python, Rust, Terraform, and YAML extras.

Use `:Lazy` for plugins, `:Mason` for language tools, and `:checkhealth` for machine
requirements. Language tools may need runtimes such as Node.js, Go, or Rust;
enabling a language extra does not install its entire toolchain.

## Backups and recovery

Backups live at `~/.dotfiles_backup/<timestamp>.<unique-id>/item.<unique-id>/`.
Each item contains the original file/directory and `target.txt`, recording where
it came from. Unique directories avoid collisions during rapid repeated runs.
Before appending the shell source line, the original `.bashrc` is copied there.

To restore an item, read its `target.txt`, move the installed target aside, then
move the backed-up file/directory to that path. Stop affected applications first.
For `.bashrc`, restoring the backup also removes the added source line.

Repeated symlink installs skip links that already point to the repo. Copy mode
backs up and replaces its targets on each run; rerun it to pick up repo changes.
Changes to `lazy-lock.json` from plugin updates are tracked; commit intentional
updates to carry them to another machine, and use `:Lazy restore` to restore locks.

## Verification

```bash
bash -n install.sh .bashrc
python3 -m unittest discover -s tests -v
python3 tests/check_nvim.py
python3 tests/check_tmux.py
HERDR_CONFIG_PATH="$PWD/herdr/config.toml" herdr config check
```

Installer tests use temporary homes and skip package installation. The optional
Neovim integration check uses already-installed plugins with isolated configs,
state, cache, and lockfiles; it checks standalone and Omarchy-style loading.
It does not download plugins. These checks do not replace testing on an actual
Omarchy machine or each supported package manager.
