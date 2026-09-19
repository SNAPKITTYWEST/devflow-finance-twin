"""JSONL persistence for replayable historical worlds."""
from pathlib import Path
import json
from ..tree import DiscoveryTree
from ..simulator.pool import SimulatorPool


class WorldStore:
    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.touch(exist_ok=True)

    def append(self, world: DiscoveryTree):
        valid, error = world.validate()
        if not valid:
            raise ValueError(error)
        with self.path.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(world.to_dict(), sort_keys=True) + "\n")

    def load(self):
        worlds = []
        with self.path.open("r", encoding="utf-8") as stream:
            for line_number, line in enumerate(stream, 1):
                if not line.strip():
                    continue
                try:
                    worlds.append(DiscoveryTree.from_dict(json.loads(line)))
                except Exception as exc:
                    raise ValueError(f"invalid world at line {line_number}: {exc}") from exc
        return worlds

    def pool(self):
        return SimulatorPool(self.load())
