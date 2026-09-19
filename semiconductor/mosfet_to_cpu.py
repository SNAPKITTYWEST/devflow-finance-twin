"""
transistor_to_cpu.py
Hand-rolled stack: MOSFET → CMOS → gates → adder → ALU → CPU.

Level 1: MOSFET switch-level simulator (nodes, transistors, union-find)
Level 2: CMOS gates built from transistors (INV, NAND2, NOR2, TG, MUX2)
Level 3: Gate-level primitives (AND, OR, XOR, NAND, NOR, NOT)
Level 4: Half adder, full adder, ripple-carry adder, add/sub
Level 5: 8-bit ALU with 8 opcodes
Level 6: Behavioral D flip-flop
Level 7: Accumulator CPU with program ROM

Run: python3 mosfet_to_cpu.py
"""

from enum import IntEnum
from collections import defaultdict


# ═════════════════════════════════════════════════════════════════════
# Level 1 — MOSFET switch-level simulator
# ═════════════════════════════════════════════════════════════════════

class L(IntEnum):
    ZERO = 0
    ONE  = 1
    Z    = 2   # high-impedance / floating
    X    = 3   # conflict (VDD and GND both driving)


class Node:
    __slots__ = ('name', 'level', 'fixed')
    def __init__(self, name, level=L.Z, fixed=False):
        self.name  = name
        self.level = level
        self.fixed = fixed
    def __repr__(self):
        return f"{self.name}={self.level.name}"


class Transistor:
    __slots__ = ('name', 'kind', 'gate', 'd', 's')
    def __init__(self, name, kind, gate, drain, source):
        assert kind in ('nmos', 'pmos')
        self.name = name
        self.kind = kind
        self.gate = gate
        self.d    = drain
        self.s    = source

    def conducts(self):
        g = self.gate.level
        return g == L.ONE if self.kind == 'nmos' else g == L.ZERO


class Circuit:
    """Switch-level circuit: nodes + transistors; evaluate by union-find
    over conducting transistors, then assign levels per connected component."""
    def __init__(self):
        self.nodes       = {}
        self.transistors = []
        self.VDD = self.add_node('VDD', L.ONE,  fixed=True)
        self.GND = self.add_node('GND', L.ZERO, fixed=True)

    def add_node(self, name, level=L.Z, fixed=False):
        if name in self.nodes:
            return self.nodes[name]
        n = Node(name, level, fixed)
        self.nodes[name] = n
        return n

    def nmos(self, name, gate, drain, source):
        self.transistors.append(Transistor(name, 'nmos', gate, drain, source))

    def pmos(self, name, gate, drain, source):
        self.transistors.append(Transistor(name, 'pmos', gate, drain, source))

    def evaluate(self):
        parent = {n: n for n in self.nodes}

        def find(x):
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x

        for t in self.transistors:
            if t.conducts():
                a, b = find(t.d.name), find(t.s.name)
                if a != b:
                    parent[a] = b

        groups = defaultdict(list)
        for n in self.nodes:
            groups[find(n)].append(n)

        new_lvl = {}
        for root, members in groups.items():
            has_vdd = any(self.nodes[m].name == 'VDD' for m in members)
            has_gnd = any(self.nodes[m].name == 'GND' for m in members)
            if has_vdd and has_gnd:
                new_lvl[root] = L.X
            elif has_vdd:
                new_lvl[root] = L.ONE
            elif has_gnd:
                new_lvl[root] = L.ZERO
            else:
                prev = {self.nodes[m].level for m in members
                        if self.nodes[m].level not in (L.Z,)}
                if len(prev) == 1:
                    new_lvl[root] = prev.pop()
                elif not prev:
                    new_lvl[root] = L.Z
                else:
                    new_lvl[root] = L.X

        for root, members in groups.items():
            lv = new_lvl[root]
            if lv == L.Z:
                continue
            for m in members:
                if not self.nodes[m].fixed:
                    self.nodes[m].level = lv

    def settle(self, max_iter=50):
        for _ in range(max_iter):
            before = tuple(n.level for n in self.nodes.values())
            self.evaluate()
            after  = tuple(n.level for n in self.nodes.values())
            if before == after:
                return True
        return False


# ═════════════════════════════════════════════════════════════════════
# Level 2 — CMOS gates built from transistors
# ═════════════════════════════════════════════════════════════════════

