"""Isolated Python command. Treats supplied code as untrusted."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


def run_python(input_data: dict[str, Any], *, timeout: int = 10) -> dict[str, Any]:
    code = input_data.get("code") or input_data.get("expr") or "print('ok')"
    with tempfile.TemporaryDirectory() as td:
        script = Path(td) / "snippet.py"
        script.write_text(code, encoding="utf-8")
        try:
            proc = subprocess.run(
                [sys.executable, str(script)],
                capture_output=True,
                text=True,
                timeout=timeout,
                cwd=td,
            )
            return {
                "status": "ok" if proc.returncode == 0 else "error",
                "exit_code": proc.returncode,
                "stdout": proc.stdout,
                "stderr": proc.stderr,
            }
        except subprocess.TimeoutExpired:
            return {"status": "timeout", "exit_code": -1, "stdout": "", "stderr": "timeout"}
