// ============================================================================
// formal-engine/LLVM/Backend.dfy
// Hand-rolled LLVM-IR abstract syntax + instruction selection
// License: GPL 2.0
// ============================================================================

module LLVM.Backend {

  import opened Core.Types
  import opened Core.Terms
  import opened Core.Formulas
  import opened GPU.H100
  import opened PTX.FullHandRoll
  import opened PTX.AtomicsBarriers
  import opened CUDA.CooperativeGroups

  datatype LLVMType =
    | LT_void
    | LT_i1 | LT_i8 | LT_i16 | LT_i32 | LT_i64
    | LT_f16 | LT_f32 | LT_f64
    | LT_ptr(pointee: LLVMType, addrspace: nat)
    | LT_array(len: nat, elem: LLVMType)
    | LT_vector(len: nat, elem: LLVMType)
    | LT_struct(fields: seq<LLVMType>)
    | LT_fn(ret: LLVMType, args: seq<LLVMType>)

  predicate ValidLLVMType(t: LLVMType) {
    match t
    case LT_ptr(p, _) => ValidLLVMType(p)
    case LT_array(_, e) => ValidLLVMType(e)
    case LT_vector(n, e) => n > 0 && ValidLLVMType(e)
    case LT_struct(fs) => forall i :: 0 <= i < |fs| ==> ValidLLVMType(fs[i])
    case LT_fn(r, a) => ValidLLVMType(r) && forall i :: 0 <= i < |a| ==> ValidLLVMType(a[i])
    case _ => true
  }

  function LLVMTypeWidth(t: LLVMType): nat {
    match t
    case LT_i1 => 1
    case LT_i8 | LT_f16 => 8
    case LT_i16 => 16
    case LT_i32 | LT_f32 => 32
    case LT_i64 | LT_f64 => 64
    case LT_ptr(_, _) => 64
    case _ => 0
  }

  datatype LLVMVal =
    | LV_reg(id: nat, ty: LLVMType)
    | LV_imm_int(v: int, ty: LLVMType)
    | LV_imm_float(v: int, ty: LLVMType)
    | LV_global(name: string, ty: LLVMType)
    | LV_undef(ty: LLVMType)
    | LV_null(ty: LLVMType)
    | LV_blockaddr(fn: string, blk: string)

  predicate ValidLLVMVal(v: LLVMVal) {
    match v
    case LV_reg(_, t) => ValidLLVMType(t)
    case LV_imm_int(_, t) => ValidLLVMType(t)
    case LV_imm_float(_, t) => ValidLLVMType(t)
    case LV_global(_, t) => ValidLLVMType(t)
    case LV_undef(t) => ValidLLVMType(t)
    case LV_null(t) => ValidLLVMType(t)
    case LV_blockaddr(_, _) => true
  }

  datatype LLVMICmpPred = ICMP_EQ | ICMP_NE | ICMP_UGT | ICMP_UGE | ICMP_ULT | ICMP_ULE
                        | ICMP_SGT | ICMP_SGE | ICMP_SLT | ICMP_SLE

