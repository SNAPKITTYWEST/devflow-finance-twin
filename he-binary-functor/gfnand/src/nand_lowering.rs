use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct NandRef(pub usize);

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum NandGate {
    Input(usize),
    Nand(NandRef, NandRef),
}

pub struct NandDag {
    pub gates: Vec<NandGate>,
    cache: HashMap<NandGate, NandRef>,
}

impl NandDag {
    pub fn new() -> Self {
        Self { gates: Vec::new(), cache: HashMap::new() }
    }

    pub fn input(&mut self, index: usize) -> NandRef {
        let gate = NandGate::Input(index);
        if let Some(&rf) = self.cache.get(&gate) { return rf; }
        let rf = NandRef(self.gates.len());
        self.gates.push(gate.clone());
        self.cache.insert(gate, rf);
        rf
    }

    pub fn nand(&mut self, a: NandRef, b: NandRef) -> NandRef {
        let gate = NandGate::Nand(a, b);
        if let Some(&rf) = self.cache.get(&gate) { return rf; }
        let rf = NandRef(self.gates.len());
        self.gates.push(gate.clone());
        self.cache.insert(gate, rf);
        rf
    }

    pub fn not(&mut self, a: NandRef) -> NandRef { self.nand(a, a) }

    pub fn and(&mut self, a: NandRef, b: NandRef) -> NandRef {
        let ab = self.nand(a, b);
        self.not(ab)
    }

    pub fn or(&mut self, a: NandRef, b: NandRef) -> NandRef {
        let na = self.not(a);
        let nb = self.not(b);
        self.nand(na, nb)
    }

    pub fn xor(&mut self, a: NandRef, b: NandRef) -> NandRef {
        let ab = self.nand(a, b);
        let a_ab = self.nand(a, ab);
        let b_ab = self.nand(b, ab);
        self.nand(a_ab, b_ab)
    }

    pub fn half_adder(&mut self, a: NandRef, b: NandRef) -> (NandRef, NandRef) {
        (self.xor(a, b), self.and(a, b))
    }

    pub fn full_adder(&mut self, a: NandRef, b: NandRef, cin: NandRef) -> (NandRef, NandRef) {
        let (s1, c1) = self.half_adder(a, b);
        let (sum, c2) = self.half_adder(s1, cin);
        (sum, self.or(c1, c2))
    }

    pub fn add_words(&mut self, a: &[NandRef], b: &[NandRef]) -> (Vec<NandRef>, NandRef) {
        assert_eq!(a.len(), b.len());
        let mut result = Vec::with_capacity(a.len());
        let mut cin = self.nand(self.input(0), self.not(self.input(0)));
        for i in 0..a.len() {
            let (sum, cout) = self.full_adder(a[i], b[i], cin);
            result.push(sum);
            cin = cout;
        }
        (result, cin)
    }
}
