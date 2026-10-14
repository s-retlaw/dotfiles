# Personal shell helpers. Sourced from ~/.bashrc by install.sh.

# User-installed binaries (herdr and optional release tools).
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# Debian/Ubuntu package names differ from the usual command names.
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
    alias fd=fdfind
fi
if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
    alias bat=batcat
fi

# Query this pane's terminal size. A subshell keeps cleanup traps local.
resize() (
    local old_stty response rows cols
    old_stty=$(stty -g < /dev/tty) || return
    trap 'stty "$old_stty" < /dev/tty; printf "\0338" > /dev/tty' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    stty raw -echo < /dev/tty
    printf '\0337\033[9999;9999H\033[6n' > /dev/tty
    if ! IFS= read -r -t 2 -d R response < /dev/tty; then
        echo "Terminal size query timed out" >&2
        return 1
    fi
    if [[ "$response" =~ $'\033'\[([0-9]+)\;([0-9]+)$ ]]; then
        rows=${BASH_REMATCH[1]}
        cols=${BASH_REMATCH[2]}
        stty "$old_stty" < /dev/tty
        if [[ -n "${TMUX:-}" ]]; then
            tmux refresh-client -C "${cols}x${rows}"
        else
            stty rows "$rows" cols "$cols" < /dev/tty
        fi
        echo "Resized to ${rows}x${cols}"
    else
        echo "Invalid terminal size response" >&2
        return 1
    fi
)
alias rs=resize

if [[ -f /.dockerenv ]] || [[ -f /run/.containerenv ]]; then
    export DEVC_CONTAINER=1
fi
