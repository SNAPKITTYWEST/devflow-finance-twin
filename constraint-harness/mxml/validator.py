"""Structural validation of parsed MXML documents."""

from __future__ import annotations

from .schema import MXMLDocument


class ValidationError(Exception):
    def __init__(self, message: str, code: str = "STRUCTURAL") -> None:
        self.code = code
        super().__init__(message)


def validate_mxml(doc: MXMLDocument) -> None:
    """Raise ValidationError if document violates structural rules."""
    rt = doc.runtime
    if rt.limits.max_workers < 1:
        raise ValidationError("max_workers must be >= 1")
    if rt.limits.max_revisions < 0:
        raise ValidationError("max_revisions must be >= 0")
    if rt.limits.timeout_seconds < 1:
        raise ValidationError("timeout_seconds must be >= 1")
    if len(rt.tasks) > rt.limits.max_tasks:
        raise ValidationError(
            f"task count {len(rt.tasks)} exceeds max_tasks {rt.limits.max_tasks}"
        )
    # Command reference check
    cmd_ids = {c.id for c in rt.commands}
    for t in rt.tasks:
        if t.command not in cmd_ids:
            raise ValidationError(f"task '{t.id}' references unknown command '{t.command}'")
    # Self-dependency check
    for t in rt.tasks:
        if t.id in t.depends_on:
            raise ValidationError(f"task '{t.id}' has self-dependency")
    # Cycle detection (simple DFS)
    graph = {t.id: list(t.depends_on) for t in rt.tasks}
    visiting: set[str] = set()
    visited: set[str] = set()

    def dfs(node: str) -> None:
        if node in visiting:
            raise ValidationError(f"dependency cycle involving '{node}'")
        if node in visited:
            return
        visiting.add(node)
        for pred in graph.get(node, []):
            dfs(pred)
        visiting.remove(node)
        visited.add(node)

    for tid in graph:
        dfs(tid)
