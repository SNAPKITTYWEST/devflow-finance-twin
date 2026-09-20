// ============================================================================
// formal-engine/CUDA/CooperativeGroups.dfy
// CUDA Cooperative Groups abstract model
// License: GPL 2.0
// ============================================================================

module CUDA.CooperativeGroups {

  import opened Core.Types
  import opened Core.Terms
  import opened Core.Formulas
  import opened GPU.H100
  import opened PTX.AtomicsBarriers

  datatype GroupKind =
    | ThreadBlockGroup
    | GridGroup
    | CoalescedGroup
    | TiledPartition(size: nat)
    | ThreadGroup

  datatype Group =
    Group(
      kind: GroupKind,
      size: nat,
      rank: nat,
      metaGroupRank: nat,
      metaGroupSize: nat,
      isValid: bool
    )

  predicate ValidGroup(g: Group) {
    g.isValid ==> (g.rank < g.size && g.metaGroupRank < g.metaGroupSize)
  }

  function ThisThreadBlock(ts: TState, cfg: Config): Group
    requires ValidCfg(cfg)
    requires ValidTS(ts, cfg.bdim, cfg.maxR, cfg.maxP)
  {
    var sz := TPB(cfg.bdim);
    var rnk := LinTid(ts.tid, cfg.bdim);
    Group(ThreadBlockGroup, sz, rnk, 0, 1, true)
  }

  function ThisGrid(ts: TState, cfg: Config): Group
    requires ValidCfg(cfg)
    requires ValidTS(ts, cfg.bdim, cfg.maxR, cfg.maxP)
  {
    var blockId := ts.bid.x + cfg.gdim.x * (ts.bid.y + cfg.gdim.y * ts.bid.z);
    var gridSize := cfg.gdim.x * cfg.gdim.y * cfg.gdim.z;
    var threadsPerBlock := TPB(cfg.bdim);
    var globalRank := blockId * threadsPerBlock + LinTid(ts.tid, cfg.bdim);
    var globalSize := gridSize * threadsPerBlock;
    Group(GridGroup, globalSize, globalRank, 0, 1, true)
  }

  function CoalescedThreads(w: WState, lane: nat): Group
    requires lane < WS
  {
    var sz := 32;
    Group(CoalescedGroup, sz, lane, 0, 1, true)
  }

  function TiledPartition(parent: Group, tileSize: nat, localRank: nat): Group
    requires ValidGroup(parent)
    requires tileSize > 0
    requires localRank < tileSize
  {
    var metaSize := if parent.size % tileSize == 0
                    then parent.size / tileSize
                    else parent.size / tileSize + 1;
    var metaRank := parent.rank / tileSize;
    Group(TiledPartition(tileSize), tileSize, localRank, metaRank, metaSize, true)
  }

  datatype SyncResult =
    | SyncOK
    | SyncDivergence

  function GroupSync(g: Group, arrived: nat): SyncResult
    requires ValidGroup(g)
  {
    if arrived >= g.size then SyncOK else SyncDivergence
  }

  function Rank(g: Group): nat
    requires ValidGroup(g)
  { g.rank }

  function Size(g: Group): nat
    requires ValidGroup(g)
  { g.size }

  function MetaGroupRank(g: Group): nat
    requires ValidGroup(g)
  { g.metaGroupRank }

  function MetaGroupSize(g: Group): nat
    requires ValidGroup(g)
  { g.metaGroupSize }

  function ThreadRank(g: Group): nat
    requires ValidGroup(g)
  { g.rank }

  function Shfl(g: Group, value: int, srcLane: nat): int
    requires ValidGroup(g)
    requires g.kind.CoalescedGroup? || g.kind.TiledPartition?
  { value }

  function ShflDown(g: Group, value: int, delta: nat): int
    requires ValidGroup(g)
  { value }

  function ShflUp(g: Group, value: int, delta: nat): int
    requires ValidGroup(g)
  { value }

  function ShflXor(g: Group, value: int, laneMask: nat): int
    requires ValidGroup(g)
  { value }

  datatype ReduceOp = RedAdd | RedMin | RedMax | RedAnd | RedOr | RedXor

  function Reduce(g: Group, value: int, op: ReduceOp): int
    requires ValidGroup(g)
  { value }

  function InclusiveScan(g: Group, value: int, op: ReduceOp): int
    requires ValidGroup(g)
  { value }

  function ExclusiveScan(g: Group, value: int, op: ReduceOp): int
    requires ValidGroup(g)
  { value }

  predicate GroupRankInRange(g: Group) {
    ValidGroup(g) ==> g.rank < g.size
  }

  predicate TiledPartitionConsistent(parent: Group, tile: Group) {
    ValidGroup(parent) && ValidGroup(tile) &&
    tile.kind.TiledPartition? &&
    tile.metaGroupSize * tile.size >= parent.size
  }

  lemma ThisThreadBlock_valid(ts: TState, cfg: Config)
    requires ValidCfg(cfg) && ValidTS(ts, cfg.bdim, cfg.maxR, cfg.maxP)
    ensures ValidGroup(ThisThreadBlock(ts, cfg))
    ensures Rank(ThisThreadBlock(ts, cfg)) == LinTid(ts.tid, cfg.bdim)
    ensures Size(ThisThreadBlock(ts, cfg)) == TPB(cfg.bdim)
  {}

  lemma ThisGrid_valid(ts: TState, cfg: Config)
    requires ValidCfg(cfg) && ValidTS(ts, cfg.bdim, cfg.maxR, cfg.maxP)
    ensures ValidGroup(ThisGrid(ts, cfg))
  {}
}
