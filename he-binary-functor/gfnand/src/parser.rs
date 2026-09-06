pub enum Dtype {
    Float32,
    Float16,
    Int8,
    Uint8,
}

impl Dtype {
    pub fn element_bytes(&self) -> usize {
        match self {
            Dtype::Float32 => 4,
            Dtype::Float16 => 2,
            Dtype::Int8 | Dtype::Uint8 => 1,
        }
    }
}

#[derive(Debug, Clone)]
pub struct TensorDescriptor {
    pub id: u32,
    pub shape: Vec<usize>,
    pub dtype: Dtype,
}

impl TensorDescriptor {
    pub fn element_count(&self) -> usize {
        self.shape.iter().product()
    }

    pub fn byte_size(&self) -> usize {
        self.element_count() * self.dtype.element_bytes()
    }
}

#[derive(Debug, Clone)]
pub enum Operator {
    MatMul { a: TensorDescriptor, b: TensorDescriptor, out: TensorDescriptor },
    Conv2D { input: TensorDescriptor, weight: TensorDescriptor, out: TensorDescriptor, stride: usize, padding: usize },
    ElementwiseAdd { a: TensorDescriptor, b: TensorDescriptor, out: TensorDescriptor },
    ReLU { input: TensorDescriptor, out: TensorDescriptor },
}

#[derive(Debug, Clone)]
pub struct OperatorRecord {
    pub id: u32,
    pub op: Operator,
    pub param_count: usize,
    pub flop_count: u64,
    pub memory_bytes: usize,
}

pub fn analyze_operator(id: u32, op: Operator) -> OperatorRecord {
    let (param_count, flop_count, memory_bytes) = match &op {
        Operator::MatMul { a, b, out } => {
            let m = a.shape[0];
            let k = a.shape[1];
            let n = b.shape[1];
            let params = b.element_count();
            let flops = 2 * (m as u64) * (n as u64) * (k as u64);
            let bytes = a.byte_size() + b.byte_size() + out.byte_size();
            (params, flops, bytes)
        }
        Operator::Conv2D { weight, out, .. } => {
            let params = weight.element_count();
            let c_in = weight.shape[1];
            let k_h = weight.shape[2];
            let k_w = weight.shape[3];
            let out_elements = out.element_count() as u64;
            let flops = 2 * out_elements * ((c_in * k_h * k_w) as u64);
            let bytes = weight.byte_size() + out.byte_size();
            (params, flops, bytes)
        }
        Operator::ElementwiseAdd { a, b, out } => {
            let flops = a.element_count() as u64;
            let bytes = a.byte_size() + b.byte_size() + out.byte_size();
            (0, flops, bytes)
        }
        Operator::ReLU { input, out } => {
            let flops = input.element_count() as u64;
            let bytes = input.byte_size() + out.byte_size();
            (0, flops, bytes)
        }
    };

    OperatorRecord { id, op, param_count, flop_count, memory_bytes }
}
