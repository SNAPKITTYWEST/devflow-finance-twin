"""Terms, atoms, variables, constants. Immutable and hashable."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Union


@dataclass(frozen=True, order=True)
class Variable:
    name: str

    def __post_init__(self) -> None:
        if not self.name or not self.name[0].isupper() and self.name[0] != "_":
            # Datalog convention: variables start with uppercase or _
            pass # allow flexible; safety checked at rule level

    def __str__(self) -> str:
        return self.name

    def __repr__(self) -> str:
        return f"Var({self.name})"


@dataclass(frozen=True, order=True)
class Constant:
    value: str

    def __str__(self) -> str:
        return self.value

    def __repr__(self) -> str:
        return f"Const({self.value!r})"


Term = Union[Variable, Constant]


@dataclass(frozen=True, order=True)
class Atom:
    predicate: str
    args: tuple[Term, ...]

    def __post_init__(self) -> None:
        if not self.predicate:
            raise ValueError("predicate name required")

    @property
    def arity(self) -> int:
        return len(self.args)

    def is_ground(self) -> bool:
        return all(isinstance(a, Constant) for a in self.args)

    def variables(self) -> frozenset[Variable]:
        return frozenset(a for a in self.args if isinstance(a, Variable))

    def __str__(self) -> str:
        if not self.args:
            return self.predicate
        return f"{self.predicate}({', '.join(str(a) for a in self.args)})"

    def __repr__(self) -> str:
        return f"Atom({self.predicate!r}, {self.args!r})"


Substitution = dict[Variable, Term]