# .bashrc - Shell customizations for dev containers

# -----------------------------------------------------------------------------
# Resize function (fixes terminal size in nested sessions)
# -----------------------------------------------------------------------------
# Use this when the outer tmux pane is resized but inner apps don't update.
# Works by querying the terminal for its actual size via escape sequences.

resize() {
    local old_stty rows cols

    # Save terminal state
    old_stty=$(stty -g)
    stty raw -echo min 0 time 5

    # Query terminal size using escape sequences
    # This queries the ACTUAL terminal (goes through all layers to host)
    printf '\033[9999;9999H\033[6n' > /dev/tty
    IFS='[;' read -r -d R _ rows cols < /dev/tty

    # Restore terminal state
    stty "$old_stty"

    if [[ -n "$rows" && -n "$cols" ]]; then
        if [[ -n "$TMUX" ]]; then
            # Inside tmux: use tmux's resize mechanism
            tmux refresh-client -C "${cols}x${rows}"
            echo "Resized tmux to ${cols}x${rows}"
        else
            # Outside tmux: set PTY directly and signal processes
            stty rows "$rows" cols "$cols"
            # Signal any running apps
            pkill -SIGWINCH -P $$ 2>/dev/null
            echo "Resized to ${rows}x${cols}"
        fi
    else
        echo "Failed to detect terminal size"
    fi
}

alias rs='resize'

# Alias for convenience
alias rs='resize'

# -----------------------------------------------------------------------------
# Container detection
# -----------------------------------------------------------------------------
if [[ -f /.dockerenv ]] || [[ -f /run/.containerenv ]]; then
    export DEVC_CONTAINER=1
fi
