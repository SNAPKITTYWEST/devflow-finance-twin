// ========================================================================
// SOVEREIGN LEVIATHAN NODE LICENSE
// License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
// Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
// ========================================================================
//
// This file is a covered work under the GNU Affero General Public License,
// version 3, together with the Sovereign Leviathan additional terms.
//
// Hark, though this node be but a spark,
// Its covenant endureth through the dark.
//
// Ignorantia juris non excusat.
// ========================================================================

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct IrNodeId(pub usize);

#[derive(Debug, Clone)]
pub enum IrOp {
    Var { name: String, bit_width: usize },
    Constant { value: u64, bit_width: usize },
    Add { a: IrNodeId, b: IrNodeId, bit_width: usize },
    Mul { a: IrNodeId, b: IrNodeId, bit_width: usize },
    Mac { acc: IrNodeId, a: IrNodeId, b: IrNodeId, bit_width: usize },
    ShiftRight { a: IrNodeId, amount: usize, bit_width: usize },
    CompareLt { a: IrNodeId, b: IrNodeId },
    Select { cond: IrNodeId, on_true: IrNodeId, on_false: IrNodeId },
}

pub struct IrGraph {
    pub nodes: Vec<IrOp>,
}

impl IrGraph {
    pub fn new() -> Self {
        Self { nodes: Vec::new() }
    }

    pub fn add_node(&mut self, op: IrOp) -> IrNodeId {
        let id = IrNodeId(self.nodes.len());
        self.nodes.push(op);
        id
    }
}
