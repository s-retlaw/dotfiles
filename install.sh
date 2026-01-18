#!/usr/bin/env bash
# install.sh - Dotfiles installer
# Installs dependencies and creates symlinks (or copies) for dotfiles
#
# Usage: ./install.sh [--copy]
#   --copy  Copy files instead of symlinking (useful for containers)

set -e

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

usage() {
    echo "Usage: ./install.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --copy    Copy files instead of symlinking (useful for containers)"
    echo "  --help    Show this help message"
}

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --copy) COPY_MODE=true ;;
        --help) usage; exit 0 ;;
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

OS=$(detect_os)
info "Detected OS: $OS"

if is_container; then
    info "Running inside a container"
fi

# -----------------------------------------------------------------------------
# Package Installation
# -----------------------------------------------------------------------------
install_packages() {
    local packages=("git" "tmux" "neovim")

    info "Checking dependencies..."

    case "$OS" in
        macos)
            if ! command -v brew &>/dev/null; then
                warn "Homebrew not found. Installing..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            for pkg in "${packages[@]}"; do
                if ! brew list "$pkg" &>/dev/null; then
                    info "Installing $pkg..."
                    brew install "$pkg"
                else
                    success "$pkg already installed"
                fi
            done
            ;;
        debian)
            local apt_packages=("git" "tmux" "neovim")
            local missing=()
            for pkg in "${apt_packages[@]}"; do
                if ! dpkg -l "$pkg" &>/dev/null; then
                    missing+=("$pkg")
                else
                    success "$pkg already installed"
                fi
            done
            if [[ ${#missing[@]} -gt 0 ]]; then
                info "Installing: ${missing[*]}"
                sudo apt-get update
                sudo apt-get install -y "${missing[@]}"
            fi
            ;;
        fedora)
            local dnf_packages=("git" "tmux" "neovim")
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
                sudo dnf install -y "${missing[@]}"
            fi
            ;;
        arch)
            local pacman_packages=("git" "tmux" "neovim")
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
                sudo pacman -S --noconfirm "${missing[@]}"
            fi
            ;;
        alpine)
            local apk_packages=("git" "tmux" "neovim")
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
                sudo apk add "${missing[@]}"
            fi
            ;;
        *)
            warn "Unknown OS. Please install git, tmux, and neovim manually."
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Dotfile Installation
# -----------------------------------------------------------------------------
backup_and_install() {
    local source="$1"
    local target="$2"
    local backup_dir="$HOME/.dotfiles_backup/$(date +%Y%m%d_%H%M%S)"

    # If target is already a symlink pointing to the right place (and not in copy mode), skip
    if [[ "$COPY_MODE" == false ]] && [[ -L "$target" ]] && [[ "$(readlink "$target")" == "$source" ]]; then
        success "$(basename "$target") already linked"
        return
    fi

    # Backup existing file/directory
    if [[ -e "$target" ]] || [[ -L "$target" ]]; then
        mkdir -p "$backup_dir"
        warn "Backing up existing $(basename "$target") to $backup_dir"
        mv "$target" "$backup_dir/"
    fi

    # Create parent directory if needed
    mkdir -p "$(dirname "$target")"

    # Create symlink or copy
    if [[ "$COPY_MODE" == true ]]; then
        cp -r "$source" "$target"
        success "Copied $(basename "$target")"
    else
        ln -s "$source" "$target"
        success "Linked $(basename "$target")"
    fi
}

install_dotfiles() {
    if [[ "$COPY_MODE" == true ]]; then
        info "Copying dotfiles..."
    else
        info "Creating symlinks..."
    fi

    # Tmux
    backup_and_install "$DOTFILES_DIR/tmux/tmux.conf" "$HOME/.tmux.conf"

    # Neovim
    backup_and_install "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
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

    install_packages
    echo ""
    install_dotfiles

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}       Installation Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    info "Next steps:"
    echo "  1. Start tmux:   tmux"
    echo "  2. Start neovim: nvim  (plugins will auto-install)"
    echo ""
    info "Useful commands:"
    echo "  - :Mason       - Open LSP installer in Neovim"
    echo "  - :LspInstall  - Install language server"
    echo "  - :Lazy        - Manage Neovim plugins"
    echo ""
}

main "$@"
