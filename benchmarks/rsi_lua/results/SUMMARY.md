# Measured results

Recorded UTC: 2026-09-19T01:30:41.520408+00:00

Python: 3.12.10; Windows-11-10.0.26200-SP0; 8 logical CPUs.

Source revision plus per-file SHA-256 hashes are in [latest.json](latest.json).

## RSI wall time

| Workload | Median ms/op | Min | Max |
|---|---:|---:|---:|
| rsi.layered.rounds_1.revisions_0 | 0.308 | 0.297 | 0.439 |
| rsi.layered.rounds_1.revisions_4 | 0.575 | 0.503 | 1.545 |
| rsi.layered.rounds_1.revisions_8 | 0.716 | 0.689 | 0.835 |
| rsi.layered.rounds_10.revisions_0 | 5.671 | 5.547 | 5.973 |
| rsi.layered.rounds_10.revisions_4 | 12.073 | 11.425 | 12.757 |
| rsi.layered.rounds_10.revisions_8 | 19.057 | 18.254 | 19.873 |
| rsi.layered.rounds_50.revisions_0 | 86.310 | 84.362 | 87.397 |
| rsi.layered.rounds_50.revisions_4 | 219.117 | 216.874 | 222.441 |
| rsi.layered.rounds_50.revisions_8 | 371.867 | 362.876 | 376.784 |
| rsi.legacy.rounds_1.default_revisions | 0.334 | 0.296 | 0.411 |
| rsi.legacy.rounds_10.default_revisions | 3.982 | 3.718 | 4.155 |
| rsi.legacy.rounds_50.default_revisions | 65.940 | 64.086 | 68.640 |
| rsi.replay.worlds_1.nodes_63 | 0.145 | 0.138 | 0.161 |
| rsi.replay.worlds_10.nodes_63 | 1.374 | 1.321 | 1.435 |
| rsi.replay.worlds_100.nodes_63 | 15.664 | 14.897 | 17.619 |
| rsi.json_roundtrip.nodes_63 | 1.780 | 1.699 | 2.953 |
| rsi.jsonl_roundtrip.nodes_63 | 7.382 | 7.170 | 9.420 |

## Lua CPU time

Header/serialization measurements use the existing invalid wire format. They do not establish working round trips.

| Workload | Median microseconds/op | Min | Max |
|---|---:|---:|---:|
| metabinary.header_pack_only | 1.400 | 1.300 | 1.600 |
| metabinary.serialize_only_invalid_wire | 3.900 | 3.900 | 4.100 |
| metabinary.nand_decode_256_words | 64.000 | 63.000 | 68.000 |
| metabinary.query_leaf | 0.110 | 0.110 | 0.120 |
| metabinary_complete.header_pack_only | 1.200 | 1.200 | 1.300 |
| metabinary_complete.serialize_only_invalid_wire | 3.900 | 3.900 | 4.100 |
| metabinary_complete.nand_decode_256_words | 61.000 | 59.000 | 62.000 |
| metabinary_complete.query_leaf | 0.100 | 0.100 | 0.110 |

## Correctness boundaries

Lua checks: 5 passed, 18 failed.

| Lua check | Result |
|---|---|
| metabinary.header_size | fail |
| metabinary.builder_methods | fail |
| metabinary.leaf_roundtrip | fail |
| metabinary.missing_params | fail |
| metabinary.impure_flag | fail |
| metabinary.truncated_input | pass |
| metabinary.nand_all_words_roundtrip | pass |
| metabinary.consumed_bytes | fail |
| metabinary.tampered_integrity_rejected | fail |
| metabinary.two_children_roundtrip | fail |
| metabinary_complete.header_size | fail |
| metabinary_complete.builder_methods | fail |
| metabinary_complete.leaf_roundtrip | fail |
| metabinary_complete.missing_params | fail |
| metabinary_complete.impure_flag | fail |
| metabinary_complete.truncated_input | pass |
| metabinary_complete.nand_all_words_roundtrip | pass |
| metabinary_complete.consumed_bytes | fail |
| metabinary_complete.tampered_integrity_rejected | fail |
| metabinary_complete.two_children_roundtrip | fail |
| facade.serialize_returns_bytes | fail |
| final_assembly_load | pass |
| examples_syntax | fail |

Native backends, GPU kernels, real discovery models, and valid serializer throughput were not benchmarked.
