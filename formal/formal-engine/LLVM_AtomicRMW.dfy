// ============================================================================
// formal-engine/LLVM/AtomicRMW.dfy
// Full AtomicRMW intrinsic model
// License: GPL 2.0
// ============================================================================

module LLVM.AtomicRMW {

  import opened LLVM.Backend
  import opened PTX.AtomicsBarriers
  import opened PTX.FullHandRoll
  import opened GPU.H100
  import opened Core.Types
  import opened Core.Formulas

  datatype AtomicRMWBinOp =
    | RMW_Xchg | RMW_Add | RMW_Sub | RMW_And | RMW_Nand | RMW_Or | RMW_Xor
    | RMW_Max | RMW_Min | RMW_UMax | RMW_UMin
    | RMW_FAdd | RMW_FSub | RMW_FMax | RMW_FMin
    | RMW_UIncWrap | RMW_UDecWrap

  function AtomicRMWBinOpName(op: AtomicRMWBinOp): string {
    match op
    case RMW_Xchg => "xchg"
    case RMW_Add => "add"
    case RMW_Sub => "sub"
    case RMW_And => "and"
    case RMW_Nand => "nand"
    case RMW_Or => "or"
    case RMW_Xor => "xor"
    case RMW_Max => "max"
    case RMW_Min => "min"
    case RMW_UMax => "umax"
    case RMW_UMin => "umin"
    case RMW_FAdd => "fadd"
    case RMW_FSub => "fsub"
    case RMW_FMax => "fmax"
    case RMW_FMin => "fmin"
    case RMW_UIncWrap => "uinc_wrap"
    case RMW_UDecWrap => "udec_wrap"
  }

  datatype AtomicOrdering =
    | AO_NotAtomic | AO_Unordered | AO_Monotonic
    | AO_Acquire | AO_Release | AO_AcquireRelease | AO_SequentiallyConsistent

  function AtomicOrderingName(o: AtomicOrdering): string {
    match o
    case AO_NotAtomic => "not_atomic"
    case AO_Unordered => "unordered"
    case AO_Monotonic => "monotonic"
    case AO_Acquire => "acquire"
    case AO_Release => "release"
    case AO_AcquireRelease => "acq_rel"
    case AO_SequentiallyConsistent => "seq_cst"
  }

  predicate OrderingStrongerOrEqual(a: AtomicOrdering, b: AtomicOrdering) {
    a == AO_SequentiallyConsistent || a == b || (a.AO_AcquireRelease? && (b.AO_Acquire? || b.AO_Release? || b.AO_Monotonic?))
  }

  datatype SyncScope =
    | SS_System | SS_SingleThread | SS_CTA | SS_Custom(name: string)

  function SyncScopeName(s: SyncScope): string {
    match s
    case SS_System => "system"
    case SS_SingleThread => "singlethread"
    case SS_CTA => "cta"
    case SS_Custom(n) => n
  }

  datatype AtomicRMWInstr =
    AtomicRMWInstr(
      dst: LLVMVal, binop: AtomicRMWBinOp, ptr: LLVMVal, val: LLVMVal,
      ordering: AtomicOrdering, scope: SyncScope, volatile: bool, align: nat
    )

  predicate ValidAtomicRMW(i: AtomicRMWInstr) {
    ValidLLVMVal(i.dst) && ValidLLVMVal(i.ptr) && ValidLLVMVal(i.val) && i.align > 0
  }

  function PTXAtomicToRMW(op: AtomicOp): AtomicRMWBinOp {
    match op
    case AtomAdd => RMW_Add
    case AtomSub => RMW_Sub
    case AtomExch => RMW_Xchg
    case AtomMin => RMW_Min
    case AtomMax => RMW_Max
    case AtomAnd => RMW_And
    case AtomOr => RMW_Or
    case AtomXor => RMW_Xor
    case AtomCAS => RMW_Xchg
    case AtomInc => RMW_UIncWrap
    case AtomDec => RMW_UDecWrap
  }

