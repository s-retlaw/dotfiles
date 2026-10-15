#!/usr/bin/env bash
# install.sh - Dotfiles installer
# Installs dependencies and creates symlinks (or copies) for dotfiles
#
# Usage: ./install.sh --help

set -euo pipefail

# -----------------------------------------------------------------------------
# Colors
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# -----------------------------------------------------------------------------
# Detect Environment
# -----------------------------------------------------------------------------
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPY_MODE=false

SKIP_PACKAGES=false
OMARCHY_MODE=auto
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BACKUP_DIR=""
TEMP_DIR=""

cleanup() {
    [[ -z "$TEMP_DIR" ]] || rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT

as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    elif command -v sudo &>/dev/null; then
        sudo "$@"
    else
        error "This operation needs root privileges. Install sudo or run as root."
        return 1
    fi
}

make_temp_dir() {
    if [[ -z "$TEMP_DIR" ]]; then
        TEMP_DIR=$(mktemp -d)
    fi
}

usage() {
    echo "Usage: ./install.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --copy           Copy files instead of symlinking (useful for containers)"
    echo "  --skip-packages  Skip package installation (useful when packages installed elsewhere)"
    echo "  --omarchy        Add overrides to an existing Omarchy Neovim setup"
    echo "  --standalone     Install the full Neovim config (override auto-detection)"
    echo "  --help           Show this help message"
}

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --copy) COPY_MODE=true ;;
        --skip-packages) SKIP_PACKAGES=true ;;
        --omarchy) OMARCHY_MODE=true ;;
        --standalone) OMARCHY_MODE=false ;;
        --help) usage; exit 0 ;;
        *) error "Unknown argument: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian) echo "debian" ;;
            fedora|rhel|centos|rocky|alma) echo "fedora" ;;
            arch|manjaro) echo "arch" ;;
            alpine) echo "alpine" ;;
            *) echo "linux" ;;
        esac
    else
        echo "unknown"
    fi
}

is_container() {
    [[ -f /.dockerenv ]] || [[ -f /run/.containerenv ]] || grep -q 'docker\|lxc\|containerd' /proc/1/cgroup 2>/dev/null
}

if [[ "$OMARCHY_MODE" == auto ]]; then
    OMARCHY_MODE=false
    if [[ -n "${OMARCHY_PATH:-}" ]] || [[ -d /usr/share/omarchy ]] || [[ -d "$HOME/.local/share/omarchy" ]] || command -v omarchy &>/dev/null; then
        OMARCHY_MODE=true
    fi
fi

OS=$(detect_os)
info "Detected OS: $OS"

if is_container; then
    info "Running inside a container"
fi

# -----------------------------------------------------------------------------
# GitHub Release Installers (for packages not in standard repos)
# -----------------------------------------------------------------------------
NVIM_MIN_VERSION="0.11.2"

version_gte() {
    # Returns 0 if $1 >= $2
    local a b c x y z
    IFS=. read -r a b c <<< "$1"
    IFS=. read -r x y z <<< "$2"
    (( a > x || (a == x && b > y) || (a == x && b == y && c >= z) ))
}

linux_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo x86_64 ;;
        aarch64|arm64) echo arm64 ;;
        *) error "Unsupported release architecture: $(uname -m)" >&2; return 1 ;;
    esac
}

neovim_version() {
    nvim --version | sed -n '1s/.*v\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p'
}

install_neovim_from_release() {
    local current_version=""
    if command -v nvim &>/dev/null; then
        current_version=$(neovim_version)
        if [[ -n "$current_version" ]] && version_gte "$current_version" "$NVIM_MIN_VERSION"; then
            success "neovim $current_version already installed"
            return
        fi
    fi
    local arch
    arch=$(linux_arch)
    make_temp_dir
    info "Installing neovim for Linux/$arch..."
    curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-$arch.tar.gz" -o "$TEMP_DIR/nvim.tar.gz"
    tar -xzf "$TEMP_DIR/nvim.tar.gz" -C "$TEMP_DIR"
    # Keep releases in the user's data directory; package-manager files stay intact.
    local release_dir="${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/neovim"
    backup_and_install "$TEMP_DIR/nvim-linux-$arch" "$release_dir" true
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$release_dir/bin/nvim" "$HOME/.local/bin/nvim"
    export PATH="$HOME/.local/bin:$PATH"
    success "neovim installed to $release_dir"
}

