"""State transition with audit event generation."""

from __future__ import annotations

import hashlib
import time
import uuid
from dataclasses import dataclass, field
from typing import Any

from .states import State, can_transition


@dataclass
class AuditEvent:
    event_type: str
    from_state: str
    to_state: str
    execution_id: str
    task_id: str
    input_hash: str
    timestamp: float
    reason: str
    metadata: dict[str, Any] = field(default_factory=dict)


class IllegalTransitionError(Exception):
    pass


class StateMachine:
    def __init__(self, execution_id: str | None = None) -> None:
        self.execution_id = execution_id or str(uuid.uuid4())
        self.current = State.RECEIVE
        self.history: list[AuditEvent] = []
        self.revision_count = 0

    def transition(
        self,
        to_state: State,
        *,
        task_id: str = "",
        input_data: Any = None,
        reason: str = "",
    ) -> AuditEvent:
        if not can_transition(self.current, to_state):
            raise IllegalTransitionError(
                f"illegal transition {self.current.value} → {to_state.value}"
            )
        payload = repr(input_data).encode("utf-8") if input_data is not None else b""
        input_hash = hashlib.sha256(payload).hexdigest()[:16]
        event = AuditEvent(
            event_type="state_transition",
            from_state=self.current.value,
            to_state=to_state.value,
            execution_id=self.execution_id,
            task_id=task_id,
            input_hash=input_hash,
            timestamp=time.time(),
            reason=reason,
        )
        self.history.append(event)
        self.current = to_state
        if to_state == State.REVISE:
            self.revision_count += 1
        return event
