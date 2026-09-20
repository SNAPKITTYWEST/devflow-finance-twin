# ============================================================================
# glm-evoke/attest.py
# Append-only attestation log — WORM-seal compatible
# Every seal emission lands here, hash-chained
# License: GPL 2.0
# ============================================================================

import hashlib
import json
import os
import time


class AttestationLog:
    def __init__(self, path="./attestation.log"):
        self.path = path
        self.prev_hash = "0" * 64
        if os.path.exists(path):
            with open(path) as f:
                lines = [l for l in f.read().splitlines() if l.strip()]
                if lines:
                    self.prev_hash = json.loads(lines[-1])["entry_hash"]

    def append(self, record):
        entry = {
            "ts": time.time(),
            "prev_hash": self.prev_hash,
            "record": record,
        }
        entry["entry_hash"] = hashlib.sha256(
            json.dumps(entry, sort_keys=True, default=str).encode()
        ).hexdigest()
        with open(self.path, "a") as f:
            f.write(json.dumps(entry, sort_keys=True, default=str) + "\n")
        self.prev_hash = entry["entry_hash"]
        return entry["entry_hash"]

    def verify_chain(self):
        """Walk the log, recompute every link. Any break = tamper evidence."""
        if not os.path.exists(self.path):
            return True, 0
        prev, n = "0" * 64, 0
        with open(self.path) as f:
            for line in f:
                if not line.strip():
                    continue
                e = json.loads(line)
                body = {k: e[k] for k in e if k != "entry_hash"}
                if e["prev_hash"] != prev or hashlib.sha256(
                    json.dumps(body, sort_keys=True, default=str).encode()
                ).hexdigest() != e["entry_hash"]:
                    return False, n
                prev, n = e["entry_hash"], n + 1
        return True, n
