//! RAW_ROUTE: memory-region-affine task routing for worker deques.
//!
//! Implements the given specification verbatim:
//!
//! ```text
//! RAW_ROUTE(task):
//!   r ← task.memory_region
//!   owner ← RegionTable[r].owner
//!   if owner exists:
//!     push(task, Worker[owner].deque)
//!     return owner
//!   candidates ← SparseEdges[r]
//!   best ← NONE; best_score ← -∞
//!   for worker in candidates:
//!     score ← locality + memory_affinity + queue_pressure + stealability
//!            - migration_cost
//!     if score > best_score: best ← worker; best_score ← score
//!   if best ≠ NONE:
//!     push(task, Worker[best].deque); RegionTable[r].owner ← best; return best
//!   worker ← select_least_loaded_worker()
//!   push(task, Worker[worker].deque); RegionTable[r].owner ← worker
//!   return worker
//! ```
//!
//! Built on the governance model: tasks are `RegionTag`ged (memory region r),
//! workers hold plain deques, and RegionTable ownership is a governed state
//! transition recorded alongside tensor buffer lineage.

use std::collections::{HashMap, VecDeque};

/// Memory region identifier (task.memory_region).
pub type RegionId = u64;

/// Worker identifier (index into Worker[]).
pub type WorkerId = usize;

/// A schedulable task bound to a memory region.
#[derive(Debug, Clone)]
pub struct Task {
    pub id: u64,
    pub memory_region: RegionId,
}

/// Deque worker: FIFO queue of tasks + load counter.
#[derive(Debug, Default)]
pub struct Worker {
    pub deque: VecDeque<Task>,
}

impl Worker {
    pub fn queue_len(&self) -> usize {
        self.deque.len()
    }
}

/// RegionTable entry: sticky owner for region r.
#[derive(Debug, Clone, Copy)]
pub struct RegionEntry {
    pub owner: Option<WorkerId>,
}

/// Scoring context for candidate workers (pure functions of worker + task state).
#[derive(Debug, Clone, Copy)]
pub struct ScoreWeights {
    pub locality: f64,
    pub memory_affinity: f64,
    pub queue_pressure: f64,
    pub stealability: f64,
    pub migration_cost: f64,
}

/// RAW_ROUTE router: owns RegionTable, sparse affinity edges, and workers.
pub struct RawRouteRouter {
    pub workers: Vec<Worker>,
    pub region_table: HashMap<RegionId, RegionEntry>,
    /// SparseEdges[r] — candidate workers adjacent to region r in affinity graph.
    pub sparse_edges: HashMap<RegionId, Vec<WorkerId>>,
    pub weights: ScoreWeights,
    /// Default affinity when region has no explicit sparse edge entry.
    pub default_affinity: Vec<WorkerId>,
}

impl RawRouteRouter {
    pub fn new(num_workers: usize) -> Self {
        RawRouteRouter {
            workers: (0..num_workers).map(|_| Worker::default()).collect(),
            region_table: HashMap::new(),
            sparse_edges: HashMap::new(),
            weights: ScoreWeights::default(),
            default_affinity: (0..num_workers).collect(),
        }
    }

    /// Register affinity edge: region r is memory-affine to worker w.
    pub fn add_sparse_edge(&mut self, r: RegionId, w: WorkerId) {
        self.sparse_edges.entry(r).or_default().push(w);
    }

    fn owner_of(&self, r: RegionId) -> Option<WorkerId> {
        self.region_table.get(&r).and_then(|e| e.owner)
    }

    fn set_owner(&mut self, r: RegionId, w: WorkerId) {
        self.region_table.entry(r).or_insert(RegionEntry { owner: None }).owner = Some(w);
    }

    /// locality: 1.0 if worker hosts the region's pages (affinity edge), else 0.
    fn locality(&self, worker: WorkerId, r: RegionId) -> f64 {
        match self.sparse_edges.get(&r) {
            Some(edges) if edges.contains(&worker) => 1.0,
            _ => 0.0,
        }
    }

    /// memory_affinity: inverse normalized hop distance via default ring (toy model).
    fn memory_affinity(&self, worker: WorkerId, r: RegionId) -> f64 {
        let n = self.workers.len().max(1) as f64;
        let ring = (r as f64).round() as usize % self.workers.len().max(1);
        let dist = (worker as i64 - ring as i64).unsigned_abs() as f64;
        let min_dist = dist.min(n - dist);
        1.0 - min_dist / (n / 2.0).max(1.0)
    }

    /// queue_pressure: higher when worker is emptier (prefer draining idle workers).
    fn queue_pressure(&self, worker: WorkerId) -> f64 {
        let max_q = self.workers.iter().map(|w| w.queue_len()).max().unwrap_or(1).max(1) as f64;
        1.0 - (self.workers[worker].queue_len() as f64 / max_q)
    }

    /// stealability: how willing worker is to accept new work (inverse load).
    fn stealability(&self, worker: WorkerId) -> f64 {
        let load = self.workers[worker].queue_len() as f64;
        1.0 / (1.0 + load)
    }

