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

#!/usr/bin/env python3
"""
Hand-rolled RCC-8 Spatial Reasoning + Materialization Engine
~600-line macro-style program.
Implements:
  - RCC-8 base relations
  - Full composition table
  - Iterative materialization to fixpoint
  - Path-consistency style inference
  - Basic consistency detection
  - SPARQL-friendly RDF export
  - Example spatial scenarios
"""

from __future__ import annotations
import itertools
from collections import defaultdict
from typing import Dict, Set, Tuple, List, Optional, Iterable
from rdflib import Graph, Namespace, URIRef, Literal, BNode
from rdflib.namespace import RDF, RDFS, OWL, XSD

# ---------------------------------------------------------------------------
# 1. Namespaces and vocabulary
# ---------------------------------------------------------------------------
RCC = Namespace("http://example.org/rcc8#")
EX = Namespace("http://example.org/spatial#")

RELATIONS = [
    "DC", "EC", "PO", "EQ", "TPP", "NTPP", "TPPi", "NTPPi"
]

# Inverse map
INVERSE = {
    "DC": "DC", "EC": "EC", "PO": "PO", "EQ": "EQ",
    "TPP": "TPPi", "NTPP": "NTPPi",
    "TPPi": "TPP", "NTPPi": "NTPP"
}

# ---------------------------------------------------------------------------
# 2. Full RCC-8 Composition Table (hand-coded)
# Source: classic RCC literature (Randell, Cui, Cohn / Renz & Nebel)
# Entry (r1, r2) -> set of possible relations for a o r1 b and b o r2 c
# ---------------------------------------------------------------------------
COMPOSITION: Dict[Tuple[str, str], Set[str]] = {
    # DC row
    ("DC", "DC"): {"DC", "EC", "PO", "TPP", "NTPP", "TPPi", "NTPPi", "EQ"},
    ("DC", "EC"): {"DC", "EC", "PO", "TPP", "NTPP"},
    ("DC", "PO"): {"DC", "EC", "PO", "TPP", "NTPP"},
    ("DC", "TPP"): {"DC", "EC", "PO", "TPP", "NTPP"},
    ("DC", "NTPP"): {"DC", "EC", "PO", "TPP", "NTPP"},
    ("DC", "TPPi"): {"DC"},
    ("DC", "NTPPi"): {"DC"},
    ("DC", "EQ"): {"DC"},

    # EC row
    ("EC", "DC"): {"DC", "EC", "PO", "TPPi", "NTPPi"},
    ("EC", "EC"): {"DC", "EC", "PO", "TPP", "TPPi", "EQ"},
    ("EC", "PO"): {"DC", "EC", "PO", "TPP", "NTPP"},
    ("EC", "TPP"): {"EC", "PO", "TPP", "NTPP"},
    ("EC", "NTPP"): {"PO", "TPP", "NTPP"},
    ("EC", "TPPi"): {"DC", "EC"},
    ("EC", "NTPPi"): {"DC"},
    ("EC", "EQ"): {"EC"},

    # PO row
    ("PO", "DC"): {"DC", "EC", "PO", "TPPi", "NTPPi"},
    ("PO", "EC"): {"DC", "EC", "PO", "TPPi", "NTPPi"},
    ("PO", "PO"): {"DC", "EC", "PO", "TPP", "NTPP", "TPPi", "NTPPi", "EQ"},
    ("PO", "TPP"): {"PO", "TPP", "NTPP"},
    ("PO", "NTPP"): {"PO", "TPP", "NTPP"},
    ("PO", "TPPi"): {"DC", "EC", "PO", "TPPi", "NTPPi"},
    ("PO", "NTPPi"): {"DC", "EC", "PO", "TPPi", "NTPPi"},
    ("PO", "EQ"): {"PO"},

    # TPP row
    ("TPP", "DC"): {"DC"},
    ("TPP", "EC"): {"DC", "EC"},
    ("TPP", "PO"): {"DC", "EC", "PO", "TPP", "NTPP"},
    ("TPP", "TPP"): {"TPP", "NTPP"},
    ("TPP", "NTPP"): {"NTPP"},
    ("TPP", "TPPi"): {"DC", "EC", "PO", "TPP", "TPPi", "EQ"},
    ("TPP", "NTPPi"): {"DC", "EC", "PO", "TPP", "NTPP"},
    ("TPP", "EQ"): {"TPP"},

    # NTPP row
    ("NTPP", "DC"): {"DC"},
    ("NTPP", "EC"): {"DC"},
    ("NTPP", "PO"): {"DC", "EC", "PO", "TPP", "NTPP"},
    ("NTPP", "TPP"): {"NTPP"},
    ("NTPP", "NTPP"): {"NTPP"},
    ("NTPP", "TPPi"): {"DC", "EC", "PO", "TPP", "NTPP"},
    ("NTPP", "NTPPi"): {"DC", "EC", "PO", "TPP", "NTPP", "TPPi", "NTPPi", "EQ"},
    ("NTPP", "EQ"): {"NTPP"},

    # TPPi row
    ("TPPi", "DC"): {"DC", "EC", "PO", "TPPi", "NTPPi"},
    ("TPPi", "EC"): {"EC", "PO", "TPPi", "NTPPi"},
    ("TPPi", "PO"): {"PO", "TPPi", "NTPPi"},
    ("TPPi", "TPP"): {"PO", "TPP", "TPPi", "EQ"},
    ("TPPi", "NTPP"): {"PO", "TPP", "NTPP"},
    ("TPPi", "TPPi"): {"TPPi", "NTPPi"},
    ("TPPi", "NTPPi"): {"NTPPi"},
    ("TPPi", "EQ"): {"TPPi"},

    # NTPPi row
    ("NTPPi", "DC"): {"DC", "EC", "PO", "TPPi", "NTPPi"},
    ("NTPPi", "EC"): {"PO", "TPPi", "NTPPi"},
    ("NTPPi", "PO"): {"PO", "TPPi", "NTPPi"},
    ("NTPPi", "TPP"): {"PO", "TPPi", "NTPPi"},
    ("NTPPi", "NTPP"): {"PO", "TPP", "NTPP", "TPPi", "NTPPi", "EQ"},
    ("NTPPi", "TPPi"): {"NTPPi"},
    ("NTPPi", "NTPPi"): {"NTPPi"},
    ("NTPPi", "EQ"): {"NTPPi"},

    # EQ row
    ("EQ", "DC"): {"DC"},
    ("EQ", "EC"): {"EC"},
    ("EQ", "PO"): {"PO"},
    ("EQ", "TPP"): {"TPP"},
    ("EQ", "NTPP"): {"NTPP"},
    ("EQ", "TPPi"): {"TPPi"},
    ("EQ", "NTPPi"): {"NTPPi"},
    ("EQ", "EQ"): {"EQ"},
}

