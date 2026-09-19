"""Run native Lua regressions and the example, failing rather than skipping errors."""
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def runtime():
    executable = os.environ.get("LUA_RUNTIME") or shutil.which("texlua") or shutil.which("lua")
    assert executable, "Install a Lua 5.3+ runtime with FFI, or set LUA_RUNTIME to its executable"
    return executable


def test_lua_engine_regressions():
    result = subprocess.run([runtime(), "benchmarks/rsi_lua/lua_audit.lua", "--check-only"],
                            cwd=ROOT, capture_output=True, text=True, encoding="utf-8", timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
    checks = [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]
    checks = [row for row in checks if row["kind"] == "check"]
    assert len(checks) >= 36, "Lua regression runner stopped before completing its checks"
    assert all(row["status"] == "pass" for row in checks), checks


def test_lua_examples_complete():
    result = subprocess.run([runtime(), "example_usage_all_backends.lua"], cwd=ROOT/"lua",
                            capture_output=True, text=True, encoding="utf-8", timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "All examples completed successfully" in result.stdout
    assert "Serialization failed" not in result.stdout
    assert "Deserialization failed" not in result.stdout
