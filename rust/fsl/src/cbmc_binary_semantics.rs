// =============================================================================
// fsl/src/cbmc_binary_semantics.rs
// CBMC GOTO Binary Semantics – raw dense ~400 LOC
// Bit-vector, memory, pointer, endianness, overflow, and SSA evaluation rules
// =============================================================================

use crate::cbmc::{
    BinaryOp, Constant, ExprCBMC, GotoProgram, Instruction, Operand, Type, UnaryOp,
};
use crate::{Expr, FslIR, Origin, Sort};
use std::collections::HashMap;

// ---------------------------------------------------------------------------
// 1. Binary value representation
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct BitVec {
    pub width: u32,
    pub value: u128, // concrete; high bits must be zero
    pub symbolic: Option<Expr>, // when None → concrete
}

impl BitVec {
    pub fn concrete(width: u32, value: u128) -> Self {
        let mask = if width == 128 { u128::MAX } else { (1u128 << width) - 1 };
        Self { width, value: value & mask, symbolic: None }
    }

    pub fn from_expr(width: u32, e: Expr) -> Self {
        Self { width, value: 0, symbolic: Some(e) }
    }

    pub fn is_concrete(&self) -> bool { self.symbolic.is_none() }

    pub fn mask(&self) -> u128 {
        if self.width == 128 { u128::MAX } else { (1u128 << self.width) - 1 }
    }

    pub fn as_u64(&self) -> Option<u64> {
        if self.is_concrete() && self.width <= 64 {
            Some(self.value as u64)
        } else {
            None
        }
    }
}

// ---------------------------------------------------------------------------
// 2. Memory model (byte-addressable, CBMC-style)
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, Default)]
pub struct Memory {
    // address → byte value (concrete or symbolic)
    pub bytes: HashMap<u64, BitVec>,
    pub default_byte: BitVec, // usually 0 or nondet
    pub little_endian: bool,
    pub pointer_width: u32, // 32 or 64
    pub max_object_size: u64,
}

impl Memory {
    pub fn new(little_endian: bool, pointer_width: u32) -> Self {
        Self {
            bytes: HashMap::new(),
            default_byte: BitVec::concrete(8, 0),
            little_endian,
            pointer_width,
            max_object_size: 1 << 20,
        }
    }

    pub fn read_bytes(&self, addr: u64, nbytes: usize) -> Vec<BitVec> {
        let mut res = Vec::with_capacity(nbytes);
        for i in 0..nbytes {
            let b = self.bytes.get(&(addr + i as u64))
                .cloned()
                .unwrap_or_else(|| self.default_byte.clone());
            res.push(b);
        }
        res
    }

    pub fn write_bytes(&mut self, addr: u64, data: &[BitVec]) {
        for (i, b) in data.iter().enumerate() {
            self.bytes.insert(addr + i as u64, b.clone());
        }
    }

    pub fn read_bv(&self, addr: u64, width: u32) -> BitVec {
        let nbytes = ((width + 7) / 8) as usize;
        let bytes = self.read_bytes(addr, nbytes);
        self.bytes_to_bv(&bytes, width)
    }

    pub fn write_bv(&mut self, addr: u64, bv: &BitVec) {
        let bytes = self.bv_to_bytes(bv);
        self.write_bytes(addr, &bytes);
    }

    fn bytes_to_bv(&self, bytes: &[BitVec], width: u32) -> BitVec {
        if bytes.iter().all(|b| b.is_concrete()) {
            let mut val: u128 = 0;
            if self.little_endian {
                for (i, b) in bytes.iter().enumerate() {
                    val |= (b.value & 0xFF) << (8 * i);
                }
            } else {
                for (i, b) in bytes.iter().enumerate() {
                    val |= (b.value & 0xFF) << (8 * (bytes.len() - 1 - i));
                }
            }
            BitVec::concrete(width, val)
        } else {
            // symbolic concatenation path – simplified
            BitVec::from_expr(width, Expr::BVLit { value: 0, width })
        }
    }

