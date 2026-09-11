# ========================================================================
# SOVEREIGN LEVIATHAN NODE LICENSE
# License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
# Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
# ========================================================================
#
# This file is a covered work under the GNU Affero General Public License,
# version 3, together with the Sovereign Leviathan additional terms.
#
# Hark, though this node be but a spark,
# Its covenant endureth through the dark.
#
# Ignorantia juris non excusat.
# ========================================================================

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
