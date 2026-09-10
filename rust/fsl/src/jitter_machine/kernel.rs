use super::ops::{pack, unpack, lcg, signed_i8, MAGIC, Opcodes, Flags};

pub struct KernelConfig {
    pub n: usize,
    pub maxdepth: u32,
    pub seed: u32,
}

impl Default for KernelConfig {
    fn default() -> Self {
        KernelConfig { n: 8, maxdepth: 8, seed: 1 }
    }
}

pub struct Kernel {
    pub state: Vec<u32>,
    pub code: Vec<u32>,
    pub depth: u32,
    pub maxdepth: u32,
    pub seed: u32,
    pub pc: u32,
    pub flags: u32,
    pub ret_stack: Vec<u32>,
    pub assert_acc: Vec<bool>,
    pub n: usize,
    pub halt_reason: String,
}

impl Kernel {
    pub fn new(config: KernelConfig) -> Self {
        Kernel {
            state: vec![0u32; config.n],
            code: Vec::new(),
            depth: 0,
            maxdepth: config.maxdepth,
            seed: config.seed,
            pc: 0,
            flags: 0,
            ret_stack: Vec::new(),
            assert_acc: Vec::new(),
            n: config.n,
            halt_reason: String::new(),
        }
    }

    pub fn with_code(config: KernelConfig, code: Vec<u32>) -> Self {
        let mut k = Kernel::new(config);
        k.code = code;
        k
    }

    pub fn from_words(words: &[u32]) -> Result<Self, String> {
        if words.len() < 8 {
            return Err("kernel image too short".into());
        }
        if words[0] != MAGIC {
            return Err(format!("bad magic: 0x{:08X} (expected 0x{:08X})", words[0], MAGIC));
        }
        let ver = words[1];
        if ver != 1 {
            return Err(format!("unsupported version: {}", ver));
        }
        let n = words[2] as usize;
        let maxdepth = words[4];
        let seed = words[5];
        let mut state = Vec::with_capacity(n);
        for i in 0..n {
            state.push(words[8 + i]);
        }
        let code = words[8 + n..].to_vec();
        Ok(Kernel {
            state, code, depth: words[3], maxdepth, seed,
            pc: words[6], flags: words[7], ret_stack: Vec::new(),
            assert_acc: Vec::new(), n, halt_reason: String::new(),
        })
    }

    pub fn to_words(&self) -> Vec<u32> {
        let mut w = Vec::with_capacity(8 + self.n + self.code.len());
        w.push(MAGIC);
        w.push(1);
        w.push(self.n as u32);
        w.push(self.depth);
        w.push(self.maxdepth);
        w.push(self.seed);
        w.push(self.pc);
        w.push(self.flags);
        for s in &self.state { w.push(*s); }
        for c in &self.code { w.push(*c); }
        w
    }

    pub fn load(&mut self, code: Vec<u32>) {
        self.code = code;
        self.pc = 0;
        self.flags = 0;
        self.depth = 0;
        self.ret_stack.clear();
        self.assert_acc.clear();
    }

    pub fn run(&mut self, max_steps: usize) -> u32 {
        let mut steps = 0;
        while !(self.flags & Flags::HALT != 0) && steps < max_steps {
            if (self.pc as usize) >= self.code.len() {
                self.flags |= Flags::FAIL | Flags::HALT;
                self.halt_reason = "PC out of bounds".into();
                break;
            }
            let word = self.code[self.pc as usize];
            let (op, a, b, c) = unpack(word);
            self.pc = self.pc.wrapping_add(1);
            self.exec(op, a, b, c);
            steps += 1;
        }
        if steps >= max_steps && !(self.flags & Flags::HALT != 0) {
            self.flags |= Flags::HALT;
            self.halt_reason = "fuel exhausted".into();
        }
        self.flags
    }