  datatype LLVMInstr =
    | LI_ret(v: LLVMVal)
    | LI_br(cond: LLVMVal, tlab: string, flab: string)
    | LI_br_uncond(lab: string)
    | LI_add(dst: LLVMVal, lhs: LLVMVal, rhs: LLVMVal, nsw: bool, nuw: bool)
    | LI_sub(dst: LLVMVal, lhs: LLVMVal, rhs: LLVMVal, nsw: bool, nuw: bool)
    | LI_mul(dst: LLVMVal, lhs: LLVMVal, rhs: LLVMVal, nsw: bool, nuw: bool)
    | LI_udiv(dst: LLVMVal, lhs: LLVMVal, rhs: LLVMVal)
    | LI_sdiv(dst: LLVMVal, lhs: LLVMVal, rhs: LLVMVal)
    | LI_and(dst: LLVMVal, lhs: LLVMVal, rhs: LLVMVal)
    | LI_or(dst: LLVMVal, lhs: LLVMVal, rhs: LLVMVal)
    | LI_xor(dst: LLVMVal, lhs: LLVMVal, rhs: LLVMVal)
    | LI_shl(dst: LLVMVal, lhs: LLVMVal, rhs: LLVMVal)
    | LI_lshr(dst: LLVMVal, lhs: LLVMVal, rhs: LLVMVal)
    | LI_ashr(dst: LLVMVal, lhs: LLVMVal, rhs: LLVMVal)
    | LI_load(dst: LLVMVal, ptr: LLVMVal, align: nat)
    | LI_store(val: LLVMVal, ptr: LLVMVal, align: nat)
    | LI_gep(dst: LLVMVal, ptr: LLVMVal, idxs: seq<LLVMVal>)
    | LI_icmp(dst: LLVMVal, pred: LLVMICmpPred, lhs: LLVMVal, rhs: LLVMVal)
    | LI_select(dst: LLVMVal, cond: LLVMVal, tval: LLVMVal, fval: LLVMVal)
    | LI_call(dst: LLVMVal, callee: string, args: seq<LLVMVal>)
    | LI_phi(dst: LLVMVal, incs: seq<(LLVMVal, string)>)
    | LI_alloca(dst: LLVMVal, ty: LLVMType, align: nat)
    | LI_zext(dst: LLVMVal, src: LLVMVal)
    | LI_sext(dst: LLVMVal, src: LLVMVal)
    | LI_trunc(dst: LLVMVal, src: LLVMVal)
    | LI_bitcast(dst: LLVMVal, src: LLVMVal)
    | LI_atomicrmw(dst: LLVMVal, op: string, ptr: LLVMVal, val: LLVMVal, ord: string)
    | LI_cmpxchg(dst: LLVMVal, ptr: LLVMVal, cmp: LLVMVal, new: LLVMVal, ord: string)
    | LI_fence(ord: string)
    | LI_unreachable
    | LI_label(name: string)

  predicate ValidLLVMInstr(i: LLVMInstr) { true }

  datatype LLVMBlock =
    LLVMBlock(name: string, instrs: seq<LLVMInstr>)

  predicate ValidLLVMBlock(b: LLVMBlock) {
    |b.name| > 0 && forall i :: 0 <= i < |b.instrs| ==> ValidLLVMInstr(b.instrs[i])
  }

  datatype LLVMParam = LLVMParam(name: string, ty: LLVMType)

  datatype LLVMFunction =
    LLVMFunction(
      name: string,
      retTy: LLVMType,
      params: seq<LLVMParam>,
      blocks: seq<LLVMBlock>,
      isKernel: bool,
      conv: string
    )

  predicate ValidLLVMFunction(f: LLVMFunction) {
    |f.name| > 0 &&
    ValidLLVMType(f.retTy) &&
    forall i :: 0 <= i < |f.params| ==> ValidLLVMType(f.params[i].ty) &&
    forall i :: 0 <= i < |f.blocks| ==> ValidLLVMBlock(f.blocks[i])
  }

  datatype LLVMModule =
    LLVMModule(
      triple: string,
      datalayout: string,
      functions: seq<LLVMFunction>,
      globals: seq<(string, LLVMType)>
    )

  predicate ValidLLVMModule(m: LLVMModule) {
    forall i :: 0 <= i < |m.functions| ==> ValidLLVMFunction(m.functions[i])
  }

  function PTXTypeToLLVM(t: PTXType): LLVMType {
    match t
    case PTXPred => LT_i1
    case PTX_u8 | PTX_s8 => LT_i8
    case PTX_u16 | PTX_s16 | PTX_b16 | PTX_f16 => LT_i16
    case PTX_u32 | PTX_s32 | PTX_b32 | PTX_f32 => LT_i32
    case PTX_u64 | PTX_s64 | PTX_b64 | PTX_f64 => LT_i64
    case PTXPtr(sp) => LT_ptr(LT_i8, MatchAddrSpace(sp))
  }

  function MatchAddrSpace(sp: MemSpace): nat {
    match sp
    case Global => 1
    case Shared => 3
    case Local => 5
    case Constant => 4
  }

