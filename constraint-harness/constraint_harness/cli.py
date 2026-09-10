"""CLI: harness validate|run|inspect ..."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from mxml.parser import parse_mxml, MXMLParseError
from mxml.validator import validate_mxml, ValidationError
from runtime.executor import Executor
from audit.seal import seal_decision


def cmd_validate(path: str) -> int:
    src = Path(path).read_text(encoding="utf-8")
    try:
        doc = parse_mxml(src)
        validate_mxml(doc)
        print(json.dumps({"status": "VALID", "runtime_id": doc.runtime.id, "tasks": len(doc.runtime.tasks)}))
        return 0
    except (MXMLParseError, ValidationError) as exc:
        print(json.dumps({"status": "INVALID", "error": str(exc)}))
        return 1


def cmd_run(path: str) -> int:
    src = Path(path).read_text(encoding="utf-8")
    ex = Executor()
    result = ex.run(src, authorized=True)
    print(json.dumps(result, indent=2, default=str))
    return 0 if result["status"] == "SUCCESS" else 2


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="harness")
    sub = parser.add_subparsers(dest="cmd")

    p_val = sub.add_parser("validate")
    p_val.add_argument("file")

    p_run = sub.add_parser("run")
    p_run.add_argument("file")

    args = parser.parse_args(argv)
    if args.cmd == "validate":
        sys.exit(cmd_validate(args.file))
    if args.cmd == "run":
        sys.exit(cmd_run(args.file))
    parser.print_help()
    sys.exit(1)


if __name__ == "__main__":
    main()
