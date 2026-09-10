"""MXML: declarative control and contract language."""

from .parser import parse_mxml, MXMLParseError
from .schema import MXMLDocument, RuntimeConfig, Limits, CommandDecl, TaskDecl
from .validator import validate_mxml, ValidationError

__all__ = [
    "parse_mxml",
    "MXMLParseError",
    "MXMLDocument",
    "RuntimeConfig",
    "Limits",
    "CommandDecl",
    "TaskDecl",
    "validate_mxml",
    "ValidationError",
]