  function MapReg(r: PTXReg, ty: LLVMType): LLVMVal {
    match r
    case R(n) => LV_reg(n, ty)
    case P(n) => LV_reg(1000 + n, LT_i1)
    case Spec(name) => LV_global(name, ty)
  }

  function MapOperand(op: PTXOperand, ty: LLVMType): LLVMVal {
    match op
    case OpReg(r) => MapReg(r, ty)
    case OpImm(v) => LV_imm_int(v, ty)
    case OpLabel(l) => LV_blockaddr("", l)
    case OpAddr(base, off, sp) =>
      MapReg(base, LT_ptr(ty, MatchAddrSpace(sp)))
    case OpVec(_) => LV_undef(ty)
  }

  function SelectInstr(ins: PTXInstr, nextReg: nat): (seq<LLVMInstr>, nat)
    requires ValidPTXInstr(ins)
  {
    var ty := PTXTypeToLLVM(ins.dtype);
    match ins.opc
    case OPC_MOV =>
      var dst := MapOperand(ins.dst, ty);
      var src := MapOperand(ins.src0, ty);
      ([LI_bitcast(dst, src)], nextReg)
    case OPC_ADD | OPC_FADD =>
      var dst := MapOperand(ins.dst, ty);
      var a := MapOperand(ins.src0, ty);
      var b := MapOperand(ins.src1, ty);
      ([LI_add(dst, a, b, false, false)], nextReg)
    case OPC_EXIT | OPC_RET =>
      ([LI_ret(LV_undef(LT_void))], nextReg)
    case OPC_NOP =>
      ([], nextReg)
    case _ =>
      ([LI_unreachable], nextReg)
  }

  function LowerKernel(k: PTXKernel): LLVMFunction
    requires ValidKernel(k)
  {
    var params := seq(|k.params|, i requires 0 <= i < |k.params| =>
      LLVMParam(k.params[i].name, PTXTypeToLLVM(k.params[i].ty)));
    var (instrs, _) := LowerInstrSeq(k.body, 0, 0);
    var entry := LLVMBlock("entry", instrs);
    LLVMFunction(k.name, LT_void, params, [entry], k.isEntry,
                 if k.isEntry then "ptx_kernel" else "ccc")
  }

  function LowerInstrSeq(body: seq<PTXInstr>, i: nat, nextReg: nat): (seq<LLVMInstr>, nat)
    requires forall j :: 0 <= j < |body| ==> ValidPTXInstr(body[j])
    decreases |body| - i
  {
    if i >= |body| then ([], nextReg)
    else
      var (ll, nr) := SelectInstr(body[i], nextReg);
      var (rest, nr2) := LowerInstrSeq(body, i + 1, nr);
      (ll + rest, nr2)
  }

  function LowerModule(ptx: PTXModule): LLVMModule
    requires ValidModule(ptx)
  {
    var fns := seq(|ptx.kernels|, i requires 0 <= i < |ptx.kernels| =>
      LowerKernel(ptx.kernels[i]));
    LLVMModule(
      "nvptx64-nvidia-cuda",
      "e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-f32:32:32-f64:64:64-v16:16:16-v32:32:32-v64:64:64-v128:128:128-n16:32:64",
      fns, [])
  }

  lemma LowerKernel_valid(k: PTXKernel)
    requires ValidKernel(k)
    ensures ValidLLVMFunction(LowerKernel(k))
  {}

  lemma LowerModule_valid(m: PTXModule)
    requires ValidModule(m)
    ensures ValidLLVMModule(LowerModule(m))
  {}

  function ShowType(t: LLVMType): string {
    match t
    case LT_void => "void"
    case LT_i1 => "i1"
    case LT_i8 => "i8"
    case LT_i16 => "i16"
    case LT_i32 => "i32"
    case LT_i64 => "i64"
    case LT_f32 => "float"
    case LT_f64 => "double"
    case LT_ptr(p, as) => ShowType(p) + " addrspace(" + NatStr(as) + ")*"
    case _ => "opaque"
  }

  function NatStr(n: nat): string {
    if n < 10 then [n as char + '0']
    else NatStr(n / 10) + [(n % 10) as char + '0']
  }
}
