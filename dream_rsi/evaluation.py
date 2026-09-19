from dataclasses import dataclass
from typing import Any, Dict


@dataclass(frozen=True)
class Evaluation:
    score: float
    valid: bool
    details: Dict[str, Any]

    def bounded(self):
        return Evaluation(max(0.0, min(1.0, float(self.score))), bool(self.valid), dict(self.details))


class Evaluator:
    def evaluate(self, execution: Dict[str, Any], task: str) -> Evaluation:
        raise NotImplementedError


def score_result(result: Dict[str, Any]) -> float:
    if not isinstance(result, dict) or "score" not in result:
        raise ValueError("evaluation result must include score")
    return max(0.0, min(1.0, float(result["score"])))
