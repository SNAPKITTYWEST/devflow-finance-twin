# Wafer Fabrication
*Phases 13–19*

---

## Phase 13: Wafer Fabrication

### High-Level Process Flow

Si Ingot → Wafer Slicing → Polishing → Cleaning → STI → Well Formation → Fin Formation → Gate Stack (HKMG) → Source/Drain → ILD → Contacts → Metallization (Cu Damascene) → Passivation → Wafer Sort → Dicing

### Detailed Steps (3nm FinFET)

#### FEOL (Front-End-of-Line)

**1. Wafer Preparation**
- Czochralski process → 300mm Si ingot (99.9999% pure)
- Sliced to 0.7mm, polished to Ra < 0.5nm

**2. Shallow Trench Isolation (STI)**
- Etch trenches 200nm deep, fill with SiO₂ (CVD), CMP

**3. Well Formation**
- N-well: Phosphorus implant (1e13 cm⁻², 100 keV) + 1000°C anneal
- P-well: Boron implant (1e13 cm⁻², 50 keV) + 1000°C anneal

**4. Fin Formation**
- EUV lithography (fin pitch 42nm)
- RIE etch → fins: height 50nm, width 5nm
- Oxide fill between fins

**5. Gate Stack (HKMG)**
- ALD HfO₂ (1nm, k=25) as gate dielectric
- TiN/Al metal gate (work function tuning)
- Poly replacement gate approach

**6. Source/Drain**
- NMOS: Arsenic implant (1e15 cm⁻², 5 keV) + spike anneal (1000°C, 1ms)
- PMOS: Boron implant (1e15 cm⁻², 3 keV) + spike anneal
- Epitaxial raise: Si:C for NMOS, Si:Ge for PMOS

**7. Contacts**
- Low-k ILD (k=2.4) deposition
- Contact etch via to source/drain/gate
- Cobalt (Co) fill

#### MOL & BEOL

**8. Local Interconnect (M0–M3):** Cobalt (M0–M2), Copper (M3+), TiN barrier, low-k dielectric

**9. Global Interconnect (M4–M8):** Cu damascene — etch trenches/vias, PVD barrier/seed, electroplate Cu, CMP

**10. Passivation:** Si₃N₄ + SiO₂ stack, protects die from moisture/oxidation

---

## Phase 14: Lithography

### Technology Comparison

| Technology      | Wavelength | Resolution | NA   | DOF (μm) | Throughput (wph) |
|-----------------|------------|------------|------|----------|-----------------|
| DUV (193nm)     | 193nm      | ~40nm      | 1.35 | ~0.5     | 275             |
| EUV (13.5nm)    | 13.5nm     | ~10nm      | 0.33 | ~0.2     | 170             |
| E-Beam          | N/A        | ~5nm       | N/A  | N/A      | < 1             |
| Nanoimprint     | N/A        | ~10nm      | N/A  | N/A      | 10              |

### EUV at 3nm Node

- **Source:** 13.5nm, 600W (ASML machine)
- **Optics:** Mo/Si multilayer mirrors (~70% reflectivity), NA = 0.33
- **Resolution:** `R = k1 × λ / NA = 0.25 × 13.5 / 0.33 ≈ 10nm`
- **Practical pitch:** ~30nm (with multiple patterning)

### Multiple Patterning

**LELE:** Print/etch odd lines → print/etch even lines → 40nm pitch → 20nm pitch  
**LELELE:** Three masks → ~13nm pitch (for critical layers)

### Resist & Pattern Transfer

- **Resist:** Chemically amplified (CAR), 50nm thick, EUV sensitivity 20 mJ/cm²
- **Etch:** Plasma transfer of resist pattern; resist:SiO₂ selectivity ~1:3
- **Overlay accuracy:** < 2nm (3nm node target)

---

## Phase 15: Deposition

### Techniques

| Technique | Method                         | Materials             | Key Property                  |
|-----------|--------------------------------|-----------------------|-------------------------------|
| CVD       | Chemical vapor deposition      | SiO₂, Si₃N₄, Poly-Si | High quality, conformal       |
| PVD       | Physical sputtering            | Al, Cu, TiN           | Fast, good for metals         |
| ALD       | Atomic layer deposition        | HfO₂, Al₂O₃          | Ångström-level control        |
| Epitaxy   | Single-crystal growth          | Si, SiGe, Si:C        | High-quality crystalline Si   |

### ALD (Critical for FinFET)

Alternating self-limiting half-reactions: HfCl₄ pulse → purge → H₂O pulse → purge. One cycle = ~1Å growth. Provides 100% step coverage inside narrow FinFET trenches. Used for HfO₂ gate oxide and Al₂O₃ barrier layers.

### CVD

`SiH₄ + O₂ → SiO₂ + 2H₂` at 400–800°C. Used for STI fill and low-k ILD (SiCOH).

### Epitaxy

Si:C raised source/drain for NMOS (tensile strain → higher electron mobility). Si:Ge raised source/drain for PMOS (compressive strain → higher hole mobility). 600–800°C, SiH₂Cl₂/GeH₄ precursors.

---

## Phase 16: Etching

### Techniques

| Technique      | Selectivity | Anisotropy | Applications              |
|----------------|-------------|------------|---------------------------|
| Plasma Etching | High        | High       | Dielectrics, metals       |
| RIE            | Medium      | High       | Polysilicon, Si fins      |
| Wet Etching    | Low         | Low        | Oxide removal (HF)        |
| CMP            | N/A         | N/A        | Planarization             |

### Fin Formation (Plasma Etch)

