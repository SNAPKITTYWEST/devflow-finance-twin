"""
Virtual Switchboard for Devflow Finance Twin.

A standard-library-only orchestration layer that turns deterministic workers into
an auditable, self-improving loop. It is intentionally independent from any
LLM SDK. A caller may attach a model or external tool through the Worker
interface, while the switchboard remains useful in offline and test settings.

The improvement loop is deliberately gated:

    observe -> evaluate -> propose -> test -> approve -> activate

The agent never edits its own source code. It only versions routing/playbook
configuration after a proposal passes deterministic checks and, by default,
requires explicit approval. Financial commands are dry-run by default and are
never executed by this module without a registered approved executor.
"""

import hashlib
import json
import os
import threading
import time
import uuid
from pathlib import Path


ZERO_HASH = "0" * 64
SCHEMA_VERSION = "1.0"
DEFAULT_MEMORY_FILE = "switchboard_memory.jsonl"
DEFAULT_POLICY_FILE = "switchboard_policy.json"
MAX_TEXT = 20000
MAX_STEPS = 12
MAX_MEMORY = 5000


class SwitchboardError(Exception):
    pass


class ValidationError(SwitchboardError):
    pass


class SafetyError(SwitchboardError):
    pass


class ApprovalRequired(SwitchboardError):
    pass


def now_text():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def new_id(prefix):
    return prefix + "_" + uuid.uuid4().hex[:16]


def clamp(value, low, high):
    if value < low:
        return low
    if value > high:
        return high
    return value


def clean_text(value, limit=MAX_TEXT):
    if value is None:
        return ""
    value = str(value)
    if len(value) > limit:
        return value[:limit] + "...[truncated]"
    return value


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), default=str)


def digest(value):
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()


def copy_value(value):
    return json.loads(json.dumps(value, default=str))


def words(text):
    text = clean_text(text).lower()
    current = []
    result = []
    for char in text:
        if char.isalnum() or char == "_":
            current.append(char)
        elif current:
            result.append("".join(current))
            current = []
    if current:
        result.append("".join(current))
    return result


def contains_any(text, values):
    lowered = clean_text(text).lower()
    for value in values:
        if value.lower() in lowered:
            return True
    return False


def require_dict(value, name):
    if not isinstance(value, dict):
        raise ValidationError(name + " must be an object")
    return value


def require_text(value, name, limit=MAX_TEXT):
    if not isinstance(value, str) or not value.strip():
        raise ValidationError(name + " must be a non-empty string")
    return clean_text(value.strip(), limit)


class Clock:
    def __init__(self, provider=None):
        self.provider = provider or now_text

    def now(self):
        return self.provider()


class EventChain:
    """Small append-only JSONL hash chain used for memory and audit events."""

    def __init__(self, path, clock=None):
        self.path = Path(path)
        self.clock = clock or Clock()
        self.lock = threading.RLock()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if not self.path.exists():
            self.path.touch()

    def last_hash(self):
        last = ZERO_HASH
        with self.lock:
            try:
                with self.path.open("r", encoding="utf-8") as stream:
                    for line in stream:
                        if line.strip():
                            item = json.loads(line)
                            last = item.get("record_hash", ZERO_HASH)
            except (OSError, ValueError) as exc:
                raise SwitchboardError("cannot read chain: " + str(exc))
        return last

    def append(self, kind, payload):
        require_text(kind, "kind", 120)
        require_dict(payload, "payload")
        with self.lock:
            previous = self.last_hash()
            record = {
                "schema": SCHEMA_VERSION,
                "kind": kind,
                "created_at": self.clock.now(),
                "previous_hash": previous,
                "payload": copy_value(payload),
            }
            record["record_hash"] = digest(record)
            line = canonical(record) + "\n"
            try:
                with self.path.open("a", encoding="utf-8") as stream:
                    stream.write(line)
                    stream.flush()
                    os.fsync(stream.fileno())
            except OSError as exc:
                raise SwitchboardError("cannot append chain: " + str(exc))
            return record

    def read(self):
        records = []
        with self.lock:
            try:
                with self.path.open("r", encoding="utf-8") as stream:
                    for number, line in enumerate(stream, 1):
                        if not line.strip():
                            continue
                        try:
                            records.append(json.loads(line))
                        except ValueError as exc:
                            raise SwitchboardError("invalid chain line " + str(number) + ": " + str(exc))
            except OSError as exc:
                raise SwitchboardError("cannot read chain: " + str(exc))
        return records

    def verify(self):
        expected = ZERO_HASH
        records = self.read()
        for index, record in enumerate(records):
            if record.get("previous_hash") != expected:
                return False, "previous hash mismatch at record " + str(index)
            stored = record.get("record_hash")
            check = dict(record)
            check.pop("record_hash", None)
            if digest(check) != stored:
                return False, "record hash mismatch at record " + str(index)
            expected = stored
        return True, None

    def tail(self, count=20):
        if count < 1:
            return []
        return self.read()[-count:]


