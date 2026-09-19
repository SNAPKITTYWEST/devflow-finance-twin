from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
import json
import uuid


def utc_now() -> str:
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

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, payload: Dict[str, Any]) -> "TreeNode":
        return cls(**payload)


class DiscoveryTree:
    """Serializable historical world and discovery tree."""

    def __init__(self, tree_id: Optional[str] = None, metadata: Optional[Dict[str, Any]] = None):
        self.tree_id = tree_id or "tree_" + uuid.uuid4().hex[:12]
        self.metadata = dict(metadata or {})
        self.created_at = utc_now()
        self.nodes: Dict[str, TreeNode] = {}
        root = TreeNode(branch_id="root", status="root", metadata={"depth": 0})
        self.root_id = root.node_id
        self.nodes[root.node_id] = root

    def add(self, parent_id: str, **fields: Any) -> TreeNode:
        if parent_id not in self.nodes:
            raise KeyError(f"unknown parent node: {parent_id}")
        node = TreeNode(parent_id=parent_id, **fields)
        self.nodes[node.node_id] = node
        self.nodes[parent_id].children.append(node.node_id)
        return node

    def get(self, node_id: str) -> TreeNode:
        return self.nodes[node_id]

    def leaves(self) -> List[TreeNode]:
        return [node for node in self.nodes.values() if not node.children and node.status != "root"]

    def validate(self):
        if self.root_id not in self.nodes:
            return False, "missing root"
        for node in self.nodes.values():
            for child_id in node.children:
                child = self.nodes.get(child_id)
                if child is None:
                    return False, f"child {child_id} missing"
                if child.parent_id != node.node_id:
                    return False, f"broken parent link for {child_id}"
        return True, None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "tree_id": self.tree_id,
            "created_at": self.created_at,
            "metadata": self.metadata,
            "root_id": self.root_id,
            "nodes": [node.to_dict() for node in self.nodes.values()],
        }

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), sort_keys=True, indent=2)

    @classmethod
    def from_dict(cls, payload: Dict[str, Any]) -> "DiscoveryTree":
        tree = cls(payload.get("tree_id"), payload.get("metadata"))
        tree.created_at = payload.get("created_at", utc_now())
        tree.root_id = payload.get("root_id", tree.root_id)
        tree.nodes = {node["node_id"]: TreeNode.from_dict(node) for node in payload.get("nodes", [])}
        return tree

    @classmethod
    def from_json(cls, raw: str) -> "DiscoveryTree":
        return cls.from_dict(json.loads(raw))