def cmos_inv(c, name, a, y):
    c.pmos(name + '_pu', a, y, c.VDD)
    c.nmos(name + '_pd', a, y, c.GND)


def cmos_nand2(c, name, a, b, y):
    c.pmos(name + '_pua', a, y, c.VDD)
    c.pmos(name + '_pub', b, y, c.VDD)
    m = c.add_node(name + '_m')
    c.nmos(name + '_pda', a, y, m)
    c.nmos(name + '_pdb', b, m, c.GND)


def cmos_nor2(c, name, a, b, y):
    m = c.add_node(name + '_m')
    c.pmos(name + '_pua', a, m, c.VDD)
    c.pmos(name + '_pub', b, y, m)
    c.nmos(name + '_pda', a, y, c.GND)
    c.nmos(name + '_pdb', b, y, c.GND)


def cmos_tgate(c, name, ctrl, ctrl_n, a, b):
    c.pmos(name + '_p', ctrl_n, a, b)
    c.nmos(name + '_n', ctrl,   a, b)


def cmos_mux2(c, name, s, a, b, y):
    sn = c.add_node(name + '_sn')
    cmos_inv(c, name + '_is', s, sn)
    cmos_tgate(c, name + '_tga', sn, s,  a, y)
    cmos_tgate(c, name + '_tgb', s,  sn, b, y)


# ═════════════════════════════════════════════════════════════════════
# Level 3 — gate-level primitives
# ═════════════════════════════════════════════════════════════════════

def NOT(a):    return 1 - a
def NAND(a,b): return 1 - (a & b)
def NOR(a,b):  return 1 - (a | b)
def AND(a,b):  return a & b
def OR(a,b):   return a | b
def XOR(a,b):  return a ^ b


# ═════════════════════════════════════════════════════════════════════
# Level 4 — adders
# ═════════════════════════════════════════════════════════════════════

def half_adder(a, b):
    return XOR(a, b), AND(a, b)

def full_adder(a, b, cin):
    s1, c1 = half_adder(a, b)
    s2, c2 = half_adder(s1, cin)
    return s2, OR(c1, c2)

def ripple_carry_adder(a_bits, b_bits, cin=0):
    out, c = [], cin
    for i in range(len(a_bits)):
        s, c = full_adder(a_bits[i], b_bits[i], c)
        out.append(s)
    return out, c


# ═════════════════════════════════════════════════════════════════════
# Level 5 — 8-bit ALU
# ═════════════════════════════════════════════════════════════════════

OP_ADD, OP_SUB, OP_AND, OP_OR  = 0, 1, 2, 3
OP_XOR, OP_NOT, OP_SHL, OP_SHR = 4, 5, 6, 7


def alu_8(op, a, b):
    """a, b: 8-element LSB-first bit lists.
    Returns (result_bits, zero, carry, overflow)."""
    if op == OP_ADD:
        r, c = ripple_carry_adder(a, b, 0)
    elif op == OP_SUB:
        b_inv = [1 - x for x in b]
        r, c  = ripple_carry_adder(a, b_inv, 1)
    elif op == OP_AND:
        r = [AND(a[i], b[i]) for i in range(8)]; c = 0
    elif op == OP_OR:
        r = [OR(a[i],  b[i]) for i in range(8)]; c = 0
    elif op == OP_XOR:
        r = [XOR(a[i], b[i]) for i in range(8)]; c = 0
    elif op == OP_NOT:
        r = [NOT(x) for x in a]; c = 0
    elif op == OP_SHL:
        r = [0] + a[:-1]; c = a[7]
    elif op == OP_SHR:
        r = a[1:] + [0];  c = a[0]
    else:
        r, c = [0]*8, 0

    zero = 1 if all(x == 0 for x in r) else 0
    if   op == OP_ADD: ov = 1 if (a[7] == b[7]  and r[7] != a[7]) else 0
    elif op == OP_SUB: ov = 1 if (a[7] != b[7]  and r[7] != a[7]) else 0
    else:              ov = 0
    return r, zero, c, ov


# ═════════════════════════════════════════════════════════════════════
# Level 6 — sequential storage
# ═════════════════════════════════════════════════════════════════════

