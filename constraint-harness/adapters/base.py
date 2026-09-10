"""Abstract model adapter. No private weights or hidden activations."""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, Iterator


class ModelAdapter(ABC):
    @abstractmethod
    def infer(self, prompt: str, **kwargs: Any) -> dict[str, Any]:
        ...

    def stream(self, prompt: str, **kwargs: Any) -> Iterator[str]:
        yield self.infer(prompt, **kwargs).get("output", "")

    def metadata(self) -> dict[str, Any]:
        return {"provider": self.__class__.__name__}