install_duckdb_from_release() {
    if command -v duckdb &>/dev/null; then
        success "duckdb already installed"
        return
    fi
    local arch asset_arch
    arch=$(linux_arch)
    case "$arch" in
        x86_64) asset_arch=amd64 ;;
        arm64) asset_arch=arm64 ;;
    esac
    if [[ "$OS" == alpine ]]; then
        asset_arch="$asset_arch-musl"
    fi
    make_temp_dir
    info "Installing DuckDB for Linux/$arch..."
    curl -fsSL "https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-$asset_arch.zip" -o "$TEMP_DIR/duckdb.zip"
    unzip -q "$TEMP_DIR/duckdb.zip" -d "$TEMP_DIR/duckdb"
    mkdir -p "$HOME/.local/bin"
    install -m 755 "$TEMP_DIR/duckdb/duckdb" "$HOME/.local/bin/duckdb"
}

install_herdr() {
    if command -v herdr &>/dev/null || [[ -x "$HOME/.local/bin/herdr" ]]; then
        success "herdr already installed"
        return
    fi
    if [[ "$OS" == alpine ]]; then
        warn "Install herdr separately on Alpine; its release installer targets glibc Linux/macOS."
        return
    fi
    make_temp_dir
    info "Installing herdr using its official installer..."
    curl -fsSL https://herdr.dev/install.sh -o "$TEMP_DIR/herdr-install.sh"
    HERDR_INSTALL_DIR="$HOME/.local/bin" sh "$TEMP_DIR/herdr-install.sh"
}

