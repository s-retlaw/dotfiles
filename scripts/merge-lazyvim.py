#!/usr/bin/env python3
"""Add shared extras while retaining the machine's LazyVim settings."""
import json
import sys
from pathlib import Path

shared, current, output = map(Path, sys.argv[1:])
settings = json.loads(current.read_text()) if current.exists() else {}
extras = settings.setdefault("extras", [])
if not isinstance(extras, list):
    raise ValueError("lazyvim.json extras must be a list")
for extra in json.loads(shared.read_text())["extras"]:
    if extra not in extras:
        extras.append(extra)
output.write_text(json.dumps(settings, indent=2) + "\n")