- **Chemistry:** Cl₂ + HBr plasma, RF 13.56 MHz
- **Parameters:** 10–100 mTorr pressure, −100V bias
- **Result:** Fins 50nm high, 5nm wide, sidewall angle ~85°

### Key Metrics

- **Selectivity:** `Etch Rate(target) / Etch Rate(mask)`. Example: SiO₂ 100nm/min, resist 1nm/min → 100:1
- **Anisotropy:** `1 − (lateral etch rate / vertical etch rate)`. Perfectly anisotropic = 1.

### Sidewall Control

Passivation (C₄F₆ polymer deposition on sidewalls during etch), low pressure, and high bias together minimize lateral etch (CD loss). Endpoint detected via OES (optical emission spectroscopy) or laser interferometry.

---

## Phase 17: Doping

### Dopant Properties

| Dopant     | Type   | Mobility (cm²/V·s) | Use Case           |
|------------|--------|--------------------|--------------------|
| Boron      | p-type | 450                | P-well, PMOS S/D   |
| Phosphorus | n-type | 1400               | N-well, NMOS S/D   |
| Arsenic    | n-type | 300                | NMOS S/D (shallow) |

### Implant Parameters (3nm FinFET)

| Region     | Dopant | Energy (keV) | Dose (cm⁻²) | Depth (nm) |
|------------|--------|--------------|-------------|------------|
| N-well     | P      | 100          | 1e13        | 200        |
| P-well     | B      | 50           | 1e13        | 200        |
| NMOS S/D   | As     | 5            | 1e15        | 15         |
| PMOS S/D   | B      | 3            | 1e15        | 12         |
| Channel Vth| B/P    | 1            | 1e12        | 5          |

### Annealing

- **Spike Anneal:** 1000°C for 1ms — used at 3nm for ultra-shallow junctions (< 20nm)
- **Laser Anneal:** 1300°C for nanoseconds — for critical junction depth control

### Electrical Impact

- **Vth:** Higher channel doping → higher threshold voltage
- **Leakage:** `I_off ∝ exp(−Vth / (n × kT/q))`. Target I_off < 1pA/μm for FinFET.

---

## Phase 18: 3D Transistor Fabrication

### FinFET Process Summary

1. STI isolation, well formation
2. EUV lithography + RIE to define fins (42nm pitch, 50nm height, 5nm width)
3. ALD HfO₂ + TiN/Al metal gate (HKMG)
4. Implant + spike anneal + epitaxial S/D raise
5. Cobalt contact fill

### GAA Nanosheet Process

1. Epitaxial superlattice: alternating Si (5nm) / SiGe (5nm) layers
2. Pattern and etch fins from superlattice
3. **Channel release:** Selective SiGe etch → freestanding Si nanosheets
4. ALD HfO₂ wraps all 4 sides of each sheet (full gate-all-around)
5. Metal gate fill, epitaxial S/D, contacts

### FinFET vs. GAA

| Parameter               | FinFET      | GAA Nanosheets  |
|-------------------------|-------------|-----------------|
| Channel Control         | 3-sided     | 4-sided         |
| Scalability             | Good (3nm)  | Better (< 2nm)  |
| Drive Current (I_on)    | High        | Higher          |
| Leakage (I_off)         | Low         | Lower           |
| Variability Source      | Fin geometry| Sheet thickness |
| Fabrication Complexity  | Moderate    | High            |

---

## Phase 19: Interconnect Stack

### BEOL Stack

| Layer | Material | Pitch (nm) | Width (nm) | Thickness (nm) | Use Case             |
|-------|----------|------------|------------|----------------|----------------------|
| M0    | Co       | 40         | 20         | 20             | Local                |
| M1    | Co       | 40         | 20         | 20             | Local                |
| M2    | Co       | 44         | 22         | 22             | Local                |
| M3    | Cu       | 48         | 24         | 24             | Intermediate         |
| M4    | Cu       | 52         | 26         | 26             | Intermediate         |
| M5    | Cu       | 60         | 30         | 30             | Semi-global          |
| M6    | Cu       | 80         | 40         | 40             | Global               |
| M7    | Cu       | 120        | 60         | 60             | Power/clock          |
| M8    | Cu       | 200        | 100        | 100            | Power grid           |

### Via Stack

| Via | Connects | Size (nm) | Resistance (Ω) |
|-----|----------|-----------|----------------|
| V0  | M0–M1    | 20×20     | 5              |
| V3  | M3–M4    | 26×26     | 2              |
| V5  | M5–M6    | 40×40     | 1              |
| V7  | M7–M8    | 100×100   | 0.1            |

### Dielectrics

| Layer       | Material      | k-value | Thickness (nm) |
|-------------|---------------|---------|----------------|
| ILD (M0–M2) | SiCOH (Low-k) | 2.4     | 20–40          |
| ILD (M3–M8) | SiCOH (ULK)   | 2.0     | 40–100         |
| Etch Stop   | SiCN          | 4.0     | 10             |
| Passivation | Si₃N₄ + SiO₂  | 7.0     | 500            |

### RC Delay

- **M1, 100μm wire:** 0.5 × 0.2 × 0.2 × 100² = **200ps**
- **M8, 1mm wire:** 0.5 × 0.01 × 0.1 × 1000² = **500ps**
- Use M6–M8 for global signals to keep RC manageable.

### Electromigration Limit

Cu current density limit: < 1 mA/μm². M8 strap (100nm × 100nm = 0.01 μm²) → I_max = 10μA. Supplying 1A requires 100 parallel straps minimum.
