# ========================================================================
# SOVEREIGN LEVIATHAN NODE LICENSE
# License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
# Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
# ========================================================================
#
# This file is a covered work under the GNU Affero General Public License,
# version 3, together with the Sovereign Leviathan additional terms.
#
# Hark, though this node be but a spark,
# Its covenant endureth through the dark.
#
# Ignorantia juris non excusat.
# ========================================================================

"""Dynamic .class loading via temp file + java subprocess, plus registry."""

from __future__ import annotations

import hashlib
import os
import subprocess
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from compiler.bytecode import generate_class
from compiler.ir import Program


@dataclass
class GeneratedClass:
    program_id: str
    class_name: str
    bytecode: bytes
    bytecode_hash: str
    timestamp: float
    source_name: str = ""


class ClassRegistry:
    def __init__(self) -> None:
        self._items: dict[str, GeneratedClass] = {}

    def register(self, gc: GeneratedClass) -> None:
        self._items[gc.program_id] = gc

    def get(self, program_id: str) -> GeneratedClass | None:
        return self._items.get(program_id)

    def all(self) -> list[GeneratedClass]:
        return list(self._items.values())


REGISTRY = ClassRegistry()


def compile_to_class(program: Program, class_name: str = "IsaProg") -> GeneratedClass:
    bc = generate_class(program, class_name)
    pid = hashlib.sha256(bc).hexdigest()[:16]
    gc = GeneratedClass(
        program_id=pid,
        class_name=class_name,
        bytecode=bc,
        bytecode_hash=hashlib.sha256(bc).hexdigest(),
        timestamp=time.time(),
        source_name=program.source_name,
    )
    REGISTRY.register(gc)
    return gc


def run_class_execute(gc: GeneratedClass) -> list[int] | None:
    """Write .class, run a tiny Java harness that reflects execute() and prints regs.
    Returns list of 8 ints or None if java fails.
    """
    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        class_path = td_path / f"{gc.class_name}.class"
        class_path.write_bytes(gc.bytecode)
        # small harness
        harness = f"""
public class Harness {{
  public static void main(String[] args) throws Exception {{
    long[] r = {gc.class_name}.execute();
    for (int i = 0; i < r.length; i++) {{
      if (i > 0) System.out.print(",");
      System.out.print(r[i]);
    }}
    System.out.println();
  }}
}}
"""
        (td_path / "Harness.java").write_text(harness)
        # compile harness referencing our class
        r1 = subprocess.run(
            ["javac", "-d", str(td_path), str(td_path / "Harness.java")],
            capture_output=True, text=True, cwd=td,
        )
        if r1.returncode != 0:
            # class may be invalid; return None
            return None
        r2 = subprocess.run(
            ["java", "-cp", str(td_path), "Harness"],
            capture_output=True, text=True, cwd=td, timeout=10,
        )
        if r2.returncode != 0:
            return None
        line = r2.stdout.strip()
        if not line:
            return None
        return [int(x) for x in line.split(",")]
