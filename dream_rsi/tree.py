"""Serializable discovery trees and historical worlds."""

from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
import json
import uuid


def utc_now():
    return datetime.now(timezone.utc).isoformat()


@dataclass
class TreeNode:
    node_id: str = field(default_factory=lambda: "node_" + uuid.uuid4().hex[:12])
    parent_id: Optional[str] = None
    children: List[str] = field(default_factory=list)
    policy_decision: Dict[str, Any] = field(default_factory=dict)
    branch_id: str = "root"
    candidate: Dict[str, Any] = field(default_factory=dict)
    execution_trace: List[Dict[str, Any]] = field(default_factory=list)
    evaluator_result: Dict[str, Any] = field(default_factory=dict)
    score: float = 0.0
    status: str = "created"
    cost: float = 0.0
    timestamp: str = field(default_factory=utc_now)
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self):
        return asdict(self)

    @classmethod
    def from_dict(cls, value):
        return cls(**value)


class DiscoveryTree:
    def __init__(self, tree_id=None, metadata=None):
        self.tree_id = tree_id or "tree_" + uuid.uuid4().hex[:12]
        self.created_at = utc_now()
        self.metadata = dict(metadata or {})
        self.nodes: Dict[str, TreeNode] = {}
        root = TreeNode(branch_id="root", status="root")
        self.root_id = root.node_id
        self.nodes[root.node_id] = root

    def add(self, parent_id, **fields):
        if parent_id not in self.nodes:
            raise KeyError("unknown parent node: " + parent_id)
        node = TreeNode(parent_id=parent_id, **fields)
        self.nodes[node.node_id] = node
        self.nodes[parent_id].children.append(node.node_id)
        return node

    def get(self, node_id):
        return self.nodes[node_id]

    def leaves(self):
        return [n for n in self.nodes.values() if not n.children and n.status != "root"]

    def to_dict(self):
        return {"tree_id": self.tree_id, "created_at": self.created_at,
                "metadata": self.metadata, "root_id": self.root_id,
                "nodes": [node.to_dict() for node in self.nodes.values()]}

    def to_json(self):
        return json.dumps(self.to_dict(), sort_keys=True, indent=2)

    @classmethod
    def from_dict(cls, value):
        tree = cls(value["tree_id"], value.get("metadata"))
        tree.created_at = value.get("created_at", utc_now())
        tree.root_id = value["root_id"]
        tree.nodes = {item["node_id"]: TreeNode.from_dict(item) for item in value["nodes"]}
        return tree

    @classmethod
    def from_json(cls, text):
        return cls.from_dict(json.loads(text))

    def validate(self):
        if self.root_id not in self.nodes:
            return False, "missing root"
        for node in self.nodes.values():
            for child in node.children:
                if child not in self.nodes or self.nodes[child].parent_id != node.node_id:
                    return False, "broken parent/child link at " + node.node_id
        return True, None