# Make table complete for missing symmetric cases if needed
for r1 in RELATIONS:
    for r2 in RELATIONS:
        if (r1, r2) not in COMPOSITION:
            COMPOSITION[(r1, r2)] = set(RELATIONS)

# ---------------------------------------------------------------------------
# 3. Core data structures
# ---------------------------------------------------------------------------
class RCCConstraintNetwork:
    """Constraint network: regions -> relation set between every pair."""

    def __init__(self):
        self.regions: Set[str] = set()
        self.constraints: Dict[Tuple[str, str], Set[str]] = defaultdict(set)

    def add_region(self, r: str):
        self.regions.add(r)
        self.constraints[(r, r)].add("EQ")

    def add_constraint(self, a: str, rel: str, b: str):
        if rel not in RELATIONS:
            raise ValueError(f"Unknown relation {rel}")
        self.add_region(a)
        self.add_region(b)
        self.constraints[(a, b)].add(rel)
        inv = INVERSE[rel]
        self.constraints[(b, a)].add(inv)

    def get(self, a: str, b: str) -> Set[str]:
        return self.constraints.get((a, b), set(RELATIONS))

    def refine(self, a: str, b: str, possible: Set[str]) -> bool:
        current = self.get(a, b)
        new = current & possible
        if not new:
            return False
        if new != current:
            self.constraints[(a, b)] = new
            inv_new = {INVERSE[r] for r in new}
            self.constraints[(b, a)] = inv_new
            return True
        return False

    def is_consistent(self) -> bool:
        for (a, b), rels in self.constraints.items():
            if not rels:
                return False
        return True

