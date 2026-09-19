from pathlib import Path
import json

from .tree import DiscoveryTree
from .replay import SimulatorPool


class WorldStore:
    """JSONL persistence for historical worlds."""

    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.touch(exist_ok=True)

    def append(self, tree: DiscoveryTree):
        valid, reason = tree.validate()
        if not valid:
            raise ValueError(reason)
        with self.path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(tree.to_dict(), sort_keys=True) + "\n")

    def load(self):
        trees = []
        with self.path.open("r", encoding="utf-8") as fh:
            for index, line in enumerate(fh, start=1):
                if not line.strip():
                    continue
                try:
                    trees.append(DiscoveryTree.from_dict(json.loads(line)))
                except Exception as exc:
                    raise ValueError(f"invalid world at line {index}: {exc}") from exc
        return trees

    def pool(self):
        return SimulatorPool(self.load())
