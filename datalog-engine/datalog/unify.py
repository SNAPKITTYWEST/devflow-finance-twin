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

"""Deterministic unification."""

from __future__ import annotations

from .terms import Atom, Constant, Substitution, Term, Variable


class UnifyError(Exception):
    pass


def unify(a: Term | Atom, b: Term | Atom, subst: Substitution | None = None) -> Substitution:
    """Return most-general unifier or raise UnifyError."""
    s: Substitution = dict(subst) if subst else {}

    def _resolve(t: Term) -> Term:
        while isinstance(t, Variable) and t in s:
            t = s[t]
        return t

    def _unify_terms(x: Term, y: Term) -> None:
        x = _resolve(x)
        y = _resolve(y)
        if x == y:
            return
        if isinstance(x, Variable):
            if _occurs(x, y, s):
                raise UnifyError(f"occurs check failed: {x} in {y}")
            s[x] = y
            return
        if isinstance(y, Variable):
            if _occurs(y, x, s):
                raise UnifyError(f"occurs check failed: {y} in {x}")
            s[y] = x
            return
        # both constants
        if isinstance(x, Constant) and isinstance(y, Constant):
            if x.value != y.value:
                raise UnifyError(f"constant mismatch: {x} vs {y}")
            return
        raise UnifyError(f"cannot unify {x} and {y}")

    if isinstance(a, Atom) and isinstance(b, Atom):
        if a.predicate != b.predicate or a.arity != b.arity:
            raise UnifyError(f"atom mismatch: {a} vs {b}")
        for xa, xb in zip(a.args, b.args):
            _unify_terms(xa, xb)
        return s

    if isinstance(a, (Variable, Constant)) and isinstance(b, (Variable, Constant)):
        _unify_terms(a, b)
        return s

    raise UnifyError(f"type mismatch: {type(a)} vs {type(b)}")


def _occurs(var: Variable, term: Term, subst: Substitution) -> bool:
    term = subst.get(term, term) if isinstance(term, Variable) else term
    if term == var:
        return True
    return False # no compound terms in core language


def apply_subst(atom: Atom, subst: Substitution) -> Atom:
    """Apply substitution to an atom, producing a (possibly still non-ground) atom."""
    new_args: list[Term] = []
    for a in atom.args:
        t = a
        while isinstance(t, Variable) and t in subst:
            t = subst[t]
        new_args.append(t)
    return Atom(atom.predicate, tuple(new_args))


def is_ground_atom(atom: Atom) -> bool:
    return atom.is_ground()