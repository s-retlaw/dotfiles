"""Load the config in a temporary tmux server, without touching existing sessions."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="dotfiles-tmux-") as tmp:
    cmd = ["tmux", "-S", str(Path(tmp) / "tmux.sock")]
    try:
        subprocess.run(cmd + ["-f", str(repo / "tmux/tmux.conf"), "new-session", "-d", "-s", "dotfiles-check"], check=True)
        subprocess.run(cmd + ["source-file", str(repo / "tmux/tmux.conf")], check=True)
        result = subprocess.run(cmd + ["show-options", "-gv", "prefix"], check=True, capture_output=True, text=True)
        print("PASS: isolated tmux startup and config reload; prefix:", result.stdout.strip())
    finally:
        subprocess.run(cmd + ["kill-server"], capture_output=True)
