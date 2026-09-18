import threading


class SessionStore:
    def __init__(self, max_sessions: int = 1024):
        self._lock = threading.RLock()
        self._max = max_sessions
        self._data: dict[str, dict] = {}

    def begin(self, session_id: str) -> dict:
        with self._lock:
            if session_id not in self._data:
                if len(self._data) >= self._max:
                    self._data.pop(next(iter(self._data)))
                self._data[session_id] = {
                    "kv": None,
                    "route": None,
                    "pending_remote": None,
                }
            return self._data[session_id]

    def attach_remote(self, session_id: str, nonce_tag: bytes):
        with self._lock:
            self._data[session_id]["pending_remote"] = nonce_tag

    def complete_remote(self, session_id: str, response: str) -> str:
        with self._lock:
            s = self._data[session_id]
            s["pending_remote"] = None
            return response