class Policy:
    """Versioned routing and safety policy, persisted as ordinary JSON."""

    def __init__(self, path=DEFAULT_POLICY_FILE):
        self.path = Path(path)
        self.lock = threading.RLock()
        self.data = self._defaults()
        self.load()

    def _defaults(self):
        return {
            "schema": SCHEMA_VERSION,
            "version": 1,
            "active": True,
            "require_approval_for_improvements": True,
            "allow_financial_side_effects": False,
            "max_iterations": 3,
            "min_confidence": 0.55,
            "min_evaluation_score": 0.70,
            "max_worker_calls": 8,
            "routes": {},
            "weights": {},
            "blocked_terms": [
                "ignore safety", "disable audit", "bypass approval",
                "steal", "exfiltrate", "delete ledger", "rewrite history",
            ],
        }

    def load(self):
        with self.lock:
            if not self.path.exists():
                self.save()
                return
            try:
                with self.path.open("r", encoding="utf-8") as stream:
                    loaded = json.load(stream)
                if isinstance(loaded, dict):
                    defaults = self._defaults()
                    defaults.update(loaded)
                    self.data = defaults
            except (OSError, ValueError):
                self.data = self._defaults()

    def save(self):
        with self.lock:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            temporary = self.path.with_suffix(self.path.suffix + ".tmp")
            with temporary.open("w", encoding="utf-8") as stream:
                json.dump(self.data, stream, sort_keys=True, indent=2)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, self.path)

    def snapshot(self):
        with self.lock:
            return copy_value(self.data)

    def version(self):
        return int(self.data.get("version", 1))

    def get(self, key, default=None):
        return self.data.get(key, default)

    def route(self, name):
        routes = self.data.get("routes", {})
        return routes.get(name, {}) if isinstance(routes, dict) else {}

    def blocked(self, text):
        return contains_any(text, self.data.get("blocked_terms", []))

    def apply_patch(self, patch):
        require_dict(patch, "patch")
        with self.lock:
            updated = copy_value(self.data)
            for key, value in patch.items():
                if key in ("schema", "version"):
                    continue
                if key == "routes" and isinstance(value, dict):
                    routes = updated.setdefault("routes", {})
                    for route, configuration in value.items():
                        if isinstance(configuration, dict):
                            routes.setdefault(route, {}).update(copy_value(configuration))
                elif key == "weights" and isinstance(value, dict):
                    weights = updated.setdefault("weights", {})
                    for worker, weight in value.items():
                        try:
                            weights[worker] = clamp(float(weight), 0.0, 2.0)
                        except (TypeError, ValueError):
                            pass
                elif key in ("max_iterations", "max_worker_calls"):
                    try:
                        updated[key] = int(clamp(int(value), 1, 20))
                    except (TypeError, ValueError):
                        pass
                elif key in ("min_confidence", "min_evaluation_score"):
                    try:
                        updated[key] = clamp(float(value), 0.0, 1.0)
                    except (TypeError, ValueError):
                        pass
                elif key in ("allow_financial_side_effects", "require_approval_for_improvements", "active"):
                    updated[key] = bool(value)
                elif key == "blocked_terms" and isinstance(value, list):
                    updated[key] = [clean_text(item, 120) for item in value[:100]]
            updated["version"] = int(updated.get("version", 1)) + 1
            updated["schema"] = SCHEMA_VERSION
            self.data = updated
            self.save()
            return self.snapshot()


