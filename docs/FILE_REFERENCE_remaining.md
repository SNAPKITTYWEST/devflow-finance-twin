# FILE REFERENCE — Remaining Directories

> Comprehensive file-by-file reference for all directories not covered by companion agent documents.
> Repository root: `devflow-finance-twin/`
> Generated: 2026-09-19

---

## Table of Contents

1. [apple-design-parser/](#1-apple-design-parser)
2. [apple6502x86/](#2-apple6502x86)
3. [assembly-120-strict-model/](#3-assembly-120-strict-model)
4. [astre-vault/](#4-astre-vault)
5. [benchmarks/](#5-benchmarks)
6. [classifier/](#6-classifier)
7. [datalog-engine/](#7-datalog-engine)
8. [docs/](#8-docs)
9. [examples/](#9-examples)
10. [gpu/](#10-gpu)
11. [isa-jvm/](#11-isa-jvm)
12. [kernel-language/](#12-kernel-language)
13. [languages/](#13-languages)
14. [lua/](#14-lua)
15. [occam-b-bscl/](#15-occam-b-bscl)
16. [physics/](#16-physics)
17. [polyglot/](#17-polyglot)
18. [qflow/](#18-qflow)
19. [quantum_computer/](#19-quantum_computer)
20. [retro-gpu/](#20-retro-gpu)
21. [rust/](#21-rust)
22. [schema/](#22-schema)
23. [scripts/](#23-scripts)
24. [spiral-detection/](#24-spiral-detection)
25. [tests/](#25-tests)

---

## 1. apple-design-parser/

**Language:** Swift 5.9+
**Purpose:** Extracts Apple Human Interface Guideline design tokens — colors, typography, spacing — from raw HTML/CSS payloads scraped from developer.apple.com. Produces normalized `DesignToken` records that feed the semantic color classifier and palette generator used by the retro-GPU visualization stack.

### Directory Layout

```
apple-design-parser/
├── README.md
├── Sources/
│   ├── AppleDesignParser_main.swift       CLI entry point
│   ├── AppearanceResolver.swift           Light/dark appearance resolution
│   ├── CSSParser.swift                    CSS rule extraction
│   ├── ColorClassifier.swift              HSL semantic family classification
│   ├── ColorFormat.swift                  Color format enum + conversion helpers
│   ├── ColorNormalizer.swift              Normalizes hex/rgb/hsl → canonical SRGB
│   ├── HTMLParser.swift                   HTML element extraction
│   ├── PaletteGenerator.swift             Palette grid builder
│   ├── PatternExtractor.swift             Design-pattern frequency extraction
│   └── SemanticClassifier.swift           Semantic color role assignment
└── Tests/
    └── (test targets, Swift XCTest)
```

### File Descriptions

#### `Sources/AppleDesignParser_main.swift`
CLI entry point. Dispatches to four sub-commands via `CommandLine.arguments`:

| Command | Handler | Purpose |
|---------|---------|---------|
| `parse` | `handleParse(_:)` | Parse full HTML payload, produce structured token JSON |
| `extract` | `handleExtract(_:)` | Extract raw color swatches from CSS |
| `resolve` | `handleResolve(_:)` | Apply light/dark appearance context |
| `validate` | `handleValidate(_:)` | Validate token conformance against HIG rules |

Input: file path argument. Output: JSON to stdout. Exit codes: 0 = success, 1 = bad args, 2 = parse error.

#### `Sources/AppearanceResolver.swift`
Resolves Apple-style adaptive color specifications into a single concrete color value for a given appearance context (light/dark/increased-contrast). Handles `@media (prefers-color-scheme: dark)` CSS blocks and the `dynamicColor(light:dark:)` Swift API pattern. Returns a `ResolvedColor` struct carrying the final SRGB triple, appearance context, and source token name.

#### `Sources/CSSParser.swift`
Parses CSS text into a structured `CSSRuleset` representation. Handles: selector specificity (inline > ID > class > element), cascade order, `var()` custom property resolution, and `calc()` arithmetic. Extracts `color`, `background-color`, `border-color`, `fill`, `stroke`, and related properties. Returns an array of `CSSRule` objects each carrying selector, property map, and computed specificity weight.

#### `Sources/ColorClassifier.swift`
Classifies a normalized color into a semantic family. The primary data structures:

```swift
enum SemanticColorFamily: String, Codable {
    case red, orange, yellow, green, cyan, blue, purple,
         magenta, neutral, unknown
}

struct ColorProperties: Codable {
    let hueFamily: SemanticColorFamily
    let hueRange: (min: Double, max: Double)
    let saturationLevel: String   // "muted" | "desaturated" | "saturated" | "vivid"
    let lightnessLevel: String    // "dark" | "gray" | "light" | "bright"
    let vibrance: Double          // 0–1
    let contrast: Double          // contrast ratio vs. white
    let temperature: String       // "warm" | "cool" | "neutral"
    let brightness: Double        // 0–1
    let isNeutral: Bool
    let isPastel: Bool
    let isAccent: Bool
    let similarity: [ColorSimilarity]
}
```

Classification proceeds via HSL bucketing: hue [0°,360°] is divided into 10 bands each mapped to a `SemanticColorFamily`; saturation < 0.15 forces `neutral`; lightness extremes force `dark`/`bright` buckets.

#### `Sources/ColorFormat.swift`
Defines `ColorFormat` enum: `.hex6`, `.hex8`, `.rgb`, `.rgba`, `.hsl`, `.hsla`, `.srgb`, `.p3`, `.oklch`. Contains conversion functions between all formats plus WCAG 2.1 relative luminance and contrast ratio calculations.

#### `Sources/ColorNormalizer.swift`
Normalizes any supported `ColorFormat` input to a canonical SRGB `(r,g,b,a)` quad in `[0,1]^4`. Handles P3 wide-gamut conversion with ICC D65 illuminant matrix. Special cases: CSS named colors (147 entries), `currentColor`, `transparent`, `inherit`. Returns a `NormalizedColor` struct with original format, canonical SRGB, and gamut flags.

#### `Sources/HTMLParser.swift`
Lightweight HTML parser using `Foundation.XMLParser` configured in HTML5 lenient mode. Walks the element tree collecting `<style>` blocks, inline `style=` attributes, `<link rel="stylesheet">` hrefs, `<svg>` fill/stroke attributes, and `data-color-*` custom data attributes. Returns a `ParsedDocument` carrying extracted CSS text and a flat list of `DesignToken` raw records.

#### `Sources/PaletteGenerator.swift`
Generates a structured color palette grid from a set of `DesignToken` records. Groups tokens by semantic family and lightness bucket, produces a 10×6 grid (families × lightness steps) with WCAG contrast annotations. Output: `PaletteGrid` JSON. Used to produce the color reference included in docs/MATH_DICTIONARY.md.

#### `Sources/PatternExtractor.swift`
Extracts frequency-ranked design patterns (color usage frequency, spacing scale regularity, typography scale ratio) from a parsed document. Computes: modal hue family, primary/secondary/accent color triples, base spacing unit (px), type scale ratio (geometric mean of adjacent size steps). Returns `PatternReport` JSON.

#### `Sources/SemanticClassifier.swift`
Assigns semantic roles (primary, secondary, accent, background, surface, on-surface, error, warning, success, info) to normalized colors by comparing against Apple's documented semantic color system using CIE 2000 delta-E distance with a threshold of 8.0 DeltaE units. Returns a `SemanticRole` for each input token.

---

## 2. apple6502x86/

**Languages:** 6502 Assembly, x86 Assembly (NASM/MASM style)
**Purpose:** Cross-architecture boot-loader and system firmware implementing an Apple II–style computer on top of an x86 host. The boot/ and rom/ directories implement authentic 6502 instruction semantics while memory/ and monitor/ bridge to the x86 host environment. Phase 1 diagnostic integration adds self-test harnesses across all modules.

### Directory Layout

```
apple6502x86/
├── MANIFEST.txt
├── PHASE1_DIAGNOSTICS_INTEGRATION.md
├── boot/
│   ├── boot.asm              6502 reset/boot sequence (1,500 LOC)
│   └── boot_diag.asm         Diagnostic variant with self-test assertions
├── memory/
│   ├── memory.asm            Memory map controller (64KB, bank-switch aware)
│   └── memory_diag.asm       Memory diagnostic: march tests, parity checks
├── monitor/
│   ├── monitor.asm           Apple II Woz Monitor reimplementation
│   └── monitor_diag.asm      Monitor diagnostic: input/output roundtrip tests
└── rom/
    ├── rom.asm               ROM image: Applesoft BASIC stubs + firmware
    └── rom_diag.asm          ROM diagnostic: checksum verification
```

### File Descriptions

#### `boot/boot.asm` — 6502 Boot Loader (1,500 LOC)

The primary reset handler. Entry at `$E000` (mapped to x86 address via segment override). Execution sequence:

```
RESET_VECTOR ($FFFC) → RESET_HANDLER ($E000)
    SEI                 ; disable interrupts
    LDX #$FF / TXS      ; initialize stack pointer
    JSR CPU_INIT        ; zero all registers
    JSR MEM_INIT        ; zero-fill $0000–$01FF, initialize zero-page
    JSR ROM_INIT        ; copy ROM image from host address space
    CLI                 ; enable interrupts
    JMP MONITOR_ENTRY   ; transfer to monitor
```

Vector table layout:
- `$FFFA` NMI_VECTOR → `NMI_HANDLER`
- `$FFFC` RESET_VECTOR → `RESET_HANDLER`
- `$FFFE` IRQ_VECTOR → `IRQ_HANDLER`

Interrupt handlers implement full register save/restore with the 6502 stack convention (RTI semantics). `CPU_INIT` zeroes A, X, Y, clears carry/overflow/decimal/break flags while preserving IRQ disable.

#### `boot/boot_diag.asm`
Diagnostic variant. After normal boot completes, injects synthetic fault conditions: stack overflow test (push 257 bytes), interrupt re-entrance test (fire IRQ inside ISR), decimal mode arithmetic test (BCD addition). Reports pass/fail codes to the `DIAG_STATUS_ADDR` ($02E0) memory-mapped diagnostic register readable by the x86 host.

#### `memory/memory.asm` — Memory Map Controller

Implements the Apple II 64KB address space with bank-switch support:

| Region | Address | Description |
|--------|---------|-------------|
| Zero Page | $0000–$00FF | Fast-access page; BASIC pointer storage |
| Stack Page | $0100–$01FF | 6502 hardware stack |
| Low RAM | $0200–$3FFF | Main BASIC program area |
| High RAM | $4000–$BFFF | Aux storage + HGR pages |
| I/O Soft Switches | $C000–$C0FF | Peripheral control soft switches |
| ROM Shadow | $D000–$DFFF | Language card / DOS 3.3 |
| ROM | $E000–$FFFF | Applesoft + monitor + vectors |

Bank-switch logic for the language card region ($D000–$DFFF) handles the $C080–$C08F soft-switch sequence (read-enable, write-enable, bank 1/2 select) as documented in the Apple II Reference Manual.

#### `memory/memory_diag.asm`
Executes a March-C memory test across all writable regions. March pattern: ↑(w0), ↑(r0,w1), ↑(r1,w0), ↓(r0,w1), ↓(r1,w0), ↓(r0). Detects: stuck-at faults, transition faults, address decoder faults. Reports first failing address to diagnostic register.

#### `monitor/monitor.asm` — Woz Monitor Reimplementation

Faithful reimplementation of Steve Wozniak's original Apple II monitor. Implements:

- `GETLN` — Read a line from keyboard with backspace support and 255-char limit
- `PRBYTE` — Print byte as two hex digits
- `PRNTAX` — Print A register as two hex, X register as two hex
- `SCAN` — Scan hex input, convert to binary address
- `XAM` — Examine memory: dump bytes with address prefixes
- `XAMINIT` — Initialize examination mode, set `XAML/XAMH` from input
- `SETMODE` — Toggle between examine, store, and run modes
- `NXTPRNT` — Print next word pair in current examination mode
- `RUN` — JMP to address in `PCL/PCH`

The monitor uses zero-page locations $24–$2B for internal state (XAML, XAMH, STL, STH, L, H, YSAV, MODE) matching the original Woz Monitor memory map exactly.

#### `monitor/monitor_diag.asm`
Tests each monitor command in isolation using the diagnostic framework. Injects known byte sequences and verifies output matches expected hex representation. Tests backspace handling, multi-address range dumps, and store-then-examine roundtrips.

#### `rom/rom.asm` — ROM Image

Assembles the 12KB ROM image ($D000–$FFFF). Includes:
- Applesoft BASIC cold-start and warm-start vectors ($E000, $E003)
- Integer BASIC compatibility stubs
- DOS 3.3 hook vectors (patched to no-ops in this implementation)
- Monitor entry point ($FF65, `MONIT`)
- Standard firmware routines: `COUT1`, `KEYIN`, `RDKEY`, `BELL`, `CLREOL`, `HOME`
- Character set ROM table (64 characters × 8 rows × 7 pixels)
- Keyboard decode table (40 key matrix entries)
- Checksum word at $FFFD (ROM integrity verification)

#### `rom/rom_diag.asm`
Verifies ROM integrity by recomputing the checksum at $FFFD using the same CRC-16 polynomial as the original ROM burning procedure. Also verifies that all vector table entries ($FFFA–$FFFF) point within the ROM address range, and that the monitor entry point responds to a synthetic call.

#### `PHASE1_DIAGNOSTICS_INTEGRATION.md`
Documents the diagnostic integration protocol: how `boot_diag.asm` harnesses chain together, the diagnostic register memory map, expected status codes, and the x86 host code path for reading results. Describes Phase 1 coverage (boot + memory + monitor + ROM) and lists Phase 2 targets (I/O soft switches, language card, video soft switches).

---

## 3. assembly-120-strict-model/

**Languages:** x86-64 Assembly (NASM), ARM64/Aarch64 Assembly
**Purpose:** A 120-module strict assembly model providing low-level implementations of every subsystem in the devflow-finance-twin architecture. "Strict" means each module maintains an exact LOC count and a defined interface contract. The model serves as the ground-truth binary reference that Lean 4 proofs and Rust/CBMC harnesses verify against.

### Files

```
assembly-120-strict-model/
├── .gitkeep
├── 08_neural_accelerator_engine.asm    Neural inference accelerator primitives
├── 09_graphics.asm                     Graphics rasterization + blit routines
├── 11_toolbox.asm                      Toolbox API: string ops, sort, hash
├── 15_scheduler.asm                    Cooperative task scheduler
├── 18_dylan_runtime.asm                Dylan language runtime support
├── 19_tests.asm                        Assembly-level test harness
├── 20_diagnostics.asm                  Diagnostic probes and reporting
├── PHASE_2_CPU_EXECUTION_ENGINE.asm    Phase 2: CPU execution engine
├── bit_pattern_kernel_avx2.asm         AVX2 NAND bit-pattern kernel
├── fibonacci_braid_x86.asm             Fibonacci braid ledger (x86-64)
└── firmware.asm                        Firmware initialization
```

### File Descriptions

#### `08_neural_accelerator_engine.asm`
Implements the neural accelerator interface for VSM-2500 binary semantic operations. Key routines:
- `NA_LOAD_PARAM` — Load a 128-bit Virtual Parameter object from memory into XMM register pair
- `NA_BINARY_OP` — Execute a binary semantic algebra operation (AND, OR, XOR, IMPL, NAND) on two VP objects
- `NA_COMMIT_RESULT` — Write result VP object back to memory with provenance tag
- `NA_FLUSH_PIPELINE` — Drain in-flight operations and emit a fence instruction

Uses SSE4.2 + POPCNT for VP population count metrics. No floating-point instructions appear in this module (enforced by the strict model constraint).

#### `09_graphics.asm`
2D graphics primitives for the retro-GPU visualization layer:
- `GFX_BLIT` — Fast memory-to-video-buffer copy using `REP MOVSD`
- `GFX_FILLRECT` — Rectangle fill with `REP STOSQ`
- `GFX_DRAWLINE` — Bresenham integer line algorithm
- `GFX_PUTCHAR` — Bitmap character blit (8×16 glyph from font table)
- `GFX_SCROLL_UP` — Scroll video buffer up by N pixel rows

Video buffer base address is passed in `RDI`; all operations are clipped to the buffer bounds (width/height in `RSI`). No malloc, no external calls.

#### `11_toolbox.asm`
General-purpose toolbox matching the Apple II Toolbox ROM interface semantics:
- String operations: `TB_STRLEN`, `TB_STRCPY`, `TB_STRCMP`, `TB_STRCAT` (null-terminated, max 255 bytes)
- Sort: `TB_QSORT` — in-place quicksort on array of 64-bit keys, recursive via call stack, pivot = median-of-three
- Hash: `TB_FNV1A` — FNV-1a 64-bit hash, single-pass, no alignment requirements
- Conversion: `TB_ITOA` — 64-bit integer to decimal ASCII, no leading zeros

All functions use the System V AMD64 ABI (RDI, RSI, RDX, RCX, R8, R9 for args; RAX for return; RBX, RBP, R12–R15 callee-saved).

#### `15_scheduler.asm`
Cooperative task scheduler supporting up to 32 concurrent tasks. Task Control Block (TCB) layout (64 bytes):
```
Offset  Size  Field
0       8     Stack pointer (RSP save)
8       8     Instruction pointer (RIP save)
16      8     Priority (lower = higher priority)
24      8     State (0=ready, 1=blocked, 2=sleeping, 3=dead)
32      8     Wake time (TSC ticks for sleep)
40      8     Wait resource pointer (for block)
48      8     Task ID
56      8     Flags
```
Routines: `SCHED_INIT`, `SCHED_SPAWN`, `SCHED_YIELD`, `SCHED_BLOCK`, `SCHED_UNBLOCK`, `SCHED_SLEEP`, `SCHED_EXIT`, `SCHED_TICK`. Uses `XCHG`+`LOCK` prefix for atomic TCB state transitions. Timer driven by `RDTSC`.

#### `18_dylan_runtime.asm`
Runtime support stubs for the Dylan-language modules (see `docs/DYLAN_EXECUTION_MODEL.md`). Implements: object header layout (8-byte tag word + 8-byte class pointer + payload), message dispatch (vtable lookup via class pointer offset), `Dylan_allocate` (bump-pointer allocator over a pre-allocated slab), `Dylan_GC_trace` (conservative stack scan for root collection). Tagged integers use 1-bit low tag.

#### `19_tests.asm`
Assembly-level test harness. Provides `TEST_ASSERT_EQ` (compare RAX vs expected immediate, log pass/fail), `TEST_RUN_SUITE` (iterate over test-descriptor table), `TEST_REPORT` (write summary counts to `DIAG_STATUS_ADDR`). Test descriptor: 16 bytes = function pointer (8) + expected-RAX (4) + test-id (4).

#### `20_diagnostics.asm`
Runtime diagnostic probes: CPUID feature detection (SSE4.2, AVX2, AVX512, POPCNT, RDRAND), memory bandwidth probe (streaming read/write loop timed by RDTSC), cache topology enumeration (L1/L2/L3 sizes via CPUID leaf 4), and a stack canary check routine. Results written to a 256-byte diagnostic report block at `DIAG_REPORT_BASE`.

#### `PHASE_2_CPU_EXECUTION_ENGINE.asm`
Phase 2 extension: full CPU execution engine for the NAND# ISA. Implements the fetch-decode-execute cycle:
1. `CPU_FETCH` — Load 16-bit instruction word from `PC`, increment `PC`
2. `CPU_DECODE` — Extract opcode[15:13], dest[12:9], srcA[8:5], srcB/imm[4:0]
3. `CPU_EXECUTE` — Dispatch on opcode via jump table (8 entries)
4. `CPU_WRITEBACK` — Write result to destination register

Register file: 16 × 64-bit virtual registers mapped to physical XMM lanes. Jump table entries: NAND, LOAD, STORE, BRANCH, CALL, RET, HALT, NOP.

#### `bit_pattern_kernel_avx2.asm`
AVX2-accelerated NAND bit-pattern kernel. Processes 256-bit NAND words at a time using `VPANDN` (bitwise NOT-AND). Inner loop:
```asm
.loop:
    VMOVDQU   YMM0, [RSI + RCX]    ; load 32-byte block from input A
    VMOVDQU   YMM1, [RDX + RCX]    ; load 32-byte block from input B
    VPANDN    YMM2, YMM0, YMM1     ; NAND = NOT(A) AND B  (AVX2)
    VMOVDQU   [RDI + RCX], YMM2    ; store result
    ADD       RCX, 32
    CMP       RCX, R8
    JL        .loop
    VZEROUPPER                      ; avoid AVX-SSE transition penalty
```
Achieves ~4 bytes/cycle sustained throughput on Zen 2 and later. Used by `vsm2500/` as the hardware-accelerated NAND evaluation path.

#### `fibonacci_braid_x86.asm`
x86-64 implementation of the Fibonacci Braid Ledger seal computation. Implements:
- `FBL_NEXT_STATE` — Apply braid word operator: `S_{n+1} = T(sigma_i, S_n)` where sigma_i is the i-th standard Artin braid generator
- `FBL_SEAL` — Compute `Seal_n = SHA256(Seal_{n-1} || C(S_n))` using SHA-NI instructions (`SHA256RNDS2`, `SHA256MSG1`, `SHA256MSG2`)
- `FBL_VERIFY` — Verify seal chain integrity by re-computing from genesis seal

SHA-NI path requires Intel Goldmont or later / AMD Zen or later. Fallback to software SHA-256 (4-round unrolled) for older CPUs detected via CPUID.

#### `firmware.asm`
Phase 2 firmware initialization (500 LOC, module 16 of the 120-module model):
- `FIRMWARE_INIT` — Disable interrupts, clear firmware state register, call four sub-routines in sequence
- `CPU_VECTOR_TABLE_SETUP` — Load IDT, install 32 exception handlers (divide-by-zero through machine check), install 16 IRQ handlers
- `ISA_INITIALIZATION` — Initialize NAND# register file, set PC to entry vector, configure privilege rings
- `X86_BRIDGE_CONFIG` — Set up NAND#↔x86 address translation table, configure segment descriptors
- `INTERRUPT_HANDLER_REGISTER` — Register all interrupt vectors with the x86 IDT, set APIC base, enable APIC

---

## 4. astre-vault/

**Languages:** Python 3.12, MATLAB (.m), Datalog (.unl)
**Purpose:** Constraint reasoning engine over RDF triples and OWL ontologies. "ASTRE" = Automated Spatial Temporal Reasoning Engine. Used by the constraint-harness to validate semantic consistency of MXML contracts against the OWL-encoded constraint constitution.

### Files

```
astre-vault/
├── astra-vault.unl              Datalog knowledge base (raw Souffle .unl format)
├── astra_math_vault.m           MATLAB symbolic math support routines
├── astra_owl_solver.py          RDF/OWL tableau-style consistency solver
└── rcc8_spatial.py              RCC-8 spatial relation constraint propagation
```

### File Descriptions

#### `astra-vault.unl`
Raw Souffle `.unl` format export of the ASTRE knowledge base. Contains EDB (Extensional Database) facts encoding:
- Ontology class hierarchy (rdfs:subClassOf chains up to 8 levels)
- Property domain/range declarations
- Individual assertions for the constraint constitution axioms
- Transitivity/symmetry/inverse property declarations

The `.unl` format is a line-per-tuple text export: `relation_name\targ1\targ2\t...`. Loaded by `datalog-engine/` for incremental IDB derivation.

#### `astra_math_vault.m`
MATLAB script providing symbolic math support. Functions:

| Function | Description |
|----------|-------------|
| `compute_wigner_distribution(psi)` | Wigner quasi-probability distribution for quantum state ψ |
| `solve_lindblad(H, L_ops, rho0, t)` | Lindblad master equation solver (Runge-Kutta 4th order) |
| `fibonacci_matrix(n)` | Compute F_n via matrix exponentiation `[[1,1],[1,0]]^n` |
| `braidword_action(sigma, state)` | Apply Artin braid generator sigma_i to state vector |
| `constraint_feasibility(A, b)` | Linear feasibility check: exists x≥0 s.t. Ax≤b (simplex phase I) |
| `owl_cardinality_check(card, actual)` | Check OWL cardinality restriction satisfaction |

Used offline to generate calibration profiles for the physics simulation layer and to validate MATLAB symbolic results against the Julia RWPT simulator.

#### `astra_owl_solver.py`
Pure-Python tableau-style OWL DL consistency solver. Core data structures:
- `Term(kind, value)` — RDF term: kind ∈ {iri, bnode, literal}
- `Triple(s, p, o)` — RDF triple
- `Graph` — In-memory triple store with `(s,p)`, `(p,o)`, `(s,o)` indices
- `Tableau` — Expansion state carrying completion graph nodes

Supported OWL constructors (OWL 2 EL profile):
- Class subsumption (`rdfs:subClassOf`)
- Property characteristics: transitive, symmetric, inverse, functional, irreflexive
- Existential restrictions (`owl:someValuesFrom`)
- Universal restrictions (`owl:allValuesFrom`)
- Cardinality restrictions (`owl:minCardinality`, `owl:maxCardinality`, `owl:exactCardinality`)
- Intersection and union (`owl:intersectionOf`, `owl:unionOf`)
- Negation via closed-world assumption

Tableau expansion rules applied in priority order: ⊓-rule, ⊔-rule, ∃-rule, ∀-rule, ≤-rule, ≥-rule. Clash detection: contradiction between C(x) and ¬C(x) for any concept C.

Entry point: `solve(graph: Graph, query: str) -> bool` — returns True iff the query is consistent with the ontology.

#### `rcc8_spatial.py`
RCC-8 (Region Connection Calculus 8) spatial relation constraint propagation. RCC-8 relations:
- DC (Disconnected), EC (Externally Connected), PO (Partially Overlapping)
- TPP (Tangential Proper Part), TPPi (inverse), NTPP (Non-Tangential Proper Part), NTPPi
- EQ (Equal)

Implements the 8×8 composition table as a Python dict of frozensets. Constraint network represented as adjacency dict `{(region_i, region_j): set_of_rcc8_relations}`. Path consistency algorithm (Mackworth 1977): iterates over all triples (i,j,k), intersects `R(i,j)` with `compose(R(i,k), R(k,j))` until fixpoint. Empty relation set signals inconsistency.

Used by the constraint-harness to validate spatial layout constraints in MXML documents describing multi-agent topologies.

---

## 5. benchmarks/

**Languages:** Python 3.12, Lua 5.4
**Purpose:** Reproducible local microbenchmarks measuring RSI orchestrator throughput and Lua metabinary serialization performance. No external services or native-backend calls. Results are deterministic: UUID generation is monkey-patched with a counter, wall-clock seconds are excluded from result hashes.

### Directory Layout

```
benchmarks/
└── rsi_lua/
    ├── README.md
    ├── lua_audit.lua           Lua correctness checks (23 tests)
    ├── run.py                  Benchmark harness (Python)
    ├── summarize.py            Result aggregator and Markdown reporter
    └── results/
        ├── PRE_REPAIR.md       Pre-repair baseline snapshot
        ├── SUMMARY.md          Latest benchmark summary (auto-generated)
        ├── latest.json         Full result JSON with source SHA-256 hashes
        ├── lua-examples.txt    Lua API usage examples
        ├── lua-test-results.jsonl  Per-test JSONL results
        ├── lua-test-stderr.txt     Lua interpreter stderr captures
        ├── pre-repair.json         Pre-repair JSON snapshot
        ├── rsi-pre-repair-tests.txt  Pre-repair test log
        └── rsi-test-results.txt    RSI test output
```

### File Descriptions

#### `run.py`
Primary benchmark harness. Key behaviors:

1. **Deterministic IDs**: patches `dream_rsi.tree.uuid.uuid4` with a counter-based UUID generator (UUID with `int=N << 80`) ensuring identical tree structures across runs.

2. **RSI workloads**: Runs `RSIOrchestrator` (layered API) and `DreamRSI` (legacy API) at 3 round counts × 3 revision counts = 9 layered workloads + 3 legacy workloads.

3. **Replay workloads**: Tests `HistoricalReplay` at world counts 1, 10, 100 over a fixed 63-node discovery tree (depth 5, binary branching).

4. **Serialization workloads**: Measures `DiscoveryTree` JSON and JSONL roundtrip for 63-node trees.

5. **Timing**: Uses `time.perf_counter_ns()`. Runs each workload 9× (warm), discards first 2, reports min/median/max of remaining 7.

6. **Output**: Writes `results/latest.json` with source SHA-256 hashes of all imported modules, Python version, platform info, and per-workload timing statistics.

#### `lua_audit.lua`
23 correctness checks for the metabinary Lua module. Test results as of the latest run (2026-09-19): 5 pass, 18 fail. Passing: `truncated_input` rejection, `nand_all_words_roundtrip` (both metabinary and metabinary_complete variants), `final_assembly_load`. Failing tests indicate that the wire format serializer (`metabinary.serialize`) does not produce a valid round-trippable binary; the deserializer rejects its own output. This is a known limitation documented in `PRE_REPAIR.md`.

#### `summarize.py`
Reads `results/latest.json`, aggregates per-workload statistics, and writes `results/SUMMARY.md` in Markdown table format. Reports RSI wall time (ms/op) and Lua CPU time (microseconds/op) in separate sections with min/median/max columns.

#### `results/SUMMARY.md`
Auto-generated summary. Key measurements from latest run:

**RSI Performance (layered API):**
- 1 round, 0 revisions: 0.308 ms/op median
- 10 rounds, 8 revisions: 19.057 ms/op median
- 50 rounds, 8 revisions: 371.867 ms/op median

**Lua Metabinary Performance:**
- Header pack only: 1.4 µs/op
- NAND decode 256 words: 64 µs/op
- Query leaf: 0.11 µs/op

#### `results/latest.json`
Complete benchmark result with source file SHA-256 hashes for reproducibility. Records UTC timestamp, Python/platform version, and 17 RSI workloads + 8 Lua workloads with 7-sample timing arrays.

---

## 6. classifier/

**Language:** Go 1.22
**Purpose:** Multi-head classification system providing routing decisions for the constraint-harness dispatch layer. A `Classifier` takes an input payload, routes it through a configurable set of `Head` (Noul) binary classifiers, and produces a `DecisionEnvelope` recording all route choices, model metadata, and input fingerprint.

### Directory Layout

```
classifier/
├── README.md
├── IMPLEMENTATION_SUMMARY.md
├── go.mod
├── classifier.go              Public facade; type aliases + constructor helpers
├── audit/
│   ├── audit.go              Audit trail recording for classification events
│   └── audit_test.go
├── backends/
│   └── backend.go            CPUBackend: vectorized parallel inference
├── batch/
│   ├── batch.go              Batch classification pipeline
│   └── batch_test.go
├── examples/
│   └── example.go            Usage example
├── model/
│   ├── classifier.go         DefaultClassifier implementation
│   ├── advanced.go           Advanced classifier variants
│   └── inference.go          Inference path: route → heads → aggregate
└── primitives/
    └── types.go              Core data types
```

### File Descriptions

#### `classifier.go` — Public Facade
Exports type aliases for all public types (no re-exported internals). Constructor helpers:
- `NewClassifier(metadata, heads, router) DefaultClassifier`
- `NewCPUBackend(maxConcurrency) CPUBackend`

Callers import only this package; sub-packages are internal.

#### `primitives/types.go` — Core Types

```go
type DecisionEnvelope struct {
    InputMetadata   InputMetadata
    ModelMetadata   ModelMetadata
    RouteChoices    []RouteChoice
    NoulChoices     []NoulChoice
    Confidence      float64
    FinalLabel      string
    ProcessedAt     time.Time
    LatencyNs       int64
}

type RouteChoice struct {
    JunctionID  string
    ChosenPath  string
    Score       float64
    Alternatives []string
}

type NoulChoice struct {
    HeadID      string
    InputHash   string
    Label       string
    Probability float64
    Threshold   float64
    Accepted    bool
}
```

`InputMetadata` carries: content hash (SHA-256 of canonical JSON), size bytes, content type, source tag. `ModelMetadata` carries: model ID, version, training date, head count, router type.

#### `model/classifier.go` — DefaultClassifier

Implements the `Classifier` interface:
```go
type Classifier interface {
    Classify(ctx context.Context, input []byte) (DecisionEnvelope, error)
    ClassifyBatch(ctx context.Context, inputs [][]byte) ([]DecisionEnvelope, error)
    Heads() []Head
    Router() Router
}
```

`DefaultClassifier.Classify` flow:
1. Compute input hash (SHA-256)
2. Route input through `Router.Route()` → ordered list of head IDs
3. For each head ID: call `Head.Infer(input)` → `NoulChoice`
4. Aggregate: majority vote on label, geometric mean on confidence
5. Wrap in `DecisionEnvelope` with timing

#### `model/inference.go`
Inference path optimizations: input pre-processing (normalize whitespace, truncate at 4096 bytes), head fan-out (parallel goroutine per head, results collected via channel), result aggregation strategies (majority, weighted-majority, confidence-threshold). Implements `InferenceOptions` struct for tuning.

#### `model/advanced.go`
Advanced classifier variants:
- `HierarchicalClassifier` — Two-stage: coarse label → fine label within coarse bucket
- `EnsembleClassifier` — N classifiers vote; tiebreak by confidence
- `CalibratedClassifier` — Platt scaling post-hoc probability calibration

#### `backends/backend.go` — CPUBackend
Vectorized CPU backend. `CPUBackend.BatchInfer(inputs [][]byte) []NoulChoice` launches up to `maxConcurrency` goroutines (semaphore via `chan struct{}`), each calling head inference. Goroutine results collected via `sync.WaitGroup` + mutex-protected slice. Suitable for throughput-oriented workloads where latency per item is less important than total batch throughput.

#### `audit/audit.go` — Audit Trail
Records every classification event to an append-only in-memory audit log. `AuditEntry` carries: event type (classify/error/batch), input hash, model metadata, decision envelope (minus raw input), wall-clock timestamp, goroutine ID. `AuditLog.Export()` serializes to JSON Lines. `AuditLog.Verify()` checks that entries are monotonically timestamped and no hash appears twice (duplicate-call detection).

#### `batch/batch.go` — Batch Pipeline
`BatchPipeline` chains multiple `Classifier` instances in sequence, with short-circuit on `FAILED_CLOSED` constitutional status. Supports retry with exponential backoff (configurable: base delay, multiplier, max retries). Emits per-batch metrics: total inputs, successful, failed, retry count, p50/p95/p99 latency.

---

## 7. datalog-engine/

**Languages:** Python 3.12, Datalog (Souffle dialect, `.dl` files)
**Purpose:** Pure-Python Datalog evaluator with a Souffle-compatible `.dl` file suite. Implements bottom-up semi-naive evaluation with incremental delta propagation. Used by the constraint-harness constitution evaluator to derive constraint violations from MXML contract facts.

### Directory Layout

```
datalog-engine/
└── datalog/
    ├── __init__.py
    ├── errors.py               Exception hierarchy
    ├── terms.py                Term model: Atom, Variable, Compound
    ├── unify.py                Robinson unification algorithm
    ├── meta_circular_evaluator.dl   Self-hosting: rules that evaluate rules
    ├── pure_ancestor_ar.dl     Pure ancestor example (active-record style)
    ├── pure_datalog_ar.dl      Pure Datalog with active records
    ├── souffle_ancestor.dl     Souffle ancestor: .decl + .input/.output
    ├── souffle_engine.dl       Souffle meta-engine (rules as data)
    ├── souffle_meta_eval.dl    Meta-circular Souffle evaluator
    ├── souffle_negation.dl     Stratified negation examples
    └── souffle_typed_ancestor.dl   Typed ancestor with record types
```

### File Descriptions

#### `datalog/__init__.py`
Package init. Exports: `Engine`, `Relation`, `Rule`, `Fact`, `evaluate`. `Engine` is the primary entry point: `engine = Engine(); engine.load_rules(rules); engine.load_facts(facts); result = engine.query("ancestor", ("alice", "?X"))`.

#### `datalog/errors.py`
Exception hierarchy:
- `DatalogError` — base
- `UnificationError(DatalogError)` — occurs-check failure or type mismatch
- `StratificationError(DatalogError)` — cyclic negation detected
- `ArityMismatchError(DatalogError)` — predicate called with wrong arity
- `DomainError(DatalogError)` — value outside declared domain

#### `datalog/terms.py`
Term representation:
- `Atom(value: str | int | float)` — ground term; `is_ground() = True`
- `Variable(name: str)` — logical variable; `is_ground() = False`
- `Compound(functor: str, args: tuple[Term, ...])` — structured term

Substitution: `dict[str, Term]`. `apply_subst(term, subst)` recursively substitutes variables. Terms are hashable (atoms hash by value, variables by name, compounds by functor+args hash).

#### `datalog/unify.py`
Robinson unification (1965 algorithm). `unify(t1: Term, t2: Term, subst: dict) -> dict | None`:
1. Apply current substitution to both terms
2. If both atoms: equal → return subst, else → fail
3. If t1 is variable: occurs-check then extend subst
4. If t2 is variable: symmetric
5. If both compounds: same functor/arity, unify arg-by-arg

Occurs-check: `occurs_in(var, term, subst)` prevents circular unification. Enabled by default (unlike Prolog which disables it).

#### `souffle_engine.dl` — Souffle Meta-Engine
Encodes the engine evaluation algorithm as Datalog facts and rules, enabling a Souffle-native self-hosting evaluation path:

```datalog
.decl fact(pred: symbol, arg1: symbol, arg2: symbol)
.decl rule_base(head_pred: symbol, body_pred: symbol)
.decl rule_transitive(head_pred: symbol, body_pred1: symbol, body_pred2: symbol)
.decl derive(pred: symbol, arg1: symbol, arg2: symbol)

derive(p, a, b) :- fact(p, a, b).
derive(head, a, b) :- rule_base(head, body), derive(body, a, b).
derive(head, a, b) :- rule_transitive(head, b1, b2), derive(b1, a, z), derive(b2, z, b).
```

This implements: base case (all EDB facts are derived), simple rule resolution, and transitive rule resolution with join. The engine can evaluate itself by loading its own rule-as-data encoding.

#### `souffle_negation.dl`
Demonstrates stratified negation in Souffle. Defines: `reachable/2`, `unreachable/2 :- node(?X), !reachable(?X, target)`. Stratification: negation-free stratum 1 computes `reachable`; stratum 2 computes `unreachable` over completed `reachable`. Souffle guarantees well-founded semantics under this stratification.

#### `souffle_typed_ancestor.dl`
Ancestor example with Souffle record types: `.type Person = [name: symbol, age: number]`. Demonstrates that typed variants produce stronger static safety guarantees than the untyped ancestor.

#### `souffle_meta_eval.dl`
Meta-circular evaluator: a Souffle program that can evaluate other Souffle programs by interpreting `.decl` and rule annotations as facts. Used in testing to verify that the engine's rule-application logic is consistent with its own output.

---

## 8. docs/

**Purpose:** Central documentation repository. Contains architecture references, phase completion reports, formal verification specifications, GPU architecture specs, audit protocols, ledger documentation, mathematical models, and legacy phase reports.

### Markdown Files (Selected)

| File | Description |
|------|-------------|
| `3D_ANATOMICAL_GRAPH_SPECIFICATION.md` | 3D graph layout spec for neuron topology visualization |
| `ABOUT.md` | Project mission statement and authorship |
| `ACHRTRN_OPERATOR_RUNBOOK.md` | Operations runbook for ACH return processing |
| `AGENT5_DELIVERY_SUMMARY.md` | Phase 5 agent delivery summary |
| `API.md` | Public API reference for sovereign ledger and constraint-harness |
| `ASP_ARCHITECTURE.md` | Answer Set Programming solver architecture |
| `AUDIT.md` | Audit framework overview and event taxonomy |
| `AUDIT_PROTOCOL.md` | Step-by-step audit execution protocol |
| `AUDIT_REPORT.md` | Consolidated audit report (auto-generated) |
| `AppleDesignParser_Guide.md` | User guide for apple-design-parser CLI |
| `BINARY_LAYER_SYNTHESIS.md` | HE-binary-functor synthesis protocol |
| `CONTRIBUTING.md` | Contribution guidelines and CLA |
| `DICTIONARY_OUTLINE.md` | Mathematical dictionary outline |
| `DREAM_RSI_RECONSTRUCTION.md` | dream_rsi design rationale and source-faithfulness notes |
| `DYLAN_EXECUTION_MODEL.md` | Dylan language execution model |
| `EMBEDDING_DEFENSE_PROTOCOL.md` | Defense protocol against embedding attacks |
| `EXAMPLES.md` | Worked examples for Funnel language |
| `FIBONACCI_BRAID_LEDGER.md` | Fibonacci Braid Ledger research paper (~8,500 words) |
| `FORMAL_ALGEBRA.md` | Formal algebra for NAND# semantics |
| `IDENTITY_PRESERVATION_AUDIT.md` | Identity preservation audit framework |
| `INSTITUTIONAL_README.md` | Institutional overview for the Bel Esprit Trust |
| `INVERTED_MONOREPO.md` | Inverted Monorepo design philosophy |
| `LEDGER.md` | Sovereign Ledger specification |
| `LIBRARY_INDEX.md` | Auto-generated library index (all modules) |
| `MATHEMATICAL_MODEL.md` | Mathematical model for NAND# semantics |
| `MATH_DICTIONARY.md` | Mathematical dictionary (terms used across the repo) |
| `NEURON_EXECUTION_TEMPLATE.md` | Template for neural execution contracts |
| `PHASE3_DYLAN_SUMMARY.md` | Phase 3 Dylan runtime summary |
| `PHASE_2_COMPLETION_REPORT.md` | Phase 2 completion certification |
| `PHASE_4_BIOLOGICAL_VALIDATION_FRAMEWORK.md` | Phase 4 biological validation |
| `PHASE_4_DESIGN_COMPLETE.md` | Phase 4 design sign-off |
| `PHASE_5_*` | Phase 5 documentation suite (13 files): audit protocols, behavioral validation, data structures, execution model, executive summary, formal verification, implementation guide, index, master index, scalable neuron model, summary, validation checklist |
| `PHASE_6_*` | Phase 6 documentation suite (10 files): artifact schemas, attack execution, bidirectional mapping, formal verification, GPU architecture, GPU graph transformation, GPU validation, GPU WORM specification, integration guide, proof of correctness |
| `PHASE_7_*` | Phase 7 documentation suite (8 files): executive summary, GPU compute kernels, index, interactive visualization, projection engine specification, technical summary, visualization formal verification, visualization WORM provenance, visual evidence validation |
| `PRIMITIVES.md` | Core primitive type reference |
| `PRODUCTION_HARDENING.md` | Production hardening checklist |
| `README.md` | Docs directory README |
| `README_API.md` | API-specific README |
| `REPOSITORY_FINANCIAL_COMPLIANCE_EXAMINATION.md` | Financial compliance examination |
| `REPOSITORY_ORGANIZATION_MANIFEST.md` | Repository organization manifest |
| `SOVEREIGN_AI_EVALUATION_ENGINE.md` | Sovereign AI evaluation engine spec |
| `SOVEREIGN_EVALUATION_ENGINE_SPEC.md` | Sovereign evaluation engine detailed spec |
| `SOVEREIGN_LEVIATHAN_COVENANT.md` | Covenant text for Sovereign Leviathan Node License |
| `STATE_MACHINE_IMPLEMENTATION.md` | State machine implementation reference |
| `STATE_MACHINE_README.md` | State machine user guide |
| `STRAY_FILE_AUDIT.md` | Audit of stray/misplaced files |
| `STRICT_ISOLATION_TRANSFORMER_BUILD_PROTOCOL.md` | Build protocol for strict isolation transformers |
| `TECHNICAL_OVERVIEW.md` | Master technical overview (see also ARCHITECTURE_DEEP.md) |
| `USER.md` | End-user guide |
| `VALIDATION_FRAMEWORK_SUMMARY.md` | Validation framework summary |
| `VERIFICATION.md` | Formal verification overview |
| `architecture.md` | Architecture summary (brief) |

### Dot/Graphviz Files

| File | Description |
|------|-------------|
| `architecture.dot` | Top-level architecture graph (Graphviz) |
| `institutional_architecture.dot` | Institutional architecture graph |
| `pipeline_flowchart.dot` | Pipeline flowchart |
| `sas_dataflow.dot` | SAS dataflow diagram |
| `sql_schema.dot` | SQL schema entity-relationship diagram |

### Subdirectories

#### `docs/audits/`
- `RSI_LUA_AUDIT.md` — RSI Lua module audit findings
- `RSI_LUA_REPAIRS.md` — Repair log for Lua module issues
- `assembly_correspondence.txt` — Assembly module correspondence table
- `organization-verification.json` — Organization verification snapshot
- `rsi-relocations.json` — RSI module relocation log
- `verification_report.txt` — Formal verification report

#### `docs/reports/`
Text-format completion reports:
- `CONTROL_IMPLEMENTATION_SUMMARY.txt`
- `CONTROL_PACKAGE_READY.txt`
- `IMPLEMENTATION_CHECKLIST.txt`
- `INTEGRATION_ACCEPTANCE_DELIVERY.txt`
- `PARSER_MODULE_SUMMARY.txt`
- `PHASE1_COMPLETION_REPORT.txt`
- `PHASE_2_MANIFEST.txt`

#### `docs/assets/`
Video demos (`.mp4`), hero images (`.jpg`, `.png`, `.gif`).

---

## 9. examples/

**Languages:** Funnel (.fnl), MATLAB/Mercury (.m), Mercury/Prolog (.pl)
**Purpose:** Worked examples demonstrating the Funnel language (devflow's custom financial DSL), Mercury backend predicates, and MATLAB transducer demonstrations.

### Files

#### `ach_return.fnl` — ACH Return in Funnel Language
Demonstrates ACH return item processing in the Funnel DSL:
```funnel
PROGRAM ach_return.
FILE achitem USING ACHITEM KEY company(3), batch(10), entry(15).
RECORD item IN achitem (company CHAR(3), batch CHAR(10), entry CHAR(15),
    state ENUM(NEW, POSTED, SETTLED, RETURNED), amount NUM(13,2), reason CHAR(3)).
PROC return_item(company, batch, entry, reason) IS
    LOAD item(company, batch, entry) AS it IF NOTFOUND THEN FAIL "NOTFOUND";
    IF it.state NOT IN (POSTED, SETTLED) THEN FAIL "BADSTATE";
    IF it.state = RETURNED THEN FAIL "ALREADYRT";
    it.state := RETURNED; it.reason := reason;
    SAVE it;
ENDPROC.
```
Guards: item must exist, state must be POSTED or SETTLED, idempotency check (already returned → ALREADYRT).

#### `ledger_post.fnl` — Ledger Post in Funnel Language
Demonstrates ledger entry creation/update:
```funnel
PROC post_entry(company, date, seq, amount, drcr) IS
    READ entry(company, date, seq) IF NOTFOUND THEN
        NEW entry(company, date, seq, amount, drcr).
        WRITE entry.
    ELSE
        entry.amount := entry.amount + amount.
        WRITE entry.
    ENDIF.
ENDPROC.
```
Upsert semantics: creates new entry if not found, accumulates amount if found.

#### `post_entry.m` — MATLAB/Mercury Ledger Post
Mercury-syntax (`:-` declarations) implementation of `post_entry/6`. Uses `semidet` mode predicate `ledger_entry/5` for lookup. Mercury type system enforces `drcr ---> d ; c` algebraic data type.

#### `post_entry.pl` — Prolog Ledger Post
Prolog predicate implementations demonstrating the same logic in ISO Prolog syntax, using assert/retract for in-memory ledger state.

#### `return_item.m` — MATLAB/Mercury Return Item
Mercury implementation of `return_item/4`. Demonstrates Mercury's mode system: `in/in/in/in` modes for all arguments, determinism `det`.

#### `return_item.pl` — Prolog Return Item
Prolog version of the return item procedure.

#### `snapkitty.transducerDemo.m` — MATLAB Transducer Demo
Demonstrates the composable transducer pattern in MATLAB. Shows how `map`, `filter`, and `fold` transducers compose without intermediate collections. The demo computes ACH transaction processing pipeline metrics using transducer composition.

---

## 10. gpu/

**Languages:** CUDA C++ (.cu), C++ (.cpp)
**Purpose:** GPU compute kernels and projection engine for the 3D anatomical graph visualization (Phase 7). Implements the GPU-accelerated graph transformation and projection pipeline documented in `docs/PHASE_7_GPU_COMPUTE_KERNELS.md`.

### Files

```
gpu/
├── kernels/
│   ├── gpu_architecture_kernels.cu    Architectural compute kernels
│   └── gpu_projection_kernels.cu      3D→2D projection kernels
└── projection_engine.cpp              Host-side projection engine driver
```

### File Descriptions

#### `kernels/gpu_architecture_kernels.cu`
CUDA kernels implementing the architectural transformation pipeline:
- `kernel_nand_batch` — Batch NAND evaluation on GPU: 1024 threads/block, each thread processes 4 NAND words using 128-bit LDG.128 loads
- `kernel_fibonacci_hash` — GPU Fibonacci braid seal computation using PTX SHA instructions in cooperative groups
- `kernel_graph_adjacency` — Sparse adjacency matrix construction from edge list using atomic scatter operations
- `kernel_bfs_frontier` — BFS frontier expansion for discovery tree traversal: bottom-up BFS variant (Beamer 2012) switching to top-down when frontier exceeds |V|/4

#### `kernels/gpu_projection_kernels.cu`
3D→2D projection kernels for the visualization layer:
- `kernel_perspective_project` — Projects 3D node positions to 2D viewport using perspective transform matrix (passed as constant memory)
- `kernel_depth_sort` — Depth sorting for correct transparency rendering using bitonic sort (power-of-2 padded, shared memory)
- `kernel_edge_tessellate` — Tessellates curved graph edges into polyline segments (Bézier cubic approximation, 16 segments/edge)
- `kernel_occlusion_cull` — GPU occlusion culling: tests node bounding spheres against frustum planes using half-space tests

#### `projection_engine.cpp`
Host-side driver for the GPU projection pipeline. Manages:
- CUDA device selection and context initialization
- Host→device memory transfer for graph topology (adjacency list) and node attribute buffers
- Kernel launch parameter calculation (grid/block dimensions based on node count)
- Device→host transfer of projected 2D coordinates and depth values
- Integration with the Phase 7 interactive visualization WebSocket server

---

## 11. isa-jvm/

**Language:** Python 3.12
**Purpose:** JVM-inspired ISA implementation in Python. Defines a typed instruction set with JVM-style opcodes, a stack-based virtual machine runtime, an agent framework for concurrent execution, and a compiler pipeline from `.isa` source files to bytecode.

### Directory Layout

```
isa-jvm/
├── README.md
├── compiler/
│   ├── __init__.py
│   ├── bytecode.py          Bytecode emitter
│   ├── ir.py                Intermediate representation
│   ├── parser.py            .isa source parser
│   ├── regmap.py            Register allocation (linear scan)
│   └── verifier.py          Bytecode verifier (type safety)
├── examples/
│   ├── arith.isa            Arithmetic operations example
│   ├── channel.isa          Channel communication example
│   └── memory.isa           Memory operations example
├── isa/
│   ├── __init__.py
│   ├── opcodes.py           Opcode definitions and encoding
│   └── types.py             Type system (INT, LONG, FLOAT, DOUBLE, REF, VOID)
├── runtime/
│   ├── __init__.py
│   ├── agents.py            Agent execution framework
│   ├── interpreter.py       Stack-based bytecode interpreter
│   ├── invokedynamic_stub.py  invokedynamic call-site stub
│   └── loader.py            Class/module loader
├── tests/
│   ├── test_differential.py  Differential tests against reference implementations
│   └── test_isa.py           Unit tests for opcode correctness
└── tools/
    └── trace_viewer.py       Execution trace viewer
```

### File Descriptions

#### `isa/opcodes.py`
Defines the complete opcode table. Categories:

| Category | Opcodes | Count |
|----------|---------|-------|
| Load/Store | ILOAD, LLOAD, FLOAD, DLOAD, ALOAD, ISTORE, LSTORE, FSTORE, DSTORE, ASTORE | 10 |
| Arithmetic | IADD, ISUB, IMUL, IDIV, IREM, INEG, LADD, LSUB, LMUL, LDIV, FADD, FSUB, FMUL, FDIV, DADD, DSUB, DMUL, DDIV | 18 |
| Bitwise | IAND, IOR, IXOR, ISHL, ISHR, IUSHR, LAND, LOR, LXOR, LSHL, LSHR, LUSHR | 12 |
| Comparison | LCMP, FCMPL, FCMPG, DCMPL, DCMPG, IFEQ, IFNE, IFLT, IFGE, IFGT, IFLE | 11 |
| Control | GOTO, JSR, RET, TABLESWITCH, LOOKUPSWITCH, IRETURN, LRETURN, FRETURN, DRETURN, ARETURN, RETURN | 11 |
| Object | NEW, NEWARRAY, ANEWARRAY, ARRAYLENGTH, INSTANCEOF, CHECKCAST, GETFIELD, PUTFIELD, GETSTATIC, PUTSTATIC | 10 |
| Invoke | INVOKEVIRTUAL, INVOKESPECIAL, INVOKESTATIC, INVOKEINTERFACE, INVOKEDYNAMIC | 5 |
| Exception | ATHROW, MONITORENTER, MONITOREXIT | 3 |

Total: 80 opcodes. Each opcode entry: `(name, opcode_byte, stack_effect: int, operand_bytes: int)`.

#### `isa/types.py`
Type system:
```python
class JVMType(Enum):
    INT = 'I'; LONG = 'J'; FLOAT = 'F'; DOUBLE = 'D'
    REF = 'L'; ARRAY = '['; VOID = 'V'; BOOL = 'Z'
    BYTE = 'B'; CHAR = 'C'; SHORT = 'S'

class VerificationType:  # bytecode verifier types
    TOP; ONE_WORD; TWO_WORD; INT; FLOAT; LONG; DOUBLE; REFERENCE; UNINITIALIZED
```

Type descriptor parsing: `parse_descriptor("(ILjava/lang/String;)[I")` → `([INT, REF_String], ARRAY_INT)`.

#### `compiler/parser.py`
Parses `.isa` source files (custom assembly syntax) into an AST. `.isa` format:
```
.class MyClass
.method compute (I)I
  .limit stack 4
  .limit locals 2
  iload_0
  bipush 10
  imul
  ireturn
.end method
```

Parser: recursive descent. Returns `ClassNode` containing `MethodNode` list, each with `InstructionNode` list.

#### `compiler/verifier.py`
Bytecode verifier implementing JVM specification Chapter 4.10 (data-flow analysis). Tracks stack type state at each instruction. Verifies: stack underflow/overflow against `.limit stack`, local variable type consistency, branch target type compatibility (stack maps at merge points), exception handler type requirements. Raises `VerificationError` on violation.

#### `runtime/interpreter.py`
Stack-based bytecode interpreter. Execution state: operand stack (Python list), local variable array (fixed-size Python list), method call stack (Python list of frames). `Frame`: `{method, pc, locals, stack}`. Dispatch: Python dict `{opcode: handler_function}` for O(1) dispatch. Handles exception propagation: searches exception table entries from current PC outward, unwinds stack to handler.

#### `runtime/agents.py`
Agent execution framework. `Agent` wraps a bytecode method with an execution context and runs in a `threading.Thread`. Agents communicate via `Channel` objects (thread-safe queue). `AgentSupervisor` manages agent lifecycle: start, join with timeout, restart on exception (exponential backoff), monitor health via heartbeat.

#### `runtime/invokedynamic_stub.py`
Stub implementation of `invokedynamic` call-site linkage. Maintains a `CallSite` object per `invokedynamic` instruction that stores the linked target method after first resolution. Resolution: calls a `BootstrapMethod` function that returns the target. Subsequent calls go directly to the linked target (inlining stub). Supports: `StringConcatFactory`, `LambdaMetafactory` (simplified).

#### `tools/trace_viewer.py`
Execution trace viewer. Reads `.isa-trace` files (JSONL, one record per instruction executed: `{pc, opcode, stack_before, stack_after, locals}`). Renders: instruction timeline, stack depth chart, hotspot analysis (most-executed PCs), type profile (what types appeared on stack at each PC). Output: terminal ANSI-colored display or HTML report.

---

## 12. kernel-language/

**Languages:** C (host compiler), C headers, Oberon (`.Mod`), Assembly (`.kl` examples)
**Purpose:** A self-hosting compiler for a kernel programming language inspired by BLISS, PL/M, and CORAL 66. Targets NVIDIA Ampere (SM80) via CUDA/PTX emission. The compiler is C-hosted (bootstraps from a C toolchain) but aims to self-host via the `.kl` examples. Oberon modules provide the language-card runtime integration.

### Directory Layout

```
kernel-language/
├── README.md
├── Makefile
├── ADVERSARIAL_ATTACK_TEST_PLAN.md
├── EXECUTION_ENGINE_PSEUDOCODE.md
├── FORMAL_VERIFICATION_FRAMEWORK_PHASE4.md
├── NEURAL_DYNAMICS_EXECUTION.md
├── PHASE4_AUDIT_SUMMARY.md
├── STATE_DYNAMICS_FORMALISM.md
├── VERIFICATION_FRAMEWORK_INDEX.md
├── examples/
│   ├── bit_ops.kl              Bit manipulation examples
│   ├── parallel_add.kl         Parallel vector addition
│   ├── self_hosted_compiler.kl Self-hosting compiler sketch
│   └── word_arith.kl           Word arithmetic
├── include/
│   ├── ast.h       AST node types
│   ├── codegen.h   Code generation interface
│   ├── ir.h        IR representation
│   ├── lexer.h     Lexer tokens
│   ├── parser.h    Parser interface
│   ├── regalloc.h  Register allocator interface
│   ├── symtab.h    Symbol table
│   └── token.h     Token types
├── oberon/
│   ├── Kernel.Mod  Oberon kernel module
│   └── ML.Mod      Oberon machine-language module
├── runtime/
│   ├── cpl_bridge.c   CPL (Combined Programming Language) bridge
│   ├── cpl_bridge.h
│   └── st80_runtime.c Smalltalk-80 runtime primitives
└── src/
    ├── codegen.c   PTX/CUDA code generator
    ├── ir.c        IR construction and passes
    ├── lexer.c     Lexer (hand-written)
    ├── main.c      Compiler driver
    ├── parser.c    Recursive-descent parser
    ├── regalloc.c  Linear scan register allocator
    └── symtab.c    Hash-chained symbol table
```

### File Descriptions

#### `src/lexer.c`
Hand-written lexer. Tokens: identifiers, integer literals (decimal, hex `0x`), float literals, string literals (C-style escapes), operators (`:=`, `+`, `-`, `*`, `/`, `MOD`, `AND`, `OR`, `NOT`, `=`, `#`, `<`, `<=`, `>`, `>=`), keywords (BEGIN, END, IF, THEN, ELSE, ELSIF, WHILE, DO, FOR, TO, BY, RETURN, PROC, MODULE, IMPORT, EXPORT, CONST, TYPE, VAR). Token struct: `{kind, text, line, col}`.

#### `src/parser.c`
Recursive-descent parser generating AST nodes (defined in `include/ast.h`). Grammar excerpt:
```
module   → MODULE ident ";" imports decls "." END ident "."
decls    → (const_decl | type_decl | var_decl | proc_decl)*
proc_decl → PROC ident formal_params ";" decls statement_seq "END" ident ";"
statement_seq → statement (";" statement)*
statement → assign | if_stmt | while_stmt | for_stmt | proc_call | return_stmt
```

Operator precedence: 1=OR, 2=AND, 3=NOT, 4=relational, 5=additive, 6=multiplicative, 7=unary.

#### `src/ir.c`
Three-address IR. IR instructions: `(op, dest, src1, src2)` where op ∈ {ADD, SUB, MUL, DIV, MOD, AND, OR, NOT, NEG, LOAD, STORE, COPY, BR, CBR, CALL, RET, PHI}. `phi` nodes for SSA form. IR passes: constant folding, dead code elimination, copy propagation, loop-invariant code motion (basic).

#### `src/codegen.c`
Emits PTX assembly for NVIDIA Ampere (SM80). Register mapping: virtual registers → `.reg .u64 %rd<N>` (64-bit) or `.reg .f32 %f<N>` (float). Memory: `.global .align 8 .u64 symbol[N]`. Function emission: `.visible .entry kernel_name(.param .u64 param0, ...)` with `.maxntid x, 1, 1`. Supports: arithmetic, load/store, branch, cooperative groups barrier.

#### `src/regalloc.c`
Linear scan register allocator (Poletto & Sarkar 1999). Computes live intervals from SSA form, sorts by start point, allocates physical registers greedily, spills to local `.local` memory on register pressure. Available registers: 128 `.reg .u64` registers per kernel on SM80.

#### `oberon/Kernel.Mod`
Oberon-07 kernel module. Provides: `Kernel.New(size)` (bump-pointer allocator from a static `.local` buffer), `Kernel.Mark(ptr)` and `Kernel.Scan()` (mark-sweep GC stubs), `Kernel.GetTimer()` (CUDA clock64()), `Kernel.Trap(code)` (trap to host via device-side assert).

#### `runtime/cpl_bridge.c`
Bridge layer between the kernel-language runtime and CPL (Christopher Strachey's Combined Programming Language) semantics. Implements: `cpl_bind(name, value)` (dynamic binding), `cpl_apply(fn, args)` (dynamic dispatch), `cpl_compose(f, g)` (function composition as first-class value). Used to support higher-order procedures in the kernel language.

#### `runtime/st80_runtime.c`
Smalltalk-80 runtime primitives for the kernel language's object system. Implements primitive numbers 1–68 as C functions: primitive 1 (`+`), 2 (`-`), ..., 10 (`=`), 60–68 (I/O and system). Object format: 2-word header (class pointer, size/tag) + payload.

---

## 13. languages/

**Purpose:** Polyglot implementations of devflow-finance-twin subsystem primitives in 14 languages. Each subdirectory demonstrates the NAND# refinement preservation predicate `EXECUTE(LOWER(e)) == EVAL(e)` in a different host language.

### Subdirectories

#### `languages/ada/` — Ada 2012
Six files implementing NAND# bootstrap firmware in Ada with SPARK-style contracts:

| File | Description |
|------|-------------|
| `cli_isa.ads` / `.adb` | CLI ISA module specification and body |
| `enochian_boot.ads` / `.adb` | Enochian boot sequence specification and body |
| `loader.ads` / `.adb` | Module loader |
| `malbolge_firmware.ads` / `.adb` | Malbolge-inspired firmware (self-modifying semantics) |
| `memory_manager.ads` / `.adb` | Memory manager with SPARK contracts for bounds safety |
| `unsigned_types.ads` | Unsigned integer type definitions (Unsigned_8 through Unsigned_64) |

`memory_manager.adb` carries SPARK 2014 contracts: `Pre => Address < 16#1000#, Post => Contents'Old(Address) = Contents(Address)` ensuring no-aliasing during allocation. The memory manager is mechanically verified by GNAT-SPARK at SPARK_Mode => On.

#### `languages/apl/` — APL (Dyalog APL)
Three files demonstrating array-oriented NAND semantics:

- `06a76100741e52c56f5e9c588bd0f572.apl` — Hash-named file; APL proof term for NAND truth-table completeness using `¬∧` (NOT-AND combinator)
- `LiquidAssert.apl` — APL implementation of liquid type assertions using APL's rank polymorphism. Assertion: `{⍵ ←→ ¬∧/⍨ ⍵}` checks NAND idempotence
- `transformer.apl` — APL transformer implementation: attention mechanism using matrix outer products `⍺∘.×⍵`, softmax via `(⍵-⌈/⍵)` for numerical stability, layer normalization via `(⍵-+/⍵÷⍴⍵)÷(+/(⍵-+/⍵÷⍴⍵)*2÷⍴⍵)*0.5`

#### `languages/braid/` — Rust (braid algebra)
- `algebra/generator.rs` — Generates Artin braid group elements. `BraidWord` type: sequence of signed generator indices `σ_i` (positive) and `σ_i⁻¹` (negative). Operations: `compose`, `inverse`, `reduce` (applying free group reduction rules). Used to generate test vectors for the Fibonacci Braid Ledger.

#### `languages/chisel/` — Chisel (Scala DSL for hardware)
- `WormHardwareAccelerator.scala` — Chisel RTL module implementing the WORM (Write-Once Read-Many) hardware accelerator. Ports: `io.write` (valid/ready + data), `io.read` (address + data out), `io.sealed` (output: true after seal). Internal: `RegInit` register array, FSM with states `OPEN`, `WRITING`, `SEALED`. Once `SEALED`, all write ports return error; read ports remain active indefinitely.

#### `languages/eclipse/` — ECLiPSe Prolog
- `eclipse_parlog_fused_kernel.ecl` — ECLiPSe constraint logic program fusing CLP(FD) constraints with Parlog-style parallel logic programming. Implements the RSI constraint evaluation kernel: given a set of candidate policies, derives the feasible set satisfying all constitutional constraints using `ic:` interval constraint domain.

#### `languages/futhark/` — Futhark
- `wigner_futhark.fut` — Futhark (data-parallel functional) implementation of Wigner quasi-probability distribution computation. `entry wigner(psi: []f64) : [][]f64` computes the W(x,p) distribution over an N×N phase-space grid using parallel map/reduce. Compiles to CUDA/OpenCL backends via `futhark cuda`.

#### `languages/lisp/` — Common Lisp
- `QA5-REACTIVE-THEOREM-PROVER.l` / `qa5-reactive-prover.lisp` — QA5 reactive theorem prover in Common Lisp. Implements a reactive logic programming kernel: assertions, rules, and queries with incremental truth maintenance. `(prove-goal goal kb)` performs backward-chaining with tabling (memoization of proven goals). Used as the Lisp backend for the Rust `qa5/` module.

#### `languages/logtalk/` — Logtalk
- `godel_symbolic_kernel.lgt` — Logtalk object implementing a Gödel numbering kernel. `godel_number(term, number)` encodes/decodes Prolog terms as Gödel numbers using a deterministic prime-product encoding. Demonstrates that the NAND# ISA can encode any computable function via Gödel numbering.

#### `languages/mathematics/topology/` — Python
- `manifold.py` — Differential geometry manifold computations. Implements: `Manifold` (chart atlas, transition maps), `TangentVector`, `Metric` (Riemannian metric tensor), `Connection` (Levi-Civita connection), `GeodesicSolver` (Runge-Kutta on geodesic equation). Used for the formal topology layer in the Cobalt compiler's type theory.

#### `languages/prolog/` — Prolog
- `funnel_backend.pl` — Prolog backend for the Funnel DSL compiler. Implements: `funnel_to_prolog(FunnelAST, PrologClauses)` — translates Funnel programs to Prolog, `execute_funnel(Program, Env, Result)` — interprets Funnel programs using Prolog's unification engine, `verify_funnel(Program, Spec)` — verifies Funnel program against a formal specification using model checking.

#### `languages/ptx/` — PTX (NVIDIA parallel thread execution)
Three files implementing GPU kernels in PTX assembly:

- `micro_kernel.ptx` — Minimal PTX kernel demonstrating NAND evaluation in PTX: uses `not.b64` and `and.b64` instructions
- `ptx_inverted_softmax.ptx` — PTX implementation of the VSM-2500 inverted softmax (binary semantic selection without floating-point): uses `setp`, `selp`, and integer comparison instructions only
- `malbolge_step_kernel.cu` / `host_launcher.cu` — CUDA C++ host code launching the Malbolge self-modifying firmware step kernel on GPU

#### `languages/topos/` — Prolog (topos-theoretic)
- `pipeline.pl` — Topos-theoretic pipeline specification in Prolog. Represents computation as morphisms in a category: objects are data types (represented as sets of values), morphisms are computable functions. `compose_morphisms(F, G, H)` verifies that `H = G ∘ F` via equational reasoning.

#### `languages/x86_64/` — x86-64 Assembly (AT&T/NASM/Intel)
Three x86-64 implementations:

- `quantum_validation.s` — AT&T syntax x86-64 assembly implementing quantum state validation. Verifies that a quantum state vector (passed as pointer + length) has unit norm using SSE4.1 dot product (`dpps` instruction).
- `treasury_serialization.nasm` — NASM syntax: serializes treasury WORM blocks to the binary wire format. Implements the 64-byte WORM block header layout: magic (4), version (2), flags (2), block_id (8), prev_hash (32), payload_len (8), seal (8).
- `treasury_worm_ipl.asm` — Intel syntax IPL (Initial Program Load) for the treasury WORM store: bootstraps the append-only block chain from ROM, verifies genesis block hash, and hands off to the main treasury firmware.

---

## 14. lua/

**Language:** Lua 5.4
**Purpose:** Lua implementation of the metabinary serialization format for HE-binary-functor (homomorphic encryption binary) and NAND# instruction encoding. Provides a pure-Lua codec for binary AST serialization, constraint validation, and NAND word decoding.

### Files

```
lua/
├── README.md
├── init.lua                        Package entry point
├── metabinary.lua                  Core metabinary module
├── metabinary_builder_facade.lua   Builder pattern facade
├── metabinary_codec.lua            Codec (encode/decode)
├── metabinary_complete.lua         Complete/final implementation
├── metabinary_ffi_bindings.lua     LuaJIT FFI bindings (optional)
├── metabinary_final_assembly.lua   Final assembly module
└── example_usage_all_backends.lua  Usage examples
```

### File Descriptions

#### `init.lua`
Package entry point. `require("lua")` returns `metabinary_complete` — the canonical implementation. Other modules (metabinary, metabinary_builder_facade, etc.) are exposed for testing/comparison.

#### `metabinary.lua` — Core Metabinary Module

Defines the opcode table (55 opcodes in 8 categories):

| Category | Opcodes (examples) |
|----------|--------------------|
| Arithmetic | IDENTITY(0x0001), ADD(0x0010), SUB(0x0012), MUL(0x0020), NEG(0x0030) |
| Relinearization | RELINEARIZE(0x0100), KEY_SWITCH(0x0101), ROTATE(0x0102) |
| Modulus Mgmt | MOD_SWITCH(0x0200), RESCALE(0x0201), MOD_UP(0x0202) |
| Encoding | ENCODE(0x0300), DECODE(0x0301), ENCRYPT(0x0302), DECRYPT(0x0303) |
| Noise | NOISE_ESTIMATE(0x0400), NOISE_ASSERT(0x0401), BOOTSTRAP(0x0402) |
| Composition | COMPOSE(0xF000), PARALLEL(0xF001), CONDITIONAL(0xF002), ITERATE(0xF003) |

Each opcode has: `arity` (input count), `output_count`, `pure` flag (false for NOISE_ESTIMATE, BOOTSTRAP), `commutative` flag.

#### `metabinary_codec.lua`
Binary encoding/decoding. Wire format:
```
Header (16 bytes):
  [0:4]   magic = 0x4D4554 41 ("META")
  [4:6]   version (uint16 LE)
  [6:8]   flags (uint16 LE)
  [8:12]  node_count (uint32 LE)
  [12:16] payload_length (uint32 LE)

Node record (variable):
  [0:2]   opcode (uint16 LE)
  [2:4]   child_count (uint16 LE)
  [4:4+child_count*4]  child offsets (uint32 LE each)
  [4+child_count*4 ...]  payload bytes
```

`encode(ast_node) -> bytes_string`; `decode(bytes_string, offset) -> (ast_node, new_offset)`. Current status: decoder rejects its own encoder output (known bug; `truncated_input` detection works correctly, `nand_all_words_roundtrip` passes for the decode-only path).

#### `metabinary_builder_facade.lua`
Builder pattern facade for constructing metabinary ASTs:
```lua
local node = Builder.new()
    :opcode("ADD")
    :child(Builder.literal(42))
    :child(Builder.variable("x"))
    :build()
```

#### `metabinary_ffi_bindings.lua`
Optional LuaJIT FFI bindings for accelerated encode/decode. Falls back to pure-Lua implementation if `ffi` module is not available. Declares C structs matching the wire format layout for zero-copy parsing.

---

## 15. occam-b-bscl/

**Languages:** B (occam-B dialect), C (runtime)
**Purpose:** Implementation of B language (Ken Thompson 1969) with occam-style channel communication (CSP semantics). BSCL = B-language System Communications Layer. Implements a process model where B programs communicate via typed channels with alternation (select).

### Directory Layout

```
occam-b-bscl/
├── README.md
├── include/
│   └── types.h           B language type definitions
├── src/
│   ├── bscl.c            BSCL runtime: channel create/send/recv/close
│   ├── cli.c             Command-line driver
│   ├── compiler.c        B-to-wordcode compiler
│   ├── emit.c            Wordcode emitter
│   └── ir.c              Intermediate representation
├── examples/
│   ├── arithmetic.b      Arithmetic operations
│   ├── channel.b         Basic channel send/receive
│   ├── factorial.b       Recursive factorial
│   ├── fibonacci.b       Fibonacci sequence
│   ├── hello.b           Hello world
│   ├── parallel.b        Parallel process launch
│   ├── producer_consumer.b  Producer-consumer pattern
│   └── select.b          Select (alternation) over channels
├── tests/
│   ├── test_channels.c   Channel correctness tests
│   ├── test_compiler.c   Compiler unit tests
│   ├── test_ir.c         IR tests
│   ├── test_lexer.c      Lexer tests
│   ├── test_parser.c     Parser tests
│   ├── test_scheduler.c  Scheduler tests
│   ├── test_vm.c         VM tests
│   └── test_wordcode.c   Wordcode encoder/decoder tests
└── docs/
    ├── CONCURRENCY.md    Concurrency model documentation
    ├── MEMORY.md         Memory model documentation
    └── WORDCODE.md       Wordcode instruction set reference
```

### File Descriptions

#### `src/bscl.c` — BSCL Runtime
Channel implementation (CSP semantics):
- `bscl_chan_create(capacity) -> chan*` — Create buffered channel (capacity 0 = synchronous)
- `bscl_chan_send(chan, value)` — Send value; blocks until receiver ready (synchronous) or buffer space available (buffered)
- `bscl_chan_recv(chan) -> value` — Receive value; blocks until sender ready
- `bscl_chan_close(chan)` — Close channel; subsequent recv returns `BSCL_CLOSED`
- `bscl_select(cases[], n) -> fired_case` — Select over N channels; non-deterministic when multiple ready

Implementation: POSIX pthreads mutex + condition variable per channel. Synchronous channels: rendezvous protocol (sender waits for receiver to call recv, and vice versa).

#### `src/compiler.c` — B-to-Wordcode Compiler
Translates B source to wordcode (stack machine bytecode). B language subset:
- Types: `int` (machine word), `char`, pointers (`*T`)
- Expressions: arithmetic, bitwise, relational, assignment `=`, compound `+=/-=/*=//=/%=`
- Statements: `if`, `while`, `for`, `return`, `goto`, label, block
- Functions: `f(a, b, c)` declaration, recursive calls
- Channel operations: `send(chan, val)`, `recv(chan)`, `select {...}`

Wordcode instructions documented in `docs/WORDCODE.md`: PUSH, POP, ADD, SUB, MUL, DIV, MOD, AND, OR, XOR, NOT, SHL, SHR, EQ, NE, LT, LE, GT, GE, JMP, JZ, JNZ, CALL, RET, LOAD, STORE, CHAN_SEND, CHAN_RECV, CHAN_SELECT.

---

## 16. physics/

**Languages:** Julia (.jl), MATLAB (.m), Isabelle/HOL (.thy)
**Purpose:** Physics simulation and formal verification of quantum dynamics. Three subsections: Hawking radiation quantum operators (MATLAB), random walk particle transport (Julia), and Jungian-Lindblad stochastic quantum dynamics (Isabelle/HOL).

### Subdirectories

#### `physics/hawking-radiation/` — MATLAB Quantum Operators
Six MATLAB files implementing quantum field operators near a black hole horizon:

| File | Description |
|------|-------------|
| `dissipationOperator.m` | Lindblad dissipation superoperator: L[ρ] = LρL† - ½{L†L, ρ} |
| `horizonFluctuations.m` | Horizon vacuum fluctuation spectrum computation |
| `incomingMode.m` | Incoming Hawking mode creation operator |
| `modeSpectrum.m` | Thermal mode spectrum: Planck distribution at Hawking temperature |
| `outgoingMode.m` | Outgoing Hawking radiation mode |
| `phaseOperator.m` | Quantum phase operator for superposition states |

The set implements a discrete model of Hawking radiation using the Bogoliubov transformation: outgoing modes are superpositions of ingoing modes and their conjugates, with coefficients determined by the surface gravity κ.

#### `physics/julia-rwpt/` — Julia RWPT (Random Walk Particle Transport)
Eight Julia files implementing a parallel random-walk particle transport simulator:

| File | Description |
|------|-------------|
| `RWPT.jl` | Core RWPT algorithm: particle trajectories, scattering, absorption |
| `FPGAMock.jl` | FPGA hardware mock for testing without physical FPGA |
| `FPGA_API.jl` | FPGA communication API (AXI-stream interface) |
| `FutharkFFI.jl` | Julia→Futhark FFI bridge for GPU-accelerated transport |
| `e2e_sim_harness.jl` | End-to-end simulation harness |
| `julia_driver.jl` | Driver: parse config, launch sim, collect results |
| `jung_rwpt_sim.jl` | Jungian dynamics + RWPT combined simulation |
| `jung_sim.jl` | Pure Jungian stochastic simulation |
| `quipper_client.jl` | Client for Quipper quantum circuit compiler |

`RWPT.jl` core: particle state `(position::Vector{Float64}, momentum::Vector{Float64}, weight::Float64)`. Step: sample free path length from exponential distribution (mean free path λ), advance position, scatter by sampling new momentum from phase function, update weight by absorption factor exp(-μ_a * path_length). Parallelized via Julia's `@threads` over particle batch.

#### `physics/jungian-dynamics/` — Isabelle/HOL Formal Verification
Ten Isabelle/HOL theory files formalizing Jungian stochastic quantum dynamics:

| File | Description |
|------|-------------|
| `Almost_Sure_Convergence.thy` | Almost-sure convergence of stochastic process |
| `Control_Invariants.thy` | Control-theoretic invariants for quantum dynamics |
| `Density_Matrix.thy` | Density matrix (positive semidefinite, trace-1) type theory |
| `GKSL_Semigroup.thy` | Gorini-Kossakowski-Sudarshan-Lindblad semigroup axioms |
| `Jungian_Formalization.thy` | Core Jungian dynamics formalization |
| `Jungian_Prob_Dynamics.thy` | Probabilistic dynamics specification |
| `Jungian_Stochastic_Convergence_Full.thy` | Full convergence theorem |
| `Lindblad_GKSL.thy` | Lindblad master equation GKSL form |
| `Quantum_Jump_Update.thy` | Quantum jump update rule |
| `Quipper_Kraus_Check.thy` | Kraus operator extraction from Quipper circuits |

`Density_Matrix.thy` defines: `density_matrix = {ρ :: complex mat | hermitian ρ ∧ pos_semidef ρ ∧ trace ρ = 1}`. Lindblad evolution: `dρ/dt = -i[H,ρ] + Σ_k (L_k ρ L_k† - ½{L_k†L_k, ρ})`. `GKSL_Semigroup.thy` proves this generates a completely positive trace-preserving (CPTP) semigroup.

---

## 17. polyglot/

**Languages:** Go, Rust, C, x86-64 Assembly
**Purpose:** Cross-language interoperability layer. Provides Go and Rust implementations of the same core abstractions (Turing machine, context-free grammar PTM, JCL-style job control) that can call each other via C FFI, plus assembly-level switchboard optimizations.

### Files

```
polyglot/
├── asm/
│   └── switchboard_optimizations.asm   x86-64 dispatch table optimizations
├── interop_ffi.h                        C header for Go-Rust FFI
├── polyglot_builder.go                  Go polyglot builder
├── polyglot_builder.h                   C header for polyglot builder
├── polyglot_builder.rs                  Rust polyglot builder
├── turing_binary_foundation.go          Go Turing machine (binary tape)
├── turing_cfg_ptm.go                    Go context-free grammar PTM
└── turing_quipper_jcl.go               Go JCL-style job control + Quipper
```

### File Descriptions

#### `turing_binary_foundation.go`
Go implementation of a binary-tape Turing machine. `TuringMachine` struct: tape as `map[int]byte` (sparse, infinite), head position `int`, state `string`, transition function `map[(state, symbol)](next_state, write_symbol, direction)`. `Step()` performs one transition. `Run(maxSteps int)` runs until halt state or step limit. Implements the NAND# ISA as a Turing machine tape program for theoretical equivalence proofs.

#### `turing_cfg_ptm.go`
Pushdown Turing Machine (PTM) for context-free grammar recognition. Implements a two-stack PTM accepting CFG languages. Used to demonstrate that the NAND# ISA is Turing-complete (PTMs can simulate any Turing machine).

#### `turing_quipper_jcl.go`
JCL (Job Control Language) inspired job scheduler with Quipper quantum circuit integration. `JCLJob`: `{job_name, steps: []Step, on_error: ErrorAction}`. `Step`: `{exec, params, cond}`. Scheduler: sequential with conditional step execution and ABEND (abnormal end) propagation. Quipper integration: `Step.exec = "QUIPPER"` dispatches to the Julia Quipper client.

#### `polyglot_builder.go` / `.rs`
Builder pattern implementations in both Go and Rust for constructing polyglot pipeline configurations. Both expose the same logical API: `NewPolyglotBuilder()`, `.AddStage(language, module, function)`, `.AddEdge(from, to)`, `.Build() -> Pipeline`. The Go version calls into Rust via CGo + the `interop_ffi.h` C header.

#### `asm/switchboard_optimizations.asm`
Optimized x86-64 dispatch table for the polyglot language switcher. Implements a computed GOTO table with 16 entries (one per supported language). Each entry: 8-byte function pointer. Dispatch: `MOV RAX, [dispatch_table + language_id * 8]; CALL RAX`. Aligned to 64-byte cache line boundary to ensure the full dispatch table fits in a single L1 cache line.

---

## 18. qflow/

**Language:** Haskell (Cabal build)
**Purpose:** Compiler for QFlow, a quantum dataflow DSL. QFlow programs describe quantum circuits as directed acyclic dataflow graphs. The compiler parses `.qflow` source files, builds an AST, type-checks (qubit types), and emits Quipper-compatible circuit descriptions.

### Files

```
qflow/
├── qflow.cabal
├── compiler/
│   ├── AST.hs      Abstract syntax tree
│   ├── Lexer.hs    Alex-style lexer
│   ├── Main.hs     Compiler entry point
│   └── Parser.hs   Happy-style parser
└── examples/
    └── bell.qflow  Bell state preparation example
```

### File Descriptions

#### `compiler/AST.hs`
QFlow AST types:
```haskell
data Circuit = Circuit { name :: Name, inputs :: [Qubit], body :: [Instruction] }
data Instruction
  = GateApp Gate [Qubit]          -- apply gate to qubits
  | Measure Qubit ClassicalBit    -- measure qubit to classical bit
  | ControlledGate Gate [Qubit] Qubit  -- controlled gate
  | Barrier [Qubit]               -- synchronization barrier
  | Reset Qubit                   -- reset qubit to |0⟩
data Gate = H | X | Y | Z | CNOT | CCNOT | S | T | Rx Double | Ry Double | Rz Double
data Qubit = Qubit Name | AncillaQubit Int
```

#### `compiler/Main.hs`
Compiler pipeline: `main = readFile inputPath >>= (lex >=> parse >=> typecheck >=> emit) >>= writeFile outputPath`. Emits Quipper `Circ` monad code. Error messages carry source position (line, column) from lexer tokens.

#### `examples/bell.qflow`
```qflow
circuit bell_state(q0, q1: qubit) -> (q0, q1: qubit):
  H q0
  CNOT q0, q1
```
Prepares a Bell state (maximally entangled 2-qubit state) by applying Hadamard to q0 then CNOT with q0 as control.

---

## 19. quantum_computer/

**Language:** Python 3.12
**Purpose:** Pure-Python quantum computer simulator. Supports arbitrary-qubit state vectors, standard gate set, circuit optimization, noise modeling, topological algorithms, and quantum error correction stubs.

### Directory Layout

```
quantum_computer/
├── __init__.py
├── algorithms/
│   ├── advanced.py       VQE, QAOA, quantum phase estimation
│   └── topological.py    Topological quantum algorithms (anyon models)
├── circuit/
│   ├── advanced_optimizer.py  Advanced circuit optimization passes
│   ├── circuit.py            Circuit construction API
│   ├── dag.py                DAG-based circuit representation
│   ├── optimizer.py          Basic circuit optimization
│   └── scheduler.py          Gate scheduling (depth minimization)
├── core/
│   ├── complex.py    Complex number arithmetic (fixed-precision)
│   ├── matrix.py     Dense complex matrix operations
│   ├── register.py   Qubit register
│   └── state.py      State vector (2^n complex amplitudes)
├── error_correction/__init__.py   (stub)
├── gates/__init__.py             Standard gate definitions
├── hardware/__init__.py          Hardware backend stub
├── noise/
│   └── advanced.py    Advanced noise models (Kraus operators)
├── serialization/__init__.py     Circuit serialization (QASM-like)
├── tests/
│   ├── test_extended.py   Extended tests
│   ├── test_full.py       Full integration tests
│   └── test_simulator.py  Simulator unit tests
├── validation/__init__.py  Validation routines
└── vm/
    └── simulator.py   State vector simulator
```

### File Descriptions

#### `core/state.py`
`QuantumState`: state vector as `numpy.ndarray` of complex128 with shape `(2^n,)`. Operations: `apply_gate(gate_matrix, qubit_indices)`, `measure(qubit) -> (bit, collapsed_state)`, `partial_trace(qubit_indices) -> density_matrix`, `fidelity(other_state) -> float`. State normalization enforced on construction and after measurement.

#### `circuit/dag.py`
DAG-based circuit representation. Nodes: gates + input/output barriers. Edges: data dependencies (qubit wire). `DAGCircuit.topological_sort()` gives valid execution ordering. `DAGCircuit.depth()` = longest path length. `DAGCircuit.commuting_sets()` groups simultaneously executable gates (no shared qubits).

#### `circuit/optimizer.py`
Basic circuit optimization passes:
- `cancel_adjacent_gates` — Cancel `X·X`, `H·H`, `CNOT·CNOT` pairs
- `merge_single_qubit_rotations` — Merge adjacent `Rz(θ₁)·Rz(θ₂)` → `Rz(θ₁+θ₂)`
- `commute_gates_through_barriers` — Reorder commuting gates across barriers
- `remove_idle_qubits` — Remove qubits with no applied gates

#### `noise/advanced.py`
Advanced noise models using Kraus operators:
- `DepolarizingChannel(p)` — Kraus: {√(1-p)I, √(p/3)X, √(p/3)Y, √(p/3)Z}
- `AmplitudeDampingChannel(γ)` — Kraus: {[[1,0],[0,√(1-γ)]], [[0,√γ],[0,0]]}
- `PhaseDampingChannel(λ)` — Kraus: {[[1,0],[0,√(1-λ)]], [[0,0],[0,√λ]]}
- `ThermalRelaxationChannel(T1, T2, gate_time)` — Combined T1/T2 relaxation

#### `algorithms/topological.py`
Topological quantum computing algorithms using anyonic models:
- Fibonacci anyons: F-matrix, R-matrix, braiding operators
- Ising anyons: topological charge fusion rules
- `AnyonBraid.compute_unitary()` — Compute unitary from anyon world-line braid
- `TopologicalQC.encode_qubit(anyon_pair)` — Encode logical qubit in anyon pair

---

## 20. retro-gpu/

**Languages:** Occam (.occ), OCaml (.ml), Standard ML (.sml), Modula-2 (.def), C/C++ (via Occam interface)
**Purpose:** Retro-style GPU simulator modeling a simplified SIMT (Single Instruction, Multiple Thread) processor. Multiple language implementations for cross-verification. The GPU model: 32-thread warps, shared memory per thread block, global memory, ALU, register file, and a tensor computation unit.

### Directory Layout

```
retro-gpu/
├── Makefile
├── ALU.occ / GlobalMemory.occ / Registers.occ / Synchronization.occ
├── RetroGPUCompiler.occ / RetroGPUTypes.occ / SharedMemory.occ / Tensor.occ / Warp.occ
├── src/RetroGPU.occ
├── tests/test.occ
├── documentation/ARCHITECTURE.md
├── examples/gemm.occ
├── modula2/definitions/
│   ├── ALU.def / Registers.def / RetroGPU.def / Warp.def
├── ocaml/
│   ├── Makefile
│   ├── src/alu/ALU.ml / compiler/RetroCompiler.ml / interpreter/Interpreter.ml
│   ├── src/registers/Registers.ml / shared/SharedMemory.ml / types/RetroGPUTypes.ml / warp/Warp.ml
│   ├── tests/BlockTests.ml / test_full_pipeline.ml / test_registers.ml
│   └── examples/GemmKernel.ml
└── sml/
    ├── ALU.sml / Compiler.sml / GEMM.sml / Hopper.sml
    ├── Instruction.sml / Interpreter.sml / Kernel.sml
    ├── Memory.sml / RetroGPUCore.sml / Scheduler.sml
    ├── Sync.sml / Tensor.sml / Warp.sml
    └── types/RetroGPUTypes.sml
```

### File Descriptions

#### `Warp.occ` — Occam Warp Model
Models a 32-thread SIMT warp using Occam's CSP-based concurrency. Each thread is an Occam process; the warp controller executes them in lockstep via channel synchronization. `WARP.EXECUTE(instruction, reg_file, shared_mem)`: broadcasts instruction to 32 thread processes via a `!` channel array, collects results via `?` channel array, applies predicate masking.

#### `sml/RetroGPUCore.sml` — SML Core
Core GPU data structures in Standard ML:
```sml
type register_file = {regs: int array, pc: int ref, flags: int ref}
type warp = {id: int, threads: thread array, active_mask: int}
type thread_block = {warps: warp array, shared_mem: int array, barrier_count: int ref}
type grid = {blocks: thread_block array, global_mem: int array}
```
`execute_instruction : instruction -> grid -> warp_id -> unit` dispatches on opcode, updates register file, handles shared/global memory loads/stores.

#### `sml/GEMM.sml` — GEMM Kernel
Matrix multiply kernel in SML. `gemm(A, B, C, M, N, K)`: tiled matrix multiply with tile size 16×16 stored in simulated shared memory. Demonstrates how the retro-GPU shared memory and warp synchronization model maps to the standard GEMM tiling algorithm.

#### `sml/Hopper.sml`
Hopper (NVIDIA H100) ISA compatibility layer. Maps retro-GPU instructions to SM90 SASS equivalents for the VSM-2500 H100 SASS bridge validation.

#### `ocaml/src/compiler/RetroCompiler.ml`
OCaml compiler for retro-GPU kernel source → retro-GPU bytecode. Parsing: Menhir-generated parser (inlined LL(1) approximation). Code generation: peephole optimization pass (combine `LOAD+STORE` → `MOV`, remove redundant `SYNC` barriers when no shared memory access between them). Output: `.retro` bytecode file.

#### `ocaml/src/interpreter/Interpreter.ml`
OCaml bytecode interpreter for retro-GPU programs. Implements the same execution model as the Occam original but in a sequential simulation for debugging. Produces an execution trace: JSONL file with one record per warp instruction dispatch.

---

## 21. rust/

**Language:** Rust (Cargo workspace: `rust/fsl/`)
**Purpose:** Formal Specification Language (FSL) library in Rust. Integrates: CBMC bounded model checking harnesses, Crux/SAW verification backend, QA5 reactive theorem prover, Eclipse/Parlog constraint solver, and the sovereign neural SaaS core. Also contains the theorem ledger for tracking proven theorems.

### Directory Layout

```
rust/fsl/
├── Cargo.toml / Cargo.lock
└── src/
    ├── lib.rs
    ├── cbmc.rs                        CBMC harness integration
    ├── cbmc_binary_semantics.rs       Binary semantics CBMC harnesses
    ├── cbmc_binary_semantics_assembly.rs  Assembly-level CBMC
    ├── sovereign_neural_saas_core.rs  Sovereign neural SaaS core
    ├── theorem_ledger.rs              Theorem tracking ledger
    ├── assert_q/
    │   ├── mod.rs     AssertQ module entry
    │   ├── constraint.rs   Constraint definitions
    │   ├── formula.rs      Logical formula types
    │   ├── propagation.rs  Constraint propagation
    │   ├── reactive_store.rs  Reactive constraint store
    │   └── solver.rs       AssertQ solver
    ├── crux/
    │   ├── mod.rs / ast.rs / lean_backend.rs / lean_monad_stack.rs
    │   ├── omega.rs (Omega test) / pcc.rs (proof-carrying code)
    │   ├── pipeline.rs / russian.rs / sas_backend.rs / z3_backend.rs
    ├── eclipse_parlog/
    │   ├── mod.rs / arithmetic.rs / domain.rs / globals.rs
    │   ├── parlog.rs / search.rs / suspension.rs
    └── qa5/
        ├── mod.rs / clause.rs / prover.rs / racket_morph.rs
        ├── reactive.rs / resolution.rs / strategy.rs / unification.rs
```

### File Descriptions

#### `src/assert_q/constraint.rs`
`Constraint` enum: `Eq(Expr, Expr)`, `Ne(Expr, Expr)`, `Lt(Expr, Expr)`, `Le(Expr, Expr)`, `And(Box<Constraint>, Box<Constraint>)`, `Or(Box<Constraint>, Box<Constraint>)`, `Not(Box<Constraint>)`, `ForAll(Var, Box<Constraint>)`, `Exists(Var, Box<Constraint>)`. Implements `Constraint::eval(env: &Env) -> Option<bool>` for ground constraint evaluation.

#### `src/crux/z3_backend.rs`
Z3 SMT solver backend via the `z3` Rust crate. `Z3Backend::check(constraints: &[Constraint]) -> SolveResult`: converts FSL constraints to Z3 AST nodes, calls `Solver::check()`, extracts model on SAT or returns UNSAT/UNKNOWN. Timeout: 30 seconds. Used for quantifier-free linear arithmetic (LIA) constraint solving.

#### `src/crux/lean_backend.rs`
Lean 4 backend. `LeanBackend::verify(theorem: &Theorem) -> VerificationResult`: serializes theorem to Lean 4 syntax, launches `lake build` in a subprocess, parses output for `sorry`-free compilation. Returns PROVED/FAILED/TIMEOUT.

#### `src/qa5/prover.rs`
QA5 (Question-Answering version 5) reactive theorem prover. `Prover::prove(goal: &Clause, kb: &KnowledgeBase) -> ProofResult`: backward-chaining with tabling. Tabling: `HashMap<ClauseSignature, TablingEntry>` where entry is PROVED/FAILED/IN_PROGRESS (for cycle detection). Resolution: SLD (Selective Linear Definite) clause resolution with occurs-check.

#### `src/theorem_ledger.rs`
Append-only ledger of proven theorems. `TheoremLedger`: `Vec<TheoremRecord>` where `TheoremRecord = {theorem_id, statement, proof_backend, verification_timestamp, proof_hash}`. `proof_hash = SHA256(canonical_json(record without hash))`. `TheoremLedger::verify_integrity()` recomputes all proof hashes and checks monotonic timestamps.

#### `src/sovereign_neural_saas_core.rs`
Sovereign Neural SaaS (Software as a Service) core. Implements the VSM-2500 Virtual Parameter algebra in Rust: `VirtualParameter` struct (128-bit, 16-byte aligned), binary semantic algebra operations (AND, OR, XOR, IMPL, NAND, NOR as type-safe enum), deterministic serialization to canonical byte string, provenance tag tracking. No floating-point. All operations are const-evaluable where possible.

---

## 22. schema/

**Language:** SQL (DB2/IBM Db2 dialect)
**Purpose:** Database schema definitions for the ORC (Orchestrator) schema and the extended event-sourced financial schema. These SQL files are the authoritative schema for the constraint-harness task queue and the sovereign treasury engine.

### Files

#### `ORC_SCHEMA.sql`
ORC (Orchestrator) schema. Tables:

| Table | Key Columns | Description |
|-------|-------------|-------------|
| `ORCTASK` | TASKID (PK), STATUS, NEXT_ATTEMPT_TS | Task queue; states: NEW, RUNNING, DONE, FAILED |
| `ORCLOG` | LOG_TS, LEVEL, MESSAGE, SOURCE | Operational log entries |
| `ORCAUD` | TASKID (FK), AUDIT_SEQ (identity), EVENT_CODE, DETAIL | Audit trail per task |

`ORCTASK` status transitions: NEW → RUNNING → DONE | FAILED. `RETRY_COUNT` incremented on each retry; `NEXT_ATTEMPT_TS` set by exponential backoff. `PAYLOAD` stored as CLOB(32K) JSON.

#### `schema-extended.sql`
Extended schema for the event-sourced treasury system. Key tables:

| Table | Key Columns | Description |
|-------|-------------|-------------|
| `EVENT_STORE` | EVENT_ID (identity PK), SEQUENCE_NUM (unique), EVENT_TYPE, AGGREGATE_ID, PAYLOAD | Append-only event store; SEQUENCE_NUM is strictly monotonic |
| `RAIL_SUBMISSIONS` | SUBMISSION_ID, RAIL_CODE, STATUS | Payment rail submissions; states: CREATED, SUBMITTED, ACKED, SETTLED, FAILED |
| `RAIL_NOTIFICATIONS` | NOTIF_ID, SUBMISSION_ID (FK), TYPE | Settlement/return/ACK notifications from payment rails |

---

## 23. scripts/

**Languages:** Bash, Python, JavaScript (Node.js), PowerShell
**Purpose:** Build, test, deploy, and tooling automation scripts.

### Files

| File | Language | Description |
|------|----------|-------------|
| `add-license-headers.ps1` | PowerShell | Prepends Sovereign Leviathan Node License header to source files missing it |
| `build.sh` | Bash | Primary build script: runs Go build, Rust cargo build, pytest, and produces artifacts |
| `build_all.sh` | Bash | Full build: all languages (Ada gnatmake, Haskell cabal, Rust cargo, Go, Python, Zig) |
| `check_deep_imports.py` | Python | Static analysis: detects direct imports of internal sub-packages (enforces classifier/ facade pattern) |
| `compile_wasm.js` | Node.js | Compiles WASM modules from AssemblyScript source; calls wasm-pack for Rust WASM crates |
| `funnelc.py` | Python | Funnel language compiler: lexer + parser + code generator → outputs Python or Prolog |
| `generate_diagrams.sh` | Bash | Runs `dot` (Graphviz) on all `.dot` files in `docs/`, generates `.svg` and `.png` outputs |
| `make_gif.py` | Python | Assembles demo GIF from frame images in `docs/assets/` |
| `prove_memory_manager.sh` | Bash | Runs GNAT-SPARK proof on `languages/ada/memory_manager.adb` |
| `publish-watch.sh` | Bash | Watches for file changes and republishes affected documentation |
| `publish.sh` | Bash | Publishes documentation to configured target (git pages branch or static host) |
| `run_pipeline.sh` | Bash | End-to-end pipeline: build → test → verify → package. Used in CI. |
| `synthesize_ptx.sh` | Bash | Calls `nvcc` to compile `.cu` files and extract PTX assembly for inspection |
| `test_runner.sh` | Bash | Runs all test suites: pytest (Python), `go test ./...` (Go), `cargo test` (Rust), custom Lua test runner |

### `funnelc.py` Details
Funnel language compiler. Three-phase pipeline:
1. **Lexer**: tokenizes Funnel keywords (PROGRAM, FILE, USING, KEY, RECORD, IN, PROC, IS, IF, THEN, ENDIF, ENDPROC, LOAD, SAVE, NEW, WRITE, READ, FAIL, NOT, IN), identifiers, literals, numeric formats (NUM(p,s), CHAR(n), ENUM(v1,v2,...))
2. **Parser**: recursive descent producing a Funnel AST: `ProgramNode`, `FileDecl`, `RecordDecl`, `ProcDecl`, `Statement` subclasses
3. **Code generator**: two backends: `PythonBackend` (emits Python functions calling a SQL DAO layer), `PrologBackend` (emits Prolog predicates using assert/retract for state)

---

## 24. spiral-detection/

This directory exists in the repository filesystem but contains no source files at the time of documentation (empty or `.gitkeep` only). Based on context from `docs/PHASE_5_SCALABLE_NEURON_MODEL.md` and `docs/3D_ANATOMICAL_GRAPH_SPECIFICATION.md`, spiral-detection is planned as a Python module implementing spiral pattern detection in neuron topology graphs using topological data analysis (persistent homology). The `tests/swift-objc/testSpiralConsistency.m` file in the tests/ directory tests spiral consistency invariants, indicating the detection logic is partially implemented in the tests layer.

---

## 25. tests/

**Languages:** Python 3.12 (pytest), Swift (XCTest), Objective-C (XCTest)
**Purpose:** Integration and unit tests covering the dream_rsi orchestrator, Lua engine, cold-boot ICP sequence, and Swift/Objective-C physics invariants.

### Directory Layout

```
tests/
├── __init__.py
├── test_cold_boot_icp.py          Cold-boot ICP (Initial Control Point) tests
├── test_dream_rsi.py              RSI orchestrator basic tests
├── test_dream_rsi_audit.py        RSI audit trail tests
├── test_dream_rsi_extensions.py   RSI extension API tests
├── test_dream_rsi_full.py         Full integration tests (all phases)
├── test_dream_rsi_phase23.py      Phase 2/3 specific tests
├── test_lua_engine.py             Lua engine correctness tests
├── test_stack.py                  Stack invariant tests
└── swift-objc/
    ├── CompleteTests.swift         Comprehensive Swift XCTest suite
    ├── testAuditSeal.m            Audit seal cryptographic correctness
    ├── testConservation.m         Physical conservation law tests
    ├── testDissipation.m          Dissipation operator tests
    ├── testMassInvariance.m       Mass invariance tests
    ├── testOmegaEST.m             Omega estimation tests
    ├── testResonance.m            Resonance pattern tests
    ├── testSpiralConsistency.m    Spiral consistency invariants
    └── testTorsionPhase.m         Torsion phase tests
```

### File Descriptions

#### `test_dream_rsi.py`
Basic dream_rsi tests. Tests: `RSIOrchestrator` initialization, `run()` with 1 round / 0 revisions returns correct metrics (`generations=1`, `policy_revisions=0`), incumbent-safety guarantee (winner score ≥ initial policy score), discovery tree serialization (JSON roundtrip preserves node count and scores), `WorldStore.add()` / `WorldStore.get()` idempotency.

#### `test_dream_rsi_full.py`
Full integration tests covering all phases of the RSI loop. Tests: multi-round accumulation (50 rounds × 8 revisions, verifies `policy_revisions == 400`), historical world pool growth (world count equals round count), replay evaluation count (equals worlds × candidates per round), metric separations (`discovery_agent_calls` only incremented in online phase, not replay), offline-online separation (no `FixedDiscoveryAgent.propose` calls during replay).

#### `test_dream_rsi_audit.py`
Audit trail tests. Verifies: every state transition produces an `AuditEvent`, `AuditEvent.from_state` and `to_state` form legal transition pairs (from `LEGAL_TRANSITIONS`), `execution_id` is consistent across all events in a single run, `input_hash` is a valid 16-character hex string, `DecisionRecord.seal` equals `hash_record(asdict(record) without seal field)`.

#### `test_cold_boot_icp.py`
Cold-boot Initial Control Point (ICP) tests. Tests the boot sequence: ROM checksum verification passes, memory map initialization covers all required regions, diagnostic register reads correct status after boot, monitor entry point is reachable, interrupt vector table entries are within ROM address range.

#### `test_lua_engine.py`
Lua engine correctness tests via Python subprocess calls to the Lua interpreter. Tests: `metabinary_final_assembly` loads without syntax error, `nand_decode_256_words` returns expected 256-entry table, `query_leaf` returns scalar within expected range, `header_pack_only` executes without exception. Captures stderr to verify no Lua runtime errors.

#### `swift-objc/testAuditSeal.m`
Objective-C XCTest: verifies that `DecisionRecord` SHA-256 seal computation is deterministic (same inputs → same seal), that tampering with any field changes the seal, and that `seal_decision()` populates all required fields.

#### `swift-objc/testConservation.m`
Tests physical conservation laws in the physics simulation layer. Verifies: total quantum state norm is preserved (|⟨ψ|ψ⟩ - 1| < 1e-10), density matrix trace is preserved after Lindblad evolution (|tr(ρ) - 1| < 1e-12), energy expectation value is conserved under unitary evolution.

#### `swift-objc/CompleteTests.swift`
Comprehensive Swift XCTest suite integrating all Objective-C test cases plus additional Swift-specific tests: Metal inference pipeline correctness (output token probabilities sum to approximately 1.0), KV cache hit rate validation, calibration profile load/save roundtrip.

---

*End of FILE_REFERENCE_remaining.md*
