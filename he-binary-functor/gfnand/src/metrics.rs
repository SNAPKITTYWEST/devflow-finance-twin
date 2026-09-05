pub struct NandConversionMetrics {
    pub flop_count: u64,
    pub nand_node_count: usize,
    pub nand_depth: usize,
    pub memory_bytes: usize,
    pub estimated_cycles: u64,
}

pub fn calculate_metrics(op_type: &str, bit_width: usize, count: u64) -> NandConversionMetrics {
    let (gates_per_op, depth_per_op) = match op_type {
        "ADD" => (9 * bit_width, 3 * bit_width + 2),
        "MUL" => (9 * bit_width * bit_width - 15 * bit_width + 6, 6 * bit_width - 4),
        "MAC" => (9 * bit_width * bit_width - 6 * bit_width + 6, 6 * bit_width + 2),
        _ => (0, 0),
    };

    let total_gates = gates_per_op * (count as usize);

    NandConversionMetrics {
        flop_count: if op_type == "MAC" { 2 * count } else { count },
        nand_node_count: total_gates,
        nand_depth: depth_per_op,
        memory_bytes: ((bit_width * 2) / 8) * (count as usize),
        estimated_cycles: (depth_per_op as u64) * count,
    }
}
