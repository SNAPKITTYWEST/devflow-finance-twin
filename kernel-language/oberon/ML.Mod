MODULE ML;
(**
  PURPOSE
    Attach machine-learning oriented metadata to kernels without
    introducing a second source language or a framework dependency.

  DESIGN
    All fields are value types. No objects, no GC, no dynamic dispatch
    in the hot path. The compiler or the CPL bridge may read these
    records and emit appropriate MMA / cp.async sequences.
*)

IMPORT Kernel;

TYPE
  Precision* = INTEGER;

  Fragment* = RECORD
    rows*, cols*, k*: INTEGER;
    precision*: Precision;
    layout*: INTEGER;
  END;

  KernelML* = RECORD
    name*: ARRAY 64 OF CHAR;
    useMMA*: BOOLEAN;
    fragA*, fragB*, fragC*: Fragment;
    accumPrecision*: Precision;
    preferShared*: BOOLEAN;
    asyncCopyStages*: INTEGER;
    deadline*: INTEGER;
    priority*: INTEGER;
  END;

PROCEDURE Default*(VAR a: KernelML);
BEGIN
  a.useMMA := FALSE;
  a.fragA.rows := 16; a.fragA.cols := 8; a.fragA.k := 8;
  a.fragA.precision := 0;
  a.fragB := a.fragA;
  a.fragC := a.fragA;
  a.accumPrecision := 0;
  a.preferShared := TRUE;
  a.asyncCopyStages := 2;
  a.deadline := 0;
  a.priority := 0
END Default;

PROCEDURE Attach*(VAR desc: Kernel.KernelDesc; VAR ml: KernelML);
BEGIN
  IF ml.deadline > 0 THEN desc.deadline := ml.deadline END;
  IF ml.priority > 0 THEN desc.priority := ml.priority END
END Attach;

END ML.
