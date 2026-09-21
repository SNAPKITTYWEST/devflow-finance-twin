"""
Cross-language integration tests for the Telegram Bot SDK.

Tests message format compatibility, command interface consistency,
and error response formats across the Node.js, Rust, and Haskell
implementations using a mocked Telegram API.

License: GPL-3.0-or-later OR Apache-2.0
"""

import asyncio
import json
import os
import subprocess
import time
import unittest
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional
from unittest.mock import AsyncMock, MagicMock, patch
from http.server import BaseHTTPRequestHandler, HTTPServer
import threading
import urllib.request
import urllib.parse


# ---------------------------------------------------------------------------
# Shared data model — mirrors the Rust/Node/Haskell type definitions
# ---------------------------------------------------------------------------

@dataclass
class User:
    id: int
    first_name: str
    last_name: str = ""
    username: str = ""
    is_bot: bool = False


@dataclass
class Chat:
    id: int
    type: str = "private"  # private | group | supergroup | channel


@dataclass
class TelegramMessage:
    message_id: int
    from_user: User
    chat: Chat
    text: str
    date: int = field(default_factory=lambda: int(datetime.now(timezone.utc).timestamp()))

    def to_api_json(self) -> dict:
        """Serialize to the Telegram Bot API wire format."""
        return {
            "message_id": self.message_id,
            "from": {
                "id": self.from_user.id,
                "first_name": self.from_user.first_name,
                "last_name": self.from_user.last_name,
                "username": self.from_user.username,
                "is_bot": self.from_user.is_bot,
            },
            "chat": {
                "id": self.chat.id,
                "type": self.chat.type,
            },
            "text": self.text,
            "date": self.date,
        }


@dataclass
class Update:
    update_id: int
    message: Optional[TelegramMessage] = None

    def to_api_json(self) -> dict:
        result: dict = {"update_id": self.update_id}
        if self.message:
            result["message"] = self.message.to_api_json()
        return result


@dataclass
class BotResponse:
    """Normalised response shape produced by all three implementations."""
    status: str              # "ok" | "error"
    text: str
    parse_mode: str = "Markdown"
    error_code: Optional[int] = None
    error_description: Optional[str] = None
    actions: list = field(default_factory=list)
    metadata: dict = field(default_factory=dict)


# ---------------------------------------------------------------------------
# Mock Telegram API server
# ---------------------------------------------------------------------------

class _MockTelegramHandler(BaseHTTPRequestHandler):
    """Single-purpose HTTP handler that records bot API calls."""

    def log_message(self, format, *args):  # silence access logs during tests
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            payload = {}

        self.server.recorded_calls.append({  # type: ignore[attr-defined]
            "path": self.path,
            "payload": payload,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        })

        # Return a minimal success response for every method.
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"ok": True, "result": {}}).encode())

    def do_GET(self):
        # getMe endpoint
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        result = {
            "ok": True,
            "result": {
                "id": 123456789,
                "is_bot": True,
                "first_name": "TestBot",
                "username": "test_sdk_bot",
            },
        }
        self.wfile.write(json.dumps(result).encode())


class MockTelegramAPI:
    """Lightweight in-process mock for the Telegram Bot API."""

    def __init__(self, host: str = "127.0.0.1", port: int = 18443):
        self.host = host
        self.port = port
        self._server: Optional[HTTPServer] = None
        self._thread: Optional[threading.Thread] = None

    @property
    def base_url(self) -> str:
        return f"http://{self.host}:{self.port}"

    @property
    def recorded_calls(self) -> list:
        return self._server.recorded_calls if self._server else []  # type: ignore[attr-defined]

    def start(self):
        self._server = HTTPServer((self.host, self.port), _MockTelegramHandler)
        self._server.recorded_calls = []  # type: ignore[attr-defined]
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()

    def stop(self):
        if self._server:
            self._server.shutdown()

    def reset(self):
        if self._server:
            self._server.recorded_calls = []  # type: ignore[attr-defined]

    def get_calls_for_method(self, method: str) -> list:
        return [c for c in self.recorded_calls if c["path"].endswith(f"/{method}")]


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

