(* Reference Interpreter for RetroGPU IR - semantic oracle *)
structure Interpreter =
struct
  open RetroGPUCore
  open ALU
  open Kernel

  type RegFile = int Array.array (* simplified value store *)

  fun newRegs n = Array.array (n, 0)

  fun execAlu (rf : RegFile, AluInst i) =
    let
      fun get (OpReg r) = Array.sub (rf, r)
        | get (OpImm v) = v
        | get _ = 0
      fun set (OpReg r, v) = Array.update (rf, r, v)
        | set _ = ()
      val a = get (#src0 i)
      val b = get (#src1 i)
      val res = case #op i of
                    ADD => evalInt ADD a b
                  | SUB => evalInt SUB a b
                  | MUL => evalInt MUL a b
                  | AND => evalInt AND a b
                  | OR => evalInt OR a b
                  | XOR => evalInt XOR a b
                  | _ => a
    in
      set (#dst i, res)
    end

  fun runBlock (rf, BB {insts, ...}) =
    List.app (fn i => execAlu (rf, i)) insts

  fun runKernel (KernelDef k, regCount) =
    let
      val rf = newRegs regCount
    in
      List.app (fn b => runBlock (rf, b)) (#blocks k);
      rf
    end
end
