use std::marker::PhantomData;

pub trait BitPredicate {
    fn verify(bits: &[bool]) -> bool;
}

#[derive(Debug, Clone)]
pub struct RefinedBitVector<P: BitPredicate> {
    pub bits: Vec<bool>,
    _phantom: PhantomData<P>,
}

impl<P: BitPredicate> RefinedBitVector<P> {
    pub fn new(bits: Vec<bool>) -> Result<Self, &'static str> {
        if P::verify(&bits) {
            Ok(Self { bits, _phantom: PhantomData })
        } else {
            Err("Bit-vector failed refinement predicate constraint")
        }
    }
}

pub struct IsUint8Bounded;
impl BitPredicate for IsUint8Bounded {
    fn verify(bits: &[bool]) -> bool { bits.len() == 8 }
}

pub type RefinedUint8 = RefinedBitVector<IsUint8Bounded>;

pub trait Predicate<T> {
    fn check(val: &T) -> bool;
}

#[derive(Debug, Copy, Clone)]
pub struct Refined<T, P: Predicate<T>> {
    value: T,
    _proof: PhantomData<P>,
}

impl<T, P: Predicate<T>> Refined<T, P> {
    pub fn new(value: T) -> Option<Self> {
        if P::check(&value) { Some(Self { value, _proof: PhantomData }) } else { None }
    }
    pub fn value(&self) -> &T { &self.value }
}

pub struct IsNandResult;
impl Predicate<(bool, bool, bool)> for IsNandResult {
    fn check(val: &(bool, bool, bool)) -> bool {
        let (a, b, r) = *val;
        r == !(a && b)
    }
}

pub fn refined_nand(a: bool, b: bool) -> Refined<(bool, bool, bool), IsNandResult> {
    let r = !(a && b);
    Refined::new((a, b, r)).expect("NAND semantics mathematically violated")
}
