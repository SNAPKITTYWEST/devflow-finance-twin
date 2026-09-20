// ============================================================================
// formal-engine/Proofs/GPUInvariants.dfy
// Proved invariants of the H100 abstract machine
// License: GPL 2.0
// ============================================================================

module Proofs.GPUInvariants {

  import opened GPU.H100

  lemma InitTS_active(tid: ThreadId, bid: BlockId)
    ensures InitTS(tid, bid).act
    ensures !InitTS(tid, bid).done
    ensures InitTS(tid, bid).pc == 0
  {}

  lemma InitWS_size(id: nat, bid: BlockId, bdim: BlockDim)
    ensures |InitWS(id, bid, bdim).th| == WS
  {}

  lemma TPB_positive(b: BlockDim)
    requires b.x > 0 && b.y > 0 && b.z > 0
    ensures TPB(b) > 0
  {}

  lemma ValidCfg_implies_positive_dims(c: Config)
    requires ValidCfg(c)
    ensures c.gdim.x > 0 && c.bdim.x > 0
  {}

  lemma InvGPU_implies_ValidGPU(g: GPUState)
    requires InvGPU(g)
    ensures ValidGPU(g)
  {}
}
