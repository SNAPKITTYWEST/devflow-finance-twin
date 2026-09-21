// ============================================================================
// formal-engine/Integration/Recursion.dfy
// Recursive ingestion driver and orchestration
// License: GPL 2.0
// ============================================================================

module Integration.Recursion {

  import opened Core.Terms
  import opened Core.Formulas
  import opened StateMachine.State
  import opened SMT.Constraints
  import opened Theorem.Kernel
  import opened GPU.CUDAAbstractModel
  import opened Cipher.Encryption
  import opened ZK.Relations

  datatype WorkKind =
      CoreWork
    | StateMachineWork
    | InvariantWork
    | SMTWork
    | TheoremWork
    | GPUWork
    | CipherWork
    | ZKWork
    | CertificateWork

  datatype WorkItem =
    WorkItem(
      id: string,
      kind: WorkKind,
      depth: nat,
      description: string
    )

  predicate ValidWorkItem(w: WorkItem)
  {
    w.id != "" &&
    w.description != ""
  }

  function NextKind(kind: WorkKind): WorkKind
  {
    match kind
      case CoreWork => StateMachineWork
      case StateMachineWork => InvariantWork
      case InvariantWork => SMTWork
      case SMTWork => TheoremWork
      case TheoremWork => GPUWork
      case GPUWork => CipherWork
      case CipherWork => ZKWork
      case ZKWork => CertificateWork
      case CertificateWork => CertificateWork
  }

  function NextWork(w: WorkItem): WorkItem
  {
    WorkItem(
      w.id + ".next",
      NextKind(w.kind),
      w.depth + 1,
      "recursive ingestion of " + w.id
    )
  }

  predicate Terminal(w: WorkItem)
  {
    w.kind == CertificateWork
  }

  method Recurse(
    work: WorkItem,
    fuel: nat
  ) returns (processed: seq<WorkItem>)
    ensures |processed| <= fuel + 1
    ensures |processed| > 0
    ensures forall i :: 0 <= i < |processed| ==> ValidWorkItem(processed[i])
  {
    if fuel == 0 || Terminal(work) {
      return [work];
    }

    var next := NextWork(work);
    var tail := Recurse(next, fuel - 1);

    return [work] + tail;
  }

  function InitialWork(): WorkItem
  {
    WorkItem(
      "ROOT",
      CoreWork,
      0,
      "initialize Dafny-only formal verification forge"
    )
  }

  method RecurseWithCallback(
    work: WorkItem,
    fuel: nat,
    callback: WorkItem -> bool
  ) returns (processed: seq<WorkItem>)
    ensures |processed| > 0
  {
    if fuel == 0 || Terminal(work) {
      var _ := callback(work);
      return [work];
    }

    var shouldContinue := callback(work);
    if !shouldContinue {
      return [work];
    }

    var next := NextWork(work);
    var tail := RecurseWithCallback(next, fuel - 1, callback);

    return [work] + tail;
  }

  predicate AllItemsValid(items: seq<WorkItem>)
  {
    forall i :: 0 <= i < |items| ==> ValidWorkItem(items[i])
  }

  lemma RecurseProducesValidItems(w: WorkItem, fuel: nat)
    ensures
      var items := Recurse(w, fuel);
      AllItemsValid(items)
  {
    if fuel == 0 || Terminal(w) {
      assert ValidWorkItem(w);
    } else {
      var next := NextWork(w);
      assert ValidWorkItem(next);
      RecurseProducesValidItems(next, fuel - 1);
    }
  }

  function ExecutionTrace(w: WorkItem, fuel: nat): seq<string>
  {
    var items := Recurse(w, fuel);
    seq(|items|, i requires 0 <= i < |items| => items[i].id)
  }

  lemma TraceIsNonEmpty(w: WorkItem, fuel: nat)
    ensures |ExecutionTrace(w, fuel)| > 0
  {
    var trace := ExecutionTrace(w, fuel);
    var items := Recurse(w, fuel);
    assert |items| > 0;
    assert |trace| == |items|;
  }
}
