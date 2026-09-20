#!/usr/bin/env python3
"""
Bootstrap script to ensure virtualenv and dependencies (androidtvremote2, zeroconf)
are installed in ~/.local/share/omarchy-androidtv/venv.
"""

import os
import sys
import subprocess
from pathlib import Path

VENV_DIR = Path.home() / ".local" / "share" / "omarchy-androidtv" / "venv"
VENV_PYTHON = VENV_DIR / "bin" / "python3"

def ensure_venv():
    """Ensure the venv exists and has required packages."""
    if not VENV_PYTHON.exists():
        VENV_DIR.parent.mkdir(parents=True, exist_ok=True)
        print(f"[bootstrap] Creating virtualenv at {VENV_DIR}...", file=sys.stderr)
        subprocess.check_call([sys.executable, "-m", "venv", str(VENV_DIR)])
        print("[bootstrap] Installing androidtvremote2 and zeroconf...", file=sys.stderr)
        subprocess.check_call([
            str(VENV_PYTHON), "-m", "pip", "install", "--upgrade", "pip",
            "androidtvremote2", "zeroconf"
        ])
    
    # Check if currently running inside this venv
    if Path(sys.executable).resolve() != VENV_PYTHON.resolve():
        # Re-execute with venv python
        os.execv(str(VENV_PYTHON), [str(VENV_PYTHON)] + sys.argv)

if __name__ == "__main__":
    ensure_venv()
