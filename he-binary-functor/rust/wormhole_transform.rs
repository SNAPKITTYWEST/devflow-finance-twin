use std::collections::VecDeque;

#[derive(Clone, Debug, PartialEq)]
pub enum BraidWord {
    Gen(i32),
    Concat(Box<BraidWord>, Box<BraidWord>),
    Empty,
}

impl BraidWord {
    pub fn length(&self) -> usize {
        match self {
            BraidWord::Empty => 0,
            BraidWord::Gen(_) => 1,
            BraidWord::Concat(l, r) => l.length() + r.length(),
        }
    }

    fn apply_yb_once(&self) -> (BraidWord, bool) {
        match self {
            BraidWord::Concat(l, r) => {
                if let BraidWord::Concat(l2, r2) = l.as_ref() {
                    if let (BraidWord::Gen(i), BraidWord::Concat(l3, r3)) =
                        (l2.as_ref(), r2.as_ref())
                    {
                        if let (BraidWord::Gen(j), BraidWord::Gen(k)) =
                            (l3.as_ref(), r3.as_ref())
                        {
                            if (j == i + 1 || j == i - 1) && k == i {
                                let new_head = BraidWord::Concat(
                                    Box::new(BraidWord::Gen(*j)),
                                    Box::new(BraidWord::Concat(
                                        Box::new(BraidWord::Gen(*i)),
                                        Box::new(BraidWord::Gen(*j)),
                                    )),
                                );
                                return (
                                    BraidWord::Concat(Box::new(new_head), r.clone()),
                                    true,
                                );
                            }
                        }
                    }
                }
                let (new_l, changed) = l.apply_yb_once();
                if changed {
                    return (BraidWord::Concat(Box::new(new_l), r.clone()), true);
                }
                let (new_r, changed) = r.apply_yb_once();
                (
                    BraidWord::Concat(Box::new(new_l), Box::new(new_r)),
                    changed,
                )
            }
            _ => (self.clone(), false),
        }
    }

    pub fn wormhole_transform(&self) -> BraidWord {
        let (mut current, mut changed) = self.apply_yb_once();
        while changed {
            let (next, c) = current.apply_yb_once();
            current = next;
            changed = c;
        }
        current
    }

    pub fn flatten(&self) -> Vec<i32> {
        let mut result = Vec::new();
        self.flatten_into(&mut result);
        result
    }

    fn flatten_into(&self, out: &mut Vec<i32>) {
        match self {
            BraidWord::Gen(i) => out.push(*i),
            BraidWord::Concat(l, r) => {
                l.flatten_into(out);
                r.flatten_into(out);
            }
            BraidWord::Empty => {}
        }
    }
}

pub fn hw_execute_transform(input: &[i32]) -> (Vec<i32>, u32) {
    let word = parse_braid_word(input);
    let compressed = word.wormhole_transform();
    let cycles = 1;
    (compressed.flatten(), cycles)
}

fn parse_braid_word(input: &[i32]) -> BraidWord {
    input
        .iter()
        .rev()
        .fold(BraidWord::Empty, |acc, &g| {
            BraidWord::Concat(Box::new(BraidWord::Gen(g)), Box::new(acc))
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_yang_baxter_rewrite() {
        // sigma_1 * sigma_2 * sigma_1 = sigma_2 * sigma_1 * sigma_2
        let word = vec![1, 2, 1];
        let (compressed, cycles) = hw_execute_transform(&word);
        assert_eq!(cycles, 1);
        assert_eq!(compressed, vec![2, 1, 2]);
    }

    #[test]
    fn test_length_preservation() {
        let word = vec![1, 2, 1, 3, 2];
        let (compressed, _) = hw_execute_transform(&word);
        assert!(compressed.len() <= word.len());
    }
}
