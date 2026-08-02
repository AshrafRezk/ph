#!/usr/bin/env python3
"""Upload Chemipharm CLM deck. Prefer scripts/upload_pharma_clms.py for both decks."""

from __future__ import annotations

import runpy
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "upload_pharma_clms.py"
sys.argv = [str(SCRIPT), "--chemipharm-only", *sys.argv[1:]]
runpy.run_path(str(SCRIPT), run_name="__main__")