class Request:
    def __init__(self, text, actor="anonymous", metadata=None, request_id=None):
        self.request_id = request_id or new_id("req")
        self.text = require_text(text, "text")
        self.actor = clean_text(actor or "anonymous", 200)
        self.metadata = copy_value(metadata or {})
        self.created_at = now_text()

    def as_dict(self):
        return {
            "request_id": self.request_id,
            "text": self.text,
            "actor": self.actor,
            "metadata": self.metadata,
            "created_at": self.created_at,
        }


class Route:
    def __init__(self, name, score=0.0, reasons=None, workers=None, confidence=0.0):
        self.name = name
        self.score = float(score)
        self.reasons = list(reasons or [])
        self.workers = list(workers or [])
        self.confidence = clamp(float(confidence), 0.0, 1.0)

    def as_dict(self):
        return {
            "name": self.name,
            "score": round(self.score, 6),
            "reasons": self.reasons,
            "workers": self.workers,
            "confidence": round(self.confidence, 6),
        }


class Result:
    def __init__(self, worker, status="ok", answer="", data=None, confidence=0.5,
                 evidence=None, warnings=None, duration=0.0):
        self.worker = worker
        self.status = status
        self.answer = clean_text(answer)
        self.data = copy_value(data or {})
        self.confidence = clamp(float(confidence), 0.0, 1.0)
        self.evidence = list(evidence or [])
        self.warnings = list(warnings or [])
        self.duration = float(duration)

    def as_dict(self):
        return {
            "worker": self.worker,
            "status": self.status,
            "answer": self.answer,
            "data": self.data,
            "confidence": round(self.confidence, 6),
            "evidence": self.evidence,
            "warnings": self.warnings,
            "duration": round(self.duration, 6),
        }


class Evaluation:
    def __init__(self, score=0.0, passed=False, reasons=None, risks=None, next_action="review"):
        self.score = clamp(float(score), 0.0, 1.0)
        self.passed = bool(passed)
        self.reasons = list(reasons or [])
        self.risks = list(risks or [])
        self.next_action = next_action

    def as_dict(self):
        return {
            "score": round(self.score, 6),
            "passed": self.passed,
            "reasons": self.reasons,
            "risks": self.risks,
            "next_action": self.next_action,
        }


class Proposal:
    def __init__(self, reason, patch, tests=None, risk="low"):
        self.proposal_id = new_id("prop")
        self.reason = clean_text(reason, 1000)
        self.patch = copy_value(patch)
        self.tests = list(tests or [])
        self.risk = risk
        self.created_at = now_text()
        self.status = "proposed"
        self.test_results = []

    def as_dict(self):
        return {
            "proposal_id": self.proposal_id,
            "reason": self.reason,
            "patch": self.patch,
            "tests": self.tests,
            "risk": self.risk,
            "created_at": self.created_at,
            "status": self.status,
            "test_results": self.test_results,
        }


class Worker:
    name = "worker"
    capabilities = ()

    def can_handle(self, request, route):
        return True

    def run(self, request, context):
        raise NotImplementedError


class BaseWorker(Worker):
    def __init__(self, name, capabilities=()):
        self.name = name
        self.capabilities = tuple(capabilities)

    def run(self, request, context):
        started = time.time()
        text = request.text
        result = self.perform(text, request, context)
        result.duration = time.time() - started
        return result

    def perform(self, text, request, context):
        raise NotImplementedError


class TriageWorker(BaseWorker):
    def __init__(self):
        super().__init__("triage", ("classification", "planning", "routing"))

    def perform(self, text, request, context):
        tokens = words(text)
        labels = []
        if contains_any(text, ("balance", "account", "invoice", "payment", "transaction", "ledger")):
            labels.append("finance")
        if contains_any(text, ("code", "python", "bug", "test", "repository", "implement")):
            labels.append("engineering")
        if contains_any(text, ("route", "agent", "loop", "improve", "switchboard")):
            labels.append("orchestration")
        if not labels:
            labels.append("general")
        answer = "Request classified as " + ", ".join(labels) + "."
        return Result(self.name, answer=answer, data={"labels": labels, "tokens": len(tokens)}, confidence=0.86)