class DFF:
    """Behavioral rising-edge D flip-flop, parameterizable width."""
    def __init__(self, width=8):
        self.width = width
        self.q = [0] * width

    def tick(self, d, rising=True):
        if rising:
            self.q = list(d)
        return list(self.q)


# ═════════════════════════════════════════════════════════════════════
# Level 7 — accumulator CPU
# ═════════════════════════════════════════════════════════════════════

class CPU:
    """
    Instruction set (opcode byte, operand byte):
      0x00 NOP
      0x10 LDA imm  ; A ← imm
      0x20 ADD imm  ; A ← A + imm
      0x21 SUB imm  ; A ← A - imm
      0x22 AND imm
      0x23 OR  imm
      0x24 XOR imm
      0x25 NOT
      0x30 STA addr ; mem[addr] ← A
      0x40 LDI addr ; A ← mem[addr]
      0x50 JMP addr ; PC ← addr
      0x60 JZ  addr ; if zero flag, PC ← addr
      0x70 HLT
    """
    def __init__(self):
        self.A        = [0]*8
        self.PC       = 0
        self.IR       = 0
        self.operand  = 0
        self.zero     = 1
        self.carry    = 0
        self.overflow = 0
        self.halted   = False
        self.mem      = [0]*256
        self.rom      = [0]*512
        self.cycles   = 0

    def _bits(self, v):
        return [(v >> i) & 1 for i in range(8)]

    def _byte(self, b):
        v = 0
        for i, x in enumerate(b):
            if x: v |= (1 << i)
        return v & 0xFF

    def load(self, program):
        for i, (op, imm) in enumerate(program):
            self.rom[2*i]   = op  & 0xFF
            self.rom[2*i+1] = imm & 0xFF

    def step(self):
        if self.halted:
            return False
        self.cycles += 1
        self.IR      = self.rom[self.PC]
        self.operand = self.rom[(self.PC + 1) & 0xFF]
        self.PC      = (self.PC + 2) & 0xFF
        op, imm = self.IR, self.operand

        if   op == 0x00: pass
        elif op == 0x10:
            self.A    = self._bits(imm)
            self.zero = 1 if imm == 0 else 0
        elif op == 0x20:
            r,z,c,v = alu_8(OP_ADD, self.A, self._bits(imm))
            self.A, self.zero, self.carry, self.overflow = r,z,c,v
        elif op == 0x21:
            r,z,c,v = alu_8(OP_SUB, self.A, self._bits(imm))
            self.A, self.zero, self.carry, self.overflow = r,z,c,v
        elif op == 0x22:
            r,z,_,_ = alu_8(OP_AND, self.A, self._bits(imm)); self.A, self.zero = r,z
        elif op == 0x23:
            r,z,_,_ = alu_8(OP_OR,  self.A, self._bits(imm)); self.A, self.zero = r,z
        elif op == 0x24:
            r,z,_,_ = alu_8(OP_XOR, self.A, self._bits(imm)); self.A, self.zero = r,z
        elif op == 0x25:
            r,z,_,_ = alu_8(OP_NOT, self.A, self._bits(0));   self.A, self.zero = r,z
        elif op == 0x30: self.mem[imm] = self._byte(self.A)
        elif op == 0x40:
            self.A    = self._bits(self.mem[imm])
            self.zero = 1 if self.mem[imm] == 0 else 0
        elif op == 0x50: self.PC = imm
        elif op == 0x60:
            if self.zero: self.PC = imm
        elif op == 0x70: self.halted = True
        else:            self.halted = True
        return not self.halted

    def run(self, max_cycles=1000):
        while not self.halted and self.cycles < max_cycles:
            self.step()
        return self._byte(self.A)


# ═════════════════════════════════════════════════════════════════════
# Verification
# ═════════════════════════════════════════════════════════════════════

def _read(c, name):
    return 1 if c.nodes[name].level == L.ONE else 0


