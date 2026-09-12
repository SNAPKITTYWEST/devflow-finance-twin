(* Block 09 - Deterministic Scheduler *)
structure Scheduler =
struct
  open RetroGPUCore

  datatype DepKind = DataDep | AntiDep | OutputDep | MemDep | SyncDep | TensorDep

  datatype DepEdge = Edge of {
    from : int, (* instruction index *)
    to : int,
    kind : DepKind
  }

  datatype SchedulePolicy =
      DependencyOrder
    | RegisterPressureOrder
    | MemoryLatencyOrder
    | TensorPriorityOrder

  datatype Schedule = Schedule of {
    order : int list, (* instruction indices in issue order *)
    policy : SchedulePolicy,
    pressure : int,
    cycles : int (* abstract *)
  }

  (* Deterministic topological-ish order based on policy *)
  fun schedule (instCount, edges, policy) =
    let
      (* simple linear order for determinism; real impl would do priority queue with stable sort *)
      val order = List.tabulate (instCount, fn i => i)
    in
      Schedule {order=order, policy=policy, pressure=0, cycles=instCount}
    end
end