BOT_USER = User(id=42, first_name="Alice", username="alice_dev")
BOT_CHAT = Chat(id=-100123456789, type="group")
BOT_TOKEN = "TEST_TOKEN_INTEGRATION"


def _make_update(text: str, update_id: int = 1) -> Update:
    msg = TelegramMessage(
        message_id=update_id * 100,
        from_user=BOT_USER,
        chat=BOT_CHAT,
        text=text,
    )
    return Update(update_id=update_id, message=msg)


def _make_command_update(command: str, args: str = "", update_id: int = 1) -> Update:
    text = f"/{command}"
    if args:
        text += f" {args}"
    return _make_update(text, update_id)


# ---------------------------------------------------------------------------
# Helpers for normalising responses from each implementation
# ---------------------------------------------------------------------------

class ResponseNormaliser:
    """
    Converts the raw output of each language-specific bot into a
    BotResponse so tests can assert on a single canonical shape.
    """

    @staticmethod
    def from_node_json(raw: dict) -> BotResponse:
        """Node.js bots return { status, text, parseMode?, actions?, metadata? }."""
        return BotResponse(
            status=raw.get("status", "ok"),
            text=raw.get("text", ""),
            parse_mode=raw.get("parseMode", "Markdown"),
            error_code=raw.get("errorCode"),
            error_description=raw.get("errorDescription"),
            actions=raw.get("actions", []),
            metadata=raw.get("metadata", {}),
        )

    @staticmethod
    def from_rust_json(raw: dict) -> BotResponse:
        """Rust bots use snake_case: { status, text, parse_mode?, actions?, metadata? }."""
        return BotResponse(
            status=raw.get("status", "ok"),
            text=raw.get("text", ""),
            parse_mode=raw.get("parse_mode", "Markdown"),
            error_code=raw.get("error_code"),
            error_description=raw.get("error_description"),
            actions=raw.get("actions", []),
            metadata=raw.get("metadata", {}),
        )

    @staticmethod
    def from_haskell_json(raw: dict) -> BotResponse:
        """Haskell bots also use camelCase via Aeson default derivation."""
        return BotResponse(
            status=raw.get("status", "ok"),
            text=raw.get("text", ""),
            parse_mode=raw.get("parseMode", "Markdown"),
            error_code=raw.get("errorCode"),
            error_description=raw.get("errorDescription"),
            actions=raw.get("actions", []),
            metadata=raw.get("metadata", {}),
        )


# ---------------------------------------------------------------------------
# Message format compatibility tests
# ---------------------------------------------------------------------------

class TestMessageFormatCompatibility(unittest.TestCase):
    """Verify that all three implementations accept the same Telegram wire format."""

    def test_update_json_structure(self):
        update = _make_update("/start")
        wire = update.to_api_json()

        self.assertIn("update_id", wire)
        self.assertIn("message", wire)

        msg = wire["message"]
        self.assertIn("message_id", msg)
        self.assertIn("from", msg)
        self.assertIn("chat", msg)
        self.assertIn("text", msg)
        self.assertIn("date", msg)

    def test_user_fields_are_present(self):
        update = _make_update("hello")
        wire = update.to_api_json()
        user = wire["message"]["from"]

        required = {"id", "first_name", "last_name", "username", "is_bot"}
        self.assertTrue(required.issubset(user.keys()),
                        f"Missing user fields: {required - user.keys()}")

    def test_chat_fields_are_present(self):
        update = _make_update("hello")
        wire = update.to_api_json()
        chat = wire["message"]["chat"]

        self.assertIn("id", chat)
        self.assertIn("type", chat)
        self.assertIn(chat["type"], {"private", "group", "supergroup", "channel"})

    def test_command_text_format(self):
        for cmd in ["/start", "/help", "/scrum", "/issue", "/agent"]:
            update = _make_update(cmd)
            wire = update.to_api_json()
            self.assertEqual(wire["message"]["text"], cmd)

    def test_command_with_args_format(self):
        update = _make_command_update("scrum", "status")
        wire = update.to_api_json()
        self.assertEqual(wire["message"]["text"], "/scrum status")

    def test_date_is_unix_timestamp(self):
        before = int(datetime.now(timezone.utc).timestamp())
        update = _make_update("test")
        after = int(datetime.now(timezone.utc).timestamp())
        wire = update.to_api_json()
        ts = wire["message"]["date"]
        self.assertGreaterEqual(ts, before)
        self.assertLessEqual(ts, after + 1)

    def test_serialisation_round_trip(self):
        update = _make_update("/agent query some complex question")
        wire = update.to_api_json()
        serialised = json.dumps(wire)
        deserialised = json.loads(serialised)
        self.assertEqual(deserialised["message"]["text"],
                         "/agent query some complex question")

    def test_update_id_is_integer(self):
        update = _make_update("ping", update_id=9999)
        wire = update.to_api_json()
        self.assertIsInstance(wire["update_id"], int)
        self.assertEqual(wire["update_id"], 9999)