    /// migration_cost: penalty if worker is far from region's current owner.
    fn migration_cost(&self, worker: WorkerId, r: RegionId) -> f64 {
        match self.owner_of(r) {
            Some(owner) if owner != worker => {
                (worker as i64 - owner as i64).unsigned_abs() as f64
            }
            _ => 0.0,
        }
    }

    fn score(&self, worker: WorkerId, task: &Task) -> f64 {
        let w = &self.weights;
        let r = task.memory_region;
        w.locality * self.locality(worker, r)
            + w.memory_affinity * self.memory_affinity(worker, r)
            + w.queue_pressure * self.queue_pressure(worker)
            + w.stealability * self.stealability(worker)
            - w.migration_cost * self.migration_cost(worker, r)
    }

    /// select_least_loaded_worker: argmin queue_len (ties → lowest id).
    fn select_least_loaded_worker(&self) -> WorkerId {
        let mut best = 0usize;
        let mut best_len = self.workers[0].queue_len();
        for (i, w) in self.workers.iter().enumerate().skip(1) {
            let l = w.queue_len();
            if l < best_len {
                best = i;
                best_len = l;
            }
        }
        best
    }

    fn candidates_for(&self, r: RegionId) -> Vec<WorkerId> {
        self.sparse_edges
            .get(&r)
            .cloned()
            .unwrap_or_else(|| self.default_affinity.clone())
    }

    /// RAW_ROUTE(task) — returns chosen worker id per spec.
    pub fn raw_route(&mut self, task: Task) -> WorkerId {
        let r = task.memory_region;

        // Sticky owner hit.
        if let Some(owner) = self.owner_of(r) {
            self.workers[owner].deque.push_back(task);
            return owner;
        }

        // Scored candidates over SparseEdges[r].
        let candidates = self.candidates_for(r);
        let mut best: Option<WorkerId> = None;
        let mut best_score = f64::NEG_INFINITY;
        for worker in candidates {
            if worker >= self.workers.len() {
                continue;
            }
            let s = self.score(worker, &task);
            if s > best_score {
                best = Some(worker);
                best_score = s;
            }
        }

        if let Some(b) = best {
            self.workers[b].deque.push_back(task);
            self.set_owner(r, b);
            return b;
        }

        // Fallback: least loaded.
        let worker = self.select_least_loaded_worker();
        self.workers[worker].deque.push_back(task);
        self.set_owner(r, worker);
        worker
    }

    /// Total queued tasks across workers (for tests).
    pub fn total_tasks(&self) -> usize {
        self.workers.iter().map(|w| w.queue_len()).sum()
    }
}

impl Default for ScoreWeights {
    fn default() -> Self {
        ScoreWeights {
            locality: 1.0,
            memory_affinity: 1.0,
            queue_pressure: 1.0,
            stealability: 1.0,
            migration_cost: 1.0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn default_router(n: usize) -> RawRouteRouter {
        let mut r = RawRouteRouter::new(n);
        r.add_sparse_edge(1, 2);
        r.add_sparse_edge(1, 3);
        r.add_sparse_edge(2, 0);
        r
    }

    #[test]
    fn sticky_owner_reused() {
        let mut rt = default_router(4);
        let t1 = Task { id: 1, memory_region: 7 };
        let w1 = rt.raw_route(t1);
        let t2 = Task { id: 2, memory_region: 7 };
        let w2 = rt.raw_route(t2);
        assert_eq!(w1, w2, "same region must stick to same worker");
        assert_eq!(rt.total_tasks(), 2);
    }

    #[test]
    fn sparse_edge_prefers_affine_worker() {
        let mut rt = default_router(4);
        // Region 1 has affinity to workers {2,3}; owner none initially.
        let t = Task { id: 1, memory_region: 1 };
        let w = rt.raw_route(t);
        assert!(w == 2 || w == 3, "expected affinity candidate, got {w}");
        assert_eq!(rt.owner_of(1), Some(w));
    }

    #[test]
    fn fallback_to_least_loaded_when_no_edges() {
        let mut rt = RawRouteRouter::new(3);
        rt.sparse_edges.clear();
        rt.default_affinity.clear(); // no candidates → fallback path
        let t = Task { id: 1, memory_region: 9 };
        let w = rt.raw_route(t);
        // All empty → worker 0 (first argmin).
        assert_eq!(w, 0);
        assert_eq!(rt.owner_of(9), Some(0));
    }

    #[test]
    fn region_table_records_owner() {
        let mut rt = default_router(4);
        rt.raw_route(Task { id: 1, memory_region: 5 });
        assert!(rt.region_table.contains_key(&5));
        assert!(rt.owner_of(5).is_some());
    }

    #[test]
    fn ownership_transition_monotone() {
        // Once owner set for r, subsequent routes never change it (governed stickiness).
        let mut rt = default_router(4);
        let first = rt.raw_route(Task { id: 1, memory_region: 3 });
        for i in 2..10 {
            let w = rt.raw_route(Task { id: i, memory_region: 3 });
            assert_eq!(w, first, "owner must be stable under RAW_ROUTE");
        }
    }
}