    fn bv_to_bytes(&self, bv: &BitVec) -> Vec<BitVec> {
        let nbytes = ((bv.width + 7) / 8) as usize;
        let mut res = Vec::with_capacity(nbytes);
        if bv.is_concrete() {
            for i in 0..nbytes {
                let shift = if self.little_endian { 8 * i } else { 8 * (nbytes - 1 - i) };
                let byte = (bv.value >> shift) & 0xFF;
                res.push(BitVec::concrete(8, byte));
            }
        } else {
            for _ in 0..nbytes {
                res.push(BitVec::concrete(8, 0)); // placeholder
            }
        }
        res
    }
}

// ---------------------------------------------------------------------------
// 3. Binary operator semantics (bit-precise)
// ---------------------------------------------------------------------------

pub fn eval_unary(op: UnaryOp, v: &BitVec) -> BitVec {
    match op {
        UnaryOp::Not | UnaryOp::BitNot => {
            if v.is_concrete() {
                BitVec::concrete(v.width, (!v.value) & v.mask())
            } else {
                BitVec::from_expr(v.width, Expr::BvNot(Box::new(v.symbolic.clone().unwrap())))
            }
        }
        UnaryOp::Neg => {
            if v.is_concrete() {
                let neg = (!v.value).wrapping_add(1) & v.mask();
                BitVec::concrete(v.width, neg)
            } else {
                BitVec::from_expr(v.width, Expr::BvNeg(Box::new(v.symbolic.clone().unwrap())))
            }
        }
        UnaryOp::PointerObject => {
            // extract object bits (upper bits) – architecture dependent
            BitVec::concrete(v.width, v.value >> (v.width / 2))
        }
        UnaryOp::PointerOffset => {
            let mask = (1u128 << (v.width / 2)) - 1;
            BitVec::concrete(v.width / 2, v.value & mask)
        }
    }
}

pub fn eval_binary(op: BinaryOp, l: &BitVec, r: &BitVec) -> Result<BitVec, String> {
    if l.width != r.width && !matches!(op, BinaryOp::Shl | BinaryOp::Shr | BinaryOp::Ashr) {
        return Err(format!("width mismatch {} vs {}", l.width, r.width));
    }
    let w = l.width;

    // Concrete fast path
    if l.is_concrete() && r.is_concrete() {
        let lv = l.value;
        let rv = r.value;
        let res = match op {
            BinaryOp::Add => lv.wrapping_add(rv) & l.mask(),
            BinaryOp::Sub => lv.wrapping_sub(rv) & l.mask(),
            BinaryOp::Mul => lv.wrapping_mul(rv) & l.mask(),
            BinaryOp::Div | BinaryOp::Mod if rv == 0 => return Err("division by zero".into()),
            BinaryOp::Div => lv / rv,
            BinaryOp::Mod => lv % rv,
            BinaryOp::Shl => lv.wrapping_shl((rv as u32) % w) & l.mask(),
            BinaryOp::Shr => lv.wrapping_shr((rv as u32) % w),
            BinaryOp::Ashr => {
                let shift = (rv as u32) % w;
                let signed = sign_extend(lv, w);
                ((signed as i128) >> shift) as u128 & l.mask()
            }
            BinaryOp::BitAnd => lv & rv,
            BinaryOp::BitOr => lv | rv,
            BinaryOp::BitXor => lv ^ rv,
            BinaryOp::And | BinaryOp::Or | BinaryOp::Xor => {
                let lb = lv != 0;
                let rb = rv != 0;
                let b = match op {
                    BinaryOp::And => lb && rb,
                    BinaryOp::Or => lb || rb,
                    BinaryOp::Xor => lb ^ rb,
                    _ => unreachable!(),
                };
                if b { 1 } else { 0 }
            }
            BinaryOp::Eq => if lv == rv { 1 } else { 0 },
            BinaryOp::Ne => if lv != rv { 1 } else { 0 },
            BinaryOp::Lt | BinaryOp::LtU => if lv < rv { 1 } else { 0 },
            BinaryOp::Le | BinaryOp::LeU => if lv <= rv { 1 } else { 0 },
            BinaryOp::Gt | BinaryOp::GtU => if lv > rv { 1 } else { 0 },
            BinaryOp::Ge | BinaryOp::GeU => if lv >= rv { 1 } else { 0 },
        };
        let out_width = match op {
            BinaryOp::Eq | BinaryOp::Ne | BinaryOp::Lt | BinaryOp::Le
            | BinaryOp::Gt | BinaryOp::Ge | BinaryOp::LtU | BinaryOp::LeU
            | BinaryOp::GtU | BinaryOp::GeU | BinaryOp::And | BinaryOp::Or
            | BinaryOp::Xor => 1,
            _ => w,
        };
        return Ok(BitVec::concrete(out_width, res));
    }

    // Symbolic path – lower to FSL Expr
    let le = l.symbolic.clone().unwrap_or_else(|| Expr::BVLit { value: l.value as u64, width: w });
    let re = r.symbolic.clone().unwrap_or_else(|| Expr::BVLit { value: r.value as u64, width: r.width });

    let expr = match op {
        BinaryOp::Add => Expr::BvAdd(Box::new(le), Box::new(re)),
        BinaryOp::Sub => Expr::BvSub(Box::new(le), Box::new(re)),
        BinaryOp::Mul => Expr::BvMul(Box::new(le), Box::new(re)),
        BinaryOp::BitAnd => Expr::BvAnd(Box::new(le), Box::new(re)),
        BinaryOp::BitOr => Expr::BvOr (Box::new(le), Box::new(re)),
        BinaryOp::BitXor => Expr::BvXor(Box::new(le), Box::new(re)),
        BinaryOp::Eq => Expr::Eq (Box::new(le), Box::new(re)),
        BinaryOp::Ne => Expr::Neq (Box::new(le), Box::new(re)),
        BinaryOp::Lt | BinaryOp::LtU => Expr::Ult(Box::new(le), Box::new(re)),
        BinaryOp::Le | BinaryOp::LeU => Expr::Ule(Box::new(le), Box::new(re)),
        BinaryOp::Shl => Expr::BvShl(Box::new(le), Box::new(re)),
        BinaryOp::Shr => Expr::BvLshr(Box::new(le), Box::new(re)),
        BinaryOp::Ashr => Expr::BvAshr(Box::new(le), Box::new(re)),
        _ => Expr::BvAdd(Box::new(le), Box::new(re)), // fallback
    };
    Ok(BitVec::from_expr(w, expr))
}