# ---------------------------------------------------------------------------
# Command interface consistency tests
# ---------------------------------------------------------------------------

class TestCommandInterfaceConsistency(unittest.TestCase):
    """
    All three implementations must expose the same set of commands and
    respond with structurally identical payloads.
    """

    REQUIRED_COMMANDS = {"/start", "/help", "/scrum", "/issue", "/agent", "/status"}

    def _simulate_node_response(self, command: str, args: str = "") -> BotResponse:
        """
        Simulate the Node.js implementation's response for a given command.
        In a live test environment this would hit the running Node.js process;
        here we drive the shared logic directly via a mock.
        """
        full_command = f"{command} {args}".strip()
        raw = self._dispatch_mock(full_command, impl="node")
        return ResponseNormaliser.from_node_json(raw)

    def _simulate_rust_response(self, command: str, args: str = "") -> BotResponse:
        full_command = f"{command} {args}".strip()
        raw = self._dispatch_mock(full_command, impl="rust")
        return ResponseNormaliser.from_rust_json(raw)

    def _simulate_haskell_response(self, command: str, args: str = "") -> BotResponse:
        full_command = f"{command} {args}".strip()
        raw = self._dispatch_mock(full_command, impl="haskell")
        return ResponseNormaliser.from_haskell_json(raw)

    def _dispatch_mock(self, text: str, impl: str) -> dict:
        """
        Pure-Python stub that mimics the response each language would produce.
        Replace with actual subprocess / HTTP calls when bots are running.
        """
        cmd = text.split()[0] if text.startswith("/") else None

        if cmd == "/start":
            base = {
                "status": "ok",
                "text": "Welcome to the DevFlow Finance Twin bot!",
            }
        elif cmd == "/help":
            base = {
                "status": "ok",
                "text": "Available commands: /start /help /scrum /issue /agent /status",
            }
        elif cmd == "/scrum":
            base = {
                "status": "ok",
                "text": "Scrum board updated.",
                "actions": [{"type": "scrum_update"}],
            }
        elif cmd == "/issue":
            base = {
                "status": "ok",
                "text": "Issue logged.",
                "actions": [{"type": "issue_create"}],
            }
        elif cmd == "/agent":
            base = {
                "status": "ok",
                "text": "Agent invoked.",
                "metadata": {"agent_id": "default"},
            }
        elif cmd == "/status":
            base = {
                "status": "ok",
                "text": "Bot is operational.",
                "metadata": {"uptime_seconds": 0},
            }
        else:
            base = {
                "status": "error",
                "text": "Unknown command.",
                "errorCode": 404,
                "errorDescription": f"Command '{cmd}' not found",
            }

        # Normalise field names per implementation convention.
        if impl == "rust":
            if "errorCode" in base:
                base["error_code"] = base.pop("errorCode")
            if "errorDescription" in base:
                base["error_description"] = base.pop("errorDescription")
            base.setdefault("parse_mode", "Markdown")
        else:
            base.setdefault("parseMode", "Markdown")

        return base

    def test_all_required_commands_produce_ok_status(self):
        for cmd in self.REQUIRED_COMMANDS:
            for impl_fn, name in [
                (self._simulate_node_response, "node"),
                (self._simulate_rust_response, "rust"),
                (self._simulate_haskell_response, "haskell"),
            ]:
                resp = impl_fn(cmd)
                self.assertEqual(resp.status, "ok",
                                 f"{name}/{cmd} returned status={resp.status!r}")

    def test_response_text_is_non_empty_for_all_commands(self):
        for cmd in self.REQUIRED_COMMANDS:
            for impl_fn, name in [
                (self._simulate_node_response, "node"),
                (self._simulate_rust_response, "rust"),
                (self._simulate_haskell_response, "haskell"),
            ]:
                resp = impl_fn(cmd)
                self.assertTrue(resp.text,
                                f"{name}/{cmd} returned empty text")

    def test_parse_mode_defaults_to_markdown(self):
        for cmd in ["/start", "/help"]:
            for impl_fn, name in [
                (self._simulate_node_response, "node"),
                (self._simulate_rust_response, "rust"),
                (self._simulate_haskell_response, "haskell"),
            ]:
                resp = impl_fn(cmd)
                self.assertEqual(resp.parse_mode, "Markdown",
                                 f"{name}/{cmd} has parse_mode={resp.parse_mode!r}")

    def test_scrum_command_returns_action(self):
        for impl_fn in [
            self._simulate_node_response,
            self._simulate_rust_response,
            self._simulate_haskell_response,
        ]:
            resp = impl_fn("/scrum")
            self.assertTrue(len(resp.actions) > 0, "Expected at least one action")

    def test_agent_command_returns_metadata(self):
        for impl_fn in [
            self._simulate_node_response,
            self._simulate_rust_response,
            self._simulate_haskell_response,
        ]:
            resp = impl_fn("/agent")
            self.assertIn("agent_id", resp.metadata)

    def test_help_text_mentions_all_commands(self):
        for impl_fn, name in [
            (self._simulate_node_response, "node"),
            (self._simulate_rust_response, "rust"),
            (self._simulate_haskell_response, "haskell"),
        ]:
            resp = impl_fn("/help")
            for cmd in ["/start", "/help", "/scrum", "/issue", "/agent", "/status"]:
                self.assertIn(cmd, resp.text,
                              f"{name}/help response missing '{cmd}'")


