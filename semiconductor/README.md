# semiconductor

End-to-end SoC design dossier: specification through silicon.

## Contents

| File | Description |
|------|-------------|
| `architecture.md` | AI Accelerator SoC chip architecture — 256×256 systolic array, RISC-V RV64IMAC scalar, 3nm FinFET, 10 TOPS @ 15W |
| `soc-pipeline-spec.md` | Full production-depth 5nm SoC pipeline trace — OoO cores, INT8/INT4, LPDDR5/HBM2e, security island |
| `logic-design-synthesis.md` | RTL design, synthesis flow, standard-cell library, device physics |
| `eda-physical-design.md` | EDA toolchain, floorplan, placement, CTS, routing, physical verification, mask prep |
| `fabrication.md` | Wafer fabrication — FEOL/BEOL, lithography, deposition, etching, doping, FinFET/GAA |
| `packaging-validation.md` | Packaging options, silicon validation, yield analysis, full traceability chain |
| `rtl-multipliers.md` | Booth radix-2/4, Wallace-tree reduction, RISC-V vector unit — Chisel + VHDL + CUDA |
| `rtl-alu.md` | Full SystemVerilog RV64 ALU — adder, shifter, compare, multiplier, divider sub-modules |
| `sk_transformer.vhd` | Q4.12 fixed-point transformer in VHDL — types pkg, RMSNorm, matvec, Weyl structure, attention, testbench |
| `sk_attention_matvec.vhd` | Parameterized M×N matvec engine + AXI4 single-head causal attention with K/V from external memory |
| `sk_logic_cells.vhd` | Standard cell library — INV, NAND, NOR, AND, OR, XOR, MUX, DFF, recursive cells, ASIC bindings |
| `transformer_matlab.m` | MATLAB transformer forward pass with Weyl deformation layer + `init_deformation()` |
| `mosfet_to_cpu.py` | 7-level bottom-up simulation: MOSFET switch-level → CMOS cells → adder → ALU → accumulator CPU |

## Design Points

Two SoC targets are documented:
- **3nm AI accelerator** (`architecture.md`): 10 TOPS, 256×256 systolic array, single die focus
- **5nm edge AI SoC** (`soc-pipeline-spec.md`): 32–64 TOPS, heterogeneous OoO + matrix engines, full security island

These are separate design points, not conflicting specs.

## Running the Python simulation

```bash
python semiconductor/mosfet_to_cpu.py
# Expected output: all levels verified.
```