class FinanceWorker(BaseWorker):
    def __init__(self):
        super().__init__("finance", ("finance", "ledger", "accounts", "risk"))

    def perform(self, text, request, context):
        data = {"mode": "analysis", "side_effect": False, "financial_action": False}
        lowered = text.lower()
        if contains_any(text, ("transfer", "pay", "post transaction", "withdraw", "send money")):
            data["financial_action"] = True
            data["side_effect"] = True
            answer = "Financial side effect identified; approval and an external executor are required."
            return Result(self.name, "needs_approval", answer, data, 0.82,
                          ["keyword classification"], ["No money movement was performed."])
        if "balance" in lowered:
            answer = "Balance inquiry routed to the finance twin; no mutation requested."
        elif "invoice" in lowered:
            answer = "Invoice workflow routed to the finance twin for deterministic validation."
        else:
            answer = "Finance request routed for ledger-safe analysis."
        return Result(self.name, answer=answer, data=data, confidence=0.78,
                      evidence=["finance vocabulary"])


class EngineeringWorker(BaseWorker):
    def __init__(self):
        super().__init__("engineering", ("python", "code", "tests", "repository"))

    def perform(self, text, request, context):
        tasks = []
        if contains_any(text, ("test", "bug", "error")):
            tasks.append("reproduce and add a regression test")
        if contains_any(text, ("implement", "create", "build")):
            tasks.append("define a small interface and deterministic acceptance checks")
        if not tasks:
            tasks.append("inspect the existing module boundary before changing code")
        return Result(self.name, answer="Engineering plan: " + "; ".join(tasks) + ".",
                      data={"tasks": tasks, "changes_applied": False}, confidence=0.80,
                      evidence=["engineering vocabulary"])


class OrchestrationWorker(BaseWorker):
    def __init__(self):
        super().__init__("orchestration", ("agents", "routing", "improvement", "switchboard"))

    def perform(self, text, request, context):
        return Result(
            self.name,
            answer="The switchboard will route this through observe, execute, evaluate, and gated improvement.",
            data={"loop": ["observe", "route", "execute", "evaluate", "remember", "propose", "gate"]},
            confidence=0.91,
            evidence=["orchestration vocabulary"],
        )


class GeneralWorker(BaseWorker):
    def __init__(self):
        super().__init__("general", ("general", "fallback"))

    def perform(self, text, request, context):
        return Result(self.name, answer="Request received; a human or domain worker should clarify the desired outcome.",
                      data={"clarification_required": True}, confidence=0.45,
                      warnings=["No specialized route matched."])


class Router:
    """Keyword router with adaptive weights learned only through proposals."""

    def __init__(self, policy):
        self.policy = policy
        self.catalog = {
            "finance": ("finance", "ledger", "account", "invoice", "payment", "transaction", "balance", "treasury"),
            "engineering": ("code", "python", "bug", "test", "repository", "implement", "function", "module"),
            "orchestration": ("agent", "route", "loop", "improve", "switchboard", "worker", "memory"),
            "general": (),
        }

    def score(self, text, route_name):
        values = self.catalog.get(route_name, ())
        score = 0.0
        token_set = set(words(text))
        for value in values:
            if value in token_set or value in text.lower():
                score += 1.0
        configured = self.policy.route(route_name)
        score += float(configured.get("bias", 0.0) or 0.0)
        score *= float(self.policy.get("weights", {}).get(route_name, 1.0) or 1.0)
        return score

    def choose(self, request):
        if self.policy.blocked(request.text):
            return Route("blocked", 100.0, ["blocked safety term"], [], 1.0)
        scores = {}
        for name in self.catalog:
            scores[name] = self.score(request.text, name)
        best = max(scores, key=scores.get)
        ordered = sorted(scores.items(), key=lambda item: item[1], reverse=True)
        if scores[best] <= 0:
            best = "general"
        total = sum(scores.values())
        confidence = 0.50 if total <= 0 else clamp(scores[best] / (total + 1.0), 0.0, 0.99)
        reasons = [name + "=" + str(round(value, 3)) for name, value in ordered]
        configured = self.policy.route(best)
        workers = configured.get("workers", [best])
        if not isinstance(workers, list):
            workers = [best]
        return Route(best, scores[best], reasons, workers, confidence)