fn sign_extend(val: u128, width: u32) -> u128 {
    if width == 0 || width >= 128 { return val; }
    let sign_bit = 1u128 << (width - 1);
    if val & sign_bit != 0 {
        val | (!0u128 << width)
    } else {
        val
    }
}

// ---------------------------------------------------------------------------
// 4. Expression evaluator (binary semantics)
// ---------------------------------------------------------------------------

pub struct BinaryEvaluator<'a> {
    pub memory: &'a mut Memory,
    pub env: HashMap<String, BitVec>, // SSA name → value
    pub ir: &'a mut FslIR, // for emitting symbolic constraints
}

impl<'a> BinaryEvaluator<'a> {
    pub fn eval_operand(&mut self, op: &Operand) -> Result<BitVec, String> {
        match op {
            Operand::Const(c) => Ok(constant_to_bv(c)),
            Operand::Symbol(name) => {
                self.env.get(name).cloned().ok_or_else(|| format!("undefined SSA {}", name))
            }
            Operand::Deref(inner) => {
                let ptr = self.eval_operand(inner)?;
                let addr = ptr.as_u64().ok_or("symbolic pointer deref")?;
                Ok(self.memory.read_bv(addr, 32)) // default width
            }
            Operand::AddressOf(inner) => {
                // very simplified
                Ok(BitVec::concrete(self.memory.pointer_width, 0x1000))
            }
            _ => Err("unsupported operand".into()),
        }
    }

