"""Simulation pool containing accumulated historical worlds."""
from typing import Iterable, List
from ..tree import DiscoveryTree


class SimulatorPool:
    def __init__(self, worlds: Iterable[DiscoveryTree] = ()):
        self.worlds: List[DiscoveryTree] = []
        for world in worlds:
            self.add(world)

    def add(self, world: DiscoveryTree):
        valid, error = world.validate()
        if not valid:
            raise ValueError(error)
        self.worlds.append(world)

    def extend(self, worlds: Iterable[DiscoveryTree]):
        for world in worlds:
            self.add(world)

    def snapshot(self):
        return tuple(self.worlds)

    def __len__(self):
        return len(self.worlds)
