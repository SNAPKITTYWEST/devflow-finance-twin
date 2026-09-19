"""Historical discovery-world storage and immutable replay snapshots."""
from pathlib import Path
from typing import Iterable, List
import json
import threading

from ..tree import DiscoveryTree


class HistoricalWorldStore:
    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.touch(exist_ok=True)
        self.lock = threading.RLock()

    def append(self, tree: DiscoveryTree) -> None:
        valid, error = tree.validate()
        if not valid:
            raise ValueError(error)
        line = json.dumps(tree.to_dict(), sort_keys=True, separators=(",", ":"))
        with self.lock, self.path.open("a", encoding="utf-8") as stream:
            stream.write(line + "\n")
            stream.flush()

    def load(self) -> List[DiscoveryTree]:
        worlds = []
        with self.lock, self.path.open("r", encoding="utf-8") as stream:
            for number, line in enumerate(stream, 1):
                if not line.strip():
                    continue
                try:
                    worlds.append(DiscoveryTree.from_dict(json.loads(line)))
                except Exception as exc:
                    raise ValueError(f"invalid historical world at line {number}: {exc}") from exc
        return worlds

    def replace(self, worlds: Iterable[DiscoveryTree]) -> None:
        temporary = self.path.with_suffix(self.path.suffix + ".tmp")
        with self.lock, temporary.open("w", encoding="utf-8") as stream:
            for tree in worlds:
                valid, error = tree.validate()
                if not valid:
                    raise ValueError(error)
                stream.write(json.dumps(tree.to_dict(), sort_keys=True) + "\n")
            stream.flush()
        temporary.replace(self.path)