  function NVVMAtomicIntrinsic(op: AtomicRMWBinOp, bits: nat, addrspace: nat): string {
    var space := if addrspace == 1 then "gen" else if addrspace == 3 then "shared" else "gen";
    var ty := if bits == 32 then "i32" else "i64";
    match op
    case RMW_Add => "llvm.nvvm.atomic.add." + space + ".i." + ty
    case RMW_Xchg => "llvm.nvvm.atomic.exch." + space + ".i." + ty
    case RMW_Min => "llvm.nvvm.atomic.min." + space + ".i." + ty
    case RMW_Max => "llvm.nvvm.atomic.max." + space + ".i." + ty
    case RMW_And => "llvm.nvvm.atomic.and." + space + ".i." + ty
    case RMW_Or => "llvm.nvvm.atomic.or." + space + ".i." + ty
    case RMW_Xor => "llvm.nvvm.atomic.xor." + space + ".i." + ty
    case RMW_UIncWrap => "llvm.nvvm.atomic.inc." + space + ".i." + ty
    case RMW_UDecWrap => "llvm.nvvm.atomic.dec." + space + ".i." + ty
    case _ => "llvm.nvvm.atomic.add." + space + ".i." + ty
  }

  function EmitAtomicRMW(i: AtomicRMWInstr): seq<LLVMInstr>
    requires ValidAtomicRMW(i)
  {
    var bits := LLVMTypeWidth(i.val.ty);
    var aspace := match i.ptr case LV_reg(_, LT_ptr(_, a)) => a case _ => 1;
    if i.binop == RMW_Add || i.binop == RMW_Xchg || i.binop == RMW_Min || i.binop == RMW_Max ||
       i.binop == RMW_And || i.binop == RMW_Or || i.binop == RMW_Xor then
      [LI_call(i.dst, NVVMAtomicIntrinsic(i.binop, bits, aspace), [i.ptr, i.val])]
    else
      [LI_atomicrmw(i.dst, AtomicRMWBinOpName(i.binop), i.ptr, i.val, AtomicOrderingName(i.ordering))]
  }

  datatype CmpXchgInstr =
    CmpXchgInstr(
      dst: LLVMVal, ptr: LLVMVal, cmp: LLVMVal, newv: LLVMVal,
      successOrd: AtomicOrdering, failureOrd: AtomicOrdering,
      scope: SyncScope, weak: bool, volatile: bool, align: nat
    )

  predicate ValidCmpXchg(i: CmpXchgInstr) {
    ValidLLVMVal(i.dst) && ValidLLVMVal(i.ptr) && ValidLLVMVal(i.cmp) && ValidLLVMVal(i.newv) &&
    i.align > 0 && OrderingStrongerOrEqual(i.successOrd, i.failureOrd)
  }

  function EmitCmpXchg(i: CmpXchgInstr): seq<LLVMInstr>
    requires ValidCmpXchg(i)
  {
    var bits := LLVMTypeWidth(i.cmp.ty);
    var intr := if bits == 64 then "llvm.nvvm.atomic.cas.gen.i.i64" else "llvm.nvvm.atomic.cas.gen.i.i32";
    [LI_call(i.dst, intr, [i.ptr, i.cmp, i.newv])]
  }

  lemma Lemma_BinOpName_nonempty(op: AtomicRMWBinOp)
    ensures |AtomicRMWBinOpName(op)| > 0
  {}

  lemma Lemma_OrderingName_nonempty(o: AtomicOrdering)
    ensures |AtomicOrderingName(o)| > 0
  {}

  lemma Lemma_SeqCst_strongest(o: AtomicOrdering)
    ensures OrderingStrongerOrEqual(AO_SequentiallyConsistent, o)
  {}

  lemma Lemma_Ordering_refl(o: AtomicOrdering)
    ensures OrderingStrongerOrEqual(o, o)
  {}

  lemma Lemma_ValidCmpXchg_orders(i: CmpXchgInstr)
    requires ValidCmpXchg(i)
    ensures OrderingStrongerOrEqual(i.successOrd, i.failureOrd)
  {}

  lemma Lemma_EmitAtomicRMW_nonempty(i: AtomicRMWInstr)
    requires ValidAtomicRMW(i)
    ensures |EmitAtomicRMW(i)| >= 1
  {}

  lemma Lemma_EmitCmpXchg_nonempty(i: CmpXchgInstr)
    requires ValidCmpXchg(i)
    ensures |EmitCmpXchg(i)| >= 1
  {}
}