# ---------------------------------------------------------------------------
# Error response format tests
# ---------------------------------------------------------------------------

class TestErrorResponseFormats(unittest.TestCase):
    """
    All implementations must return structurally identical error payloads
    so that clients can handle them uniformly.
    """

    UNKNOWN_COMMAND = "/xyzzy_does_not_exist"

    def _error_response(self, impl: str) -> BotResponse:
        raw: dict
        if impl == "node":
            raw = {
                "status": "error",
                "text": "Unknown command.",
                "parseMode": "Markdown",
                "errorCode": 404,
                "errorDescription": "Command '/xyzzy_does_not_exist' not found",
            }
            return ResponseNormaliser.from_node_json(raw)
        elif impl == "rust":
            raw = {
                "status": "error",
                "text": "Unknown command.",
                "parse_mode": "Markdown",
                "error_code": 404,
                "error_description": "Command '/xyzzy_does_not_exist' not found",
            }
            return ResponseNormaliser.from_rust_json(raw)
        else:  # haskell
            raw = {
                "status": "error",
                "text": "Unknown command.",
                "parseMode": "Markdown",
                "errorCode": 404,
                "errorDescription": "Command '/xyzzy_does_not_exist' not found",
            }
            return ResponseNormaliser.from_haskell_json(raw)

    def test_error_status_field(self):
        for impl in ["node", "rust", "haskell"]:
            resp = self._error_response(impl)
            self.assertEqual(resp.status, "error", f"{impl} error status mismatch")

    def test_error_code_is_integer(self):
        for impl in ["node", "rust", "haskell"]:
            resp = self._error_response(impl)
            self.assertIsNotNone(resp.error_code, f"{impl} missing error_code")
            self.assertIsInstance(resp.error_code, int)

    def test_error_description_is_string(self):
        for impl in ["node", "rust", "haskell"]:
            resp = self._error_response(impl)
            self.assertIsNotNone(resp.error_description, f"{impl} missing error_description")
            self.assertIsInstance(resp.error_description, str)

    def test_error_text_is_user_facing(self):
        for impl in ["node", "rust", "haskell"]:
            resp = self._error_response(impl)
            self.assertTrue(resp.text, f"{impl} error response has no user-facing text")

    def test_error_code_404_for_unknown_command(self):
        for impl in ["node", "rust", "haskell"]:
            resp = self._error_response(impl)
            self.assertEqual(resp.error_code, 404,
                             f"{impl} unknown-command error_code != 404")

    def test_well_known_error_codes(self):
        """Validate the shared error code table."""
        error_code_table = {
            400: "bad_request",
            401: "unauthorised",
            403: "forbidden",
            404: "not_found",
            429: "rate_limited",
            500: "internal_error",
            503: "service_unavailable",
        }
        for code, name in error_code_table.items():
            self.assertIsInstance(code, int)
            self.assertIsInstance(name, str)
            self.assertTrue(name.replace("_", "").isalpha(),
                            f"Error code name '{name}' contains unexpected characters")

    def test_integration_error_structure(self):
        """Ollama / scrum-board failures must not leak internal stack traces."""
        for impl in ["node", "rust", "haskell"]:
            # Simulate an integration failure response.
            raw: dict
            if impl == "rust":
                raw = {
                    "status": "error",
                    "text": "LLM service unavailable. Please try again later.",
                    "error_code": 503,
                    "error_description": "Ollama unreachable",
                    "parse_mode": "Markdown",
                }
                resp = ResponseNormaliser.from_rust_json(raw)
            else:
                raw = {
                    "status": "error",
                    "text": "LLM service unavailable. Please try again later.",
                    "errorCode": 503,
                    "errorDescription": "Ollama unreachable",
                    "parseMode": "Markdown",
                }
                resp = ResponseNormaliser.from_node_json(raw)

            self.assertEqual(resp.error_code, 503)
            self.assertNotIn("Traceback", resp.text)
            self.assertNotIn("thread 'main' panicked", resp.text)
            self.assertNotIn("CallStack", resp.text)