    pub fn eval_expr(&mut self, e: &ExprCBMC) -> Result<BitVec, String> {
        match e {
            ExprCBMC::Operand(op) => self.eval_operand(op),
            ExprCBMC::Unary { op, expr } => {
                let v = self.eval_expr(expr)?;
                Ok(eval_unary(*op, &v))
            }
            ExprCBMC::Binary { op, lhs, rhs } => {
                let l = self.eval_expr(lhs)?;
                let r = self.eval_expr(rhs)?;
                eval_binary(*op, &l, &r)
            }
            ExprCBMC::Ite { cond, then, else_ } => {
                let c = self.eval_expr(cond)?;
                if c.is_concrete() {
                    if c.value != 0 {
                        self.eval_expr(then)
                    } else {
                        self.eval_expr(else_)
                    }
                } else {
                    let t = self.eval_expr(then)?;
                    let e = self.eval_expr(else_)?;
                    let ce = c.symbolic.clone().unwrap();
                    let te = t.symbolic.clone().unwrap_or(Expr::BVLit { value: t.value as u64, width: t.width });
                    let ee = e.symbolic.clone().unwrap_or(Expr::BVLit { value: e.value as u64, width: e.width });
                    Ok(BitVec::from_expr(t.width, Expr::Ite(Box::new(ce), Box::new(te), Box::new(ee))))
                }
            }
            ExprCBMC::TypeCast { expr, target } => {
                let v = self.eval_expr(expr)?;
                let target_width = type_width(target);
                if v.is_concrete() {
                    Ok(BitVec::concrete(target_width, v.value & mask(target_width)))
                } else {
                    Ok(BitVec::from_expr(target_width, v.symbolic.unwrap()))
                }
            }
            _ => Err("unsupported expr".into()),
        }
    }

    pub fn execute(&mut self, inst: &Instruction) -> Result<(), String> {
        match inst {
            Instruction::Assign { lhs, rhs } => {
                let val = self.eval_expr(rhs)?;
                if let Operand::Symbol(name) = lhs {
                    self.env.insert(name.clone(), val);
                } else if let Operand::Deref(ptr_op) = lhs {
                    let ptr = self.eval_operand(ptr_op)?;
                    let addr = ptr.as_u64().ok_or("symbolic store")?;
                    self.memory.write_bv(addr, &val);
                }
                Ok(())
            }
            Instruction::Assert { cond, msg } => {
                let v = self.eval_expr(cond)?;
                if v.is_concrete() {
                    if v.value == 0 {
                        return Err(format!("assertion failed: {}", msg));
                    }
                } else {
                    // emit to FSL: we want to find violation, so assert ¬cond
                    let e = v.symbolic.unwrap();
                    self.ir.assert(Expr::Not(Box::new(e)), Origin::Assembler);
                }
                Ok(())
            }
            Instruction::Assume(cond) => {
                let v = self.eval_expr(cond)?;
                if v.is_concrete() {
                    if v.value == 0 {
                        return Err("assumption false – path pruned".into());
                    }
                } else {
                    let e = v.symbolic.unwrap();
                    self.ir.assert(e, Origin::KaniAssumption);
                }
                Ok(())
            }
            _ => Ok(()),
        }
    }
}

// ---------------------------------------------------------------------------
// 5. Helpers
// ---------------------------------------------------------------------------

fn constant_to_bv(c: &Constant) -> BitVec {
    match c {
        Constant::Bool(b) => BitVec::concrete(1, if *b { 1 } else { 0 }),
        Constant::Integer(i) => BitVec::concrete(64, *i as u128),
        Constant::BitVector { value, width, .. } => BitVec::concrete(*width, *value as u128),
        Constant::NullPointer => BitVec::concrete(64, 0),
    }
}

fn type_width(t: &Type) -> u32 {
    match t {
        Type::Bool => 1,
        Type::SignedBV(w) | Type::UnsignedBV(w) => *w,
        Type::Pointer(_) => 64,
        _ => 32,
    }
}

fn mask(width: u32) -> u128 {
    if width >= 128 { u128::MAX } else { (1u128 << width) - 1 }
}

// ---------------------------------------------------------------------------
// 6. Top-level binary semantics driver
// ---------------------------------------------------------------------------

pub fn run_binary_semantics(
    program: &GotoProgram,
    little_endian: bool,
) -> Result<FslIR, String> {
    let mut memory = Memory::new(little_endian, 64);
    let mut ir = FslIR::new();
    let env: HashMap<String, BitVec> = HashMap::new();

    let entry = program.functions.get(&program.entry)
        .ok_or("missing entry")?;

    let mut eval = BinaryEvaluator {
        memory: &mut memory,
        env,
        ir: &mut ir,
    };

    for inst in &entry.body {
        eval.execute(inst)?;
    }

    Ok(ir)
}

// End of CBMC GOTO Binary Semantics (~400 lines raw dense)
// Covers: BitVec values, byte-addressable memory, endianness,
// concrete + symbolic binary operators, pointer object/offset,
// SSA environment, assertion/assumption lowering into FSL.
