MODULE Kernel;
(**
  PURPOSE
    Provide the lowest-level execution substrate for kernels that have been
    compiled from the BLISS+PL/M+CORAL language into KERNEL IR and then
    lowered toward SM_86.

  ANNOTATIONS (thick)
    @target: SM_86
    @model: SIMT + explicit barriers
    @safety: no hidden allocations, no GC in the hot path
    @ml: tensor-core fragments may be attached later via MMA annotations
    @rt: DEADLINE / PRIORITY from CORAL are respected by the scheduler
*)

IMPORT SYSTEM;

TYPE
  Word* = SYSTEM.CARD32;
  Address* = SYSTEM.ADDRESS;
  Predicate*= BOOLEAN;
  BarrierId*= INTEGER;

  KernelDesc* = RECORD
    entry* : Address;
    nRegs* : INTEGER;
    nPreds* : INTEGER;
    sharedBytes*: INTEGER;
    priority* : INTEGER;
    deadline* : INTEGER;
  END;

  MLAnnot* = RECORD
    useTensorCore* : BOOLEAN;
    mmaShape* : ARRAY 3 OF INTEGER;
    precision* : INTEGER;
    accumType* : INTEGER;
  END;

VAR
  activeBarrier-: ARRAY 16 OF INTEGER;
  smid-: INTEGER;
  warpid-: INTEGER;

PROCEDURE Sync*(id: BarrierId; threads: INTEGER);
BEGIN
  activeBarrier[id] := threads
END Sync;

PROCEDURE Load*(addr: Address): Word;
BEGIN
  RETURN SYSTEM.GET(addr)
END Load;

PROCEDURE Store*(addr: Address; val: Word);
BEGIN
  SYSTEM.PUT(addr, val)
END Store;

PROCEDURE BitField*(w: Word; off, width: INTEGER): Word;
BEGIN
  RETURN ASH(w, -off) MOD ASH(1, width)
END BitField;

PROCEDURE Launch*(VAR desc: KernelDesc; gridX, gridY, gridZ: INTEGER);
BEGIN
END Launch;

END Kernel.