def verify_gates():
    print("── transistor-level gate verification ──")

    for a in (0, 1):
        c = Circuit()
        c.add_node('A', L.ONE if a else L.ZERO, fixed=True); c.add_node('Y')
        cmos_inv(c, 'g', c.nodes['A'], c.nodes['Y'])
        c.settle()
        assert _read(c, 'Y') == (1 - a), f"INV({a})"
    print(" INV : OK")

    for a in (0,1):
        for b in (0,1):
            c = Circuit()
            c.add_node('A', L.ONE if a else L.ZERO, fixed=True)
            c.add_node('B', L.ONE if b else L.ZERO, fixed=True)
            c.add_node('Y')
            cmos_nand2(c, 'g', c.nodes['A'], c.nodes['B'], c.nodes['Y'])
            c.settle()
            assert _read(c, 'Y') == NAND(a, b), f"NAND({a},{b})"
    print(" NAND2 : OK")

    for a in (0,1):
        for b in (0,1):
            c = Circuit()
            c.add_node('A', L.ONE if a else L.ZERO, fixed=True)
            c.add_node('B', L.ONE if b else L.ZERO, fixed=True)
            c.add_node('Y')
            cmos_nor2(c, 'g', c.nodes['A'], c.nodes['B'], c.nodes['Y'])
            c.settle()
            assert _read(c, 'Y') == NOR(a, b), f"NOR({a},{b})"
    print(" NOR2 : OK")

    for s in (0,1):
        for a in (0,1):
            for b in (0,1):
                c = Circuit()
                c.add_node('S', L.ONE if s else L.ZERO, fixed=True)
                c.add_node('A', L.ONE if a else L.ZERO, fixed=True)
                c.add_node('B', L.ONE if b else L.ZERO, fixed=True)
                c.add_node('Y')
                cmos_mux2(c, 'g', c.nodes['S'], c.nodes['A'], c.nodes['B'], c.nodes['Y'])
                c.settle()
                assert _read(c, 'Y') == (b if s else a), f"MUX2(s={s},a={a},b={b})"
    print(" MUX2 : OK (built from transmission gates)")


def verify_alu():
    print("── ALU verification ──")
    enc = lambda v: [(v >> i) & 1 for i in range(8)]
    dec = lambda b: sum(x << i for i, x in enumerate(b)) & 0xFF

    tests = [
        (OP_ADD, 0x12, 0x34, 0x46),
        (OP_SUB, 0x50, 0x20, 0x30),
        (OP_SUB, 0x10, 0x20, 0xF0),
        (OP_AND, 0xF0, 0x0F, 0x00),
        (OP_OR,  0xF0, 0x0F, 0xFF),
        (OP_XOR, 0xAA, 0x55, 0xFF),
        (OP_NOT, 0xAA, 0x00, 0x55),
        (OP_SHL, 0x01, 0x00, 0x02),
        (OP_SHR, 0x80, 0x00, 0x40),
    ]
    for op, a, b, want in tests:
        r,z,c,v = alu_8(op, enc(a), enc(b))
        got = dec(r)
        assert got == want, f"op={op} {a:02X},{b:02X} -> {got:02X} want {want:02X}"
    print(f" {len(tests)} ALU operations : OK")


def verify_cpu():
    print("── CPU verification ──")
    cpu = CPU()
    program = [
        (0x10, 0x05),   # LDA 5
        (0x20, 0x03),   # ADD 3  -> A=8
        (0x30, 0x10),   # STA 0x10 -> mem[0x10]=8
        (0x10, 0x00),   # LDA 0
        (0x20, 0x00),   # ADD 0  -> A=0, Z=1
        (0x60, 0x0E),   # JZ 0x0E
        (0x10, 0xFF),   # LDA 0xFF  (skipped)
        (0x70, 0x00),   # HLT
    ]
    cpu.load(program)
    cpu.run()
    assert cpu.mem[0x10] == 8,  f"mem[0x10]={cpu.mem[0x10]}"
    assert cpu._byte(cpu.A) == 0, f"A={cpu._byte(cpu.A)}"
    assert cpu.halted
    print(f" halted after {cpu.cycles} cycles")
    print(f" mem[0x10] = {cpu.mem[0x10]} (want 8)")
    print(f" final A   = {cpu._byte(cpu.A)} (want 0)")


# ═════════════════════════════════════════════════════════════════════
if __name__ == '__main__':
    print("╔══════════════════════════════════════════════════════╗")
    print("║  MOSFET → CMOS → gates → adder → ALU → CPU         ║")
    print("╚══════════════════════════════════════════════════════╝\n")
    verify_gates()
    print()
    verify_alu()
    print()
    verify_cpu()
    print("\nall levels verified.")