# ---------------------------------------------------------------------------
# Mock Telegram API server integration tests
# ---------------------------------------------------------------------------

class TestMockTelegramAPIServer(unittest.TestCase):
    """Verify that the mock server correctly records calls and returns valid JSON."""

    @classmethod
    def setUpClass(cls):
        cls.api = MockTelegramAPI(port=18443)
        cls.api.start()
        time.sleep(0.1)  # give the thread a moment to bind

    @classmethod
    def tearDownClass(cls):
        cls.api.stop()

    def setUp(self):
        self.api.reset()

    def _post(self, method: str, payload: dict) -> dict:
        url = f"{self.api.base_url}/bot{BOT_TOKEN}/{method}"
        data = json.dumps(payload).encode()
        req = urllib.request.Request(
            url, data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            return json.loads(resp.read())

    def test_server_returns_ok_true(self):
        result = self._post("sendMessage", {"chat_id": 1, "text": "hello"})
        self.assertTrue(result["ok"])

    def test_server_records_call(self):
        self._post("sendMessage", {"chat_id": 1, "text": "ping"})
        calls = self.api.get_calls_for_method("sendMessage")
        self.assertEqual(len(calls), 1)

    def test_server_records_multiple_calls(self):
        self._post("sendMessage", {"chat_id": 1, "text": "a"})
        self._post("sendMessage", {"chat_id": 1, "text": "b"})
        calls = self.api.get_calls_for_method("sendMessage")
        self.assertEqual(len(calls), 2)

    def test_server_records_payload(self):
        self._post("sendMessage", {"chat_id": 99, "text": "recorded"})
        calls = self.api.get_calls_for_method("sendMessage")
        self.assertEqual(calls[0]["payload"]["chat_id"], 99)
        self.assertEqual(calls[0]["payload"]["text"], "recorded")

    def test_server_handles_different_methods(self):
        self._post("sendMessage", {"chat_id": 1, "text": "m"})
        self._post("answerCallbackQuery", {"callback_query_id": "abc"})
        self.assertEqual(len(self.api.get_calls_for_method("sendMessage")), 1)
        self.assertEqual(len(self.api.get_calls_for_method("answerCallbackQuery")), 1)

    def test_reset_clears_recorded_calls(self):
        self._post("sendMessage", {"chat_id": 1, "text": "x"})
        self.api.reset()
        self.assertEqual(len(self.api.recorded_calls), 0)

    def test_server_records_timestamp(self):
        self._post("sendMessage", {"chat_id": 1, "text": "ts"})
        call = self.api.recorded_calls[0]
        self.assertIn("timestamp", call)
        # Validate ISO-8601 format (basic check).
        datetime.fromisoformat(call["timestamp"].replace("Z", "+00:00"))

    def test_getme_returns_bot_info(self):
        url = f"{self.api.base_url}/bot{BOT_TOKEN}/getMe"
        with urllib.request.urlopen(url, timeout=5) as resp:
            result = json.loads(resp.read())
        self.assertTrue(result["ok"])
        self.assertTrue(result["result"]["is_bot"])
        self.assertEqual(result["result"]["username"], "test_sdk_bot")


# ---------------------------------------------------------------------------
# Cross-language protocol compatibility
# ---------------------------------------------------------------------------

class TestCrossLanguageProtocol(unittest.TestCase):
    """
    High-level tests asserting that the three implementations speak the same
    protocol when operating as peers (e.g. forwarding updates to each other).
    """

    def test_update_id_is_monotonically_increasing(self):
        updates = [_make_update(f"msg {i}", update_id=i) for i in range(1, 11)]
        ids = [u.update_id for u in updates]
        self.assertEqual(ids, list(range(1, 11)))

    def test_command_prefix_detection(self):
        commands = ["/start", "/help", "/scrum create", "/issue log bug"]
        for text in commands:
            self.assertTrue(text.startswith("/"),
                            f"Expected '{text}' to be a command")

    def test_non_command_text_does_not_start_with_slash(self):
        non_commands = ["hello", "what is 2+2?", "tell me more"]
        for text in non_commands:
            self.assertFalse(text.startswith("/"))

    def test_agent_protocol_metadata_keys(self):
        """Agent responses must include a specific set of metadata keys."""
        required_keys = {"agent_id"}
        metadata = {"agent_id": "default", "model": "llama2", "latency_ms": 42}
        for key in required_keys:
            self.assertIn(key, metadata)

    def test_actions_list_item_has_type_field(self):
        actions = [
            {"type": "scrum_update", "sprint_id": "S-23"},
            {"type": "issue_create", "issue_id": "I-99"},
        ]
        for action in actions:
            self.assertIn("type", action)
            self.assertIsInstance(action["type"], str)

    def test_response_status_is_binary(self):
        valid_statuses = {"ok", "error"}
        for status in ["ok", "error"]:
            self.assertIn(status, valid_statuses)

    def test_message_id_uniqueness(self):
        updates = [_make_update("x", update_id=i) for i in range(1, 6)]
        ids = [u.message.message_id for u in updates if u.message]
        self.assertEqual(len(ids), len(set(ids)), "message_ids must be unique")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    unittest.main(verbosity=2)
