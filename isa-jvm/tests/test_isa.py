"""ISA foundation tests: parse, verify, interpret."""

import pytest
from compiler.parser import parse_program, ParseError
from compiler.verifier import verify, VerifyError
from runtime.interpreter import Interpreter
from isa.types import MachineState


def test_parse_arith():
    src = open("examples/arith.isa").read()
    prog = parse_program(src)
    assert len(prog.instructions) >= 8
    assert "equal" in prog.labels
    assert "done" in prog.labels


def test_verify_ok():
    src = open("examples/arith.isa").read()
    prog = parse_program(src)
    cfg = verify(prog)
    assert cfg.entry == 0
    assert len(cfg.blocks) >= 1


def test_unknown_mnemonic():
    with pytest.raises(ParseError):
        parse_program("FOOBAR R0, R1\n")


def test_wrong_arity():
    with pytest.raises(ParseError):
        parse_program("ADD R0, R1\n")


def test_undefined_label():
    with pytest.raises(ParseError):
        parse_program("JMP nowhere\n")


def test_interpret_add():
    src = """
    LOAD_IMM R0, 10
    LOAD_IMM R1, 32
    ADD R2, R0, R1
    HALT
    """
    prog = parse_program(src)
    verify(prog)
    interp = Interpreter(prog)
    st = interp.run()
    assert st.halted
    assert st.registers.get(2) == 42


def test_interpret_branch():
    src = open("examples/arith.isa").read()
    prog = parse_program(src)
    verify(prog)
    st = Interpreter(prog).run()
    assert st.registers.get(4) == 1 # equal path taken


def test_interpret_memory():
    src = open("examples/memory.isa").read()
    prog = parse_program(src)
    verify(prog)
    st = Interpreter(prog).run()
    assert st.registers.get(2) == 7
    assert st.memory[100] == 7


def test_interpret_channel():
    src = open("examples/channel.isa").read()
    prog = parse_program(src)
    verify(prog)
    st = Interpreter(prog).run()
    assert st.registers.get(3) == 99


def test_stack_push_pop():
    src = """
    LOAD_IMM R0, 5
    PUSH R0
    LOAD_IMM R0, 0
    POP R1
    HALT
    """
    prog = parse_program(src)
    verify(prog)
    st = Interpreter(prog).run()
    assert st.registers.get(1) == 5


def test_call_ret():
    src = """
    LOAD_IMM R0, 1
    CALL sub
    HALT
sub:
    LOAD_IMM R0, 99
    RET
    """
    prog = parse_program(src)
    verify(prog)
    st = Interpreter(prog).run()
    assert st.registers.get(0) == 99


def test_trace():
    src = """
    LOAD_IMM R0, 1
    ADD R0, R0, R0
    HALT
    """
    prog = parse_program(src)
    verify(prog)
    interp = Interpreter(prog)
    interp.run(collect_trace=True)
    assert len(interp.trace) == 3
    assert interp.trace[0]["op"] == "LOAD_IMM"