class Evaluator:
    def __init__(self, policy):
        self.policy = policy

    def evaluate(self, request, route, results):
        reasons = []
        risks = []
        if not results:
            return Evaluation(0.0, False, ["no worker result"], ["silent failure"], "retry")
        total = 0.0
        valid = 0
        for result in results:
            if not isinstance(result, Result):
                risks.append("malformed worker result")
                continue
            valid += 1
            total += result.confidence
            if result.status not in ("ok", "needs_approval"):
                risks.append(result.status)
            reasons.append(result.worker + " confidence=" + str(round(result.confidence, 2)))
            risks.extend(result.warnings)
        average = total / valid if valid else 0.0
        score = average
        if route.name == "blocked":
            return Evaluation(0.0, False, ["request blocked by policy"], ["unsafe request"], "abstain")
        if any(result.data.get("financial_action") for result in results if isinstance(result.data, dict)):
            risks.append("financial side effect requested")
            score = min(score, 0.79)
        passed = score >= float(self.policy.get("min_evaluation_score", 0.70)) and not any(
            "unsafe" in risk.lower() for risk in risks
        )
        action = "complete" if passed else ("approve" if "financial side effect requested" in risks else "retry")
        return Evaluation(score, passed, reasons, risks, action)


class Memory:
    def __init__(self, chain, maximum=MAX_MEMORY):
        self.chain = chain
        self.maximum = maximum
        self.lock = threading.RLock()
        self.items = []
        self._load()

    def _load(self):
        try:
            for record in self.chain.read()[-self.maximum:]:
                if record.get("kind") == "experience":
                    self.items.append(record.get("payload", {}))
        except SwitchboardError:
            self.items = []

    def remember(self, payload):
        require_dict(payload, "memory payload")
        with self.lock:
            self.items.append(copy_value(payload))
            if len(self.items) > self.maximum:
                self.items = self.items[-self.maximum:]
            return self.chain.append("experience", payload)

    def recent(self, count=20):
        with self.lock:
            return copy_value(self.items[-max(0, count):])

    def search(self, text, count=10):
        query = set(words(text))
        ranked = []
        with self.lock:
            for item in self.items:
                body = canonical(item)
                overlap = len(query.intersection(set(words(body))))
                if overlap:
                    ranked.append((overlap, item))
        ranked.sort(key=lambda pair: pair[0], reverse=True)
        return [copy_value(item) for _, item in ranked[:count]]

    def stats(self):
        with self.lock:
            passed = sum(1 for item in self.items if item.get("evaluation", {}).get("passed"))
            return {"experiences": len(self.items), "passed": passed, "failed": len(self.items) - passed}


class SafetyGate:
    """Rejects unsafe requests and prevents unapproved mutation."""

    def __init__(self, policy):
        self.policy = policy

    def inspect_request(self, request):
        if self.policy.blocked(request.text):
            raise SafetyError("request contains a blocked safety term")
        return True

    def inspect_result(self, result):
        if not isinstance(result, Result):
            raise SafetyError("worker returned an invalid result")
        if result.data.get("execute_external") and not self.policy.get("allow_financial_side_effects", False):
            result.status = "needs_approval"
            result.warnings.append("external execution disabled by policy")
        return result

    def inspect_proposal(self, proposal):
        if proposal.risk == "critical":
            raise SafetyError("critical improvements cannot be activated automatically")
        if proposal.patch.get("allow_financial_side_effects") is True:
            raise SafetyError("improvement cannot enable financial side effects")
        if proposal.patch.get("blocked_terms") == []:
            raise SafetyError("improvement cannot remove all blocked terms")
        return True

    def requires_approval(self, proposal):
        return bool(self.policy.get("require_approval_for_improvements", True)) or proposal.risk != "low"


