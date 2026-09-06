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

/-- Observe what subjects a Rust function published to — extracted from Rust MIR -/
opaque observe_published : NatsObservation → List (Subject × String)

/-- Core Cobalt axiom: the Rust binary satisfies its Lean specification.
    Each instance of this axiom must be discharged by running `cobalt verify`.
    An undischarged axiom = an unproved Cobalt obligation. -/
axiom cobalt_discharge
    {spec : Prop}
    (fn_name : String)
    (h : CobaltProof spec) : spec

/-- Verus/Prusti bridge: alternative verification path using SMT over Rust contracts.
    Parallel to Cobalt — use whichever toolchain is available.
    For Verus: `verus --crate-name sovereign_conductor src/handler.rs` -/
opaque VerusProof (inv : Prop) : Prop

end Sovereign.Cobalt.Runtime
