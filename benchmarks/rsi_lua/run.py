"""Reproducible local microbenchmarks; no external services or native-backend claims."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import itertools
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from dream_rsi import DreamRSI, RunConfig, RSIOrchestrator, WorldStore, SearchPolicy, HistoricalReplay, DiscoveryTree


@contextmanager
def repeatable_ids():
    # Only the benchmark substitutes IDs. UUID prefixes must be unique because
    # TreeNode uses the FIRST 12 hex digits. Production still uses random UUIDs.
    counter = itertools.count(1)
    with patch('dream_rsi.tree.uuid.uuid4', side_effect=lambda: uuid.UUID(int=next(counter) << 80)):
        yield


def online(rounds, revisions, legacy=False):
    with repeatable_ids():
        if legacy:
            system = DreamRSI()
            result = system.run(RunConfig('benchmark fixture', rounds, revisions))
            metrics = result['metrics'].__dict__.copy()
        else:
            system = RSIOrchestrator()
            result = system.run('benchmark fixture', rounds, revisions)
            metrics = result['metrics'].copy()
        metrics.pop('wall_clock_seconds', None)
        assert metrics['generations'] == rounds
        if not legacy:
            assert metrics['policy_revisions'] == rounds * revisions
        return metrics


def fixture(depth=5):
    with repeatable_ids():
        tree = DiscoveryTree()
        frontier = [tree.get(tree.root_id)]
        for level in range(depth):
            following = []
            for parent in frontier:
                for branch in range(2):
                    following.append(tree.add(parent.node_id, score=(branch + level) / 20,
                        cost=1, branch_id=str(branch), metadata={'depth': level+1}))
            frontier = following
        assert len(tree.nodes) == 2 ** (depth+1) - 1
        return tree


def measure(name, fn, samples, batch):
    reference = fn()  # warm-up and correctness check, excluded from timings
    durations = []
    for _ in range(samples):
        start = time.perf_counter_ns()
        for _ in range(batch):
            assert fn() == reference, name + ': workload changed between repetitions'
        durations.append((time.perf_counter_ns() - start) / 1e9 / batch)
    return {'name': name, 'status': 'measured', 'samples': samples, 'batch': batch,
            'seconds_per_operation': durations, 'median_seconds': statistics.median(durations),
            'min_seconds': min(durations), 'max_seconds': max(durations), 'work': reference}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--samples', type=int, default=7)
    parser.add_argument('--batch', type=int, default=5)
    parser.add_argument('--lua', help='Lua 5.3/5.4 or texlua executable')
    parser.add_argument('--output', type=Path, default=ROOT/'benchmarks/rsi_lua/results/latest.json')
    args = parser.parse_args()
    if args.samples < 1 or args.batch < 1:
        parser.error('samples and batch must be positive')
    tree = fixture()
    policy = SearchPolicy(max_nodes=128, max_depth=10, budget=128, stop_score=1)
    jobs = []
    for rounds in (1, 10, 50):
        for revisions in (0, 4, 8):
            jobs.append((f'rsi.layered.rounds_{rounds}.revisions_{revisions}',
                         lambda r=rounds, v=revisions: online(r, v)))
    for rounds in (1, 10, 50):
        jobs.append((f'rsi.legacy.rounds_{rounds}.default_revisions', lambda r=rounds: online(r, 4, True)))
    for count in (1, 10, 100):
        worlds = [DiscoveryTree.from_dict(tree.to_dict()) for _ in range(count)]
        def replay(worlds=worlds):
            result = HistoricalReplay().replay(policy, worlds)
            assert result.visited == len(worlds) * 63
            assert result.cost == len(worlds) * 62
            return {'worlds': result.worlds, 'visited': result.visited, 'cost': result.cost, 'score': result.score}
        jobs.append((f'rsi.replay.worlds_{count}.nodes_63', replay))
    def roundtrip():
        restored = DiscoveryTree.from_json(tree.to_json())
        assert restored.to_dict() == tree.to_dict()
        return {'nodes': len(restored.nodes)}
    jobs.append(('rsi.json_roundtrip.nodes_63', roundtrip))
    def persistence():
        with tempfile.TemporaryDirectory(prefix='rsi-benchmark-') as directory:
            store = WorldStore(Path(directory)/'worlds.jsonl')
            store.append(tree)
            restored = store.load()
            assert restored[0].to_dict() == tree.to_dict()
            return {'worlds': len(restored), 'nodes': len(restored[0].nodes)}
    jobs.append(('rsi.jsonl_roundtrip.nodes_63', persistence))
    rows = []
    for name, fn in jobs:
        try:
            row = measure(name, fn, args.samples, args.batch)
            print(f"{name}: {row['median_seconds'] * 1000:.3f} ms median", flush=True)
        except Exception as exc:
            row = {'name': name, 'status': 'failed', 'error': repr(exc)}
            print(f'{name}: FAILED {exc}', flush=True)
        rows.append(row)
    lua = {'status': 'not_run', 'reason': 'No --lua executable supplied'}
    if args.lua:
        process = subprocess.run([args.lua, str(Path(__file__).with_name('lua_audit.lua'))],
                                 cwd=ROOT, capture_output=True, text=True, timeout=60)
        lua = {'executable': args.lua, 'exit_code': process.returncode, 'stderr': process.stderr,
               'stdout': process.stdout, 'records': []}
        for line in process.stdout.splitlines():
            try:
                lua['records'].append(json.loads(line))
            except json.JSONDecodeError:
                pass
        lua['status'] = 'completed' if process.returncode == 0 and lua['records'] else 'failed'
    sources = sorted([*ROOT.glob('dream_rsi/**/*.py'), *ROOT.glob('lua/*.lua'),
                      *ROOT.glob('tests/test_dream_rsi*.py'), ROOT/'tests/test_lua_engine.py',
                      *ROOT.glob('benchmarks/rsi_lua/*.py'), *ROOT.glob('benchmarks/rsi_lua/*.lua')])
    result = {'timestamp_utc': datetime.now(timezone.utc).isoformat(),
              'git_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'python': sys.version, 'platform': platform.platform(), 'processor': platform.processor(),
              'logical_cpus': os.cpu_count(), 'clock': 'perf_counter_ns wall time',
              'scope': 'local synthetic CPU workloads; no real discovery, GPU execution, or native FFI performance',
              'source_sha256': {str(p.relative_to(ROOT)).replace('\\','/'): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
              'rsi': rows, 'lua': lua}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print('Results:', args.output)
    failures = [r for r in lua.get('records', []) if r.get('kind') == 'check' and r['status'] == 'fail']
    print('Lua audit checks failing:', len(failures))
    return int(any(row['status'] == 'failed' for row in rows) or lua['status'] == 'failed' or bool(failures))


if __name__ == '__main__':
    raise SystemExit(main())