# -----------------------------------------------------------------------------
# Package Installation
# -----------------------------------------------------------------------------
install_packages() {
    info "Checking dependencies..."

    case "$OS" in
        macos)
            if ! command -v brew &>/dev/null; then
                warn "Homebrew not found. Installing..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            for pkg in git vim tmux neovim curl wget ripgrep fd fzf gh w3m bat duckdb; do
                if ! brew list "$pkg" &>/dev/null; then
                    info "Installing $pkg..."
                    brew install "$pkg"
                else
                    success "$pkg already installed"
                fi
            done
            ;;
        debian)
            local apt_packages=("git" "vim" "tmux" "build-essential" "curl" "wget" "ripgrep" "fd-find" "fzf" "w3m" "bat" "unzip" "wl-clipboard" "xclip")
            local missing=()
            for pkg in "${apt_packages[@]}"; do
                if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "^install ok installed$"; then
                    success "$pkg already installed"
                else
                    missing+=("$pkg")
                fi
            done
            if [[ ${#missing[@]} -gt 0 ]]; then
                info "Installing: ${missing[*]}"
                as_root apt-get update
                as_root apt-get install -y "${missing[@]}"
            fi
            # gh (GitHub CLI) needs special repo on Debian/Ubuntu
            if ! command -v gh &>/dev/null; then
                info "Installing gh (GitHub CLI)..."
                curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | as_root dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | as_root tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                as_root apt-get update
                as_root apt-get install -y gh
            else
                success "gh already installed"
            fi
            # Install neovim from GitHub releases for latest version
            install_neovim_from_release
            # Install duckdb from GitHub releases
            install_duckdb_from_release
            ;;
        fedora)
            local dnf_packages=("gcc" "gcc-c++" "make" "git" "vim" "tmux" "neovim" "curl" "wget" "ripgrep" "fd-find" "fzf" "gh" "w3m" "bat" "unzip" "wl-clipboard" "xclip")
            local missing=()
            for pkg in "${dnf_packages[@]}"; do
                if ! rpm -q "$pkg" &>/dev/null; then
                    missing+=("$pkg")
                else
                    success "$pkg already installed"
                fi
            done
            if [[ ${#missing[@]} -gt 0 ]]; then
                info "Installing: ${missing[*]}"
                as_root dnf install -y "${missing[@]}"
            fi
            # Install duckdb from GitHub releases
            install_duckdb_from_release
            ;;
        arch)
            local pacman_packages=("base-devel" "git" "vim" "tmux" "neovim" "curl" "wget" "ripgrep" "fd" "fzf" "github-cli" "w3m" "bat" "unzip" "wl-clipboard" "xclip")
            local missing=()
            for pkg in "${pacman_packages[@]}"; do
                if ! pacman -Q "$pkg" &>/dev/null; then
                    missing+=("$pkg")
                else
                    success "$pkg already installed"
                fi
            done
            if [[ ${#missing[@]} -gt 0 ]]; then
                info "Installing: ${missing[*]}"
                as_root pacman -S --needed --noconfirm "${missing[@]}"
            fi
            # Install duckdb from GitHub releases
            install_duckdb_from_release
            ;;
        alpine)
            local apk_packages=("build-base" "git" "vim" "tmux" "neovim" "curl" "wget" "ripgrep" "fd" "fzf" "github-cli" "w3m" "bat" "unzip" "wl-clipboard" "xclip")
            local missing=()
            for pkg in "${apk_packages[@]}"; do
                if ! apk info -e "$pkg" &>/dev/null; then
                    missing+=("$pkg")
                else
                    success "$pkg already installed"
                fi
            done
            if [[ ${#missing[@]} -gt 0 ]]; then
                info "Installing: ${missing[*]}"
                as_root apk add "${missing[@]}"
            fi
            # Install duckdb from GitHub releases
            install_duckdb_from_release
            ;;
        *)
            warn "Unknown OS. Please install packages manually: git, vim, tmux, neovim, curl, wget, ripgrep, fd, fzf, gh, w3m, bat, duckdb"
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Dotfile Installation
# -----------------------------------------------------------------------------
backup_and_install() {
    local source="$1"
    local target="$2"
    local force_copy="${3:-$COPY_MODE}"
    [[ -e "$source" ]] || { error "Missing source: $source" >&2; return 1; }

    # If target is already a symlink pointing to the right place (and not in copy mode), skip
    if [[ "$force_copy" == false ]] && [[ -L "$target" ]] && [[ "$(readlink "$target")" == "$source" ]]; then
        success "$(basename "$target") already linked"
        return
    fi

    # Backup existing file/directory
    if [[ -e "$target" ]] || [[ -L "$target" ]]; then
        ensure_backup_dir
        local entry_dir
        entry_dir=$(mktemp -d "$BACKUP_DIR/item.XXXXXX")
        warn "Backing up $target to $entry_dir"
        printf '%s\n' "$target" > "$entry_dir/target.txt"
        mv -- "$target" "$entry_dir/$(basename "$target")"
    fi

    # Create parent directory if needed
    mkdir -p "$(dirname "$target")"

    # Create symlink or copy
    if [[ "$force_copy" == true ]]; then
        cp -R "$source" "$target"
        success "Copied $(basename "$target")"
    else
        ln -s "$source" "$target"
        success "Linked $(basename "$target")"
    fi
}

ensure_backup_dir() {
    if [[ -z "$BACKUP_DIR" ]]; then
        mkdir -p "$HOME/.dotfiles_backup"
        BACKUP_DIR=$(mktemp -d "$HOME/.dotfiles_backup/$(date +%Y%m%d_%H%M%S).XXXXXX")
    fi
}

install_shell() {
    backup_and_install "$DOTFILES_DIR/.bashrc" "$CONFIG_HOME/dotfiles/bashrc"
    local rc="$HOME/.bashrc"
    local source_line='[ ! -r "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/bashrc" ] || source "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/bashrc"'
    if ! grep -qFx "$source_line" "$rc" 2>/dev/null; then
        if [[ -e "$rc" ]]; then
            ensure_backup_dir
            local entry_dir
            entry_dir=$(mktemp -d "$BACKUP_DIR/item.XXXXXX")
            printf '%s\n' "$rc" > "$entry_dir/target.txt"
            cp -L "$rc" "$entry_dir/.bashrc"
            # Detach a symlink before appending; do not edit its source.
            if [[ -L "$rc" ]]; then
                unlink "$rc"
                cp "$entry_dir/.bashrc" "$rc"
            fi
        fi
        printf '\n# Personal dotfiles helpers\n%s\n' "$source_line" >> "$rc"
    fi
}

validate_install() {
    if [[ "$OMARCHY_MODE" == true ]]; then
        command -v python3 &>/dev/null || { error "Omarchy overrides require python3 to merge LazyVim extras." >&2; return 1; }
        if [[ ! -f "$CONFIG_HOME/nvim/init.lua" || ! -f "$CONFIG_HOME/nvim/lua/config/lazy.lua" ]]; then
            error "Omarchy mode requires an existing LazyVim config. Set it up first, or use --standalone." >&2
            return 1
        fi
        # Never overlay the standalone repo onto itself (including through a link).
        if [[ "$CONFIG_HOME/nvim/init.lua" -ef "$DOTFILES_DIR/nvim/init.lua" ]]; then
            error "Neovim already uses this repo. Use --standalone here; --omarchy is for an Omarchy-owned config." >&2
            return 1
        fi
        make_temp_dir
        python3 "$DOTFILES_DIR/scripts/merge-lazyvim.py" "$DOTFILES_DIR/nvim/lazyvim.json" "$CONFIG_HOME/nvim/lazyvim.json" "$TEMP_DIR/lazyvim.json"
    fi
}

install_dotfiles() {
    backup_and_install "$DOTFILES_DIR/tmux/tmux.conf" "$HOME/.tmux.conf"
    if [[ "$OMARCHY_MODE" == true ]]; then
        info "Adding Neovim overrides; keeping the existing bootstrap and theme"
        backup_and_install "$DOTFILES_DIR/nvim/lua/dotfiles" "$CONFIG_HOME/nvim/lua/dotfiles"
        backup_and_install "$DOTFILES_DIR/nvim/lua/plugins/walter.lua" "$CONFIG_HOME/nvim/lua/plugins/walter.lua"
        if ! cmp -s "$TEMP_DIR/lazyvim.json" "$CONFIG_HOME/nvim/lazyvim.json"; then
            backup_and_install "$TEMP_DIR/lazyvim.json" "$CONFIG_HOME/nvim/lazyvim.json" true
        fi
    else
        backup_and_install "$DOTFILES_DIR/nvim" "$CONFIG_HOME/nvim"
    fi
    # Omarchy owns its Herdr defaults; only deploy our baseline elsewhere.
    # Only manage the config file, never sockets, logs, or session data.
    if [[ "$OMARCHY_MODE" == true ]]; then
        info "Keeping Omarchy's existing Herdr configuration"
    else
        backup_and_install "$DOTFILES_DIR/herdr/config.toml" "$CONFIG_HOME/herdr/config.toml"
    fi
    install_shell
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}       Dotfiles Installation${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    validate_install

    if [[ "$SKIP_PACKAGES" == true ]]; then
        info "Skipping package installation (--skip-packages)"
    else
        install_packages
        install_herdr
        if ! command -v nvim &>/dev/null; then
            error "Neovim is missing after package installation." >&2
            return 1
        fi
        local installed_version
        installed_version=$(neovim_version)
        if [[ -z "$installed_version" ]] || ! version_gte "$installed_version" "$NVIM_MIN_VERSION"; then
            error "LazyVim needs Neovim >= $NVIM_MIN_VERSION; update your distro's Neovim package." >&2
            return 1
        fi
    fi
    echo ""
    install_dotfiles

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}       Installation Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    info "Next steps:"
    echo "  1. Reload your shell: source ~/.bashrc"
    echo "  2. Start herdr: herdr (or start tmux: tmux)"
    echo "  3. Start neovim: nvim  (plugins will auto-install)"
    echo ""
    info "Useful commands:"
    echo "  - :Mason       - Open LSP installer in Neovim"
    echo "  - :LspInstall  - Install language server"
    echo "  - :Lazy        - Manage Neovim plugins"
    echo ""
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