class ImprovementManager:
    """Turns evaluations into reversible policy proposals."""

    def __init__(self, policy, safety, chain):
        self.policy = policy
        self.safety = safety
        self.chain = chain
        self.pending = {}
        self.lock = threading.RLock()

    def propose(self, request, route, evaluation, results):
        if evaluation.passed:
            return None
        patch = {}
        reason = ""
        tests = []
        if evaluation.next_action == "retry":
            patch["max_iterations"] = min(int(self.policy.get("max_iterations", 3)) + 1, 8)
            reason = "Increase bounded retries after a failed evaluation."
            tests.append("max_iterations remains between 1 and 8")
        if route.name == "general" and evaluation.score < 0.6:
            patch["routes"] = {"general": {"bias": 0.2}}
            reason = "Give the fallback route a small deterministic bias for unmatched work."
            tests.append("general route remains available")
        if not patch:
            return None
        proposal = Proposal(reason, patch, tests, "low")
        with self.lock:
            self.pending[proposal.proposal_id] = proposal
            self.chain.append("proposal", proposal.as_dict())
        return proposal

    def test(self, proposal):
        results = []
        for test in proposal.tests:
            passed = True
            if "between 1 and 8" in test:
                value = proposal.patch.get("max_iterations", 0)
                passed = 1 <= int(value) <= 8
            if "remains available" in test:
                passed = "routes" in proposal.patch and "general" in proposal.patch["routes"]
            results.append({"test": test, "passed": passed})
        proposal.test_results = results
        proposal.status = "tested" if all(item["passed"] for item in results) else "rejected"
        self.chain.append("proposal_test", proposal.as_dict())
        return all(item["passed"] for item in results)

    def approve(self, proposal_id, approver="operator"):
        with self.lock:
            proposal = self.pending.get(proposal_id)
            if proposal is None:
                raise ValidationError("unknown proposal")
            self.safety.inspect_proposal(proposal)
            if proposal.status not in ("tested", "proposed"):
                raise ValidationError("proposal is not activatable")
            if not self.test(proposal):
                raise ValidationError("proposal tests failed")
            policy = self.policy.apply_patch(proposal.patch)
            proposal.status = "activated"
            self.chain.append("proposal_activation", {
                "proposal": proposal.as_dict(),
                "approver": clean_text(approver, 200),
                "policy_version": policy.get("version"),
            })
            return copy_value(policy)

    def pending_list(self):
        with self.lock:
            return [item.as_dict() for item in self.pending.values()]


class Switchboard:
    """Main virtual switchboard and bounded self-improvement loop."""

    def __init__(self, memory_path=DEFAULT_MEMORY_FILE, policy_path=DEFAULT_POLICY_FILE,
                 workers=None, clock=None):
        self.clock = clock or Clock()
        self.policy = Policy(policy_path)
        self.audit = EventChain(memory_path, self.clock)
        self.memory = Memory(self.audit)
        self.safety = SafetyGate(self.policy)
        self.router = Router(self.policy)
        self.evaluator = Evaluator(self.policy)
        self.improver = ImprovementManager(self.policy, self.safety, self.audit)
        self.workers = {}
        for worker in workers or [TriageWorker(), FinanceWorker(), EngineeringWorker(), OrchestrationWorker(), GeneralWorker()]:
            self.register(worker)
        self.lock = threading.RLock()

    def register(self, worker):
        if not isinstance(worker, Worker):
            raise ValidationError("worker must implement Worker")
        if not worker.name or worker.name in self.workers:
            raise ValidationError("worker name must be unique")
        self.workers[worker.name] = worker

    def _worker_names(self, route):
        names = []
        for name in route.workers + [route.name, "general"]:
            if name in self.workers and name not in names:
                names.append(name)
        return names[:int(self.policy.get("max_worker_calls", 8))]

    def _execute(self, request, route, memories):
        results = []
        context = {
            "route": route.as_dict(),
            "memories": memories,
            "policy_version": self.policy.version(),
        }
        for name in self._worker_names(route):
            worker = self.workers[name]
            if not worker.can_handle(request, route):
                continue
            try:
                result = worker.run(request, context)
                result = self.safety.inspect_result(result)
            except Exception as exc:
                result = Result(name, "error", "Worker failed safely.", {}, 0.0, [], [str(exc)])
            results.append(result)
        return results

    def _final_answer(self, results, evaluation):
        if not results:
            return "No worker was available."
        pieces = []
        for result in results:
            if result.answer and result.answer not in pieces:
                pieces.append(result.answer)
        answer = " ".join(pieces)
        if not evaluation.passed:
            answer += " Review status: " + evaluation.next_action + "."
        return answer

    def handle(self, text, actor="anonymous", metadata=None, learn=True):
        request = Request(text, actor, metadata)
        with self.lock:
            self.safety.inspect_request(request)
            route = self.router.choose(request)
            if route.name == "blocked":
                evaluation = Evaluation(0.0, False, route.reasons, ["blocked request"], "abstain")
                results = []
                proposal = None
            else:
                memories = self.memory.search(request.text, 5)
                results = self._execute(request, route, memories)
                evaluation = self.evaluator.evaluate(request, route, results)
                proposal = self.improver.propose(request, route, evaluation, results) if learn else None
            payload = {
                "request": request.as_dict(),
                "route": route.as_dict(),
                "results": [result.as_dict() for result in results],
                "evaluation": evaluation.as_dict(),
                "proposal": proposal.as_dict() if proposal else None,
                "answer": self._final_answer(results, evaluation),
                "policy_version": self.policy.version(),
            }
            self.memory.remember(payload)
            self.audit.append("decision", payload)
            return payload

    def approve(self, proposal_id, approver="operator"):
        return self.improver.approve(proposal_id, approver)

    def verify(self):
        return self.audit.verify()

    def status(self):
        return {
            "policy_version": self.policy.version(),
            "workers": sorted(self.workers),
            "memory": self.memory.stats(),
            "pending_proposals": len(self.improver.pending),
            "chain": self.verify(),
        }


