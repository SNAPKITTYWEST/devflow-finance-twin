"""Root conftest.py — makes src/ importable for all pytest runs without
requiring PYTHONPATH to be set manually."""

import sys
from pathlib import Path

SRC = Path(__file__).resolve().parent / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))
