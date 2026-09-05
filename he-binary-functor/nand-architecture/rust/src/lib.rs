pub type RegId = u8;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Opcode {
    Nand = 0b000,
    Load = 0b001,
    Store = 0b010,
    JmpZ = 0b011,
    Halt = 0b111,
}

#[derive(Debug, Clone, Copy)]
pub struct Instruction {
    pub op: Opcode,
    pub dst: RegId,
    pub src_a: RegId,
    pub src_b: u8,
}

impl Instruction {
    pub fn encode(&self) -> u16 {
        let op = (self.op as u16) << 13;
        let dst = ((self.dst & 0x0F) as u16) << 9;
        let src_a = ((self.src_a & 0x0F) as u16) << 5;
        let src_b = (self.src_b & 0x1F) as u16;
        op | dst | src_a | src_b
    }

    pub fn decode(word: u16) -> Result<Self, &'static str> {
        let op_val = (word >> 13) & 0x07;
        let op = match op_val {
            0b000 => Opcode::Nand,
            0b001 => Opcode::Load,
            0b010 => Opcode::Store,
            0b011 => Opcode::JmpZ,
            0b111 => Opcode::Halt,
            _ => return Err("Invalid Opcode"),
        };
        Ok(Self {
            op,
            dst: ((word >> 9) & 0x0F) as RegId,
            src_a: ((word >> 5) & 0x0F) as RegId,
            src_b: (word & 0x1F) as u8,
        })
    }
}

pub struct VirtualMachine {
    pub regs: [bool; 16],
    pub memory: [bool; 65536],
    pub pc: u16,
    pub halted: bool,
}

impl VirtualMachine {
    pub fn new() -> Self {
        Self {
            regs: [false; 16],
            memory: [false; 65536],
            pc: 0,
            halted: false,
        }
    }

    pub fn step(&mut self, rom: &[u16]) -> Result<(), &'static str> {
        if self.halted || (self.pc as usize) >= rom.len() {
            self.halted = true;
            return Ok(());
        }

        let word = rom[self.pc as usize];
        self.pc = self.pc.checked_add(1).ok_or("PC Overflow")?;
        let inst = Instruction::decode(word)?;

        match inst.op {
            Opcode::Nand => {
                let a = if inst.src_a == 0 { false } else { self.regs[inst.src_a as usize] };
                let b_val = (inst.src_b & 0x0F) as usize;
                let b = if b_val == 0 { false } else { self.regs[b_val] };
                let res = !(a && b);
                if inst.dst > 0 {
                    self.regs[inst.dst as usize] = res;
                }
            }
            Opcode::Load => {
                let addr = inst.src_b as usize;
                if inst.dst > 0 {
                    self.regs[inst.dst as usize] = self.memory[addr];
                }
            }
            Opcode::Store => {
                let addr = inst.src_b as usize;
                let val = if inst.src_a == 0 { false } else { self.regs[inst.src_a as usize] };
                self.memory[addr] = val;
            }
            Opcode::JmpZ => {
                let cond = if inst.src_a == 0 { false } else { self.regs[inst.src_a as usize] };
                if !cond {
                    self.pc = inst.src_b as u16;
                }
            }
            Opcode::Halt => {
                self.halted = true;
            }
        }
        Ok(())
    }
}
