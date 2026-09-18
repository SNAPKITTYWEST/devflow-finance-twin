import re
from dataclasses import dataclass

DIRECTIVE_MARKERS = [
    r"ignore\s+(all\s+)?previous\s+instructions",
    r"system\s*:\s*override",
    r"developer\s*mode",
    r"jailbreak",
    r"role\s*=\s*system",
    r"<\s*\|?\s*system\s*\|?\s*>",
]

COMPILED = [re.compile(p, re.IGNORECASE) for p in DIRECTIVE_MARKERS]


@dataclass
class Verdict:
    allowed: bool
    reason: str


def screen_user_input(user_text: str, policy_tag: str) -> Verdict:
    for rx in COMPILED:
        if rx.search(user_text):
            return Verdict(False, f"directive_override:{rx.pattern}")
    if policy_tag != "system" and "<|system|>" in user_text:
        return Verdict(False, "channel_spoof")
    return Verdict(True, "ok")
