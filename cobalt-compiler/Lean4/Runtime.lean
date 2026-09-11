/-
 ========================================================================
 SOVEREIGN LEVIATHAN NODE LICENSE
 License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
 Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
 ========================================================================

 This file is a covered work under the GNU Affero General Public License,
 version 3, together with the Sovereign Leviathan additional terms.

 Hark, though this node be but a spark,
 Its covenant endureth through the dark.

 Ignorantia juris non excusat.
 ========================================================================
-/

-- Cobalt Runtime Interface
-- Axioms and types that Cobalt would fill in when the Rust MIR verifier is integrated.
-- Each `axiom` here is a proof obligation for the Cobalt pipeline.

import Lean4PolicyKernel.Policies.Core

namespace Sovereign.Cobalt.Runtime
open Sovereign.Policy

/-- A Cobalt proof term: evidence that a Rust function satisfies a Lean spec.
    When Cobalt tooling is installed, this becomes a proper type with constructors. -/
opaque CobaltProof (spec : Prop) : Prop := spec

/-- A Cobalt ghost observation: the set of NATS messages published by a Rust function -/
opaque NatsObservation : Type

/-- Observe what subjects a Rust function published to â€” extracted from Rust MIR -/
opaque observe_published : NatsObservation â†’ List (Subject Ã— String)

/-- Core Cobalt axiom: the Rust binary satisfies its Lean specification.
    Each instance of this axiom must be discharged by running `cobalt verify`.
    An undischarged axiom = an unproved Cobalt obligation. -/
axiom cobalt_discharge
    {spec : Prop}
    (fn_name : String)
    (h : CobaltProof spec) : spec

/-- Verus/Prusti bridge: alternative verification path using SMT over Rust contracts.
    Parallel to Cobalt â€” use whichever toolchain is available.
    For Verus: `verus --crate-name sovereign_conductor src/handler.rs` -/
opaque VerusProof (inv : Prop) : Prop

end Sovereign.Cobalt.Runtime
