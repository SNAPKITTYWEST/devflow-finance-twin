(* Blocks 04 + 05 - Shared & Global Memory *)
structure Memory =
struct
  open RetroGPUCore

  datatype SharedBank = Bank of int (* 0..31 typical *)

  datatype SharedRegion = SharedRegion of {
    base : int,
    size : int,
    alignment : int,
    banks : int
  }

  datatype SharedAccess = SharedAccess of {
    addr : int,
    width : int,
    isLoad : bool,
    bank : SharedBank,
    conflict : bool
  }

  fun bankOf addr banks = Bank (addr mod banks)

  fun analyzeConflict (accesses : SharedAccess list) =
    (* true if any two accesses hit same bank with different addresses *)
    let
      fun conflict (SharedAccess a1) (SharedAccess a2) =
        #bank a1 = #bank a2 andalso #addr a1 <> #addr a2
    in
      List.exists (fn a => List.exists (conflict a) accesses) accesses
    end

  datatype GlobalAccess = GlobalAccess of {
    addr : int,
    space : MemorySpace,
    width : int,
    alignment : int,
    order : MemoryOrder,
    isAtomic : bool
  }

  fun checkAlignment (GlobalAccess {addr, alignment, ...}) =
    addr mod alignment = 0
end
