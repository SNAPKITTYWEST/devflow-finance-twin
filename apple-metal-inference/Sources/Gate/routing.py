from dataclasses import dataclass
from enum import Enum
from typing import Sequence

from .entropy import logit_entropy


class Route(Enum):
    LOCAL = "local"
    REMOTE = "remote"


@dataclass(frozen=True)
class RoutePolicy:
    h_max: float = 1.8
    min_margin: float = 0.05
    max_prompt_bytes: int = 16384


@dataclass
class RequestEnvelope:
    session_id: str
    prompt: str
    max_tokens: int
    task: str


def decide(logits: Sequence[float], policy: RoutePolicy,
           env: RequestEnvelope) -> Route:
    if len(env.prompt.encode("utf-8")) > policy.max_prompt_bytes:
        return Route.REMOTE
    h = logit_entropy(logits)
    if h <= policy.h_max:
        return Route.LOCAL
    return Route.REMOTE
