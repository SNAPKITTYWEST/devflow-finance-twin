"""Render the saved benchmark JSON without rerunning measurements."""
import json
from pathlib import Path
import statistics

directory = Path(__file__).resolve().parent / 'results'
data = json.loads((directory / 'latest.json').read_text(encoding='utf-8'))
lines = ['# Measured results', '', f"Recorded UTC: {data['timestamp_utc']}", '',
         f"Python: {data['python'].split()[0]}; {data['platform']}; {data['logical_cpus']} logical CPUs.", '',
         'Source revision plus per-file SHA-256 hashes are in [latest.json](latest.json).', '',
         '## RSI wall time', '', '| Workload | Median ms/op | Min | Max |', '|---|---:|---:|---:|']
for row in data['rsi']:
    if row['status'] == 'measured':
        lines.append(f"| {row['name']} | {row['median_seconds']*1000:.3f} | {row['min_seconds']*1000:.3f} | {row['max_seconds']*1000:.3f} |")
    else:
        lines.append(f"| {row['name']} | FAILED | | |")
records = data['lua'].get('records', [])
groups = {}
for row in records:
    if row['kind'] == 'benchmark' and row['status'] == 'measured':
        groups.setdefault(row['name'], []).append(row['seconds']/row['iterations']*1e6)
lines += ['', '## Lua CPU time', '',
          'Codec measurements now include leaf serialization, integrity-checked deserialization, and exact-buffer validation.', '',
          '| Workload | Median microseconds/op | Min | Max |', '|---|---:|---:|---:|']
for name, values in groups.items():
    lines.append(f'| {name} | {statistics.median(values):.3f} | {min(values):.3f} | {max(values):.3f} |')
checks = [r for r in records if r['kind'] == 'check']
lines += ['', '## Correctness boundaries', '',
          f"Lua checks: {sum(r['status']=='pass' for r in checks)} passed, {sum(r['status']=='fail' for r in checks)} failed.", '',
          '| Lua check | Result |', '|---|---|']
for row in checks:
    lines.append(f"| {row['name']} | {row['status']} |")
lines += ['', 'Native backends, GPU kernels, and real discovery models were not benchmarked. The Lua checksum is not cryptographic BLAKE3.', '']
(directory / 'SUMMARY.md').write_text('\n'.join(lines), encoding='utf-8')
print(directory / 'SUMMARY.md')
