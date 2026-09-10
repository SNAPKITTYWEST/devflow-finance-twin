#!/usr/bin/env python3

"""
souffle_symbolic_agent.py

Soufflé subprocess bridge for a dense symbolic reasoning kernel.

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
      +--> Generated Soufflé Datalog
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
Soufflé is the Datalog compiler and evaluator.
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
# Soufflé identifier escaping
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
# Soufflé variable detection
# ================================================================

def is_variable(value: str) -> bool:
    if not value:
        return False

    return (
        value[0].isupper()
        or value[0] == "_"
    )


# ================================================================
# Soufflé source builder
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
# Soufflé compiler
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
                    "Soufflé failed:\n"
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
            "منطق",
            "reasoning",
        ),

        DictionaryEntry(
            "reason",
            "reason",
            "استدلال",
            "reasoning",
        ),

        DictionaryEntry(
            "knowledge",
            "knowledge",
            "معرفة",
            "reasoning",
        ),

        DictionaryEntry(
            "concept",
            "concept",
            "مفهوم",
            "semantic",
        ),

        DictionaryEntry(
            "relation",
            "relation",
            "علاقة",
            "semantic",
        ),

        DictionaryEntry(
            "fact",
            "fact",
            "حقيقة",
            "logic",
        ),

        DictionaryEntry(
            "rule",
            "rule",
            "قاعدة",
            "logic",
        ),

        DictionaryEntry(
            "proof",
            "proof",
            "برهان",
            "logic",
        ),

        DictionaryEntry(
            "inference",
            "inference",
            "استنتاج",
            "reasoning",
        ),

        DictionaryEntry(
            "symbol",
            "symbol",
            "رمز",
            "language",
        ),

        DictionaryEntry(
            "language",
            "language",
            "لغة",
            "language",
        ),

        DictionaryEntry(
            "arabic",
            "Arabic",
            "العربية",
            "language",
        ),

        DictionaryEntry(
            "english",
            "English",
            "الإنجليزية",
            "language",
        ),

        DictionaryEntry(
            "truth",
            "truth",
            "حقيقة",
            "logic",
        ),

        DictionaryEntry(
            "false",
            "false",
            "خطأ",
            "logic",
        ),

        DictionaryEntry(
            "true",
            "true",
            "صحيح",
            "logic",
        ),

        DictionaryEntry(
            "set",
            "set",
            "مجموعة",
            "mathematics",
        ),

        DictionaryEntry(
            "number",
            "number",
            "عدد",
            "mathematics",
        ),

        DictionaryEntry(
            "function",
            "function",
            "دالة",
            "mathematics",
        ),

        DictionaryEntry(
            "structure",
            "structure",
            "بنية",
            "mathematics",
        ),

        DictionaryEntry(
            "system",
            "system",
            "نظام",
            "architecture",
        ),

        DictionaryEntry(
            "state",
            "state",
            "حالة",
            "architecture",
        ),

        DictionaryEntry(
            "transition",
            "transition",
            "انتقال",
            "architecture",
        ),

        DictionaryEntry(
            "network",
            "network",
            "شبكة",
            "architecture",
        ),

        DictionaryEntry(
            "graph",
            "graph",
            "رسم بياني",
            "mathematics",
        ),

        DictionaryEntry(
            "node",
            "node",
            "عقدة",
            "graph",
        ),

        DictionaryEntry(
            "edge",
            "edge",
            "حافة",
            "graph",
        ),

        DictionaryEntry(
            "path",
            "path",
            "مسار",
            "graph",
        ),

        DictionaryEntry(
            "root",
            "root",
            "جذر",
            "graph",
        ),

        DictionaryEntry(
            "ancestor",
            "ancestor",
            "سلف",
            "graph",
        ),

        DictionaryEntry(
            "descendant",
            "descendant",
            "نسل",
            "graph",
        ),

        DictionaryEntry(
            "parent",
            "parent",
            "والد",
            "graph",
        ),

        DictionaryEntry(
            "child",
            "child",
            "ابن",
            "graph",
        ),

        DictionaryEntry(
            "equivalence",
            "equivalence",
            "تكافؤ",
            "logic",
        ),

        DictionaryEntry(
            "identity",
            "identity",
            "هوية",
            "logic",
        ),

        DictionaryEntry(
            "difference",
            "difference",
            "اختلاف",
            "logic",
        ),

        DictionaryEntry(
            "dependency",
            "dependency",
            "اعتماد",
            "architecture",
        ),

        DictionaryEntry(
            "input",
            "input",
            "مدخل",
            "system",
        ),

        DictionaryEntry(
            "output",
            "output",
            "مخرج",
            "system",
        ),

        DictionaryEntry(
            "compile",
            "compile",
            "ترجمة",
            "system",
        ),

        DictionaryEntry(
            "execute",
            "execute",
            "تنفيذ",
            "system",
        ),

        DictionaryEntry(
            "query",
            "query",
            "استعلام",
            "database",
        ),

        DictionaryEntry(
            "database",
            "database",
            "قاعدة بيانات",
            "database",
        ),

        DictionaryEntry(
            "relation_database",
            "relational database",
            "قاعدة بيانات علائقية",
            "database",
        ),

        DictionaryEntry(
            "predicate",
            "predicate",
            "محمول",
            "logic",
        ),

        DictionaryEntry(
            "variable",
            "variable",
            "متغير",
            "logic",
        ),

        DictionaryEntry(
            "constant",
            "constant",
            "ثابت",
            "logic",
        ),

        DictionaryEntry(
            "term",
            "term",
            "حد",
            "logic",
        ),

        DictionaryEntry(
            "atom",
            "atom",
            "ذرة",
            "logic",
        ),

        DictionaryEntry(
            "negation",
            "negation",
            "نفي",
            "logic",
        ),

        DictionaryEntry(
            "stratum",
            "stratum",
            "طبقة",
            "logic",
        ),

        DictionaryEntry(
            "recursive",
            "recursive",
            "تكراري",
            "logic",
        ),

        DictionaryEntry(
            "deterministic",
            "deterministic",
            "حتمي",
            "system",
        ),

        DictionaryEntry(
            "symbolic",
            "symbolic",
            "رمزي",
            "reasoning",
        ),

        DictionaryEntry(
            "semantic_reasoning",
            "semantic reasoning",
            "استدلال دلالي",
            "reasoning",
        ),

        DictionaryEntry(
            "formal_reasoning",
            "formal reasoning",
            "استدلال صوري",
            "reasoning",
        ),

        DictionaryEntry(
            "deduction",
            "deduction",
            "استنباط",
            "reasoning",
        ),

        DictionaryEntry(
            "derivation",
            "derivation",
            "اشتقاق",
            "reasoning",
        ),

        DictionaryEntry(
            "closure",
            "closure",
            "إغلاق",
            "mathematics",
        ),

        DictionaryEntry(
            "fixed_point",
            "fixed point",
            "نقطة ثابتة",
            "mathematics",
        ),

        DictionaryEntry(
            "iteration",
            "iteration",
            "تكرار",
            "mathematics",
        ),

        DictionaryEntry(
            "invariant",
            "invariant",
            "ثابت بنيوي",
            "mathematics",
        ),

        DictionaryEntry(
            "verification",
            "verification",
            "تحقق",
            "logic",
        ),

        DictionaryEntry(
            "validation",
            "validation",
            "تصديق",
            "system",
        ),

        DictionaryEntry(
            "constraint",
            "constraint",
            "قيد",
            "logic",
        ),

        DictionaryEntry(
            "model",
            "model",
            "نموذج",
            "reasoning",
        ),

        DictionaryEntry(
            "schema",
            "schema",
            "مخطط",
            "database",
        ),

        DictionaryEntry(
            "index",
            "index",
            "فهرس",
            "database",
        ),

        DictionaryEntry(
            "tuple",
            "tuple",
            "صف",
            "database",
        ),

        DictionaryEntry(
            "join",
            "join",
            "ضم",
            "database",
        ),

        DictionaryEntry(
            "projection",
            "projection",
            "إسقاط",
            "database",
        ),

        DictionaryEntry(
            "recursion",
            "recursion",
            "استدعاء ذاتي",
            "logic",
        ),

        DictionaryEntry(
            "compiler",
            "compiler",
            "مترجم",
            "system",
        ),

        DictionaryEntry(
            "kernel",
            "kernel",
            "نواة",
            "system",
        ),

        DictionaryEntry(
            "agent",
            "agent",
            "وكيل",
            "system",
        ),

        DictionaryEntry(
            "context",
            "context",
            "سياق",
            "reasoning",
        ),

        DictionaryEntry(
            "memory",
            "memory",
            "ذاكرة",
            "system",
        ),

        DictionaryEntry(
            "knowledge_graph",
            "knowledge graph",
            "رسم بياني معرفي",
            "reasoning",
        ),

        DictionaryEntry(
            "translation",
            "translation",
            "ترجمة",
            "language",
        ),

        DictionaryEntry(
            "meaning",
            "meaning",
            "معنى",
            "language",
        ),

        DictionaryEntry(
            "word",
            "word",
            "كلمة",
            "language",
        ),

        DictionaryEntry(
            "sentence",
            "sentence",
            "جملة",
            "language",
        ),

        DictionaryEntry(
            "text",
            "text",
            "نص",
            "language",
        ),

        DictionaryEntry(
            "character",
            "character",
            "حرف",
            "language",
        ),

        DictionaryEntry(
            "unicode",
            "Unicode",
            "يونيكود",
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
            "ترميز",
            "encoding",
        ),

        DictionaryEntry(
            "normalization",
            "normalization",
            "تطبيع",
            "language",
        ),

        DictionaryEntry(
            "token",
            "token",
            "رمز لغوي",
            "language",
        ),

        DictionaryEntry(
            "lexicon",
            "lexicon",
            "معجم",
            "language",
        ),

        DictionaryEntry(
            "ontology",
            "ontology",
            "أنطولوجيا",
            "reasoning",
        ),

        DictionaryEntry(
            "classification",
            "classification",
            "تصنيف",
            "reasoning",
        ),

        DictionaryEntry(
            "category",
            "category",
            "فئة",
            "logic",
        ),

        DictionaryEntry(
            "attribute",
            "attribute",
            "خاصية",
            "database",
        ),

        DictionaryEntry(
            "property",
            "property",
            "خاصية",
            "logic",
        ),

        DictionaryEntry(
            "entity",
            "entity",
            "كيان",
            "ontology",
        ),

        DictionaryEntry(
            "object",
            "object",
            "كائن",
            "ontology",
        ),

        DictionaryEntry(
            "event",
            "event",
            "حدث",
            "reasoning",
        ),

        DictionaryEntry(
            "condition",
            "condition",
            "شرط",
            "logic",
        ),

        DictionaryEntry(
            "conclusion",
            "conclusion",
            "استنتاج نهائي",
            "reasoning",
        ),

        DictionaryEntry(
            "premise",
            "premise",
            "مقدمة",
            "logic",
        ),

        DictionaryEntry(
            "axiom",
            "axiom",
            "مسلمة",
            "logic",
        ),

        DictionaryEntry(
            "theorem",
            "theorem",
            "مبرهنة",
            "logic",
        ),

        DictionaryEntry(
            "consistency",
            "consistency",
            "اتساق",
            "logic",
        ),

        DictionaryEntry(
            "soundness",
            "soundness",
            "سلامة",
            "logic",
        ),

        DictionaryEntry(
            "completeness",
            "completeness",
            "اكتمال",
            "logic",
        ),

        DictionaryEntry(
            "truth_value",
            "truth value",
            "قيمة الحقيقة",
            "logic",
        ),

        DictionaryEntry(
            "domain",
            "domain",
            "مجال",
            "mathematics",
        ),

        DictionaryEntry(
            "codomain",
            "codomain",
            "المجال المقابل",
            "mathematics",
        ),

        DictionaryEntry(
            "mapping",
            "mapping",
            "تطبيق",
            "mathematics",
        ),

        DictionaryEntry(
            "composition",
            "composition",
            "تركيب",
            "mathematics",
        ),

        DictionaryEntry(
            "order",
            "order",
            "ترتيب",
            "mathematics",
        ),

        DictionaryEntry(
            "partial_order",
            "partial order",
            "ترتيب جزئي",
            "mathematics",
        ),

        DictionaryEntry(
            "lattice",
            "lattice",
            "شبكة رياضية",
            "mathematics",
        ),

        DictionaryEntry(
            "set_member",
            "set member",
            "عضو مجموعة",
            "mathematics",
        ),

        DictionaryEntry(
            "subset",
            "subset",
            "مجموعة جزئية",
            "mathematics",
        ),

        DictionaryEntry(
            "intersection",
            "intersection",
            "تقاطع",
            "mathematics",
        ),

        DictionaryEntry(
            "union",
            "union",
            "اتحاد",
            "mathematics",
        ),

        DictionaryEntry(
            "difference_set",
            "set difference",
            "فرق المجموعات",
            "mathematics",
        ),

        DictionaryEntry(
            "cardinality",
            "cardinality",
            "عدد العناصر",
            "mathematics",
        ),

        DictionaryEntry(
            "finite",
            "finite",
            "منته",
            "mathematics",
        ),

        DictionaryEntry(
            "infinite",
            "infinite",
            "لانهائي",
            "mathematics",
        ),

        DictionaryEntry(
            "algorithm",
            "algorithm",
            "خوارزمية",
            "system",
        ),

        DictionaryEntry(
            "evaluation",
            "evaluation",
            "تقييم",
            "logic",
        ),

        DictionaryEntry(
            "bottom_up",
            "bottom-up",
            "من الأسفل إلى الأعلى",
            "logic",
        ),

        DictionaryEntry(
            "semi_naive",
            "semi-naive evaluation",
            "تقييم شبه ساذج",
            "logic",
        ),

        DictionaryEntry(
            "dependency_graph",
            "dependency graph",
            "رسم بياني للاعتماد",
            "logic",
        ),

        DictionaryEntry(
            "negative_dependency",
            "negative dependency",
            "اعتماد سلبي",
            "logic",
        ),

        DictionaryEntry(
            "positive_dependency",
            "positive dependency",
            "اعتماد إيجابي",
            "logic",
        ),

        DictionaryEntry(
            "stratified_negation",
            "stratified negation",
            "النفي الطبقي",
            "logic",
        ),

        DictionaryEntry(
            "ground_fact",
            "ground fact",
            "حقيقة مكتملة",
            "logic",
        ),

        DictionaryEntry(
            "substitution",
            "substitution",
            "استبدال",
            "logic",
        ),

        DictionaryEntry(
            "unification",
            "unification",
            "توحيد",
            "logic",
        ),

        DictionaryEntry(
            "variable_binding",
            "variable binding",
            "ربط المتغير",
            "logic",
        ),

        DictionaryEntry(
            "pattern",
            "pattern",
            "نمط",
            "logic",
        ),

        DictionaryEntry(
            "match",
            "match",
            "مطابقة",
            "logic",
        ),

        DictionaryEntry(
            "grounding",
            "grounding",
            "تثبيت",
            "logic",
        ),

        DictionaryEntry(
            "derivation_tree",
            "derivation tree",
            "شجرة الاشتقاق",
            "logic",
        ),

        DictionaryEntry(
            "proof_tree",
            "proof tree",
            "شجرة البرهان",
            "logic",
        ),

        DictionaryEntry(
            "dependency",
            "dependency",
            "تبعية",
            "architecture",
        ),

        DictionaryEntry(
            "pipeline",
            "pipeline",
            "خط معالجة",
            "architecture",
        ),

        DictionaryEntry(
            "compiler_pass",
            "compiler pass",
            "مرحلة مترجم",
            "compiler",
        ),

        DictionaryEntry(
            "intermediate_representation",
            "intermediate representation",
            "تمثيل وسيط",
            "compiler",
        ),

        DictionaryEntry(
            "runtime",
            "runtime",
            "بيئة تشغيل",
            "system",
        ),

        DictionaryEntry(
            "process",
            "process",
            "عملية",
            "system",
        ),

        DictionaryEntry(
            "subprocess",
            "subprocess",
            "عملية فرعية",
            "system",
        ),

        DictionaryEntry(
            "filesystem",
            "filesystem",
            "نظام ملفات",
            "system",
        ),

        DictionaryEntry(
            "temporary_directory",
            "temporary directory",
            "دليل مؤقت",
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
            "تسلسل",
            "system",
        ),

        DictionaryEntry(
            "hash",
            "hash",
            "بصمة",
            "security",
        ),

        DictionaryEntry(
            "integrity",
            "integrity",
            "سلامة",
            "security",
        ),

        DictionaryEntry(
            "determinism",
            "determinism",
            "حتمية",
            "security",
        ),

        DictionaryEntry(
            "audit",
            "audit",
            "تدقيق",
            "security",
        ),

        DictionaryEntry(
            "trace",
            "trace",
            "تتبع",
            "reasoning",
        ),

        DictionaryEntry(
            "explain",
            "explain",
            "شرح",
            "reasoning",
        ),

        DictionaryEntry(
            "evidence",
            "evidence",
            "دليل",
            "reasoning",
        ),

        DictionaryEntry(
            "assertion",
            "assertion",
            "تأكيد",
            "logic",
        ),

        DictionaryEntry(
            "verification_state",
            "verification state",
            "حالة التحقق",
            "logic",
        ),

        DictionaryEntry(
            "accepted",
            "accepted",
            "مقبول",
            "verification",
        ),

        DictionaryEntry(
            "rejected",
            "rejected",
            "مرفوض",
            "verification",
        ),

        DictionaryEntry(
            "unknown",
            "unknown",
            "غير معروف",
            "reasoning",
        ),

        DictionaryEntry(
            "known",
            "known",
            "معروف",
            "reasoning",
        ),

        DictionaryEntry(
            "derived",
            "derived",
            "مشتق",
            "reasoning",
        ),

        DictionaryEntry(
            "source",
            "source",
            "مصدر",
            "reasoning",
        ),

        DictionaryEntry(
            "target",
            "target",
            "هدف",
            "reasoning",
        ),

        DictionaryEntry(
            "dependency_edge",
            "dependency edge",
            "حافة اعتماد",
            "graph",
        ),

        DictionaryEntry(
            "semantic_edge",
            "semantic edge",
            "حافة دلالية",
            "graph",
        ),

        DictionaryEntry(
            "logical_edge",
            "logical edge",
            "حافة منطقية",
            "graph",
        ),

        DictionaryEntry(
            "activation",
            "activation",
            "تنشيط",
            "reasoning",
        ),

        DictionaryEntry(
            "selection",
            "selection",
            "اختيار",
            "reasoning",
        ),

        DictionaryEntry(
            "resolution",
            "resolution",
            "حل",
            "logic",
        ),

        DictionaryEntry(
            "conflict",
            "conflict",
            "تعارض",
            "logic",
        ),

        DictionaryEntry(
            "agreement",
            "agreement",
            "اتفاق",
            "logic",
        ),

        DictionaryEntry(
            "contradiction",
            "contradiction",
            "تناقض",
            "logic",
        ),

        DictionaryEntry(
            "consensus",
            "consensus",
            "إجماع",
            "reasoning",
        ),

        DictionaryEntry(
            "priority",
            "priority",
            "أولوية",
            "reasoning",
        ),

        DictionaryEntry(
            "weight",
            "weight",
            "وزن",
            "mathematics",
        ),

        DictionaryEntry(
            "score",
            "score",
            "درجة",
            "reasoning",
        ),

        DictionaryEntry(
            "threshold",
            "threshold",
            "عتبة",
            "reasoning",
        ),

        DictionaryEntry(
            "rank",
            "rank",
            "رتبة",
            "mathematics",
        ),

        DictionaryEntry(
            "dimension",
            "dimension",
            "بُعد",
            "mathematics",
        ),

        DictionaryEntry(
            "matrix",
            "matrix",
            "مصفوفة",
            "mathematics",
        ),

        DictionaryEntry(
            "vector",
            "vector",
            "متجه",
            "mathematics",
        ),

        DictionaryEntry(
            "tensor",
            "tensor",
            "موتر",
            "mathematics",
        ),

        DictionaryEntry(
            "operation",
            "operation",
            "عملية",
            "mathematics",
        ),

        DictionaryEntry(
            "composition_rule",
            "composition rule",
            "قاعدة التركيب",
            "logic",
        ),

        DictionaryEntry(
            "rewrite",
            "rewrite",
            "إعادة كتابة",
            "logic",
        ),

        DictionaryEntry(
            "normal_form",
            "normal form",
            "صيغة معيارية",
            "logic",
        ),

        DictionaryEntry(
            "canonical",
            "canonical",
            "قياسي",
            "mathematics",
        ),

        DictionaryEntry(
            "representation",
            "representation",
            "تمثيل",
            "system",
        ),

        DictionaryEntry(
            "serialization_format",
            "serialization format",
            "تنسيق التسلسل",
            "system",
        ),

        DictionaryEntry(
            "configuration",
            "configuration",
            "تهيئة",
            "system",
        ),

        DictionaryEntry(
            "parameter",
            "parameter",
            "معامل",
            "mathematics",
        ),

        DictionaryEntry(
            "argument",
            "argument",
            "وسيط",
            "logic",
        ),

        DictionaryEntry(
            "arity",
            "arity",
            "رتبة العلاقة",
            "logic",
        ),

        DictionaryEntry(
            "predicate_symbol",
            "predicate symbol",
            "رمز المحمول",
            "logic",
        ),

        DictionaryEntry(
            "relation_symbol",
            "relation symbol",
            "رمز العلاقة",
            "logic",
        ),

        DictionaryEntry(
            "database_fact",
            "database fact",
            "حقيقة قاعدة البيانات",
            "database",
        ),

        DictionaryEntry(
            "derived_relation",
            "derived relation",
            "علاقة مشتقة",
            "database",
        ),

        DictionaryEntry(
            "base_relation",
            "base relation",
            "علاقة أساسية",
            "database",
        ),

        DictionaryEntry(
            "recursive_relation",
            "recursive relation",
            "علاقة تكرارية",
            "database",
        ),

        DictionaryEntry(
            "query_result",
            "query result",
            "نتيجة الاستعلام",
            "database",
        ),

        DictionaryEntry(
            "relation_algebra",
            "relational algebra",
            "الجبر العلائقي",
            "database",
        ),

        DictionaryEntry(
            "join_condition",
            "join condition",
            "شرط الضم",
            "database",
        ),

        DictionaryEntry(
            "selection_condition",
            "selection condition",
            "شرط الاختيار",
            "database",
        ),

        DictionaryEntry(
            "projection_column",
            "projection column",
            "عمود الإسقاط",
            "database",
        ),

        DictionaryEntry(
            "closure_operator",
            "closure operator",
            "مؤثر الإغلاق",
            "mathematics",
        ),

        DictionaryEntry(
            "fixed_point_operator",
            "fixed point operator",
            "مؤثر النقطة الثابتة",
            "mathematics",
        ),

        DictionaryEntry(
            "least_fixed_point",
            "least fixed point",
            "أصغر نقطة ثابتة",
            "mathematics",
        ),

        DictionaryEntry(
            "monotonic",
            "monotonic",
            "رتيب",
            "mathematics",
        ),

        DictionaryEntry(
            "finite_model",
            "finite model",
            "نموذج منته",
            "logic",
        ),

        DictionaryEntry(
            "model_checking",
            "model checking",
            "فحص النموذج",
            "logic",
        ),

        DictionaryEntry(
            "formal_system",
            "formal system",
            "نظام صوري",
            "logic",
        ),

        DictionaryEntry(
            "symbolic_execution",
            "symbolic execution",
            "تنفيذ رمزي",
            "reasoning",
        ),

        DictionaryEntry(
            "symbolic_state",
            "symbolic state",
            "حالة رمزية",
            "reasoning",
        ),

        DictionaryEntry(
            "reasoning_kernel",
            "reasoning kernel",
            "نواة الاستدلال",
            "reasoning",
        ),

        DictionaryEntry(
            "dense_reasoning",
            "dense reasoning",
            "استدلال كثيف",
            "reasoning",
        ),

        DictionaryEntry(
            "knowledge_base",
            "knowledge base",
            "قاعدة معرفة",
            "reasoning",
        ),

        DictionaryEntry(
            "knowledge_relation",
            "knowledge relation",
            "علاقة معرفية",
            "reasoning",
        ),

        DictionaryEntry(
            "semantic_relation",
            "semantic relation",
            "علاقة دلالية",
            "reasoning",
        ),

        DictionaryEntry(
            "lexical_relation",
            "lexical relation",
            "علاقة معجمية",
            "language",
        ),

        DictionaryEntry(
            "bilingual",
            "bilingual",
            "ثنائي اللغة",
            "language",
        ),

        DictionaryEntry(
            "multilingual",
            "multilingual",
            "متعدد اللغات",
            "language",
        ),

        DictionaryEntry(
            "arabic_script",
            "Arabic script",
            "الخط العربي",
            "language",
        ),

        DictionaryEntry(
            "right_to_left",
            "right-to-left",
            "من اليمين إلى اليسار",
            "language",
        ),

        DictionaryEntry(
            "left_to_right",
            "left-to-right",
            "من اليسار إلى اليمين",
            "language",
        ),

        DictionaryEntry(
            "bidirectional_text",
            "bidirectional text",
            "نص ثنائي الاتجاه",
            "language",
        ),

        DictionaryEntry(
            "unicode_symbol",
            "Unicode symbol",
            "رمز يونيكود",
            "encoding",
        ),

        DictionaryEntry(
            "arabic_semantics",
            "Arabic semantics",
            "دلالات عربية",
            "language",
        ),

        DictionaryEntry(
            "english_semantics",
            "English semantics",
            "دلالات إنجليزية",
            "language",
        ),

        DictionaryEntry(
            "cross_language",
            "cross-language",
            "عبر اللغات",
            "language",
        ),

        DictionaryEntry(
            "semantic_equivalence",
            "semantic equivalence",
            "تكافؤ دلالي",
            "reasoning",
        ),

        DictionaryEntry(
            "translation_edge",
            "translation edge",
            "حافة ترجمة",
            "language",
        ),

        DictionaryEntry(
            "concept_identity",
            "concept identity",
            "هوية المفهوم",
            "reasoning",
        ),

        DictionaryEntry(
            "concept_relation",
            "concept relation",
            "علاقة المفهوم",
            "reasoning",
        ),

        DictionaryEntry(
            "knowledge_edge",
            "knowledge edge",
            "حافة معرفية",
            "reasoning",
        ),

        DictionaryEntry(
            "reasoning_edge",
            "reasoning edge",
            "حافة استدلالية",
            "reasoning",
        ),

        DictionaryEntry(
            "proof_edge",
            "proof edge",
            "حافة برهانية",
            "logic",
        ),

        DictionaryEntry(
            "derivation_edge",
            "derivation edge",
            "حافة اشتقاق",
            "logic",
        ),

        DictionaryEntry(
            "constraint_edge",
            "constraint edge",
            "حافة قيد",
            "logic",
        ),

        DictionaryEntry(
            "verification_edge",
            "verification edge",
            "حافة تحقق",
            "verification",
        ),

        DictionaryEntry(
            "audit_edge",
            "audit edge",
            "حافة تدقيق",
            "security",
        ),

        DictionaryEntry(
            "trust",
            "trust",
            "ثقة",
            "security",
        ),

        DictionaryEntry(
            "authorization",
            "authorization",
            "تفويض",
            "security",
        ),

        DictionaryEntry(
            "permission",
            "permission",
            "إذن",
            "security",
        ),

        DictionaryEntry(
            "policy",
            "policy",
            "سياسة",
            "security",
        ),

        DictionaryEntry(
            "governance",
            "governance",
            "حوكمة",
            "security",
        ),

        DictionaryEntry(
            "provenance",
            "provenance",
            "مصدرية",
            "security",
        ),

        DictionaryEntry(
            "lineage",
            "lineage",
            "سلسلة الأصل",
            "reasoning",
        ),

        DictionaryEntry(
            "traceability",
            "traceability",
            "قابلية التتبع",
            "reasoning",
        ),

        DictionaryEntry(
            "reproducibility",
            "reproducibility",
            "قابلية إعادة الإنتاج",
            "system",
        ),

        DictionaryEntry(
            "deterministic_output",
            "deterministic output",
            "مخرج حتمي",
            "system",
        ),

        DictionaryEntry(
            "failure",
            "failure",
            "فشل",
            "system",
        ),

        DictionaryEntry(
            "error",
            "error",
            "خطأ",
            "system",
        ),

        DictionaryEntry(
            "exception",
            "exception",
            "استثناء",
            "system",
        ),

        DictionaryEntry(
            "timeout",
            "timeout",
            "مهلة",
            "system",
        ),

        DictionaryEntry(
            "process_exit",
            "process exit",
            "خروج العملية",
            "system",
        ),

        DictionaryEntry(
            "compiler_error",
            "compiler error",
            "خطأ المترجم",
            "compiler",
        ),

        DictionaryEntry(
            "compile_success",
            "compile success",
            "نجاح الترجمة",
            "compiler",
        ),

        DictionaryEntry(
            "result_set",
            "result set",
            "مجموعة النتائج",
            "database",
        ),

        DictionaryEntry(
            "row",
            "row",
            "صف",
            "database",
        ),

        DictionaryEntry(
            "column",
            "column",
            "عمود",
            "database",
        ),

        DictionaryEntry(
            "schema_declaration",
            "schema declaration",
            "تصريح المخطط",
            "database",
        ),

        DictionaryEntry(
            "relation_declaration",
            "relation declaration",
            "تصريح العلاقة",
            "database",
        ),

        DictionaryEntry(
            "fact_store",
            "fact store",
            "مخزن الحقائق",
            "database",
        ),

        DictionaryEntry(
            "knowledge_store",
            "knowledge store",
            "مخزن المعرفة",
            "reasoning",
        ),

        DictionaryEntry(
            "reasoning_engine",
            "reasoning engine",
            "محرك الاستدلال",
            "reasoning",
        ),

        DictionaryEntry(
            "logical_engine",
            "logical engine",
            "محرك منطقي",
            "reasoning",
        ),

        DictionaryEntry(
            "symbolic_engine",
            "symbolic engine",
            "محرك رمزي",
            "reasoning",
        ),

        DictionaryEntry(
            "datalog",
            "Datalog",
            "داتالوج",
            "logic",
        ),

        DictionaryEntry(
            "souffle",
            "Soufflé",
            "Soufflé",
            "compiler",
        ),

        DictionaryEntry(
            "subprocess_bridge",
            "subprocess bridge",
            "جسر العملية الفرعية",
            "system",
        ),

        DictionaryEntry(
            "agent_reasoning",
            "agent reasoning",
            "استدلال الوكيل",
            "reasoning",
        ),

        DictionaryEntry(
            "massive",
            "massive",
            "ضخم",
            "system",
        ),

        DictionaryEntry(
            "dense",
            "dense",
            "كثيف",
            "system",
        ),

        DictionaryEntry(
            "kernel_layer",
            "kernel layer",
            "طبقة النواة",
            "architecture",
        ),

        DictionaryEntry(
            "reasoning_layer",
            "reasoning layer",
            "طبقة الاستدلال",
            "architecture",
        ),

        DictionaryEntry(
            "language_layer",
            "language layer",
            "طبقة اللغة",
            "architecture",
        ),

        DictionaryEntry(
            "data_layer",
            "data layer",
            "طبقة البيانات",
            "architecture",
        ),

        DictionaryEntry(
            "execution_layer",
            "execution layer",
            "طبقة التنفيذ",
            "architecture",
        ),

        DictionaryEntry(
            "interface_layer",
            "interface layer",
            "طبقة الواجهة",
            "architecture",
        ),

        DictionaryEntry(
            "knowledge_layer",
            "knowledge layer",
            "طبقة المعرفة",
            "architecture",
        ),

        DictionaryEntry(
            "semantic_layer",
            "semantic layer",
            "الطبقة الدلالية",
            "architecture",
        ),

        DictionaryEntry(
            "proof_layer",
            "proof layer",
            "طبقة البرهان",
            "architecture",
        ),

        DictionaryEntry(
            "verification_layer",
            "verification layer",
            "طبقة التحقق",
            "architecture",
        ),

        DictionaryEntry(
            "audit_layer",
            "audit layer",
            "طبقة التدقيق",
            "architecture",
        ),

        DictionaryEntry(
            "decision",
            "decision",
            "قرار",
            "reasoning",
        ),

        DictionaryEntry(
            "decision_rule",
            "decision rule",
            "قاعدة القرار",
            "reasoning",
        ),

        DictionaryEntry(
            "decision_graph",
            "decision graph",
            "رسم بياني للقرار",
            "reasoning",
        ),

        DictionaryEntry(
            "decision_path",
            "decision path",
            "مسار القرار",
            "reasoning",
        ),

        DictionaryEntry(
            "decision_state",
            "decision state",
            "حالة القرار",
            "reasoning",
        ),

        DictionaryEntry(
            "proof_state",
            "proof state",
            "حالة البرهان",
            "logic",
        ),

        DictionaryEntry(
            "logical_state",
            "logical state",
            "حالة منطقية",
            "logic",
        ),

        DictionaryEntry(
            "semantic_state",
            "semantic state",
            "حالة دلالية",
            "reasoning",
        ),

        DictionaryEntry(
            "language_state",
            "language state",
            "حالة لغوية",
            "language",
        ),

        DictionaryEntry(
            "translation_state",
            "translation state",
            "حالة الترجمة",
            "language",
        ),

        DictionaryEntry(
            "knowledge_state",
            "knowledge state",
            "حالة المعرفة",
            "reasoning",
        ),

        DictionaryEntry(
            "consistency_check",
            "consistency check",
            "فحص الاتساق",
            "verification",
        ),

        DictionaryEntry(
            "constraint_check",
            "constraint check",
            "فحص القيود",
            "verification",
        ),

        DictionaryEntry(
            "proof_check",
            "proof check",
            "فحص البرهان",
            "verification",
        ),

        DictionaryEntry(
            "semantic_check",
            "semantic check",
            "الفحص الدلالي",
            "verification",
        ),

        DictionaryEntry(
            "dictionary_check",
            "dictionary check",
            "فحص المعجم",
            "verification",
        ),

        DictionaryEntry(
            "bilingual_check",
            "bilingual check",
            "الفحص ثنائي اللغة",
            "verification",
        ),

        DictionaryEntry(
            "kernel_check",
            "kernel check",
            "فحص النواة",
            "verification",
        ),

        DictionaryEntry(
            "agent_check",
            "agent check",
            "فحص الوكيل",
            "verification",
        ),

        DictionaryEntry(
            "reasoning_check",
            "reasoning check",
            "فحص الاستدلال",
            "verification",
        ),

        DictionaryEntry(
            "final_result",
            "final result",
            "النتيجة النهائية",
            "reasoning",
        ),

        DictionaryEntry(
            "derived_fact",
            "derived fact",
            "حقيقة مشتقة",
            "reasoning",
        ),

        DictionaryEntry(
            "base_fact",
            "base fact",
            "حقيقة أساسية",
            "reasoning",
        ),

        DictionaryEntry(
            "rule_application",
            "rule application",
            "تطبيق القاعدة",
            "reasoning",
        ),

        DictionaryEntry(
            "inference_step",
            "inference step",
            "خطوة استدلال",
            "reasoning",
        ),

        DictionaryEntry(
            "proof_step",
            "proof step",
            "خطوة برهان",
            "logic",
        ),

        DictionaryEntry(
            "reasoning_step",
            "reasoning step",
            "خطوة استدلال",
            "reasoning",
        ),

        DictionaryEntry(
            "symbolic_step",
            "symbolic step",
            "خطوة رمزية",
            "reasoning",
        ),

        DictionaryEntry(
            "semantic_step",
            "semantic step",
            "خطوة دلالية",
            "reasoning",
        ),

        DictionaryEntry(
            "language_step",
            "language step",
            "خطوة لغوية",
            "language",
        ),

        DictionaryEntry(
            "graph_step",
            "graph step",
            "خطوة بيانية",
            "graph",
        ),

        DictionaryEntry(
            "database_step",
            "database step",
            "خطوة قاعدة بيانات",
            "database",
        ),

        DictionaryEntry(
            "compiler_step",
            "compiler step",
            "خطوة مترجم",
            "compiler",
        ),

        DictionaryEntry(
            "execution_step",
            "execution step",
            "خطوة تنفيذ",
            "system",
        ),

        DictionaryEntry(
            "system_step",
            "system step",
            "خطوة نظام",
            "system",
        ),

        DictionaryEntry(
            "terminal_state",
            "terminal state",
            "حالة نهائية",
            "system",
        ),

        DictionaryEntry(
            "initial_state",
            "initial state",
            "حالة ابتدائية",
            "system",
        ),

        DictionaryEntry(
            "transition_rule",
            "transition rule",
            "قاعدة الانتقال",
            "system",
        ),

        DictionaryEntry(
            "state_relation",
            "state relation",
            "علاقة الحالة",
            "system",
        ),

        DictionaryEntry(
            "state_graph",
            "state graph",
            "رسم بياني للحالة",
            "system",
        ),

        DictionaryEntry(
            "causal_relation",
            "causal relation",
            "علاقة سببية",
            "reasoning",
        ),

        DictionaryEntry(
            "logical_relation",
            "logical relation",
            "علاقة منطقية",
            "logic",
        ),

        DictionaryEntry(
            "syntactic_relation",
            "syntactic relation",
            "علاقة نحوية",
            "language",
        ),

        DictionaryEntry(
            "morphological_relation",
            "morphological relation",
            "علاقة صرفية",
            "language",
        ),

        DictionaryEntry(
            "lexical_relation",
            "lexical relation",
            "علاقة معجمية",
            "language",
        ),

        DictionaryEntry(
            "translation_relation",
            "translation relation",
            "علاقة ترجمة",
            "language",
        ),

        DictionaryEntry(
            "semantic_mapping",
            "semantic mapping",
            "تطبيق دلالي",
            "language",
        ),

        DictionaryEntry(
            "concept_mapping",
            "concept mapping",
            "مطابقة المفاهيم",
            "reasoning",
        ),

        DictionaryEntry(
            "cross_reference",
            "cross-reference",
            "مرجع متقاطع",
            "reasoning",
        ),

        DictionaryEntry(
            "knowledge_reference",
            "knowledge reference",
            "مرجع معرفي",
            "reasoning",
        ),

        DictionaryEntry(
            "symbol_reference",
            "symbol reference",
            "مرجع رمزي",
            "logic",
        ),

        DictionaryEntry(
            "relation_reference",
            "relation reference",
            "مرجع العلاقة",
            "database",
        ),

        DictionaryEntry(
            "dictionary_reference",
            "dictionary reference",
            "مرجع المعجم",
            "language",
        ),

        DictionaryEntry(
            "proof_reference",
            "proof reference",
            "مرجع البرهان",
            "logic",
        ),

        DictionaryEntry(
            "audit_reference",
            "audit reference",
            "مرجع التدقيق",
            "security",
        ),

        DictionaryEntry(
            "execution_reference",
            "execution reference",
            "مرجع التنفيذ",
            "system",
        ),

        DictionaryEntry(
            "compiler_reference",
            "compiler reference",
            "مرجع المترجم",
            "compiler",
        ),

        DictionaryEntry(
            "agent_reference",
            "agent reference",
            "مرجع الوكيل",
            "reasoning",
        ),

        DictionaryEntry(
            "reasoning_reference",
            "reasoning reference",
            "مرجع الاستدلال",
            "reasoning",
        ),

        DictionaryEntry(
            "kernel_reference",
            "kernel reference",
            "مرجع النواة",
            "system",
        ),

        DictionaryEntry(
            "dense_kernel",
            "dense kernel",
            "نواة كثيفة",
            "system",
        ),

        DictionaryEntry(
            "symbolic_kernel",
            "symbolic kernel",
            "نواة رمزية",
            "reasoning",
        ),

        DictionaryEntry(
            "language_kernel",
            "language kernel",
            "نواة لغوية",
            "language",
        ),

        DictionaryEntry(
            "semantic_kernel",
            "semantic kernel",
            "نواة دلالية",
            "reasoning",
        ),

        DictionaryEntry(
            "logic_kernel",
            "logic kernel",
            "نواة منطقية",
            "logic",
        ),

        DictionaryEntry(
            "database_kernel",
            "database kernel",
            "نواة قاعدة البيانات",
            "database",
        ),

        DictionaryEntry(
            "compiler_kernel",
            "compiler kernel",
            "نواة المترجم",
            "compiler",
        ),

        DictionaryEntry(
            "verification_kernel",
            "verification kernel",
            "نواة التحقق",
            "verification",
        ),

        DictionaryEntry(
            "audit_kernel",
            "audit kernel",
            "نواة التدقيق",
            "security",
        ),

        DictionaryEntry(
            "sovereign",
            "sovereign",
            "سيادي",
            "architecture",
        ),

        DictionaryEntry(
            "local",
            "local",
            "محلي",
            "architecture",
        ),

        DictionaryEntry(
            "portable",
            "portable",
            "محمول",
            "system",
        ),

        DictionaryEntry(
            "reproducible",
            "reproducible",
            "قابل لإعادة الإنتاج",
            "system",
        ),

        DictionaryEntry(
            "auditable",
            "auditable",
            "قابل للتدقيق",
            "security",
        ),

        DictionaryEntry(
            "formalizable",
            "formalizable",
            "قابل للصياغة الرسمية",
            "logic",
        ),

        DictionaryEntry(
            "machine_reasoning",
            "machine reasoning",
            "استدلال آلي",
            "reasoning",
        ),

        DictionaryEntry(
            "symbolic_reasoning",
            "symbolic reasoning",
            "استدلال رمزي",
            "reasoning",
        ),

        DictionaryEntry(
            "logical_reasoning",
            "logical reasoning",
            "استدلال منطقي",
            "reasoning",
        ),

        DictionaryEntry(
            "deductive_reasoning",
            "deductive reasoning",
            "استدلال استنباطي",
            "reasoning",
        ),

        DictionaryEntry(
            "relational_reasoning",
            "relational reasoning",
            "استدلال علائقي",
            "reasoning",
        ),

        DictionaryEntry(
            "graph_reasoning",
            "graph reasoning",
            "استدلال بياني",
            "reasoning",
        ),

        DictionaryEntry(
            "semantic_reasoning_engine",
            "semantic reasoning engine",
            "محرك الاستدلال الدلالي",
            "reasoning",
        ),

        DictionaryEntry(
            "bilingual_reasoning",
            "bilingual reasoning",
            "استدلال ثنائي اللغة",
            "reasoning",
        ),

        DictionaryEntry(
            "arabic_english_reasoning",
            "Arabic English reasoning",
            "استدلال عربي إنجليزي",
            "reasoning",
        ),

        DictionaryEntry(
            "knowledge_compilation",
            "knowledge compilation",
            "تجميع المعرفة",
            "reasoning",
        ),

        DictionaryEntry(
            "reasoning_compilation",
            "reasoning compilation",
            "تجميع الاستدلال",
            "reasoning",
        ),

        DictionaryEntry(
            "symbolic_compilation",
            "symbolic compilation",
            "تجميع رمزي",
            "compiler",
        ),

        DictionaryEntry(
            "relation_compilation",
            "relation compilation",
            "تجميع علائقي",
            "compiler",
        ),

        DictionaryEntry(
            "query_compilation",
            "query compilation",
            "تجميع الاستعلام",
            "compiler",
        ),

        DictionaryEntry(
            "rule_compilation",
            "rule compilation",
            "تجميع القواعد",
            "compiler",
        ),

        DictionaryEntry(
            "fact_compilation",
            "fact compilation",
            "تجميع الحقائق",
            "compiler",
        ),

        DictionaryEntry(
            "semantic_compilation",
            "semantic compilation",
            "تجميع دلالي",
            "compiler",
        ),

        DictionaryEntry(
            "language_compilation",
            "language compilation",
            "تجميع لغوي",
            "compiler",
        ),

        DictionaryEntry(
            "arabic_processing",
            "Arabic processing",
            "معالجة العربية",
            "language",
        ),

        DictionaryEntry(
            "english_processing",
            "English processing",
            "معالجة الإنجليزية",
            "language",
        ),

        DictionaryEntry(
            "bilingual_processing",
            "bilingual processing",
            "معالجة ثنائية اللغة",
            "language",
        ),

        DictionaryEntry(
            "semantic_processing",
            "semantic processing",
            "معالجة دلالية",
            "reasoning",
        ),

        DictionaryEntry(
            "symbolic_processing",
            "symbolic processing",
            "معالجة رمزية",
            "reasoning",
        ),

        DictionaryEntry(
            "formal_processing",
            "formal processing",
            "معالجة صورية",
            "logic",
        ),

        DictionaryEntry(
            "reasoning_context",
            "reasoning context",
            "سياق الاستدلال",
            "reasoning",
        ),

        DictionaryEntry(
            "dictionary_context",
            "dictionary context",
            "سياق المعجم",
            "language",
        ),

        DictionaryEntry(
            "semantic_context",
            "semantic context",
            "سياق دلالي",
            "reasoning",
        ),

        DictionaryEntry(
            "symbolic_context",
            "symbolic context",
            "سياق رمزي",
            "reasoning",
        ),

        DictionaryEntry(
            "logical_context",
            "logical context",
            "سياق منطقي",
            "logic",
        ),

        DictionaryEntry(
            "graph_context",
            "graph context",
            "سياق بياني",
            "graph",
        ),

        DictionaryEntry(
            "database_context",
            "database context",
            "سياق قاعدة البيانات",
            "database",
        ),

        DictionaryEntry(
            "execution_context",
            "execution context",
            "سياق التنفيذ",
            "system",
        ),

        DictionaryEntry(
            "compiler_context",
            "compiler context",
            "سياق المترجم",
            "compiler",
        ),

        DictionaryEntry(
            "verification_context",
            "verification context",
            "سياق التحقق",
            "verification",
        ),

        DictionaryEntry(
            "audit_context",
            "audit context",
            "سياق التدقيق",
            "security",
        ),

        DictionaryEntry(
            "agent_context",
            "agent context",
            "سياق الوكيل",
            "reasoning",
        ),

        DictionaryEntry(
            "kernel_context",
            "kernel context",
            "سياق النواة",
            "system",
        ),

        DictionaryEntry(
            "system_context",
            "system context",
            "سياق النظام",
            "system",
        ),

        DictionaryEntry(
            "final_state",
            "final state",
            "الحالة النهائية",
            "system",
        ),

        DictionaryEntry(
            "stable_state",
            "stable state",
            "حالة مستقرة",
            "system",
        ),

        DictionaryEntry(
            "converged_state",
            "converged state",
            "حالة متقاربة",
            "mathematics",
        ),

        DictionaryEntry(
            "closure_state",
            "closure state",
            "حالة الإغلاق",
            "mathematics",
        ),

        DictionaryEntry(
            "reasoning_closure",
            "reasoning closure",
            "إغلاق الاستدلال",
            "reasoning",
        ),

        DictionaryEntry(
            "knowledge_closure",
            "knowledge closure",
            "إغلاق المعرفة",
            "reasoning",
        ),

        DictionaryEntry(
            "semantic_closure",
            "semantic closure",
            "الإغلاق الدلالي",
            "reasoning",
        ),

        DictionaryEntry(
            "logical_closure",
            "logical closure",
            "الإغلاق المنطقي",
            "logic",
        ),

        DictionaryEntry(
            "graph_closure",
            "graph closure",
            "إغلاق الرسم البياني",
            "graph",
        ),

        DictionaryEntry(
            "transitive_closure",
            "transitive closure",
            "الإغلاق الانتقالي",
            "mathematics",
        ),

        DictionaryEntry(
            "dependency_closure",
            "dependency closure",
            "إغلاق التبعيات",
            "architecture",
        ),

        DictionaryEntry(
            "translation_closure",
            "translation closure",
            "إغلاق الترجمة",
            "language",
        ),

        DictionaryEntry(
            "dictionary_closure",
            "dictionary closure",
            "إغلاق المعجم",
            "language",
        ),

        DictionaryEntry(
            "proof_closure",
            "proof closure",
            "إغلاق البرهان",
            "logic",
        ),

        DictionaryEntry(
            "verification_closure",
            "verification closure",
            "إغلاق التحقق",
            "verification",
        ),

        DictionaryEntry(
            "audit_closure",
            "audit closure",
            "إغلاق التدقيق",
            "security",
        ),

        DictionaryEntry(
            "agent_closure",
            "agent closure",
            "إغلاق الوكيل",
            "reasoning",
        ),

        DictionaryEntry(
            "kernel_closure",
            "kernel closure",
            "إغلاق النواة",
            "system",
        ),

        DictionaryEntry(
            "system_closure",
            "system closure",
            "إغلاق النظام",
            "system",
        ),

        DictionaryEntry(
            "complete_reasoning",
            "complete reasoning",
            "استدلال كامل",
            "reasoning",
        ),

        DictionaryEntry(
            "verified_reasoning",
            "verified reasoning",
            "استدلال متحقق",
            "verification",
        ),

        DictionaryEntry(
            "audited_reasoning",
            "audited reasoning",
            "استدلال مدقق",
            "security",
        ),

        DictionaryEntry(
            "deterministic_reasoning",
            "deterministic reasoning",
            "استدلال حتمي",
            "reasoning",
        ),

        DictionaryEntry(
            "formal_reasoning_kernel",
            "formal reasoning kernel",
            "نواة استدلال صورية",
            "reasoning",
        ),

        DictionaryEntry(
            "bilingual_symbolic_kernel",
            "bilingual symbolic kernel",
            "نواة رمزية ثنائية اللغة",
            "reasoning",
        ),

        DictionaryEntry(
            "arabic_english_dictionary",
            "Arabic English dictionary",
            "معجم عربي إنجليزي",
            "language",
        ),

        DictionaryEntry(
            "dense_symbolic_kernel",
            "dense symbolic kernel",
            "نواة رمزية كثيفة",
            "reasoning",
        ),

    ]
