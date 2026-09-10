"""Strict MXML parser. Rejects malformed input. Never silently repairs."""

from __future__ import annotations

import hashlib
import xml.etree.ElementTree as ET
from typing import Any

from .schema import (
    CommandDecl,
    Limits,
    MXMLDocument,
    RuntimeConfig,
    TaskDecl,
)


class MXMLParseError(Exception):
    """Raised when MXML is malformed or violates structural rules."""

    def __init__(self, message: str, path: str = "") -> None:
        self.path = path
        super().__init__(f"{path}: {message}" if path else message)


def _require_child(parent: ET.Element, tag: str, path: str) -> ET.Element:
    child = parent.find(tag)
    if child is None:
        raise MXMLParseError(f"missing required element <{tag}>", path)
    return child


def _require_attr(elem: ET.Element, name: str, path: str) -> str:
    val = elem.get(name)
    if val is None or val == "":
        raise MXMLParseError(f"missing required attribute '{name}'", path)
    return val


def _parse_int(text: str | None, path: str, name: str) -> int:
    if text is None or text.strip() == "":
        raise MXMLParseError(f"missing integer value for {name}", path)
    try:
        v = int(text.strip())
    except ValueError as exc:
        raise MXMLParseError(f"invalid integer for {name}: {text!r}", path) from exc
    if v < 0:
        raise MXMLParseError(f"{name} must be non-negative", path)
    return v


def _parse_limits(elem: ET.Element, path: str) -> Limits:
    return Limits(
        max_workers=_parse_int(elem.findtext("max_workers"), f"{path}/max_workers", "max_workers"),
        max_revisions=_parse_int(elem.findtext("max_revisions"), f"{path}/max_revisions", "max_revisions"),
        timeout_seconds=_parse_int(elem.findtext("timeout_seconds"), f"{path}/timeout_seconds", "timeout_seconds"),
        max_tasks=_parse_int(elem.findtext("max_tasks") or "256", f"{path}/max_tasks", "max_tasks"),
        max_tool_calls=_parse_int(elem.findtext("max_tool_calls") or "64", f"{path}/max_tool_calls", "max_tool_calls"),
    )


def _parse_commands(elem: ET.Element, path: str) -> tuple[CommandDecl, ...]:
    cmds: list[CommandDecl] = []
    seen: set[str] = set()
    for i, c in enumerate(elem.findall("command")):
        cpath = f"{path}/command[{i}]"
        cid = _require_attr(c, "id", cpath)
        if cid in seen:
            raise MXMLParseError(f"duplicate command id '{cid}'", cpath)
        seen.add(cid)
        ctype = _require_attr(c, "type", cpath)
        isolation = c.get("isolation", "none")
        if isolation not in ("none", "process"):
            raise MXMLParseError(f"invalid isolation '{isolation}'", cpath)
        cmds.append(CommandDecl(id=cid, type=ctype, isolation=isolation, version=c.get("version", "1.0")))
    if not cmds:
        raise MXMLParseError("at least one <command> required", path)
    return tuple(cmds)


def _parse_tasks(elem: ET.Element, path: str) -> tuple[TaskDecl, ...]:
    tasks: list[TaskDecl] = []
    seen: set[str] = set()
    for i, t in enumerate(elem.findall("task")):
        tpath = f"{path}/task[{i}]"
        tid = _require_attr(t, "id", tpath)
        if tid in seen:
            raise MXMLParseError(f"duplicate task id '{tid}'", tpath)
        seen.add(tid)
        command = _require_attr(t, "command", tpath)
        deps_raw = t.get("depends_on", "")
        depends_on = tuple(d.strip() for d in deps_raw.split(",") if d.strip())
        input_data: dict[str, Any] = {}
        for child in t:
            if child.tag == "input":
                for kv in child:
                    input_data[kv.tag] = (kv.text or "").strip()
            elif child.tag not in ("depends_on",):
                input_data[child.tag] = (child.text or "").strip()
        rev = t.get("revision_limit")
        revision_limit = int(rev) if rev is not None else None
        tasks.append(
            TaskDecl(
                id=tid,
                command=command,
                depends_on=depends_on,
                input=input_data,
                revision_limit=revision_limit,
            )
        )
    if not tasks:
        raise MXMLParseError("at least one <task> required", path)
    return tuple(tasks)


def parse_mxml(source: str) -> MXMLDocument:
    """Parse MXML string into MXMLDocument. Raises MXMLParseError on failure."""
    try:
        root = ET.fromstring(source)
    except ET.ParseError as exc:
        raise MXMLParseError(f"XML parse error: {exc}") from exc

    if root.tag != "mxml":
        raise MXMLParseError(f"expected <mxml> root, got <{root.tag}>")

    version = root.get("version", "")
    if not version:
        raise MXMLParseError("missing version attribute on <mxml>")

    runtime_elem = _require_child(root, "runtime", "mxml")
    runtime_id = _require_attr(runtime_elem, "id", "mxml/runtime")

    limits_elem = _require_child(runtime_elem, "limits", "mxml/runtime")
    limits = _parse_limits(limits_elem, "mxml/runtime/limits")

    # Constitution axioms
    axioms: tuple[str, ...] = ()
    constitution_elem = runtime_elem.find("constitution")
    if constitution_elem is not None:
        axioms = tuple(
            a.get("ref", "") for a in constitution_elem.findall("axiom") if a.get("ref")
        )

    commands_elem = _require_child(runtime_elem, "commands", "mxml/runtime")
    commands = _parse_commands(commands_elem, "mxml/runtime/commands")

    tasks_elem = _require_child(runtime_elem, "tasks", "mxml/runtime")
    tasks = _parse_tasks(tasks_elem, "mxml/runtime/tasks")

    raw_hash = hashlib.sha256(source.encode("utf-8")).hexdigest()[:32]

    return MXMLDocument(
        version=version,
        runtime=RuntimeConfig(
            id=runtime_id,
            limits=limits,
            axioms=axioms,
            commands=commands,
            tasks=tasks,
        ),
        raw_hash=raw_hash,
    )
