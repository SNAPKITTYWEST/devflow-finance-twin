#!/usr/bin/env python3
"""check_deep_imports.py — Import boundary linter for the devflow-finance-twin repo.

Rules enforced
--------------
1. For every .py file **outside** dream_rsi/:
   Flag any ``from dream_rsi.X.Y import …`` (3 or more dotted segments,
   i.e. reaching into internal sub-submodules).

2. For every .py file **outside** constraint-harness/:
   Flag imports of the following internal module paths:
     from mxml.parser import …
     from mxml.validator import …
     from mxml.schema import …
     from runtime.executor import …
     from scheduler.dag import …
     from scheduler.scheduler import …

Exit codes
----------
0  — no violations found
1  — one or more violations found
"""

import ast
import pathlib
import sys

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]

EXCLUDED_DIRS = {".git", ".continuity", ".pytest_cache", "__pycache__", "venv"}

# deep dream_rsi imports: from dream_rsi.X.Y import …  (3+ segments)
DREAM_RSI_PREFIX = "dream_rsi."

# constraint-harness internal modules that must not leak outside
CONSTRAINT_HARNESS_FORBIDDEN = {
    "mxml.parser",
    "mxml.validator",
    "mxml.schema",
    "runtime.executor",
    "scheduler.dag",
    "scheduler.scheduler",
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _collect_py_files(root: pathlib.Path):
    """Yield all .py files under *root*, skipping excluded directories."""
    for path in root.rglob("*.py"):
        # Skip any path that contains an excluded directory component.
        if any(part in EXCLUDED_DIRS for part in path.parts):
            continue
        yield path


def _is_under(path: pathlib.Path, dirname: str) -> bool:
    """Return True if *path* is somewhere inside a directory named *dirname*."""
    return any(part == dirname for part in path.relative_to(REPO_ROOT).parts)


def _parse_imports(source: str, filepath: pathlib.Path):
    """Yield (lineno, module, names_str) tuples for every import statement."""
    try:
        tree = ast.parse(source, filename=str(filepath))
    except SyntaxError:
        return

    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module:
            names = ", ".join(
                (alias.asname or alias.name) for alias in node.names
            )
            yield node.lineno, node.module, names
        elif isinstance(node, ast.Import):
            for alias in node.names:
                yield node.lineno, alias.name, ""


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    violations = []

    for py_file in sorted(_collect_py_files(REPO_ROOT)):
        rel = py_file.relative_to(REPO_ROOT)
        in_dream_rsi = _is_under(py_file, "dream_rsi")
        in_constraint_harness = _is_under(py_file, "constraint-harness")

        try:
            source = py_file.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue

        for lineno, module, names in _parse_imports(source, py_file):
            # Rule 1 — deep dream_rsi sub-submodule imports from outside dream_rsi/
            if not in_dream_rsi:
                if module.startswith(DREAM_RSI_PREFIX):
                    # Count segments: dream_rsi.X.Y has 3 segments → internal
                    if module.count(".") >= 2:
                        msg = (
                            f"deep dream_rsi import: "
                            f"'from {module} import {names}' — "
                            "import from dream_rsi public API instead"
                        )
                        violations.append(f"{rel}:{lineno}: {msg}")

            # Rule 2 — constraint-harness internal modules from outside
            if not in_constraint_harness:
                for forbidden in CONSTRAINT_HARNESS_FORBIDDEN:
                    if module == forbidden or module.startswith(forbidden + "."):
                        msg = (
                            f"constraint-harness internal import: "
                            f"'from {module} import {names}' — "
                            "this module must not be imported outside constraint-harness/"
                        )
                        violations.append(f"{rel}:{lineno}: {msg}")
                        break  # one report per import node

    if violations:
        for v in violations:
            print(v)
        sys.exit(1)
    else:
        print("check_deep_imports: no violations found")
        sys.exit(0)


if __name__ == "__main__":
    main()