# ---------------------------------------------------------------------------
# 4. Materialization / Path-consistency engine
# ---------------------------------------------------------------------------
class RCC8Reasoner:
    def __init__(self):
        self.net = RCCConstraintNetwork()
        self.inferred_count = 0
        self.iterations = 0

    def assert_fact(self, a: str, rel: str, b: str):
        self.net.add_constraint(a, rel, b)

    def materialize(self, max_iter: int = 100) -> bool:
        changed = True
        self.iterations = 0
        regions = list(self.net.regions)

        while changed and self.iterations < max_iter:
            changed = False
            self.iterations += 1
            for a, b, c in itertools.product(regions, repeat=3):
                if a == b or b == c:
                    continue
                rels_ab = self.net.get(a, b)
                rels_bc = self.net.get(b, c)
                if not rels_ab or not rels_bc:
                    continue

                possible = set()
                for r1 in rels_ab:
                    for r2 in rels_bc:
                        possible |= COMPOSITION.get((r1, r2), set(RELATIONS))

                if not possible:
                    return False

                if self.net.refine(a, c, possible):
                    changed = True
                    self.inferred_count += 1

        return self.net.is_consistent()

    def get_all_relations(self) -> List[Tuple[str, str, str]]:
        result = []
        for (a, b), rels in self.net.constraints.items():
            if a == b:
                continue
            for r in sorted(rels):
                result.append((a, r, b))
        return result

    def to_rdflib(self) -> Graph:
        g = Graph()
        g.bind("rcc", RCC)
        g.bind("ex", EX)
        g.bind("owl", OWL)

        for rel in RELATIONS:
            prop = RCC[rel]
            g.add((prop, RDF.type, OWL.ObjectProperty))
            g.add((prop, RDFS.label, Literal(rel)))

        for a, rel, b in self.get_all_relations():
            g.add((EX[a], RCC[rel], EX[b]))

        return g

    def sparql_query(self, query: str):
        g = self.to_rdflib()
        return list(g.query(query))

# ---------------------------------------------------------------------------
# 5. Helper macros / high-level API
# ---------------------------------------------------------------------------
def print_network(reasoner: RCC8Reasoner):
    print("\n=== Current Constraint Network ===")
    for a, rel, b in sorted(reasoner.get_all_relations()):
        print(f" {a} --{rel}--> {b}")
    print(f"Regions: {sorted(reasoner.net.regions)}")
    print(f"Iterations performed: {reasoner.iterations}")
    print(f"Inferred refinements: {reasoner.inferred_count}")

def run_example_scenario():
    print("=" * 70)
    print("RCC-8 Hand-rolled Materialization Engine â€“ Example Execution")
    print("=" * 70)

    r = RCC8Reasoner()

    r.assert_fact("RoomA", "EC", "RoomB")
    r.assert_fact("RoomB", "TPP", "Building")
    r.assert_fact("Corridor", "NTPP", "Building")
    r.assert_fact("RoomA", "PO", "ZoneX")
    r.assert_fact("ZoneX", "DC", "RoomC")

    print("\n--- Before materialization ---")
    print_network(r)

    consistent = r.materialize()
    print(f"\nMaterialization finished. Consistent? {consistent}")

    print("\n--- After materialization (inferred relations) ---")
    print_network(r)

    g = r.to_rdflib()
    print(f"\nRDF triples materialized: {len(g)}")
    print(g.serialize(format="turtle")[:800], "...")

    q = """
    PREFIX rcc: <http://example.org/rcc8#>
    PREFIX ex: <http://example.org/spatial#>
    SELECT ?x ?y WHERE {
        ?x rcc:NTPP ?y .
    }
    """
    print("\nSPARQL result (NTPP relations):")
    for row in r.sparql_query(q):
        print(" ", row)

    return r

# ---------------------------------------------------------------------------
# 6. Additional utility macros (composition lookup, inverse, etc.)
# ---------------------------------------------------------------------------
def compose(r1: str, r2: str) -> Set[str]:
    return COMPOSITION.get((r1, r2), set(RELATIONS))

def is_inverse(r1: str, r2: str) -> bool:
    return INVERSE.get(r1) == r2

def all_possible_between(a: str, b: str, reasoner: RCC8Reasoner) -> Set[str]:
    return reasoner.net.get(a, b)

# ---------------------------------------------------------------------------
# 7. Larger synthetic test (to exercise the engine)
# ---------------------------------------------------------------------------
def stress_test(n_regions: int = 12):
    print("\n" + "=" * 70)
    print(f"Stress test with {n_regions} regions")
    r = RCC8Reasoner()
    regions = [f"R{i}" for i in range(n_regions)]
    for reg in regions:
        r.net.add_region(reg)

    for i in range(n_regions - 1):
        rel = RELATIONS[i % len(RELATIONS)]
        r.assert_fact(regions[i], rel, regions[i + 1])

    consistent = r.materialize(max_iter=50)
    print(f"Consistent: {consistent}")
    print(f"Iterations: {r.iterations}")
    print(f"Total directed constraints: {len(r.get_all_relations())}")
    return r

# ---------------------------------------------------------------------------
# 8. Main execution entry point
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    engine = run_example_scenario()

    print("\n" + "=" * 70)
    print("Engine ready. You can now assert more facts and call .materialize()")
    print("Example interactive usage:")
    print(" engine.assert_fact('Park', 'NTPP', 'City')")
    print(" engine.materialize()")
    print(" print_network(engine)")
    print("=" * 70)
