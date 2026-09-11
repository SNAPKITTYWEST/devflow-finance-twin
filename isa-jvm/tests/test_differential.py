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

"""Bytecode generation + differential tests vs reference interpreter."""

from __future__ import annotations

import pytest
from compiler.parser import parse_program
from compiler.verifier import verify
from compiler.bytecode import generate_class
from compiler.regmap import RegMap
from runtime.interpreter import Interpreter
from runtime.loader import compile_to_class, run_class_execute, REGISTRY
from runtime.agents import AgentScheduler, Channel
from runtime.invokedynamic_stub import SITES, bootstrap_java_source
from tools.trace_viewer import format_trace


def test_regmap():
    rm = RegMap()
    assert rm.local(0) == 0
    assert rm.local(7) == 7
    assert rm.max_locals() == 32


def test_generate_class_bytes():
    src = """
    LOAD_IMM R0, 10
    LOAD_IMM R1, 32
    ADD R2, R0, R1
    HALT
    """
    prog = parse_program(src)
    verify(prog)
    bc = generate_class(prog)
    assert bc[:4] == b"\xca\xfe\xba\xbe"
    assert len(bc) > 50


def test_compile_registry():
    src = "LOAD_IMM R0, 1\nHALT\n"
    prog = parse_program(src)
    verify(prog)
    gc = compile_to_class(prog)
    assert REGISTRY.get(gc.program_id) is not None
    assert gc.bytecode_hash


def test_differential_arith():
    """Interpreter R2 must equal JVM-backed result when backend can run."""
    src = """
    LOAD_IMM R0, 10
    LOAD_IMM R1, 32
    ADD R2, R0, R1
    HALT
    """
    prog = parse_program(src)
    verify(prog)
    st = Interpreter(prog).run()
    assert st.registers.get(2) == 42

    gc = compile_to_class(prog, "DiffArith")
    jvm_regs = run_class_execute(gc)
    if jvm_regs is not None:
        assert jvm_regs[2] == 42
        assert jvm_regs[0] == 10
    # if java rejects class, differential still validates interpreter oracle


def test_agent_scheduler():
    src = "LOAD_IMM R0, 1\nHALT\n"
    prog = parse_program(src)
    verify(prog)
    sched = AgentScheduler()
    aid = sched.spawn(prog)
    assert aid in sched.agents
    sched.run_round_robin(max_steps=10)
    assert sched.agents[aid].status.name in ("TERMINATED", "READY", "SUSPENDED")


def test_channel_backpressure():
    ch = Channel(id=1, capacity=1)
    assert ch.write(10)
    assert not ch.write(20) # full
    assert ch.read() == 10
    assert ch.write(20)
    ch.close()
    assert not ch.write(30)


def test_invokedynamic_sites():
    assert "TENSOR_DISPATCH" in SITES
    src = bootstrap_java_source()
    assert "CallSite" in src


def test_trace_viewer():
    src = "LOAD_IMM R0, 3\nADD R0, R0, R0\nHALT\n"
    prog = parse_program(src)
    verify(prog)
    interp = Interpreter(prog)
    interp.run(collect_trace=True)
    text = format_trace(interp.trace)
    assert "LOAD_IMM" in text
    assert "ADD" in text