class JsonLineProtocol:
    """Line protocol for embedding the switchboard in another process."""

    def __init__(self, switchboard):
        self.switchboard = switchboard

    def dispatch(self, message):
        require_dict(message, "message")
        operation = message.get("operation", "handle")
        if operation == "handle":
            return self.switchboard.handle(message.get("text", ""), message.get("actor", "anonymous"), message.get("metadata"))
        if operation == "status":
            return self.switchboard.status()
        if operation == "verify":
            valid, error = self.switchboard.verify()
            return {"valid": valid, "error": error}
        if operation == "approve":
            return {"policy": self.switchboard.approve(message.get("proposal_id"), message.get("approver", "operator"))}
        if operation == "pending":
            return {"proposals": self.switchboard.improver.pending_list()}
        raise ValidationError("unknown protocol operation: " + str(operation))

    def serve(self, input_stream=None, output_stream=None):
        import sys
        source = input_stream or sys.stdin
        target = output_stream or sys.stdout
        for line in source:
            if not line.strip():
                continue
            try:
                message = json.loads(line)
                result = self.dispatch(message)
                target.write(json.dumps({"ok": True, "result": result}, sort_keys=True) + "\n")
            except Exception as exc:
                target.write(json.dumps({"ok": False, "error": str(exc)}, sort_keys=True) + "\n")
            target.flush()


def example():
    board = Switchboard(".switchboard/example_memory.jsonl", ".switchboard/example_policy.json")
    first = board.handle("How should the agent route a finance transaction?", "demo")
    return {"answer": first["answer"], "status": board.status()}


def main(argv=None):
    import argparse
    parser = argparse.ArgumentParser(description="Raw Python virtual switchboard")
    parser.add_argument("--memory", default=DEFAULT_MEMORY_FILE)
    parser.add_argument("--policy", default=DEFAULT_POLICY_FILE)
    parser.add_argument("--text")
    parser.add_argument("--actor", default="cli")
    parser.add_argument("--status", action="store_true")
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--serve", action="store_true")
    parser.add_argument("--approve")
    args = parser.parse_args(argv)
    board = Switchboard(args.memory, args.policy)
    if args.status:
        print(json.dumps(board.status(), indent=2, sort_keys=True))
        return 0
    if args.verify:
        valid, error = board.verify()
        print(json.dumps({"valid": valid, "error": error}, indent=2))
        return 0 if valid else 1
    if args.approve:
        print(json.dumps(board.approve(args.approve, args.actor), indent=2, sort_keys=True))
        return 0
    if args.serve:
        JsonLineProtocol(board).serve()
        return 0
    if args.text:
        print(json.dumps(board.handle(args.text, args.actor), indent=2, sort_keys=True))
        return 0
    parser.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
