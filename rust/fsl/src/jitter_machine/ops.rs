use std::fmt;

pub const MAGIC: u32 = 0x52544A52;

pub mod Opcodes {
    pub const NOP: u8 = 0x00;
    pub const LOADK: u8 = 0x01;
    pub const ADD: u8 = 0x02;
    pub const SUB: u8 = 0x03;
    pub const MUL: u8 = 0x04;
    pub const JITTER: u8 = 0x05;
    pub const RECUR: u8 = 0x06;
    pub const RET: u8 = 0x07;
    pub const ASSERT: u8 = 0x08;
    pub const FUSE: u8 = 0x09;
    pub const HALT: u8 = 0x0A;
    pub const JMP: u8 = 0x0B;
    pub const JZ: u8 = 0x0C;
}

pub mod Flags {
    pub const HALT: u32 = 1;
    pub const FAIL: u32 = 2;
    pub const FUSED: u32 = 4;
}

pub fn pack(op: u8, a: u8, b: u8, c: u8) -> u32 {
    ((op as u32) << 24) | ((a as u32) << 16) | ((b as u32) << 8) | (c as u32)
}

pub fn unpack(w: u32) -> (u8, u8, u8, u8) {
    ((w >> 24) as u8, (w >> 16) as u8, (w >> 8) as u8, w as u8)
}

pub fn lcg(seed: u32) -> u32 {
    seed.wrapping_mul(1664525).wrapping_add(1013904223)
}

pub fn signed_i8(v: u8) -> i32 {
    if v < 128 { v as i32 } else { v as i32 - 256 }
}

pub struct Instr {
    pub op: u8,
    pub a: u8,
    pub b: u8,
    pub c: u8,
    pub raw: u32,
}

impl Instr {
    pub fn decode(w: u32) -> Self {
        let (op, a, b, c) = unpack(w);
        Instr { op, a, b, c, raw: w }
    }
}

impl fmt::Display for Instr {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        let name = match self.op {
            Opcodes::NOP => "NOP",
            Opcodes::LOADK => "LOADK",
            Opcodes::ADD => "ADD",
            Opcodes::SUB => "SUB",
            Opcodes::MUL => "MUL",
            Opcodes::JITTER => "JITTER",
            Opcodes::RECUR => "RECUR",
            Opcodes::RET => "RET",
            Opcodes::ASSERT => "ASSERT",
            Opcodes::FUSE => "FUSE",
            Opcodes::HALT => "HALT",
            Opcodes::JMP => "JMP",
            Opcodes::JZ => "JZ",
            _ => "???",
        };
        write!(f, "{:02X} {} A={} B={} C={}", self.op, name, self.a, self.b, self.c)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pack_unpack() {
        let w = pack(Opcodes::LOADK, 0, 0, 42);
        let (op, a, b, c) = unpack(w);
        assert_eq!(op, Opcodes::LOADK);
        assert_eq!(a, 0);
        assert_eq!(b, 0);
        assert_eq!(c, 42);
    }

    #[test]
    fn test_lcg_deterministic() {
        let s = 1u32;
        assert_eq!(lcg(s), lcg(s));
        assert_ne!(lcg(s), lcg(lcg(s)));
    }

    #[test]
    fn test_signed_i8() {
        assert_eq!(signed_i8(0), 0);
        assert_eq!(signed_i8(127), 127);
        assert_eq!(signed_i8(128), -128);
        assert_eq!(signed_i8(255), -1);
    }
}
