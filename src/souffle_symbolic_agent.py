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
souffle_symbolic_agent.py

SoufflÃ© subprocess bridge for a dense symbolic reasoning kernel.

Architecture:

    Agent
      |
      v
    Python orchestration
      |
      +--> Dictionary: Arabic + English
      |
      +--> Symbolic facts/rules
      |
      +--> Generated SoufflÃ© Datalog
      |
      v
    souffle compiler
      |
      v
    CSV relations
      |
      v
    Symbolic result index
      |
      v
    Agent reasoning state

The Python layer does not implement the Datalog evaluator.
SoufflÃ© is the Datalog compiler and evaluator.
"""

from __future__ import annotations

import csv
import hashlib
import json
import os
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


# ================================================================
# Configuration
# ================================================================

SOUFFLE_BINARY = os.environ.get("SOUFFLE", "souffle")

DEFAULT_TIMEOUT = int(
    os.environ.get("SOUFFLE_TIMEOUT", "120")
)

DEFAULT_WORKERS = int(
    os.environ.get("SOUFFLE_WORKERS", "0")
)


# ================================================================
# Symbol
# ================================================================

@dataclass(frozen=True, order=True)
class Symbol:
    value: str

    @property
    def normalized(self) -> str:
        return self.value.strip()

    def __str__(self) -> str:
        return self.value


# ================================================================
# Dictionary entry
# ================================================================

@dataclass(frozen=True)
class DictionaryEntry:
    key: str
    english: str
    arabic: str
    category: str = "general"
    aliases: Tuple[str, ...] = ()
    metadata: Tuple[Tuple[str, str], ...] = ()

    def as_record(self) -> Tuple[str, str, str, str]:
        return (
            self.key,
            self.english,
            self.arabic,
            self.category,
        )


# ================================================================
# Arabic + English dictionary
# ================================================================

class BilingualDictionary:

    def __init__(self) -> None:
        self.entries: Dict[str, DictionaryEntry] = {}

    def add(
        self,
        key: str,
        english: str,
        arabic: str,
        category: str = "general",
        aliases: Sequence[str] = (),
        metadata: Optional[Dict[str, str]] = None,
    ) -> None:

        if metadata is None:
            metadata = {}

        self.entries[key] = DictionaryEntry(
            key=key,
            english=english,
            arabic=arabic,
            category=category,
            aliases=tuple(aliases),
            metadata=tuple(sorted(metadata.items())),
        )

    def get(self, key: str) -> Optional[DictionaryEntry]:
        return self.entries.get(key)

    def __contains__(self, key: str) -> bool:
        return key in self.entries

    def __len__(self) -> int:
        return len(self.entries)

    def records(self) -> Iterable[Tuple[str, str, str, str]]:
        for entry in self.entries.values():
            yield entry.as_record()


# ================================================================
# Symbolic fact
# ================================================================

@dataclass(frozen=True)
class Fact:
    predicate: str
    arguments: Tuple[str, ...]

    def arity(self) -> int:
        return len(self.arguments)


# ================================================================
# Symbolic rule
# ================================================================

@dataclass(frozen=True)
class Rule:
    head: Fact
    body: Tuple[Fact, ...]
    negated_body: Tuple[Fact, ...] = ()

    def arity(self) -> int:
        return self.head.arity()


# ================================================================
# Reasoning result
# ================================================================

@dataclass
class ReasoningResult:
    relation: str
    rows: List[Tuple[str, ...]] = field(default_factory=list)

    @property
    def count(self) -> int:
        return len(self.rows)


# ================================================================
# Symbolic kernel
# ================================================================

class SymbolicKernel:

    def __init__(self) -> None:
        self.facts: List[Fact] = []
        self.rules: List[Rule] = []
        self.relations: Dict[str, int] = {}
        self.outputs: List[str] = []

    def declare(
        self,
        predicate: str,
        arity: int,
    ) -> None:

        previous = self.relations.get(predicate)

        if previous is not None and previous != arity:
            raise ValueError(
                f"arity conflict: {predicate}: "
                f"{previous} != {arity}"
            )

        self.relations[predicate] = arity

    def fact(
        self,
        predicate: str,
        *arguments: str,
    ) -> None:

        self.declare(predicate, len(arguments))

        self.facts.append(
            Fact(
                predicate,
                tuple(arguments),
            )
        )

    def rule(
        self,
        head: Fact,
        *body: Fact,
        negated_body: Sequence[Fact] = (),
    ) -> None:

        self.declare(
            head.predicate,
            head.arity(),
        )

        for atom in body:
            self.declare(
                atom.predicate,
                atom.arity(),
            )

        for atom in negated_body:
            self.declare(
                atom.predicate,
                atom.arity(),
            )

        self.rules.append(
            Rule(
                head=head,
                body=tuple(body),
                negated_body=tuple(negated_body),
            )
        )

    def output(
        self,
        predicate: str,
    ) -> None:

        if predicate not in self.relations:
            raise ValueError(
                f"unknown relation: {predicate}"
            )

        if predicate not in self.outputs:
            self.outputs.append(predicate)


# ================================================================
# SoufflÃ© identifier escaping
# ================================================================

def souffle_string(value: str) -> str:
    escaped = (
        value
        .replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "\\r")
    )

    return f'"{escaped}"'


# ================================================================
# SoufflÃ© variable detection
# ================================================================

def is_variable(value: str) -> bool:
    if not value:
        return False

    return (
        value[0].isupper()
        or value[0] == "_"
    )


# ================================================================
# SoufflÃ© source builder
# ================================================================

class SouffleBuilder:

    def __init__(
        self,
        kernel: SymbolicKernel,
    ) -> None:

        self.kernel = kernel

    def build(self) -> str:

        lines: List[str] = []

        lines.append(
            ".type Symbol = symbol"
        )

        lines.append("")

        for predicate, arity in sorted(
            self.kernel.relations.items()
        ):

            columns = ", ".join(
                f"a{i}:Symbol"
                for i in range(arity)
            )

            lines.append(
                f".decl {predicate}({columns})"
            )

        lines.append("")

        for fact in self.kernel.facts:

            args = ", ".join(
                souffle_string(a)
                for a in fact.arguments
            )

            lines.append(
                f"{fact.predicate}({args})."
            )

        lines.append("")

        for rule in self.kernel.rules:

            head = self._atom(
                rule.head
            )

            body: List[str] = []

            for atom in rule.body:
                body.append(
                    self._atom(atom)
                )

            for atom in rule.negated_body:
                body.append(
                    "!" + self._atom(atom)
                )

            if body:
                lines.append(
                    f"{head} :-\n    "
                    + ",\n    ".join(body)
                    + "."
                )
            else:
                lines.append(
                    f"{head}."
                )

            lines.append("")

        for predicate in self.kernel.outputs:
            lines.append(
                f".output {predicate}"
            )

        lines.append("")

        return "\n".join(lines)

    @staticmethod
    def _atom(atom: Fact) -> str:

        args = ", ".join(
            (
                argument
                if is_variable(argument)
                else souffle_string(argument)
            )
            for argument in atom.arguments
        )

        return (
            f"{atom.predicate}"
            f"({args})"
        )


# ================================================================
# SoufflÃ© compiler
# ================================================================

class SouffleCompiler:

    def __init__(
        self,
        binary: str = SOUFFLE_BINARY,
        timeout: int = DEFAULT_TIMEOUT,
        workers: int = DEFAULT_WORKERS,
    ) -> None:

        self.binary = binary
        self.timeout = timeout
        self.workers = workers

    def check(self) -> None:

        result = subprocess.run(
            [
                self.binary,
                "--version",
            ],
            capture_output=True,
            text=True,
            timeout=15,
        )

        if result.returncode != 0:
            raise RuntimeError(
                result.stderr.strip()
            )

    def compile_and_run(
        self,
        source: str,
        outputs: Sequence[str],
    ) -> Dict[str, ReasoningResult]:

        with tempfile.TemporaryDirectory(
            prefix="souffle_symbolic_"
        ) as directory:

            root = Path(directory)

            program_file = (
                root / "kernel.dl"
            )

            output_directory = (
                root / "output"
            )

            output_directory.mkdir()

            program_file.write_text(
                source,
                encoding="utf-8",
            )

            command = [
                self.binary,
                str(program_file),
                "-D",
                str(output_directory),
            ]

            if self.workers > 0:
                command.extend(
                    [
                        "-j",
                        str(self.workers),
                    ]
                )

            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=self.timeout,
            )

            if result.returncode != 0:
                raise RuntimeError(
                    "SoufflÃ© failed:\n"
                    + result.stderr
                )

            return {
                relation: self._read_relation(
                    output_directory,
                    relation,
                )
                for relation in outputs
            }

    @staticmethod
    def _read_relation(
        directory: Path,
        relation: str,
    ) -> ReasoningResult:

        candidates = [
            directory / f"{relation}.csv",
            directory / f"{relation}.tsv",
        ]

        file_path = next(
            (
                path
                for path in candidates
                if path.exists()
            ),
            None,
        )

        if file_path is None:
            return ReasoningResult(
                relation=relation,
                rows=[],
            )

        delimiter = (
            "\t"
            if file_path.suffix == ".tsv"
            else ","
        )

        rows: List[Tuple[str, ...]] = []

        with file_path.open(
            "r",
            encoding="utf-8",
            newline="",
        ) as handle:

            reader = csv.reader(
                handle,
                delimiter=delimiter,
            )

            for row in reader:
                rows.append(
                    tuple(row)
                )

        return ReasoningResult(
            relation=relation,
            rows=rows,
        )


# ================================================================
# Dense reasoning kernel
# ================================================================

class DenseReasoningKernel:

    def __init__(
        self,
        compiler: Optional[SouffleCompiler] = None,
    ) -> None:

        self.dictionary = (
            BilingualDictionary()
        )

        self.kernel = SymbolicKernel()

        self.compiler = (
            compiler
            or SouffleCompiler()
        )

        self.results: Dict[
            str,
            ReasoningResult,
        ] = {}

    def add_dictionary_entry(
        self,
        key: str,
        english: str,
        arabic: str,
        category: str = "general",
        aliases: Sequence[str] = (),
    ) -> None:

        self.dictionary.add(
            key=key,
            english=english,
            arabic=arabic,
            category=category,
            aliases=aliases,
        )

    def add_fact(
        self,
        predicate: str,
        *arguments: str,
    ) -> None:

        self.kernel.fact(
            predicate,
            *arguments,
        )

    def add_rule(
        self,
        head: Fact,
        *body: Fact,
        negated_body: Sequence[Fact] = (),
    ) -> None:

        self.kernel.rule(
            head,
            *body,
            negated_body=negated_body,
        )

    def expose(
        self,
        predicate: str,
    ) -> None:

        self.kernel.output(
            predicate
        )

    def source(self) -> str:

        return SouffleBuilder(
            self.kernel
        ).build()

    def reason(self) -> Dict[
        str,
        ReasoningResult,
    ]:

        source = self.source()

        self.results = (
            self.compiler.compile_and_run(
                source,
                self.kernel.outputs,
            )
        )

        return self.results


# ================================================================
# Bilingual symbolic relations
# ================================================================

def build_bilingual_kernel() -> DenseReasoningKernel:

    engine = DenseReasoningKernel()

    engine.kernel.declare(
        "dictionary",
        4,
    )

    engine.kernel.declare(
        "english_term",
        2,
    )

    engine.kernel.declare(
        "arabic_term",
        2,
    )

    engine.kernel.declare(
        "translation",
        3,
    )

    engine.kernel.declare(
        "semantic",
        3,
    )

    engine.kernel.declare(
        "concept",
        2,
    )

    engine.kernel.declare(
        "relation",
        3,
    )

    engine.kernel.declare(
        "inference",
        3,
    )

    engine.kernel.declare(
        "reachable",
        2,
    )

    engine.kernel.declare(
        "equivalent",
        2,
    )

    engine.kernel.declare(
        "not_equivalent",
        2,
    )

    engine.kernel.declare(
        "active_concept",
        2,
    )

    engine.kernel.declare(
        "reasoning_path",
        3,
    )

    for entry in default_dictionary_entries():

        engine.add_dictionary_entry(
            entry.key,
            entry.english,
            entry.arabic,
            entry.category,
            entry.aliases,
        )

        engine.add_fact(
            "dictionary",
            entry.key,
            entry.english,
            entry.arabic,
            entry.category,
        )

        engine.add_fact(
            "english_term",
            entry.key,
            entry.english,
        )

        engine.add_fact(
            "arabic_term",
            entry.key,
            entry.arabic,
        )

    engine.add_rule(
        Fact(
            "translation",
            "X",
            "E",
            "A",
        ),
        Fact(
            "english_term",
            "X",
            "E",
        ),
        Fact(
            "arabic_term",
            "X",
            "A",
        ),
    )

    engine.add_rule(
        Fact(
            "concept",
            "X",
            "C",
        ),
        Fact(
            "dictionary",
            "X",
            "E",
            "A",
            "C",
        ),
    )

    engine.add_rule(
        Fact(
            "semantic",
            "X",
            "E",
            "A",
        ),
        Fact(
            "translation",
            "X",
            "E",
            "A",
        ),
    )

    engine.add_rule(
        Fact(
            "reachable",
            "X",
            "Y",
        ),
        Fact(
            "relation",
            "X",
            "Y",
            "R",
        ),
    )

    engine.add_rule(
        Fact(
            "reachable",
            "X",
            "Y",
        ),
        Fact(
            "relation",
            "X",
            "Z",
            "R",
        ),
        Fact(
            "reachable",
            "Z",
            "Y",
        ),
    )

    engine.add_rule(
        Fact(
            "reasoning_path",
            "X",
            "Y",
            "R",
        ),
        Fact(
            "relation",
            "X",
            "Y",
            "R",
        ),
    )

    engine.add_rule(
        Fact(
            "reasoning_path",
            "X",
            "Y",
            "R",
        ),
        Fact(
            "relation",
            "X",
            "Z",
            "R",
        ),
        Fact(
            "reachable",
            "Z",
            "Y",
        ),
    )

    engine.add_rule(
        Fact(
            "active_concept",
            "X",
            "C",
        ),
        Fact(
            "concept",
            "X",
            "C",
        ),
    )

    engine.expose(
        "dictionary"
    )

    engine.expose(
        "translation"
    )

    engine.expose(
        "semantic"
    )

    engine.expose(
        "concept"
    )

    engine.expose(
        "reachable"
    )

    engine.expose(
        "reasoning_path"
    )

    engine.expose(
        "active_concept"
    )

    return engine


# ================================================================
# Dictionary seed
# ================================================================

def default_dictionary_entries() -> List[
    DictionaryEntry
]:

    return [

        DictionaryEntry(
            "logic",
            "logic",
            "Ù…Ù†Ø·Ù‚",
            "reasoning",
        ),

        DictionaryEntry(
            "reason",
            "reason",
            "Ø§Ø³ØªØ¯Ù„Ø§Ù„",
            "reasoning",
        ),

        DictionaryEntry(
            "knowledge",
            "knowledge",
            "Ù…Ø¹Ø±ÙØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "concept",
            "concept",
            "Ù…ÙÙ‡ÙˆÙ…",
            "semantic",
        ),

        DictionaryEntry(
            "relation",
            "relation",
            "Ø¹Ù„Ø§Ù‚Ø©",
            "semantic",
        ),

        DictionaryEntry(
            "fact",
            "fact",
            "Ø­Ù‚ÙŠÙ‚Ø©",
            "logic",
        ),

        DictionaryEntry(
            "rule",
            "rule",
            "Ù‚Ø§Ø¹Ø¯Ø©",
            "logic",
        ),

        DictionaryEntry(
            "proof",
            "proof",
            "Ø¨Ø±Ù‡Ø§Ù†",
            "logic",
        ),

        DictionaryEntry(
            "inference",
            "inference",
            "Ø§Ø³ØªÙ†ØªØ§Ø¬",
            "reasoning",
        ),

        DictionaryEntry(
            "symbol",
            "symbol",
            "Ø±Ù…Ø²",
            "language",
        ),

        DictionaryEntry(
            "language",
            "language",
            "Ù„ØºØ©",
            "language",
        ),

        DictionaryEntry(
            "arabic",
            "Arabic",
            "Ø§Ù„Ø¹Ø±Ø¨ÙŠØ©",
            "language",
        ),

        DictionaryEntry(
            "english",
            "English",
            "Ø§Ù„Ø¥Ù†Ø¬Ù„ÙŠØ²ÙŠØ©",
            "language",
        ),

        DictionaryEntry(
            "truth",
            "truth",
            "Ø­Ù‚ÙŠÙ‚Ø©",
            "logic",
        ),

        DictionaryEntry(
            "false",
            "false",
            "Ø®Ø·Ø£",
            "logic",
        ),

        DictionaryEntry(
            "true",
            "true",
            "ØµØ­ÙŠØ­",
            "logic",
        ),

        DictionaryEntry(
            "set",
            "set",
            "Ù…Ø¬Ù…ÙˆØ¹Ø©",
            "mathematics",
        ),

        DictionaryEntry(
            "number",
            "number",
            "Ø¹Ø¯Ø¯",
            "mathematics",
        ),

        DictionaryEntry(
            "function",
            "function",
            "Ø¯Ø§Ù„Ø©",
            "mathematics",
        ),

        DictionaryEntry(
            "structure",
            "structure",
            "Ø¨Ù†ÙŠØ©",
            "mathematics",
        ),

        DictionaryEntry(
            "system",
            "system",
            "Ù†Ø¸Ø§Ù…",
            "architecture",
        ),

        DictionaryEntry(
            "state",
            "state",
            "Ø­Ø§Ù„Ø©",
            "architecture",
        ),

        DictionaryEntry(
            "transition",
            "transition",
            "Ø§Ù†ØªÙ‚Ø§Ù„",
            "architecture",
        ),

        DictionaryEntry(
            "network",
            "network",
            "Ø´Ø¨ÙƒØ©",
            "architecture",
        ),

        DictionaryEntry(
            "graph",
            "graph",
            "Ø±Ø³Ù… Ø¨ÙŠØ§Ù†ÙŠ",
            "mathematics",
        ),

        DictionaryEntry(
            "node",
            "node",
            "Ø¹Ù‚Ø¯Ø©",
            "graph",
        ),

        DictionaryEntry(
            "edge",
            "edge",
            "Ø­Ø§ÙØ©",
            "graph",
        ),

        DictionaryEntry(
            "path",
            "path",
            "Ù…Ø³Ø§Ø±",
            "graph",
        ),

        DictionaryEntry(
            "root",
            "root",
            "Ø¬Ø°Ø±",
            "graph",
        ),

        DictionaryEntry(
            "ancestor",
            "ancestor",
            "Ø³Ù„Ù",
            "graph",
        ),

        DictionaryEntry(
            "descendant",
            "descendant",
            "Ù†Ø³Ù„",
            "graph",
        ),

        DictionaryEntry(
            "parent",
            "parent",
            "ÙˆØ§Ù„Ø¯",
            "graph",
        ),

        DictionaryEntry(
            "child",
            "child",
            "Ø§Ø¨Ù†",
            "graph",
        ),

        DictionaryEntry(
            "equivalence",
            "equivalence",
            "ØªÙƒØ§ÙØ¤",
            "logic",
        ),

        DictionaryEntry(
            "identity",
            "identity",
            "Ù‡ÙˆÙŠØ©",
            "logic",
        ),

        DictionaryEntry(
            "difference",
            "difference",
            "Ø§Ø®ØªÙ„Ø§Ù",
            "logic",
        ),

        DictionaryEntry(
            "dependency",
            "dependency",
            "Ø§Ø¹ØªÙ…Ø§Ø¯",
            "architecture",
        ),

        DictionaryEntry(
            "input",
            "input",
            "Ù…Ø¯Ø®Ù„",
            "system",
        ),

        DictionaryEntry(
            "output",
            "output",
            "Ù…Ø®Ø±Ø¬",
            "system",
        ),

        DictionaryEntry(
            "compile",
            "compile",
            "ØªØ±Ø¬Ù…Ø©",
            "system",
        ),

        DictionaryEntry(
            "execute",
            "execute",
            "ØªÙ†ÙÙŠØ°",
            "system",
        ),

        DictionaryEntry(
            "query",
            "query",
            "Ø§Ø³ØªØ¹Ù„Ø§Ù…",
            "database",
        ),

        DictionaryEntry(
            "database",
            "database",
            "Ù‚Ø§Ø¹Ø¯Ø© Ø¨ÙŠØ§Ù†Ø§Øª",
            "database",
        ),

        DictionaryEntry(
            "relation_database",
            "relational database",
            "Ù‚Ø§Ø¹Ø¯Ø© Ø¨ÙŠØ§Ù†Ø§Øª Ø¹Ù„Ø§Ø¦Ù‚ÙŠØ©",
            "database",
        ),

        DictionaryEntry(
            "predicate",
            "predicate",
            "Ù…Ø­Ù…ÙˆÙ„",
            "logic",
        ),

        DictionaryEntry(
            "variable",
            "variable",
            "Ù…ØªØºÙŠØ±",
            "logic",
        ),

        DictionaryEntry(
            "constant",
            "constant",
            "Ø«Ø§Ø¨Øª",
            "logic",
        ),

        DictionaryEntry(
            "term",
            "term",
            "Ø­Ø¯",
            "logic",
        ),

        DictionaryEntry(
            "atom",
            "atom",
            "Ø°Ø±Ø©",
            "logic",
        ),

        DictionaryEntry(
            "negation",
            "negation",
            "Ù†ÙÙŠ",
            "logic",
        ),

        DictionaryEntry(
            "stratum",
            "stratum",
            "Ø·Ø¨Ù‚Ø©",
            "logic",
        ),

        DictionaryEntry(
            "recursive",
            "recursive",
            "ØªÙƒØ±Ø§Ø±ÙŠ",
            "logic",
        ),

        DictionaryEntry(
            "deterministic",
            "deterministic",
            "Ø­ØªÙ…ÙŠ",
            "system",
        ),

        DictionaryEntry(
            "symbolic",
            "symbolic",
            "Ø±Ù…Ø²ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "semantic_reasoning",
            "semantic reasoning",
            "Ø§Ø³ØªØ¯Ù„Ø§Ù„ Ø¯Ù„Ø§Ù„ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "formal_reasoning",
            "formal reasoning",
            "Ø§Ø³ØªØ¯Ù„Ø§Ù„ ØµÙˆØ±ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "deduction",
            "deduction",
            "Ø§Ø³ØªÙ†Ø¨Ø§Ø·",
            "reasoning",
        ),

        DictionaryEntry(
            "derivation",
            "derivation",
            "Ø§Ø´ØªÙ‚Ø§Ù‚",
            "reasoning",
        ),

        DictionaryEntry(
            "closure",
            "closure",
            "Ø¥ØºÙ„Ø§Ù‚",
            "mathematics",
        ),

        DictionaryEntry(
            "fixed_point",
            "fixed point",
            "Ù†Ù‚Ø·Ø© Ø«Ø§Ø¨ØªØ©",
            "mathematics",
        ),

        DictionaryEntry(
            "iteration",
            "iteration",
            "ØªÙƒØ±Ø§Ø±",
            "mathematics",
        ),

        DictionaryEntry(
            "invariant",
            "invariant",
            "Ø«Ø§Ø¨Øª Ø¨Ù†ÙŠÙˆÙŠ",
            "mathematics",
        ),

        DictionaryEntry(
            "verification",
            "verification",
            "ØªØ­Ù‚Ù‚",
            "logic",
        ),

        DictionaryEntry(
            "validation",
            "validation",
            "ØªØµØ¯ÙŠÙ‚",
            "system",
        ),

        DictionaryEntry(
            "constraint",
            "constraint",
            "Ù‚ÙŠØ¯",
            "logic",
        ),

        DictionaryEntry(
            "model",
            "model",
            "Ù†Ù…ÙˆØ°Ø¬",
            "reasoning",
        ),

        DictionaryEntry(
            "schema",
            "schema",
            "Ù…Ø®Ø·Ø·",
            "database",
        ),

        DictionaryEntry(
            "index",
            "index",
            "ÙÙ‡Ø±Ø³",
            "database",
        ),

        DictionaryEntry(
            "tuple",
            "tuple",
            "ØµÙ",
            "database",
        ),

        DictionaryEntry(
            "join",
            "join",
            "Ø¶Ù…",
            "database",
        ),

        DictionaryEntry(
            "projection",
            "projection",
            "Ø¥Ø³Ù‚Ø§Ø·",
            "database",
        ),

        DictionaryEntry(
            "recursion",
            "recursion",
            "Ø§Ø³ØªØ¯Ø¹Ø§Ø¡ Ø°Ø§ØªÙŠ",
            "logic",
        ),

        DictionaryEntry(
            "compiler",
            "compiler",
            "Ù…ØªØ±Ø¬Ù…",
            "system",
        ),

        DictionaryEntry(
            "kernel",
            "kernel",
            "Ù†ÙˆØ§Ø©",
            "system",
        ),

        DictionaryEntry(
            "agent",
            "agent",
            "ÙˆÙƒÙŠÙ„",
            "system",
        ),

        DictionaryEntry(
            "context",
            "context",
            "Ø³ÙŠØ§Ù‚",
            "reasoning",
        ),

        DictionaryEntry(
            "memory",
            "memory",
            "Ø°Ø§ÙƒØ±Ø©",
            "system",
        ),

        DictionaryEntry(
            "knowledge_graph",
            "knowledge graph",
            "Ø±Ø³Ù… Ø¨ÙŠØ§Ù†ÙŠ Ù…Ø¹Ø±ÙÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "translation",
            "translation",
            "ØªØ±Ø¬Ù…Ø©",
            "language",
        ),

        DictionaryEntry(
            "meaning",
            "meaning",
            "Ù…Ø¹Ù†Ù‰",
            "language",
        ),

        DictionaryEntry(
            "word",
            "word",
            "ÙƒÙ„Ù…Ø©",
            "language",
        ),

        DictionaryEntry(
            "sentence",
            "sentence",
            "Ø¬Ù…Ù„Ø©",
            "language",
        ),

        DictionaryEntry(
            "text",
            "text",
            "Ù†Øµ",
            "language",
        ),

        DictionaryEntry(
            "character",
            "character",
            "Ø­Ø±Ù",
            "language",
        ),

        DictionaryEntry(
            "unicode",
            "Unicode",
            "ÙŠÙˆÙ†ÙŠÙƒÙˆØ¯",
            "language",
        ),

        DictionaryEntry(
            "utf8",
            "UTF-8",
            "UTF-8",
            "encoding",
        ),

        DictionaryEntry(
            "encoding",
            "encoding",
            "ØªØ±Ù…ÙŠØ²",
            "encoding",
        ),

        DictionaryEntry(
            "normalization",
            "normalization",
            "ØªØ·Ø¨ÙŠØ¹",
            "language",
        ),

        DictionaryEntry(
            "token",
            "token",
            "Ø±Ù…Ø² Ù„ØºÙˆÙŠ",
            "language",
        ),

        DictionaryEntry(
            "lexicon",
            "lexicon",
            "Ù…Ø¹Ø¬Ù…",
            "language",
        ),

        DictionaryEntry(
            "ontology",
            "ontology",
            "Ø£Ù†Ø·ÙˆÙ„ÙˆØ¬ÙŠØ§",
            "reasoning",
        ),

        DictionaryEntry(
            "classification",
            "classification",
            "ØªØµÙ†ÙŠÙ",
            "reasoning",
        ),

        DictionaryEntry(
            "category",
            "category",
            "ÙØ¦Ø©",
            "logic",
        ),

        DictionaryEntry(
            "attribute",
            "attribute",
            "Ø®Ø§ØµÙŠØ©",
            "database",
        ),

        DictionaryEntry(
            "property",
            "property",
            "Ø®Ø§ØµÙŠØ©",
            "logic",
        ),

        DictionaryEntry(
            "entity",
            "entity",
            "ÙƒÙŠØ§Ù†",
            "ontology",
        ),

        DictionaryEntry(
            "object",
            "object",
            "ÙƒØ§Ø¦Ù†",
            "ontology",
        ),

        DictionaryEntry(
            "event",
            "event",
            "Ø­Ø¯Ø«",
            "reasoning",
        ),

        DictionaryEntry(
            "condition",
            "condition",
            "Ø´Ø±Ø·",
            "logic",
        ),

        DictionaryEntry(
            "conclusion",
            "conclusion",
            "Ø§Ø³ØªÙ†ØªØ§Ø¬ Ù†Ù‡Ø§Ø¦ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "premise",
            "premise",
            "Ù…Ù‚Ø¯Ù…Ø©",
            "logic",
        ),

        DictionaryEntry(
            "axiom",
            "axiom",
            "Ù…Ø³Ù„Ù…Ø©",
            "logic",
        ),

        DictionaryEntry(
            "theorem",
            "theorem",
            "Ù…Ø¨Ø±Ù‡Ù†Ø©",
            "logic",
        ),

        DictionaryEntry(
            "consistency",
            "consistency",
            "Ø§ØªØ³Ø§Ù‚",
            "logic",
        ),

        DictionaryEntry(
            "soundness",
            "soundness",
            "Ø³Ù„Ø§Ù…Ø©",
            "logic",
        ),

        DictionaryEntry(
            "completeness",
            "completeness",
            "Ø§ÙƒØªÙ…Ø§Ù„",
            "logic",
        ),

        DictionaryEntry(
            "truth_value",
            "truth value",
            "Ù‚ÙŠÙ…Ø© Ø§Ù„Ø­Ù‚ÙŠÙ‚Ø©",
            "logic",
        ),

        DictionaryEntry(
            "domain",
            "domain",
            "Ù…Ø¬Ø§Ù„",
            "mathematics",
        ),

        DictionaryEntry(
            "codomain",
            "codomain",
            "Ø§Ù„Ù…Ø¬Ø§Ù„ Ø§Ù„Ù…Ù‚Ø§Ø¨Ù„",
            "mathematics",
        ),

        DictionaryEntry(
            "mapping",
            "mapping",
            "ØªØ·Ø¨ÙŠÙ‚",
            "mathematics",
        ),

        DictionaryEntry(
            "composition",
            "composition",
            "ØªØ±ÙƒÙŠØ¨",
            "mathematics",
        ),

        DictionaryEntry(
            "order",
            "order",
            "ØªØ±ØªÙŠØ¨",
            "mathematics",
        ),

        DictionaryEntry(
            "partial_order",
            "partial order",
            "ØªØ±ØªÙŠØ¨ Ø¬Ø²Ø¦ÙŠ",
            "mathematics",
        ),

        DictionaryEntry(
            "lattice",
            "lattice",
            "Ø´Ø¨ÙƒØ© Ø±ÙŠØ§Ø¶ÙŠØ©",
            "mathematics",
        ),

        DictionaryEntry(
            "set_member",
            "set member",
            "Ø¹Ø¶Ùˆ Ù…Ø¬Ù…ÙˆØ¹Ø©",
            "mathematics",
        ),

        DictionaryEntry(
            "subset",
            "subset",
            "Ù…Ø¬Ù…ÙˆØ¹Ø© Ø¬Ø²Ø¦ÙŠØ©",
            "mathematics",
        ),

        DictionaryEntry(
            "intersection",
            "intersection",
            "ØªÙ‚Ø§Ø·Ø¹",
            "mathematics",
        ),

        DictionaryEntry(
            "union",
            "union",
            "Ø§ØªØ­Ø§Ø¯",
            "mathematics",
        ),

        DictionaryEntry(
            "difference_set",
            "set difference",
            "ÙØ±Ù‚ Ø§Ù„Ù…Ø¬Ù…ÙˆØ¹Ø§Øª",
            "mathematics",
        ),

        DictionaryEntry(
            "cardinality",
            "cardinality",
            "Ø¹Ø¯Ø¯ Ø§Ù„Ø¹Ù†Ø§ØµØ±",
            "mathematics",
        ),

        DictionaryEntry(
            "finite",
            "finite",
            "Ù…Ù†ØªÙ‡",
            "mathematics",
        ),

        DictionaryEntry(
            "infinite",
            "infinite",
            "Ù„Ø§Ù†Ù‡Ø§Ø¦ÙŠ",
            "mathematics",
        ),

        DictionaryEntry(
            "algorithm",
            "algorithm",
            "Ø®ÙˆØ§Ø±Ø²Ù…ÙŠØ©",
            "system",
        ),

        DictionaryEntry(
            "evaluation",
            "evaluation",
            "ØªÙ‚ÙŠÙŠÙ…",
            "logic",
        ),

        DictionaryEntry(
            "bottom_up",
            "bottom-up",
            "Ù…Ù† Ø§Ù„Ø£Ø³ÙÙ„ Ø¥Ù„Ù‰ Ø§Ù„Ø£Ø¹Ù„Ù‰",
            "logic",
        ),

        DictionaryEntry(
            "semi_naive",
            "semi-naive evaluation",
            "ØªÙ‚ÙŠÙŠÙ… Ø´Ø¨Ù‡ Ø³Ø§Ø°Ø¬",
            "logic",
        ),

        DictionaryEntry(
            "dependency_graph",
            "dependency graph",
            "Ø±Ø³Ù… Ø¨ÙŠØ§Ù†ÙŠ Ù„Ù„Ø§Ø¹ØªÙ…Ø§Ø¯",
            "logic",
        ),

        DictionaryEntry(
            "negative_dependency",
            "negative dependency",
            "Ø§Ø¹ØªÙ…Ø§Ø¯ Ø³Ù„Ø¨ÙŠ",
            "logic",
        ),

        DictionaryEntry(
            "positive_dependency",
            "positive dependency",
            "Ø§Ø¹ØªÙ…Ø§Ø¯ Ø¥ÙŠØ¬Ø§Ø¨ÙŠ",
            "logic",
        ),

        DictionaryEntry(
            "stratified_negation",
            "stratified negation",
            "Ø§Ù„Ù†ÙÙŠ Ø§Ù„Ø·Ø¨Ù‚ÙŠ",
            "logic",
        ),

        DictionaryEntry(
            "ground_fact",
            "ground fact",
            "Ø­Ù‚ÙŠÙ‚Ø© Ù…ÙƒØªÙ…Ù„Ø©",
            "logic",
        ),

        DictionaryEntry(
            "substitution",
            "substitution",
            "Ø§Ø³ØªØ¨Ø¯Ø§Ù„",
            "logic",
        ),

        DictionaryEntry(
            "unification",
            "unification",
            "ØªÙˆØ­ÙŠØ¯",
            "logic",
        ),

        DictionaryEntry(
            "variable_binding",
            "variable binding",
            "Ø±Ø¨Ø· Ø§Ù„Ù…ØªØºÙŠØ±",
            "logic",
        ),

        DictionaryEntry(
            "pattern",
            "pattern",
            "Ù†Ù…Ø·",
            "logic",
        ),

        DictionaryEntry(
            "match",
            "match",
            "Ù…Ø·Ø§Ø¨Ù‚Ø©",
            "logic",
        ),

        DictionaryEntry(
            "grounding",
            "grounding",
            "ØªØ«Ø¨ÙŠØª",
            "logic",
        ),

        DictionaryEntry(
            "derivation_tree",
            "derivation tree",
            "Ø´Ø¬Ø±Ø© Ø§Ù„Ø§Ø´ØªÙ‚Ø§Ù‚",
            "logic",
        ),

        DictionaryEntry(
            "proof_tree",
            "proof tree",
            "Ø´Ø¬Ø±Ø© Ø§Ù„Ø¨Ø±Ù‡Ø§Ù†",
            "logic",
        ),

        DictionaryEntry(
            "dependency",
            "dependency",
            "ØªØ¨Ø¹ÙŠØ©",
            "architecture",
        ),

        DictionaryEntry(
            "pipeline",
            "pipeline",
            "Ø®Ø· Ù…Ø¹Ø§Ù„Ø¬Ø©",
            "architecture",
        ),

        DictionaryEntry(
            "compiler_pass",
            "compiler pass",
            "Ù…Ø±Ø­Ù„Ø© Ù…ØªØ±Ø¬Ù…",
            "compiler",
        ),

        DictionaryEntry(
            "intermediate_representation",
            "intermediate representation",
            "ØªÙ…Ø«ÙŠÙ„ ÙˆØ³ÙŠØ·",
            "compiler",
        ),

        DictionaryEntry(
            "runtime",
            "runtime",
            "Ø¨ÙŠØ¦Ø© ØªØ´ØºÙŠÙ„",
            "system",
        ),

        DictionaryEntry(
            "process",
            "process",
            "Ø¹Ù…Ù„ÙŠØ©",
            "system",
        ),

        DictionaryEntry(
            "subprocess",
            "subprocess",
            "Ø¹Ù…Ù„ÙŠØ© ÙØ±Ø¹ÙŠØ©",
            "system",
        ),

        DictionaryEntry(
            "filesystem",
            "filesystem",
            "Ù†Ø¸Ø§Ù… Ù…Ù„ÙØ§Øª",
            "system",
        ),

        DictionaryEntry(
            "temporary_directory",
            "temporary directory",
            "Ø¯Ù„ÙŠÙ„ Ù…Ø¤Ù‚Øª",
            "system",
        ),

        DictionaryEntry(
            "csv",
            "CSV",
            "CSV",
            "encoding",
        ),

        DictionaryEntry(
            "serialization",
            "serialization",
            "ØªØ³Ù„Ø³Ù„",
            "system",
        ),

        DictionaryEntry(
            "hash",
            "hash",
            "Ø¨ØµÙ…Ø©",
            "security",
        ),

        DictionaryEntry(
            "integrity",
            "integrity",
            "Ø³Ù„Ø§Ù…Ø©",
            "security",
        ),

        DictionaryEntry(
            "determinism",
            "determinism",
            "Ø­ØªÙ…ÙŠØ©",
            "security",
        ),

        DictionaryEntry(
            "audit",
            "audit",
            "ØªØ¯Ù‚ÙŠÙ‚",
            "security",
        ),

        DictionaryEntry(
            "trace",
            "trace",
            "ØªØªØ¨Ø¹",
            "reasoning",
        ),

        DictionaryEntry(
            "explain",
            "explain",
            "Ø´Ø±Ø­",
            "reasoning",
        ),

        DictionaryEntry(
            "evidence",
            "evidence",
            "Ø¯Ù„ÙŠÙ„",
            "reasoning",
        ),

        DictionaryEntry(
            "assertion",
            "assertion",
            "ØªØ£ÙƒÙŠØ¯",
            "logic",
        ),

        DictionaryEntry(
            "verification_state",
            "verification state",
            "Ø­Ø§Ù„Ø© Ø§Ù„ØªØ­Ù‚Ù‚",
            "logic",
        ),

        DictionaryEntry(
            "accepted",
            "accepted",
            "Ù…Ù‚Ø¨ÙˆÙ„",
            "verification",
        ),

        DictionaryEntry(
            "rejected",
            "rejected",
            "Ù…Ø±ÙÙˆØ¶",
            "verification",
        ),

        DictionaryEntry(
            "unknown",
            "unknown",
            "ØºÙŠØ± Ù…Ø¹Ø±ÙˆÙ",
            "reasoning",
        ),

        DictionaryEntry(
            "known",
            "known",
            "Ù…Ø¹Ø±ÙˆÙ",
            "reasoning",
        ),

        DictionaryEntry(
            "derived",
            "derived",
            "Ù…Ø´ØªÙ‚",
            "reasoning",
        ),

        DictionaryEntry(
            "source",
            "source",
            "Ù…ØµØ¯Ø±",
            "reasoning",
        ),

        DictionaryEntry(
            "target",
            "target",
            "Ù‡Ø¯Ù",
            "reasoning",
        ),

        DictionaryEntry(
            "dependency_edge",
            "dependency edge",
            "Ø­Ø§ÙØ© Ø§Ø¹ØªÙ…Ø§Ø¯",
            "graph",
        ),

        DictionaryEntry(
            "semantic_edge",
            "semantic edge",
            "Ø­Ø§ÙØ© Ø¯Ù„Ø§Ù„ÙŠØ©",
            "graph",
        ),

        DictionaryEntry(
            "logical_edge",
            "logical edge",
            "Ø­Ø§ÙØ© Ù…Ù†Ø·Ù‚ÙŠØ©",
            "graph",
        ),

        DictionaryEntry(
            "activation",
            "activation",
            "ØªÙ†Ø´ÙŠØ·",
            "reasoning",
        ),

        DictionaryEntry(
            "selection",
            "selection",
            "Ø§Ø®ØªÙŠØ§Ø±",
            "reasoning",
        ),

        DictionaryEntry(
            "resolution",
            "resolution",
            "Ø­Ù„",
            "logic",
        ),

        DictionaryEntry(
            "conflict",
            "conflict",
            "ØªØ¹Ø§Ø±Ø¶",
            "logic",
        ),

        DictionaryEntry(
            "agreement",
            "agreement",
            "Ø§ØªÙØ§Ù‚",
            "logic",
        ),

        DictionaryEntry(
            "contradiction",
            "contradiction",
            "ØªÙ†Ø§Ù‚Ø¶",
            "logic",
        ),

        DictionaryEntry(
            "consensus",
            "consensus",
            "Ø¥Ø¬Ù…Ø§Ø¹",
            "reasoning",
        ),

        DictionaryEntry(
            "priority",
            "priority",
            "Ø£ÙˆÙ„ÙˆÙŠØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "weight",
            "weight",
            "ÙˆØ²Ù†",
            "mathematics",
        ),

        DictionaryEntry(
            "score",
            "score",
            "Ø¯Ø±Ø¬Ø©",
            "reasoning",
        ),

        DictionaryEntry(
            "threshold",
            "threshold",
            "Ø¹ØªØ¨Ø©",
            "reasoning",
        ),

        DictionaryEntry(
            "rank",
            "rank",
            "Ø±ØªØ¨Ø©",
            "mathematics",
        ),

        DictionaryEntry(
            "dimension",
            "dimension",
            "Ø¨ÙØ¹Ø¯",
            "mathematics",
        ),

        DictionaryEntry(
            "matrix",
            "matrix",
            "Ù…ØµÙÙˆÙØ©",
            "mathematics",
        ),

        DictionaryEntry(
            "vector",
            "vector",
            "Ù…ØªØ¬Ù‡",
            "mathematics",
        ),

        DictionaryEntry(
            "tensor",
            "tensor",
            "Ù…ÙˆØªØ±",
            "mathematics",
        ),

        DictionaryEntry(
            "operation",
            "operation",
            "Ø¹Ù…Ù„ÙŠØ©",
            "mathematics",
        ),

        DictionaryEntry(
            "composition_rule",
            "composition rule",
            "Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„ØªØ±ÙƒÙŠØ¨",
            "logic",
        ),

        DictionaryEntry(
            "rewrite",
            "rewrite",
            "Ø¥Ø¹Ø§Ø¯Ø© ÙƒØªØ§Ø¨Ø©",
            "logic",
        ),

        DictionaryEntry(
            "normal_form",
            "normal form",
            "ØµÙŠØºØ© Ù…Ø¹ÙŠØ§Ø±ÙŠØ©",
            "logic",
        ),

        DictionaryEntry(
            "canonical",
            "canonical",
            "Ù‚ÙŠØ§Ø³ÙŠ",
            "mathematics",
        ),

        DictionaryEntry(
            "representation",
            "representation",
            "ØªÙ…Ø«ÙŠÙ„",
            "system",
        ),

        DictionaryEntry(
            "serialization_format",
            "serialization format",
            "ØªÙ†Ø³ÙŠÙ‚ Ø§Ù„ØªØ³Ù„Ø³Ù„",
            "system",
        ),

        DictionaryEntry(
            "configuration",
            "configuration",
            "ØªÙ‡ÙŠØ¦Ø©",
            "system",
        ),

        DictionaryEntry(
            "parameter",
            "parameter",
            "Ù…Ø¹Ø§Ù…Ù„",
            "mathematics",
        ),

        DictionaryEntry(
            "argument",
            "argument",
            "ÙˆØ³ÙŠØ·",
            "logic",
        ),

        DictionaryEntry(
            "arity",
            "arity",
            "Ø±ØªØ¨Ø© Ø§Ù„Ø¹Ù„Ø§Ù‚Ø©",
            "logic",
        ),

        DictionaryEntry(
            "predicate_symbol",
            "predicate symbol",
            "Ø±Ù…Ø² Ø§Ù„Ù…Ø­Ù…ÙˆÙ„",
            "logic",
        ),

        DictionaryEntry(
            "relation_symbol",
            "relation symbol",
            "Ø±Ù…Ø² Ø§Ù„Ø¹Ù„Ø§Ù‚Ø©",
            "logic",
        ),

        DictionaryEntry(
            "database_fact",
            "database fact",
            "Ø­Ù‚ÙŠÙ‚Ø© Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„Ø¨ÙŠØ§Ù†Ø§Øª",
            "database",
        ),

        DictionaryEntry(
            "derived_relation",
            "derived relation",
            "Ø¹Ù„Ø§Ù‚Ø© Ù…Ø´ØªÙ‚Ø©",
            "database",
        ),

        DictionaryEntry(
            "base_relation",
            "base relation",
            "Ø¹Ù„Ø§Ù‚Ø© Ø£Ø³Ø§Ø³ÙŠØ©",
            "database",
        ),

        DictionaryEntry(
            "recursive_relation",
            "recursive relation",
            "Ø¹Ù„Ø§Ù‚Ø© ØªÙƒØ±Ø§Ø±ÙŠØ©",
            "database",
        ),

        DictionaryEntry(
            "query_result",
            "query result",
            "Ù†ØªÙŠØ¬Ø© Ø§Ù„Ø§Ø³ØªØ¹Ù„Ø§Ù…",
            "database",
        ),

        DictionaryEntry(
            "relation_algebra",
            "relational algebra",
            "Ø§Ù„Ø¬Ø¨Ø± Ø§Ù„Ø¹Ù„Ø§Ø¦Ù‚ÙŠ",
            "database",
        ),

        DictionaryEntry(
            "join_condition",
            "join condition",
            "Ø´Ø±Ø· Ø§Ù„Ø¶Ù…",
            "database",
        ),

        DictionaryEntry(
            "selection_condition",
            "selection condition",
            "Ø´Ø±Ø· Ø§Ù„Ø§Ø®ØªÙŠØ§Ø±",
            "database",
        ),

        DictionaryEntry(
            "projection_column",
            "projection column",
            "Ø¹Ù…ÙˆØ¯ Ø§Ù„Ø¥Ø³Ù‚Ø§Ø·",
            "database",
        ),

        DictionaryEntry(
            "closure_operator",
            "closure operator",
            "Ù…Ø¤Ø«Ø± Ø§Ù„Ø¥ØºÙ„Ø§Ù‚",
            "mathematics",
        ),

        DictionaryEntry(
            "fixed_point_operator",
            "fixed point operator",
            "Ù…Ø¤Ø«Ø± Ø§Ù„Ù†Ù‚Ø·Ø© Ø§Ù„Ø«Ø§Ø¨ØªØ©",
            "mathematics",
        ),

        DictionaryEntry(
            "least_fixed_point",
            "least fixed point",
            "Ø£ØµØºØ± Ù†Ù‚Ø·Ø© Ø«Ø§Ø¨ØªØ©",
            "mathematics",
        ),

        DictionaryEntry(
            "monotonic",
            "monotonic",
            "Ø±ØªÙŠØ¨",
            "mathematics",
        ),

        DictionaryEntry(
            "finite_model",
            "finite model",
            "Ù†Ù…ÙˆØ°Ø¬ Ù…Ù†ØªÙ‡",
            "logic",
        ),

        DictionaryEntry(
            "model_checking",
            "model checking",
            "ÙØ­Øµ Ø§Ù„Ù†Ù…ÙˆØ°Ø¬",
            "logic",
        ),

        DictionaryEntry(
            "formal_system",
            "formal system",
            "Ù†Ø¸Ø§Ù… ØµÙˆØ±ÙŠ",
            "logic",
        ),

        DictionaryEntry(
            "symbolic_execution",
            "symbolic execution",
            "ØªÙ†ÙÙŠØ° Ø±Ù…Ø²ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "symbolic_state",
            "symbolic state",
            "Ø­Ø§Ù„Ø© Ø±Ù…Ø²ÙŠØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "reasoning_kernel",
            "reasoning kernel",
            "Ù†ÙˆØ§Ø© Ø§Ù„Ø§Ø³ØªØ¯Ù„Ø§Ù„",
            "reasoning",
        ),

        DictionaryEntry(
            "dense_reasoning",
            "dense reasoning",
            "Ø§Ø³ØªØ¯Ù„Ø§Ù„ ÙƒØ«ÙŠÙ",
            "reasoning",
        ),

        DictionaryEntry(
            "knowledge_base",
            "knowledge base",
            "Ù‚Ø§Ø¹Ø¯Ø© Ù…Ø¹Ø±ÙØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "knowledge_relation",
            "knowledge relation",
            "Ø¹Ù„Ø§Ù‚Ø© Ù…Ø¹Ø±ÙÙŠØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "semantic_relation",
            "semantic relation",
            "Ø¹Ù„Ø§Ù‚Ø© Ø¯Ù„Ø§Ù„ÙŠØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "lexical_relation",
            "lexical relation",
            "Ø¹Ù„Ø§Ù‚Ø© Ù…Ø¹Ø¬Ù…ÙŠØ©",
            "language",
        ),

        DictionaryEntry(
            "bilingual",
            "bilingual",
            "Ø«Ù†Ø§Ø¦ÙŠ Ø§Ù„Ù„ØºØ©",
            "language",
        ),

        DictionaryEntry(
            "multilingual",
            "multilingual",
            "Ù…ØªØ¹Ø¯Ø¯ Ø§Ù„Ù„ØºØ§Øª",
            "language",
        ),

        DictionaryEntry(
            "arabic_script",
            "Arabic script",
            "Ø§Ù„Ø®Ø· Ø§Ù„Ø¹Ø±Ø¨ÙŠ",
            "language",
        ),

        DictionaryEntry(
            "right_to_left",
            "right-to-left",
            "Ù…Ù† Ø§Ù„ÙŠÙ…ÙŠÙ† Ø¥Ù„Ù‰ Ø§Ù„ÙŠØ³Ø§Ø±",
            "language",
        ),

        DictionaryEntry(
            "left_to_right",
            "left-to-right",
            "Ù…Ù† Ø§Ù„ÙŠØ³Ø§Ø± Ø¥Ù„Ù‰ Ø§Ù„ÙŠÙ…ÙŠÙ†",
            "language",
        ),

        DictionaryEntry(
            "bidirectional_text",
            "bidirectional text",
            "Ù†Øµ Ø«Ù†Ø§Ø¦ÙŠ Ø§Ù„Ø§ØªØ¬Ø§Ù‡",
            "language",
        ),

        DictionaryEntry(
            "unicode_symbol",
            "Unicode symbol",
            "Ø±Ù…Ø² ÙŠÙˆÙ†ÙŠÙƒÙˆØ¯",
            "encoding",
        ),

        DictionaryEntry(
            "arabic_semantics",
            "Arabic semantics",
            "Ø¯Ù„Ø§Ù„Ø§Øª Ø¹Ø±Ø¨ÙŠØ©",
            "language",
        ),

        DictionaryEntry(
            "english_semantics",
            "English semantics",
            "Ø¯Ù„Ø§Ù„Ø§Øª Ø¥Ù†Ø¬Ù„ÙŠØ²ÙŠØ©",
            "language",
        ),

        DictionaryEntry(
            "cross_language",
            "cross-language",
            "Ø¹Ø¨Ø± Ø§Ù„Ù„ØºØ§Øª",
            "language",
        ),

        DictionaryEntry(
            "semantic_equivalence",
            "semantic equivalence",
            "ØªÙƒØ§ÙØ¤ Ø¯Ù„Ø§Ù„ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "translation_edge",
            "translation edge",
            "Ø­Ø§ÙØ© ØªØ±Ø¬Ù…Ø©",
            "language",
        ),

        DictionaryEntry(
            "concept_identity",
            "concept identity",
            "Ù‡ÙˆÙŠØ© Ø§Ù„Ù…ÙÙ‡ÙˆÙ…",
            "reasoning",
        ),

        DictionaryEntry(
            "concept_relation",
            "concept relation",
            "Ø¹Ù„Ø§Ù‚Ø© Ø§Ù„Ù…ÙÙ‡ÙˆÙ…",
            "reasoning",
        ),

        DictionaryEntry(
            "knowledge_edge",
            "knowledge edge",
            "Ø­Ø§ÙØ© Ù…Ø¹Ø±ÙÙŠØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "reasoning_edge",
            "reasoning edge",
            "Ø­Ø§ÙØ© Ø§Ø³ØªØ¯Ù„Ø§Ù„ÙŠØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "proof_edge",
            "proof edge",
            "Ø­Ø§ÙØ© Ø¨Ø±Ù‡Ø§Ù†ÙŠØ©",
            "logic",
        ),

        DictionaryEntry(
            "derivation_edge",
            "derivation edge",
            "Ø­Ø§ÙØ© Ø§Ø´ØªÙ‚Ø§Ù‚",
            "logic",
        ),

        DictionaryEntry(
            "constraint_edge",
            "constraint edge",
            "Ø­Ø§ÙØ© Ù‚ÙŠØ¯",
            "logic",
        ),

        DictionaryEntry(
            "verification_edge",
            "verification edge",
            "Ø­Ø§ÙØ© ØªØ­Ù‚Ù‚",
            "verification",
        ),

        DictionaryEntry(
            "audit_edge",
            "audit edge",
            "Ø­Ø§ÙØ© ØªØ¯Ù‚ÙŠÙ‚",
            "security",
        ),

        DictionaryEntry(
            "trust",
            "trust",
            "Ø«Ù‚Ø©",
            "security",
        ),

        DictionaryEntry(
            "authorization",
            "authorization",
            "ØªÙÙˆÙŠØ¶",
            "security",
        ),

        DictionaryEntry(
            "permission",
            "permission",
            "Ø¥Ø°Ù†",
            "security",
        ),

        DictionaryEntry(
            "policy",
            "policy",
            "Ø³ÙŠØ§Ø³Ø©",
            "security",
        ),

        DictionaryEntry(
            "governance",
            "governance",
            "Ø­ÙˆÙƒÙ…Ø©",
            "security",
        ),

        DictionaryEntry(
            "provenance",
            "provenance",
            "Ù…ØµØ¯Ø±ÙŠØ©",
            "security",
        ),

        DictionaryEntry(
            "lineage",
            "lineage",
            "Ø³Ù„Ø³Ù„Ø© Ø§Ù„Ø£ØµÙ„",
            "reasoning",
        ),

        DictionaryEntry(
            "traceability",
            "traceability",
            "Ù‚Ø§Ø¨Ù„ÙŠØ© Ø§Ù„ØªØªØ¨Ø¹",
            "reasoning",
        ),

        DictionaryEntry(
            "reproducibility",
            "reproducibility",
            "Ù‚Ø§Ø¨Ù„ÙŠØ© Ø¥Ø¹Ø§Ø¯Ø© Ø§Ù„Ø¥Ù†ØªØ§Ø¬",
            "system",
        ),

        DictionaryEntry(
            "deterministic_output",
            "deterministic output",
            "Ù…Ø®Ø±Ø¬ Ø­ØªÙ…ÙŠ",
            "system",
        ),

        DictionaryEntry(
            "failure",
            "failure",
            "ÙØ´Ù„",
            "system",
        ),

        DictionaryEntry(
            "error",
            "error",
            "Ø®Ø·Ø£",
            "system",
        ),

        DictionaryEntry(
            "exception",
            "exception",
            "Ø§Ø³ØªØ«Ù†Ø§Ø¡",
            "system",
        ),

        DictionaryEntry(
            "timeout",
            "timeout",
            "Ù…Ù‡Ù„Ø©",
            "system",
        ),

        DictionaryEntry(
            "process_exit",
            "process exit",
            "Ø®Ø±ÙˆØ¬ Ø§Ù„Ø¹Ù…Ù„ÙŠØ©",
            "system",
        ),

        DictionaryEntry(
            "compiler_error",
            "compiler error",
            "Ø®Ø·Ø£ Ø§Ù„Ù…ØªØ±Ø¬Ù…",
            "compiler",
        ),

        DictionaryEntry(
            "compile_success",
            "compile success",
            "Ù†Ø¬Ø§Ø­ Ø§Ù„ØªØ±Ø¬Ù…Ø©",
            "compiler",
        ),

        DictionaryEntry(
            "result_set",
            "result set",
            "Ù…Ø¬Ù…ÙˆØ¹Ø© Ø§Ù„Ù†ØªØ§Ø¦Ø¬",
            "database",
        ),

        DictionaryEntry(
            "row",
            "row",
            "ØµÙ",
            "database",
        ),

        DictionaryEntry(
            "column",
            "column",
            "Ø¹Ù…ÙˆØ¯",
            "database",
        ),

        DictionaryEntry(
            "schema_declaration",
            "schema declaration",
            "ØªØµØ±ÙŠØ­ Ø§Ù„Ù…Ø®Ø·Ø·",
            "database",
        ),

        DictionaryEntry(
            "relation_declaration",
            "relation declaration",
            "ØªØµØ±ÙŠØ­ Ø§Ù„Ø¹Ù„Ø§Ù‚Ø©",
            "database",
        ),

        DictionaryEntry(
            "fact_store",
            "fact store",
            "Ù…Ø®Ø²Ù† Ø§Ù„Ø­Ù‚Ø§Ø¦Ù‚",
            "database",
        ),

        DictionaryEntry(
            "knowledge_store",
            "knowledge store",
            "Ù…Ø®Ø²Ù† Ø§Ù„Ù…Ø¹Ø±ÙØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "reasoning_engine",
            "reasoning engine",
            "Ù…Ø­Ø±Ùƒ Ø§Ù„Ø§Ø³ØªØ¯Ù„Ø§Ù„",
            "reasoning",
        ),

        DictionaryEntry(
            "logical_engine",
            "logical engine",
            "Ù…Ø­Ø±Ùƒ Ù…Ù†Ø·Ù‚ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "symbolic_engine",
            "symbolic engine",
            "Ù…Ø­Ø±Ùƒ Ø±Ù…Ø²ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "datalog",
            "Datalog",
            "Ø¯Ø§ØªØ§Ù„ÙˆØ¬",
            "logic",
        ),

        DictionaryEntry(
            "souffle",
            "SoufflÃ©",
            "SoufflÃ©",
            "compiler",
        ),

        DictionaryEntry(
            "subprocess_bridge",
            "subprocess bridge",
            "Ø¬Ø³Ø± Ø§Ù„Ø¹Ù…Ù„ÙŠØ© Ø§Ù„ÙØ±Ø¹ÙŠØ©",
            "system",
        ),

        DictionaryEntry(
            "agent_reasoning",
            "agent reasoning",
            "Ø§Ø³ØªØ¯Ù„Ø§Ù„ Ø§Ù„ÙˆÙƒÙŠÙ„",
            "reasoning",
        ),

        DictionaryEntry(
            "massive",
            "massive",
            "Ø¶Ø®Ù…",
            "system",
        ),

        DictionaryEntry(
            "dense",
            "dense",
            "ÙƒØ«ÙŠÙ",
            "system",
        ),

        DictionaryEntry(
            "kernel_layer",
            "kernel layer",
            "Ø·Ø¨Ù‚Ø© Ø§Ù„Ù†ÙˆØ§Ø©",
            "architecture",
        ),

        DictionaryEntry(
            "reasoning_layer",
            "reasoning layer",
            "Ø·Ø¨Ù‚Ø© Ø§Ù„Ø§Ø³ØªØ¯Ù„Ø§Ù„",
            "architecture",
        ),

        DictionaryEntry(
            "language_layer",
            "language layer",
            "Ø·Ø¨Ù‚Ø© Ø§Ù„Ù„ØºØ©",
            "architecture",
        ),

        DictionaryEntry(
            "data_layer",
            "data layer",
            "Ø·Ø¨Ù‚Ø© Ø§Ù„Ø¨ÙŠØ§Ù†Ø§Øª",
            "architecture",
        ),

        DictionaryEntry(
            "execution_layer",
            "execution layer",
            "Ø·Ø¨Ù‚Ø© Ø§Ù„ØªÙ†ÙÙŠØ°",
            "architecture",
        ),

        DictionaryEntry(
            "interface_layer",
            "interface layer",
            "Ø·Ø¨Ù‚Ø© Ø§Ù„ÙˆØ§Ø¬Ù‡Ø©",
            "architecture",
        ),

        DictionaryEntry(
            "knowledge_layer",
            "knowledge layer",
            "Ø·Ø¨Ù‚Ø© Ø§Ù„Ù…Ø¹Ø±ÙØ©",
            "architecture",
        ),

        DictionaryEntry(
            "semantic_layer",
            "semantic layer",
            "Ø§Ù„Ø·Ø¨Ù‚Ø© Ø§Ù„Ø¯Ù„Ø§Ù„ÙŠØ©",
            "architecture",
        ),

        DictionaryEntry(
            "proof_layer",
            "proof layer",
            "Ø·Ø¨Ù‚Ø© Ø§Ù„Ø¨Ø±Ù‡Ø§Ù†",
            "architecture",
        ),

        DictionaryEntry(
            "verification_layer",
            "verification layer",
            "Ø·Ø¨Ù‚Ø© Ø§Ù„ØªØ­Ù‚Ù‚",
            "architecture",
        ),

        DictionaryEntry(
            "audit_layer",
            "audit layer",
            "Ø·Ø¨Ù‚Ø© Ø§Ù„ØªØ¯Ù‚ÙŠÙ‚",
            "architecture",
        ),

        DictionaryEntry(
            "decision",
            "decision",
            "Ù‚Ø±Ø§Ø±",
            "reasoning",
        ),

        DictionaryEntry(
            "decision_rule",
            "decision rule",
            "Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„Ù‚Ø±Ø§Ø±",
            "reasoning",
        ),

        DictionaryEntry(
            "decision_graph",
            "decision graph",
            "Ø±Ø³Ù… Ø¨ÙŠØ§Ù†ÙŠ Ù„Ù„Ù‚Ø±Ø§Ø±",
            "reasoning",
        ),

        DictionaryEntry(
            "decision_path",
            "decision path",
            "Ù…Ø³Ø§Ø± Ø§Ù„Ù‚Ø±Ø§Ø±",
            "reasoning",
        ),

        DictionaryEntry(
            "decision_state",
            "decision state",
            "Ø­Ø§Ù„Ø© Ø§Ù„Ù‚Ø±Ø§Ø±",
            "reasoning",
        ),

        DictionaryEntry(
            "proof_state",
            "proof state",
            "Ø­Ø§Ù„Ø© Ø§Ù„Ø¨Ø±Ù‡Ø§Ù†",
            "logic",
        ),

        DictionaryEntry(
            "logical_state",
            "logical state",
            "Ø­Ø§Ù„Ø© Ù…Ù†Ø·Ù‚ÙŠØ©",
            "logic",
        ),

        DictionaryEntry(
            "semantic_state",
            "semantic state",
            "Ø­Ø§Ù„Ø© Ø¯Ù„Ø§Ù„ÙŠØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "language_state",
            "language state",
            "Ø­Ø§Ù„Ø© Ù„ØºÙˆÙŠØ©",
            "language",
        ),

        DictionaryEntry(
            "translation_state",
            "translation state",
            "Ø­Ø§Ù„Ø© Ø§Ù„ØªØ±Ø¬Ù…Ø©",
            "language",
        ),

        DictionaryEntry(
            "knowledge_state",
            "knowledge state",
            "Ø­Ø§Ù„Ø© Ø§Ù„Ù…Ø¹Ø±ÙØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "consistency_check",
            "consistency check",
            "ÙØ­Øµ Ø§Ù„Ø§ØªØ³Ø§Ù‚",
            "verification",
        ),

        DictionaryEntry(
            "constraint_check",
            "constraint check",
            "ÙØ­Øµ Ø§Ù„Ù‚ÙŠÙˆØ¯",
            "verification",
        ),

        DictionaryEntry(
            "proof_check",
            "proof check",
            "ÙØ­Øµ Ø§Ù„Ø¨Ø±Ù‡Ø§Ù†",
            "verification",
        ),

        DictionaryEntry(
            "semantic_check",
            "semantic check",
            "Ø§Ù„ÙØ­Øµ Ø§Ù„Ø¯Ù„Ø§Ù„ÙŠ",
            "verification",
        ),

        DictionaryEntry(
            "dictionary_check",
            "dictionary check",
            "ÙØ­Øµ Ø§Ù„Ù…Ø¹Ø¬Ù…",
            "verification",
        ),

        DictionaryEntry(
            "bilingual_check",
            "bilingual check",
            "Ø§Ù„ÙØ­Øµ Ø«Ù†Ø§Ø¦ÙŠ Ø§Ù„Ù„ØºØ©",
            "verification",
        ),

        DictionaryEntry(
            "kernel_check",
            "kernel check",
            "ÙØ­Øµ Ø§Ù„Ù†ÙˆØ§Ø©",
            "verification",
        ),

        DictionaryEntry(
            "agent_check",
            "agent check",
            "ÙØ­Øµ Ø§Ù„ÙˆÙƒÙŠÙ„",
            "verification",
        ),

        DictionaryEntry(
            "reasoning_check",
            "reasoning check",
            "ÙØ­Øµ Ø§Ù„Ø§Ø³ØªØ¯Ù„Ø§Ù„",
            "verification",
        ),

        DictionaryEntry(
            "final_result",
            "final result",
            "Ø§Ù„Ù†ØªÙŠØ¬Ø© Ø§Ù„Ù†Ù‡Ø§Ø¦ÙŠØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "derived_fact",
            "derived fact",
            "Ø­Ù‚ÙŠÙ‚Ø© Ù…Ø´ØªÙ‚Ø©",
            "reasoning",
        ),

        DictionaryEntry(
            "base_fact",
            "base fact",
            "Ø­Ù‚ÙŠÙ‚Ø© Ø£Ø³Ø§Ø³ÙŠØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "rule_application",
            "rule application",
            "ØªØ·Ø¨ÙŠÙ‚ Ø§Ù„Ù‚Ø§Ø¹Ø¯Ø©",
            "reasoning",
        ),

        DictionaryEntry(
            "inference_step",
            "inference step",
            "Ø®Ø·ÙˆØ© Ø§Ø³ØªØ¯Ù„Ø§Ù„",
            "reasoning",
        ),

        DictionaryEntry(
            "proof_step",
            "proof step",
            "Ø®Ø·ÙˆØ© Ø¨Ø±Ù‡Ø§Ù†",
            "logic",
        ),

        DictionaryEntry(
            "reasoning_step",
            "reasoning step",
            "Ø®Ø·ÙˆØ© Ø§Ø³ØªØ¯Ù„Ø§Ù„",
            "reasoning",
        ),

        DictionaryEntry(
            "symbolic_step",
            "symbolic step",
            "Ø®Ø·ÙˆØ© Ø±Ù…Ø²ÙŠØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "semantic_step",
            "semantic step",
            "Ø®Ø·ÙˆØ© Ø¯Ù„Ø§Ù„ÙŠØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "language_step",
            "language step",
            "Ø®Ø·ÙˆØ© Ù„ØºÙˆÙŠØ©",
            "language",
        ),

        DictionaryEntry(
            "graph_step",
            "graph step",
            "Ø®Ø·ÙˆØ© Ø¨ÙŠØ§Ù†ÙŠØ©",
            "graph",
        ),

        DictionaryEntry(
            "database_step",
            "database step",
            "Ø®Ø·ÙˆØ© Ù‚Ø§Ø¹Ø¯Ø© Ø¨ÙŠØ§Ù†Ø§Øª",
            "database",
        ),

        DictionaryEntry(
            "compiler_step",
            "compiler step",
            "Ø®Ø·ÙˆØ© Ù…ØªØ±Ø¬Ù…",
            "compiler",
        ),

        DictionaryEntry(
            "execution_step",
            "execution step",
            "Ø®Ø·ÙˆØ© ØªÙ†ÙÙŠØ°",
            "system",
        ),

        DictionaryEntry(
            "system_step",
            "system step",
            "Ø®Ø·ÙˆØ© Ù†Ø¸Ø§Ù…",
            "system",
        ),

        DictionaryEntry(
            "terminal_state",
            "terminal state",
            "Ø­Ø§Ù„Ø© Ù†Ù‡Ø§Ø¦ÙŠØ©",
            "system",
        ),

        DictionaryEntry(
            "initial_state",
            "initial state",
            "Ø­Ø§Ù„Ø© Ø§Ø¨ØªØ¯Ø§Ø¦ÙŠØ©",
            "system",
        ),

        DictionaryEntry(
            "transition_rule",
            "transition rule",
            "Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„Ø§Ù†ØªÙ‚Ø§Ù„",
            "system",
        ),

        DictionaryEntry(
            "state_relation",
            "state relation",
            "Ø¹Ù„Ø§Ù‚Ø© Ø§Ù„Ø­Ø§Ù„Ø©",
            "system",
        ),

        DictionaryEntry(
            "state_graph",
            "state graph",
            "Ø±Ø³Ù… Ø¨ÙŠØ§Ù†ÙŠ Ù„Ù„Ø­Ø§Ù„Ø©",
            "system",
        ),

        DictionaryEntry(
            "causal_relation",
            "causal relation",
            "Ø¹Ù„Ø§Ù‚Ø© Ø³Ø¨Ø¨ÙŠØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "logical_relation",
            "logical relation",
            "Ø¹Ù„Ø§Ù‚Ø© Ù…Ù†Ø·Ù‚ÙŠØ©",
            "logic",
        ),

        DictionaryEntry(
            "syntactic_relation",
            "syntactic relation",
            "Ø¹Ù„Ø§Ù‚Ø© Ù†Ø­ÙˆÙŠØ©",
            "language",
        ),

        DictionaryEntry(
            "morphological_relation",
            "morphological relation",
            "Ø¹Ù„Ø§Ù‚Ø© ØµØ±ÙÙŠØ©",
            "language",
        ),

        DictionaryEntry(
            "lexical_relation",
            "lexical relation",
            "Ø¹Ù„Ø§Ù‚Ø© Ù…Ø¹Ø¬Ù…ÙŠØ©",
            "language",
        ),

        DictionaryEntry(
            "translation_relation",
            "translation relation",
            "Ø¹Ù„Ø§Ù‚Ø© ØªØ±Ø¬Ù…Ø©",
            "language",
        ),

        DictionaryEntry(
            "semantic_mapping",
            "semantic mapping",
            "ØªØ·Ø¨ÙŠÙ‚ Ø¯Ù„Ø§Ù„ÙŠ",
            "language",
        ),

        DictionaryEntry(
            "concept_mapping",
            "concept mapping",
            "Ù…Ø·Ø§Ø¨Ù‚Ø© Ø§Ù„Ù…ÙØ§Ù‡ÙŠÙ…",
            "reasoning",
        ),

        DictionaryEntry(
            "cross_reference",
            "cross-reference",
            "Ù…Ø±Ø¬Ø¹ Ù…ØªÙ‚Ø§Ø·Ø¹",
            "reasoning",
        ),

        DictionaryEntry(
            "knowledge_reference",
            "knowledge reference",
            "Ù…Ø±Ø¬Ø¹ Ù…Ø¹Ø±ÙÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "symbol_reference",
            "symbol reference",
            "Ù…Ø±Ø¬Ø¹ Ø±Ù…Ø²ÙŠ",
            "logic",
        ),

        DictionaryEntry(
            "relation_reference",
            "relation reference",
            "Ù…Ø±Ø¬Ø¹ Ø§Ù„Ø¹Ù„Ø§Ù‚Ø©",
            "database",
        ),

        DictionaryEntry(
            "dictionary_reference",
            "dictionary reference",
            "Ù…Ø±Ø¬Ø¹ Ø§Ù„Ù…Ø¹Ø¬Ù…",
            "language",
        ),

        DictionaryEntry(
            "proof_reference",
            "proof reference",
            "Ù…Ø±Ø¬Ø¹ Ø§Ù„Ø¨Ø±Ù‡Ø§Ù†",
            "logic",
        ),

        DictionaryEntry(
            "audit_reference",
            "audit reference",
            "Ù…Ø±Ø¬Ø¹ Ø§Ù„ØªØ¯Ù‚ÙŠÙ‚",
            "security",
        ),

        DictionaryEntry(
            "execution_reference",
            "execution reference",
            "Ù…Ø±Ø¬Ø¹ Ø§Ù„ØªÙ†ÙÙŠØ°",
            "system",
        ),

        DictionaryEntry(
            "compiler_reference",
            "compiler reference",
            "Ù…Ø±Ø¬Ø¹ Ø§Ù„Ù…ØªØ±Ø¬Ù…",
            "compiler",
        ),

        DictionaryEntry(
            "agent_reference",
            "agent reference",
            "Ù…Ø±Ø¬Ø¹ Ø§Ù„ÙˆÙƒÙŠÙ„",
            "reasoning",
        ),

        DictionaryEntry(
            "reasoning_reference",
            "reasoning reference",
            "Ù…Ø±Ø¬Ø¹ Ø§Ù„Ø§Ø³ØªØ¯Ù„Ø§Ù„",
            "reasoning",
        ),

        DictionaryEntry(
            "kernel_reference",
            "kernel reference",
            "Ù…Ø±Ø¬Ø¹ Ø§Ù„Ù†ÙˆØ§Ø©",
            "system",
        ),

        DictionaryEntry(
            "dense_kernel",
            "dense kernel",
            "Ù†ÙˆØ§Ø© ÙƒØ«ÙŠÙØ©",
            "system",
        ),

        DictionaryEntry(
            "symbolic_kernel",
            "symbolic kernel",
            "Ù†ÙˆØ§Ø© Ø±Ù…Ø²ÙŠØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "language_kernel",
            "language kernel",
            "Ù†ÙˆØ§Ø© Ù„ØºÙˆÙŠØ©",
            "language",
        ),

        DictionaryEntry(
            "semantic_kernel",
            "semantic kernel",
            "Ù†ÙˆØ§Ø© Ø¯Ù„Ø§Ù„ÙŠØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "logic_kernel",
            "logic kernel",
            "Ù†ÙˆØ§Ø© Ù…Ù†Ø·Ù‚ÙŠØ©",
            "logic",
        ),

        DictionaryEntry(
            "database_kernel",
            "database kernel",
            "Ù†ÙˆØ§Ø© Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„Ø¨ÙŠØ§Ù†Ø§Øª",
            "database",
        ),

        DictionaryEntry(
            "compiler_kernel",
            "compiler kernel",
            "Ù†ÙˆØ§Ø© Ø§Ù„Ù…ØªØ±Ø¬Ù…",
            "compiler",
        ),

        DictionaryEntry(
            "verification_kernel",
            "verification kernel",
            "Ù†ÙˆØ§Ø© Ø§Ù„ØªØ­Ù‚Ù‚",
            "verification",
        ),

        DictionaryEntry(
            "audit_kernel",
            "audit kernel",
            "Ù†ÙˆØ§Ø© Ø§Ù„ØªØ¯Ù‚ÙŠÙ‚",
            "security",
        ),

        DictionaryEntry(
            "sovereign",
            "sovereign",
            "Ø³ÙŠØ§Ø¯ÙŠ",
            "architecture",
        ),

        DictionaryEntry(
            "local",
            "local",
            "Ù…Ø­Ù„ÙŠ",
            "architecture",
        ),

        DictionaryEntry(
            "portable",
            "portable",
            "Ù…Ø­Ù…ÙˆÙ„",
            "system",
        ),

        DictionaryEntry(
            "reproducible",
            "reproducible",
            "Ù‚Ø§Ø¨Ù„ Ù„Ø¥Ø¹Ø§Ø¯Ø© Ø§Ù„Ø¥Ù†ØªØ§Ø¬",
            "system",
        ),

        DictionaryEntry(
            "auditable",
            "auditable",
            "Ù‚Ø§Ø¨Ù„ Ù„Ù„ØªØ¯Ù‚ÙŠÙ‚",
            "security",
        ),

        DictionaryEntry(
            "formalizable",
            "formalizable",
            "Ù‚Ø§Ø¨Ù„ Ù„Ù„ØµÙŠØ§ØºØ© Ø§Ù„Ø±Ø³Ù…ÙŠØ©",
            "logic",
        ),

        DictionaryEntry(
            "machine_reasoning",
            "machine reasoning",
            "Ø§Ø³ØªØ¯Ù„Ø§Ù„ Ø¢Ù„ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "symbolic_reasoning",
            "symbolic reasoning",
            "Ø§Ø³ØªØ¯Ù„Ø§Ù„ Ø±Ù…Ø²ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "logical_reasoning",
            "logical reasoning",
            "Ø§Ø³ØªØ¯Ù„Ø§Ù„ Ù…Ù†Ø·Ù‚ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "deductive_reasoning",
            "deductive reasoning",
            "Ø§Ø³ØªØ¯Ù„Ø§Ù„ Ø§Ø³ØªÙ†Ø¨Ø§Ø·ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "relational_reasoning",
            "relational reasoning",
            "Ø§Ø³ØªØ¯Ù„Ø§Ù„ Ø¹Ù„Ø§Ø¦Ù‚ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "graph_reasoning",
            "graph reasoning",
            "Ø§Ø³ØªØ¯Ù„Ø§Ù„ Ø¨ÙŠØ§Ù†ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "semantic_reasoning_engine",
            "semantic reasoning engine",
            "Ù…Ø­Ø±Ùƒ Ø§Ù„Ø§Ø³ØªØ¯Ù„Ø§Ù„ Ø§Ù„Ø¯Ù„Ø§Ù„ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "bilingual_reasoning",
            "bilingual reasoning",
            "Ø§Ø³ØªØ¯Ù„Ø§Ù„ Ø«Ù†Ø§Ø¦ÙŠ Ø§Ù„Ù„ØºØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "arabic_english_reasoning",
            "Arabic English reasoning",
            "Ø§Ø³ØªØ¯Ù„Ø§Ù„ Ø¹Ø±Ø¨ÙŠ Ø¥Ù†Ø¬Ù„ÙŠØ²ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "knowledge_compilation",
            "knowledge compilation",
            "ØªØ¬Ù…ÙŠØ¹ Ø§Ù„Ù…Ø¹Ø±ÙØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "reasoning_compilation",
            "reasoning compilation",
            "ØªØ¬Ù…ÙŠØ¹ Ø§Ù„Ø§Ø³ØªØ¯Ù„Ø§Ù„",
            "reasoning",
        ),

        DictionaryEntry(
            "symbolic_compilation",
            "symbolic compilation",
            "ØªØ¬Ù…ÙŠØ¹ Ø±Ù…Ø²ÙŠ",
            "compiler",
        ),

        DictionaryEntry(
            "relation_compilation",
            "relation compilation",
            "ØªØ¬Ù…ÙŠØ¹ Ø¹Ù„Ø§Ø¦Ù‚ÙŠ",
            "compiler",
        ),

        DictionaryEntry(
            "query_compilation",
            "query compilation",
            "ØªØ¬Ù…ÙŠØ¹ Ø§Ù„Ø§Ø³ØªØ¹Ù„Ø§Ù…",
            "compiler",
        ),

        DictionaryEntry(
            "rule_compilation",
            "rule compilation",
            "ØªØ¬Ù…ÙŠØ¹ Ø§Ù„Ù‚ÙˆØ§Ø¹Ø¯",
            "compiler",
        ),

        DictionaryEntry(
            "fact_compilation",
            "fact compilation",
            "ØªØ¬Ù…ÙŠØ¹ Ø§Ù„Ø­Ù‚Ø§Ø¦Ù‚",
            "compiler",
        ),

        DictionaryEntry(
            "semantic_compilation",
            "semantic compilation",
            "ØªØ¬Ù…ÙŠØ¹ Ø¯Ù„Ø§Ù„ÙŠ",
            "compiler",
        ),

        DictionaryEntry(
            "language_compilation",
            "language compilation",
            "ØªØ¬Ù…ÙŠØ¹ Ù„ØºÙˆÙŠ",
            "compiler",
        ),

        DictionaryEntry(
            "arabic_processing",
            "Arabic processing",
            "Ù…Ø¹Ø§Ù„Ø¬Ø© Ø§Ù„Ø¹Ø±Ø¨ÙŠØ©",
            "language",
        ),

        DictionaryEntry(
            "english_processing",
            "English processing",
            "Ù…Ø¹Ø§Ù„Ø¬Ø© Ø§Ù„Ø¥Ù†Ø¬Ù„ÙŠØ²ÙŠØ©",
            "language",
        ),

        DictionaryEntry(
            "bilingual_processing",
            "bilingual processing",
            "Ù…Ø¹Ø§Ù„Ø¬Ø© Ø«Ù†Ø§Ø¦ÙŠØ© Ø§Ù„Ù„ØºØ©",
            "language",
        ),

        DictionaryEntry(
            "semantic_processing",
            "semantic processing",
            "Ù…Ø¹Ø§Ù„Ø¬Ø© Ø¯Ù„Ø§Ù„ÙŠØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "symbolic_processing",
            "symbolic processing",
            "Ù…Ø¹Ø§Ù„Ø¬Ø© Ø±Ù…Ø²ÙŠØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "formal_processing",
            "formal processing",
            "Ù…Ø¹Ø§Ù„Ø¬Ø© ØµÙˆØ±ÙŠØ©",
            "logic",
        ),

        DictionaryEntry(
            "reasoning_context",
            "reasoning context",
            "Ø³ÙŠØ§Ù‚ Ø§Ù„Ø§Ø³ØªØ¯Ù„Ø§Ù„",
            "reasoning",
        ),

        DictionaryEntry(
            "dictionary_context",
            "dictionary context",
            "Ø³ÙŠØ§Ù‚ Ø§Ù„Ù…Ø¹Ø¬Ù…",
            "language",
        ),

        DictionaryEntry(
            "semantic_context",
            "semantic context",
            "Ø³ÙŠØ§Ù‚ Ø¯Ù„Ø§Ù„ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "symbolic_context",
            "symbolic context",
            "Ø³ÙŠØ§Ù‚ Ø±Ù…Ø²ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "logical_context",
            "logical context",
            "Ø³ÙŠØ§Ù‚ Ù…Ù†Ø·Ù‚ÙŠ",
            "logic",
        ),

        DictionaryEntry(
            "graph_context",
            "graph context",
            "Ø³ÙŠØ§Ù‚ Ø¨ÙŠØ§Ù†ÙŠ",
            "graph",
        ),

        DictionaryEntry(
            "database_context",
            "database context",
            "Ø³ÙŠØ§Ù‚ Ù‚Ø§Ø¹Ø¯Ø© Ø§Ù„Ø¨ÙŠØ§Ù†Ø§Øª",
            "database",
        ),

        DictionaryEntry(
            "execution_context",
            "execution context",
            "Ø³ÙŠØ§Ù‚ Ø§Ù„ØªÙ†ÙÙŠØ°",
            "system",
        ),

        DictionaryEntry(
            "compiler_context",
            "compiler context",
            "Ø³ÙŠØ§Ù‚ Ø§Ù„Ù…ØªØ±Ø¬Ù…",
            "compiler",
        ),

        DictionaryEntry(
            "verification_context",
            "verification context",
            "Ø³ÙŠØ§Ù‚ Ø§Ù„ØªØ­Ù‚Ù‚",
            "verification",
        ),

        DictionaryEntry(
            "audit_context",
            "audit context",
            "Ø³ÙŠØ§Ù‚ Ø§Ù„ØªØ¯Ù‚ÙŠÙ‚",
            "security",
        ),

        DictionaryEntry(
            "agent_context",
            "agent context",
            "Ø³ÙŠØ§Ù‚ Ø§Ù„ÙˆÙƒÙŠÙ„",
            "reasoning",
        ),

        DictionaryEntry(
            "kernel_context",
            "kernel context",
            "Ø³ÙŠØ§Ù‚ Ø§Ù„Ù†ÙˆØ§Ø©",
            "system",
        ),

        DictionaryEntry(
            "system_context",
            "system context",
            "Ø³ÙŠØ§Ù‚ Ø§Ù„Ù†Ø¸Ø§Ù…",
            "system",
        ),

        DictionaryEntry(
            "final_state",
            "final state",
            "Ø§Ù„Ø­Ø§Ù„Ø© Ø§Ù„Ù†Ù‡Ø§Ø¦ÙŠØ©",
            "system",
        ),

        DictionaryEntry(
            "stable_state",
            "stable state",
            "Ø­Ø§Ù„Ø© Ù…Ø³ØªÙ‚Ø±Ø©",
            "system",
        ),

        DictionaryEntry(
            "converged_state",
            "converged state",
            "Ø­Ø§Ù„Ø© Ù…ØªÙ‚Ø§Ø±Ø¨Ø©",
            "mathematics",
        ),

        DictionaryEntry(
            "closure_state",
            "closure state",
            "Ø­Ø§Ù„Ø© Ø§Ù„Ø¥ØºÙ„Ø§Ù‚",
            "mathematics",
        ),

        DictionaryEntry(
            "reasoning_closure",
            "reasoning closure",
            "Ø¥ØºÙ„Ø§Ù‚ Ø§Ù„Ø§Ø³ØªØ¯Ù„Ø§Ù„",
            "reasoning",
        ),

        DictionaryEntry(
            "knowledge_closure",
            "knowledge closure",
            "Ø¥ØºÙ„Ø§Ù‚ Ø§Ù„Ù…Ø¹Ø±ÙØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "semantic_closure",
            "semantic closure",
            "Ø§Ù„Ø¥ØºÙ„Ø§Ù‚ Ø§Ù„Ø¯Ù„Ø§Ù„ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "logical_closure",
            "logical closure",
            "Ø§Ù„Ø¥ØºÙ„Ø§Ù‚ Ø§Ù„Ù…Ù†Ø·Ù‚ÙŠ",
            "logic",
        ),

        DictionaryEntry(
            "graph_closure",
            "graph closure",
            "Ø¥ØºÙ„Ø§Ù‚ Ø§Ù„Ø±Ø³Ù… Ø§Ù„Ø¨ÙŠØ§Ù†ÙŠ",
            "graph",
        ),

        DictionaryEntry(
            "transitive_closure",
            "transitive closure",
            "Ø§Ù„Ø¥ØºÙ„Ø§Ù‚ Ø§Ù„Ø§Ù†ØªÙ‚Ø§Ù„ÙŠ",
            "mathematics",
        ),

        DictionaryEntry(
            "dependency_closure",
            "dependency closure",
            "Ø¥ØºÙ„Ø§Ù‚ Ø§Ù„ØªØ¨Ø¹ÙŠØ§Øª",
            "architecture",
        ),

        DictionaryEntry(
            "translation_closure",
            "translation closure",
            "Ø¥ØºÙ„Ø§Ù‚ Ø§Ù„ØªØ±Ø¬Ù…Ø©",
            "language",
        ),

        DictionaryEntry(
            "dictionary_closure",
            "dictionary closure",
            "Ø¥ØºÙ„Ø§Ù‚ Ø§Ù„Ù…Ø¹Ø¬Ù…",
            "language",
        ),

        DictionaryEntry(
            "proof_closure",
            "proof closure",
            "Ø¥ØºÙ„Ø§Ù‚ Ø§Ù„Ø¨Ø±Ù‡Ø§Ù†",
            "logic",
        ),

        DictionaryEntry(
            "verification_closure",
            "verification closure",
            "Ø¥ØºÙ„Ø§Ù‚ Ø§Ù„ØªØ­Ù‚Ù‚",
            "verification",
        ),

        DictionaryEntry(
            "audit_closure",
            "audit closure",
            "Ø¥ØºÙ„Ø§Ù‚ Ø§Ù„ØªØ¯Ù‚ÙŠÙ‚",
            "security",
        ),

        DictionaryEntry(
            "agent_closure",
            "agent closure",
            "Ø¥ØºÙ„Ø§Ù‚ Ø§Ù„ÙˆÙƒÙŠÙ„",
            "reasoning",
        ),

        DictionaryEntry(
            "kernel_closure",
            "kernel closure",
            "Ø¥ØºÙ„Ø§Ù‚ Ø§Ù„Ù†ÙˆØ§Ø©",
            "system",
        ),

        DictionaryEntry(
            "system_closure",
            "system closure",
            "Ø¥ØºÙ„Ø§Ù‚ Ø§Ù„Ù†Ø¸Ø§Ù…",
            "system",
        ),

        DictionaryEntry(
            "complete_reasoning",
            "complete reasoning",
            "Ø§Ø³ØªØ¯Ù„Ø§Ù„ ÙƒØ§Ù…Ù„",
            "reasoning",
        ),

        DictionaryEntry(
            "verified_reasoning",
            "verified reasoning",
            "Ø§Ø³ØªØ¯Ù„Ø§Ù„ Ù…ØªØ­Ù‚Ù‚",
            "verification",
        ),

        DictionaryEntry(
            "audited_reasoning",
            "audited reasoning",
            "Ø§Ø³ØªØ¯Ù„Ø§Ù„ Ù…Ø¯Ù‚Ù‚",
            "security",
        ),

        DictionaryEntry(
            "deterministic_reasoning",
            "deterministic reasoning",
            "Ø§Ø³ØªØ¯Ù„Ø§Ù„ Ø­ØªÙ…ÙŠ",
            "reasoning",
        ),

        DictionaryEntry(
            "formal_reasoning_kernel",
            "formal reasoning kernel",
            "Ù†ÙˆØ§Ø© Ø§Ø³ØªØ¯Ù„Ø§Ù„ ØµÙˆØ±ÙŠØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "bilingual_symbolic_kernel",
            "bilingual symbolic kernel",
            "Ù†ÙˆØ§Ø© Ø±Ù…Ø²ÙŠØ© Ø«Ù†Ø§Ø¦ÙŠØ© Ø§Ù„Ù„ØºØ©",
            "reasoning",
        ),

        DictionaryEntry(
            "arabic_english_dictionary",
            "Arabic English dictionary",
            "Ù…Ø¹Ø¬Ù… Ø¹Ø±Ø¨ÙŠ Ø¥Ù†Ø¬Ù„ÙŠØ²ÙŠ",
            "language",
        ),

        DictionaryEntry(
            "dense_symbolic_kernel",
            "dense symbolic kernel",
            "Ù†ÙˆØ§Ø© Ø±Ù…Ø²ÙŠØ© ÙƒØ«ÙŠÙØ©",
            "reasoning",
        ),

    ]