    fn exec(&mut self, op: u8, a: u8, b: u8, c: u8) {
        match op {
            Opcodes::NOP => {}
            Opcodes::LOADK => {
                self.state[a as usize] = c as u32;
            }
            Opcodes::ADD => {
                let r = self.state[b as usize].wrapping_add(self.state[c as usize]);
                self.state[a as usize] = r;
            }
            Opcodes::SUB => {
                let r = self.state[b as usize].wrapping_sub(self.state[c as usize]);
                self.state[a as usize] = r;
            }
            Opcodes::MUL => {
                let r = self.state[b as usize].wrapping_mul(self.state[c as usize]);
                self.state[a as usize] = r;
            }
            Opcodes::JITTER => {
                self.seed = lcg(self.seed);
                let xor = self.seed >> 16;
                self.state[a as usize] = self.state[a as usize] ^ xor;
            }
            Opcodes::RECUR => {
                if self.depth >= self.maxdepth {
                    self.flags |= Flags::FAIL | Flags::HALT;
                    self.halt_reason = "recursion overflow".into();
                    return;
                }
                self.ret_stack.push(self.pc);
                self.depth += 1;
                self.pc = self.state[a as usize] & 0xFFFF;
            }
            Opcodes::RET => {
                if self.ret_stack.is_empty() {
                    self.flags |= Flags::HALT;
                    return;
                }
                self.depth = self.depth.saturating_sub(1);
                self.pc = self.ret_stack.pop().unwrap();
            }
            Opcodes::ASSERT => {
                let ok = self.state[a as usize] == self.state[b as usize];
                self.assert_acc.push(ok);
                if !ok {
                    self.flags |= Flags::FAIL;
                }
            }
            Opcodes::FUSE => {
                let fused = if self.assert_acc.is_empty() { true } else { self.assert_acc.iter().all(|x| *x) };
                self.assert_acc.clear();
                if fused && !(self.flags & Flags::FAIL != 0) {
                    self.flags |= Flags::FUSED;
                } else {
                    self.flags = (self.flags & !Flags::FUSED) | Flags::FAIL;
                }
            }
            Opcodes::HALT => {
                self.flags |= Flags::HALT;
            }
            Opcodes::JMP => {
                let off = signed_i8(c);
                self.pc = self.pc.wrapping_add(off as u32);
            }
            Opcodes::JZ => {
                if self.state[a as usize] == 0 {
                    let off = signed_i8(c);
                    self.pc = self.pc.wrapping_add(off as u32);
                }
            }
            _ => {
                self.flags |= Flags::FAIL | Flags::HALT;
                self.halt_reason = format!("illegal opcode 0x{:02X}", op);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::ops::pack;

    #[test]
    fn test_kernel_halt() {
        let code = vec![pack(Opcodes::HALT, 0, 0, 0)];
        let mut k = Kernel::with_code(KernelConfig::default(), code);
        k.run(100);
        assert!(k.flags & Flags::HALT != 0);
    }

    #[test]
    fn test_add_sub() {
        let code = vec![
            pack(Opcodes::LOADK, 0, 0, 2),
            pack(Opcodes::LOADK, 1, 0, 3),
            pack(Opcodes::ADD, 2, 0, 1),
            pack(Opcodes::SUB, 3, 2, 0),
            pack(Opcodes::HALT, 0, 0, 0),
        ];
        let mut k = Kernel::with_code(KernelConfig { n: 4, ..Default::default() }, code);
        k.run(100);
        assert_eq!(k.state[2], 5);
        assert_eq!(k.state[3], 3);
    }

    #[test]
    fn test_assert_fuse_ok() {
        let code = vec![
            pack(Opcodes::LOADK, 0, 0, 5),
            pack(Opcodes::LOADK, 1, 0, 5),
            pack(Opcodes::ASSERT, 0, 1, 0),
            pack(Opcodes::FUSE, 0, 0, 0),
            pack(Opcodes::HALT, 0, 0, 0),
        ];
        let mut k = Kernel::with_code(KernelConfig::default(), code);
        k.run(100);
        assert!(k.flags & Flags::FUSED != 0);
        assert!(k.flags & Flags::HALT != 0);
    }

    #[test]
    fn test_assert_fuse_fail() {
        let code = vec![
            pack(Opcodes::LOADK, 0, 0, 1),
            pack(Opcodes::LOADK, 1, 0, 2),
            pack(Opcodes::ASSERT, 0, 1, 0),
            pack(Opcodes::FUSE, 0, 0, 0),
            pack(Opcodes::HALT, 0, 0, 0),
        ];
        let mut k = Kernel::with_code(KernelConfig::default(), code);
        k.run(100);
        assert!(k.flags & Flags::FAIL != 0);
        assert!(k.flags & Flags::FUSED == 0);
    }

    #[test]
    fn test_jitter_deterministic() {
        let code = vec![
            pack(Opcodes::LOADK, 0, 0, 0),
            pack(Opcodes::JITTER, 0, 0, 0),
            pack(Opcodes::HALT, 0, 0, 0),
        ];
        let mut k1 = Kernel::with_code(KernelConfig { n: 2, seed: 99, ..Default::default() }, code.clone());
        k1.run(100);
        let mut k2 = Kernel::with_code(KernelConfig { n: 2, seed: 99, ..Default::default() }, code);
        k2.run(100);
        assert_eq!(k1.state[0], k2.state[0]);
    }

    #[test]
    fn test_jz_branch() {
        let code = vec![
            pack(Opcodes::LOADK, 0, 0, 0),
            pack(Opcodes::JZ, 0, 0, 2),
            pack(Opcodes::LOADK, 1, 0, 99),
            pack(Opcodes::HALT, 0, 0, 0),
            pack(Opcodes::LOADK, 1, 0, 42),
            pack(Opcodes::HALT, 0, 0, 0),
        ];
        let mut k = Kernel::with_code(KernelConfig { n: 2, ..Default::default() }, code);
        k.run(100);
        assert_eq!(k.state[1], 42);
    }

    #[test]
    fn test_recur_overflow() {
        let code = vec![
            pack(Opcodes::LOADK, 0, 0, 0),
            pack(Opcodes::RECUR, 0, 0, 0),
            pack(Opcodes::HALT, 0, 0, 0),
        ];
        let mut k = Kernel::with_code(KernelConfig { n: 2, maxdepth: 1, ..Default::default() }, code);
        k.run(100);
        assert!(k.flags & Flags::FAIL != 0);
    }

    #[test]
    fn test_from_to_words_roundtrip() {
        let code = vec![
            pack(Opcodes::LOADK, 0, 0, 7),
            pack(Opcodes::ADD, 1, 0, 0),
            pack(Opcodes::HALT, 0, 0, 0),
        ];
        let mut k = Kernel::with_code(KernelConfig { n: 4, seed: 42, ..Default::default() }, code);
        k.run(100);
        let words = k.to_words();
        let mut k2 = Kernel::from_words(&words).unwrap();
        assert_eq!(k2.state[0], 7);
        assert_eq!(k2.state[1], 14);
        assert!(k2.flags & Flags::HALT != 0);
    }

    #[test]
    fn test_pc_oob_fails() {
        let code = vec![pack(Opcodes::JMP, 0, 0, 127)];
        let mut k = Kernel::with_code(KernelConfig::default(), code);
        k.run(100);
        assert!(k.flags & Flags::FAIL != 0);
    }
}
