// ============================================================================
// formal-engine/ZK/R1CS.dfy
// Rank-1 constraint system (R1CS)
// License: GPL 2.0
// ============================================================================

module ZK.Constraint {

  datatype WireKind = Public | Private | Internal

  datatype Wire = Wire(id: nat, kind: WireKind, name: string)

  datatype Gate = Gate(a: nat, b: nat, c: nat, d: nat)

  datatype Constraint = Constraint(gate: Gate, label: string)

  datatype ConstraintSystem =
    ConstraintSystem(
      wires: seq<Wire>,
      constraints: seq<Constraint>
    )

  predicate ValidCS(cs: ConstraintSystem)
  {
    true
  }

  function ConstraintCount(cs: ConstraintSystem): nat
  { |cs.constraints| }

  function WireCount(cs: ConstraintSystem): nat
  { |cs.wires| }

  predicate Satisfies(cs: ConstraintSystem, assignment: map<nat, int>)
  {
    forall i :: 0 <= i < |cs.constraints| ==>
      var g := cs.constraints[i].gate;
      (if g.a in assignment && g.b in assignment && g.c in assignment && g.d in assignment then
         assignment[g.a] * assignment[g.b] + assignment[g.c] == assignment[g.d]
       else false)
  }
}
