import json
import os

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from .routing import RequestEnvelope


def pack_remote(env: RequestEnvelope, key: bytes, aad: bytes) -> bytes:
    assert len(key) == 32
    aes = AESGCM(key)
    nonce = os.urandom(12)
    plaintext = json.dumps({
        "session": env.session_id,
        "prompt": env.prompt,
        "max_tokens": env.max_tokens,
        "task": env.task,
    }).encode("utf-8")
    ct = aes.encrypt(nonce, plaintext, aad)
    return nonce + ct


def unpack_remote(blob: bytes, key: bytes, aad: bytes) -> dict:
    nonce, ct = blob[:12], blob[12:]
    pt = AESGCM(key).decrypt(nonce, ct, aad)
    return json.loads(pt)
