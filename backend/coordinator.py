"""
Hand-rolled flow coordinator.

The server owns the step machine. Clients report events; this module
returns the next command. In-memory only — swap SessionStore for Redis
or Postgres when you leave the sketch stage.
"""

from __future__ import annotations

import secrets
import time
from enum import Enum
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field


class Step(str, Enum):
    boot = "boot"
    authenticate = "authenticate"
    hydrate = "hydrate"
    work = "work"
    complete = "complete"


class Command(str, Enum):
    show_auth = "show_auth"
    hydrate = "hydrate"
    retry_hydrate = "retry_hydrate"
    show_work = "show_work"
    complete = "complete"
    idle = "idle"
    reject = "reject"


# event -> (from_step, to_step, command)
TRANSITIONS: dict[str, tuple[Step, Step, Command]] = {
    "device_hello": (Step.boot, Step.authenticate, Command.show_auth),
    "signed_in": (Step.authenticate, Step.hydrate, Command.hydrate),
    "auth_failed": (Step.authenticate, Step.authenticate, Command.show_auth),
    "local_ready": (Step.hydrate, Step.work, Command.show_work),
    "hydrate_failed": (Step.hydrate, Step.hydrate, Command.retry_hydrate),
    "task_done": (Step.work, Step.work, Command.show_work),
    "task_failed": (Step.work, Step.work, Command.show_work),
    "flow_complete": (Step.work, Step.complete, Command.complete),
    "ack": (Step.complete, Step.complete, Command.idle),
}


class CreateSession(BaseModel):
    device_id: str
    app_version: str = "1.0.0"


class AdvanceRequest(BaseModel):
    event: str
    payload: dict[str, Any] = Field(default_factory=dict)
    checksum: str | None = None


class SessionView(BaseModel):
    session_id: str
    device_id: str
    step: Step
    command: Command
    payload: dict[str, Any]
    checkpoint: int
    updated_at: float


class Session:
    def __init__(self, device_id: str) -> None:
        self.id = "ses_" + secrets.token_hex(8)
        self.device_id = device_id
        self.step = Step.boot
        self.checkpoint = 0
        self.tasks_done = 0
        self.updated_at = time.time()
        self.last_command = Command.show_auth
        self.payload: dict[str, Any] = {"hint": "send device_hello"}


class SessionStore:
    def __init__(self) -> None:
        self._items: dict[str, Session] = {}

    def create(self, device_id: str) -> Session:
        session = Session(device_id)
        self._items[session.id] = session
        return session

    def get(self, session_id: str) -> Session | None:
        return self._items.get(session_id)


store = SessionStore()
app = FastAPI(title="Coordinator", version="0.1.0")


def view(session: Session) -> SessionView:
    return SessionView(
        session_id=session.id,
        device_id=session.device_id,
        step=session.step,
        command=session.last_command,
        payload=session.payload,
        checkpoint=session.checkpoint,
        updated_at=session.updated_at,
    )


@app.post("/sessions", response_model=SessionView)
def create_session(body: CreateSession) -> SessionView:
    session = store.create(body.device_id)
    return view(session)


@app.get("/sessions/{session_id}", response_model=SessionView)
def get_session(session_id: str) -> SessionView:
    session = store.get(session_id)
    if session is None:
        raise HTTPException(404, "unknown session")
    return view(session)


@app.post("/sessions/{session_id}/advance", response_model=SessionView)
def advance(session_id: str, body: AdvanceRequest) -> SessionView:
    session = store.get(session_id)
    if session is None:
        raise HTTPException(404, "unknown session")

    spec = TRANSITIONS.get(body.event)
    if spec is None:
        raise HTTPException(400, f"unknown event {body.event}")

    expected_from, to_step, command = spec
    if session.step != expected_from:
        raise HTTPException(
            409,
            f"event {body.event} illegal in step {session.step.value}",
        )

    if body.event == "task_done" and body.checksum is None:
        raise HTTPException(400, "task_done requires checksum")

    session.step = to_step
    session.last_command = command
    session.checkpoint += 1
    session.updated_at = time.time()

    if body.event == "task_done":
        session.tasks_done += 1
        session.payload = {
            "task_id": f"t-{session.tasks_done + 1}",
            "completed": session.tasks_done,
            "ack_checksum": body.checksum,
        }
        if session.tasks_done >= 3:
            session.step = Step.complete
            session.last_command = Command.complete
            session.payload = {"completed": session.tasks_done}
    elif body.event == "signed_in":
        session.payload = {"user_id": body.payload.get("user_id")}
    elif body.event == "local_ready":
        session.payload = {"task_id": "t-1"}
    else:
        session.payload = body.payload

    return view(session)
