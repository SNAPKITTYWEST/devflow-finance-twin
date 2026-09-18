import math
from typing import Sequence


def logit_entropy(logits: Sequence[float], temperature: float = 1.0) -> float:
    if not logits:
        return 0.0
    t = max(temperature, 1e-6)
    m = max(logits)
    exps = [math.exp((l - m) / t) for l in logits]
    z = sum(exps)
    if z <= 0.0:
        return 0.0
    h = 0.0
    for e in exps:
        p = e / z
        if p > 1e-12:
            h -= p * math.log(p)
    return h
