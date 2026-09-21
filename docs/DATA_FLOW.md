# Data Flow

> Data lineage for every major data object in the repository, with Mermaid flowcharts showing creation, mutation, storage, and consumption.
> Repository: devflow-finance-twin
> Generated: 2026-09-19

---

## Table of Contents

1. [Discovery Trees](#1-discovery-trees)
2. [Policy Objects](#2-policy-objects)
3. [WORM Blocks](#3-worm-blocks)
4. [Ledger Events](#4-ledger-events)
5. [Audit Records](#5-audit-records)
6. [Calibration Profiles](#6-calibration-profiles)
7. [KV Cache](#7-kv-cache)
8. [Tensor Buffers](#8-tensor-buffers)
9. [MXML Contracts](#9-mxml-contracts)
10. [Virtual Parameter Objects](#10-virtual-parameter-objects)
11. [Bytecode Artifacts](#11-bytecode-artifacts)
12. [Quantum State Vectors](#12-quantum-state-vectors)
13. [Metabinary Frames](#13-metabinary-frames)
14. [Theorem Records](#14-theorem-records)
15. [Benchmark Results](#15-benchmark-results)
16. [Decision Seals](#16-decision-seals)
17. [Constitution Axiom Sets](#17-constitution-axiom-sets)
18. [Assembly Module Interfaces](#18-assembly-module-interfaces)
19. [Schema Events (ORC + Extended)](#19-schema-events-orc--extended)
20. [GPU Projection Frames](#20-gpu-projection-frames)

---

## 1. Discovery Trees

**Type:** `DiscoveryTree` (`dream_rsi/tree.py`)
**Schema:** `{root_id: str, nodes: dict[str, TreeNode]}` where `TreeNode = {node_id, parent_id, score, cost, branch_id, metadata, children: list[str]}`

### Data Lineage

```mermaid
flowchart LR
    subgraph CREATION[Creation]
        AGENT[FixedDiscoveryAgent\n.propose(parent_node)\n.execute(proposal)]
        EVAL[DomainEvaluator\n.evaluate(proposal)\n→ score ∈ [0,1]]
        TREE_ADD[DiscoveryTree.add(\nparent_id, score, cost,\nbranch_id, metadata\n)]
    end

    AGENT -->|proposal + execution result| EVAL
    EVAL -->|score| TREE_ADD
    TREE_ADD -->|TreeNode created with UUID-prefix ID| TREE_OBJ[(DiscoveryTree\nin memory)]

    subgraph MUTATION[Mutation — Append Only]
        MORE_NODES[More nodes added\nvia online exploration\nFIFO frontier expansion]
    end

    TREE_OBJ -->|frontier expansion| MORE_NODES
    MORE_NODES -->|add more nodes| TREE_OBJ

    subgraph STORAGE[Storage]
        WORLD_STORE[WorldStore.add(tree)\nIn-memory list of trees\nH_t = {T_1,...,T_t}]
        JSONL_FILE[WorldStore.save_to_jsonl(path)\n.jsonl file: one JSON object per line\nper tree]
    end

    TREE_OBJ -->|round complete| WORLD_STORE
    TREE_OBJ -->|serialize| JSONL_FILE

    subgraph CONSUMPTION[Consumption]
        REPLAY[HistoricalReplay.evaluate(\npolicy, tree)\nRead-only traversal\nno new nodes]
        METRICS[MetricsCollector\nonline_executions\ndiscovery_agent_calls]
        BENCHMARK[benchmarks/rsi_lua/run.py\nJSON roundtrip test\nnodes_63 tree fixture]
    end

    WORLD_STORE -->|replay evaluation| REPLAY
    TREE_OBJ -->|metrics recorded| METRICS
    TREE_OBJ -->|serialize + deserialize| BENCHMARK

    subgraph LINEAGE[Downstream Lineage]
        SCORE_MATRIX[Score matrix\nS[i][j] = policy_i score on tree_j]
        WINNER_SELECTION[Policy selection\nargmax(mean score)]
    end

    REPLAY -->|score ∈ [0,1]| SCORE_MATRIX
    SCORE_MATRIX -->|aggregated| WINNER_SELECTION

    style TREE_OBJ fill:#adf,stroke:#333
    style JSONL_FILE fill:#afa,stroke:#333
    style REPLAY fill:#ffc,stroke:#333
```

### Immutability Guarantee
Once a `TreeNode` is added to a `DiscoveryTree`, its `score`, `cost`, `metadata`, and `parent_id` fields are never modified. The `children` list is append-only (new children may be added but existing children are never removed). This ensures that historical replay is reproducible: the same tree always produces the same evaluation.

### Serialization Format (JSONL)
```json
{"root_id": "abc123def456", "nodes": {
  "abc123def456": {"node_id": "abc123def456", "parent_id": null, "score": 0.5, "cost": 1, "branch_id": "0", "metadata": {}, "children": ["bcd234efg567"]},
  "bcd234efg567": {"node_id": "bcd234efg567", "parent_id": "abc123def456", "score": 0.75, "cost": 1, "branch_id": "1", "metadata": {"depth": 1}, "children": []}
}}
```

---

## 2. Policy Objects

**Type:** `SearchPolicy` (`dream_rsi/policy/`)
**Schema:** `{policy_id: str, parameters: dict, generation: int, parent_id: str | None}`

### Data Lineage

```mermaid
flowchart LR
    subgraph CREATION[Creation]
        DEFAULT_POLICY[Default policy\ncreated at orchestrator init\npolicy_id=UUID, generation=0\nparent_id=None]
        REVISION[PolicyDeveloper.generate_revisions(\npolicy_t, M\n)\n→ M new policies]
    end

    DEFAULT_POLICY -->|policy_0| CANDIDATE_SET[(Candidate set\n[π_0, π_1, ..., π_M])]
    REVISION -->|π_1..π_M| CANDIDATE_SET

    subgraph EVALUATION[Evaluation]
        REPLAY_EVAL[HistoricalReplay.evaluate\nfor each (policy, world) pair\n→ score float]
        MEAN_SCORE[Compute mean score\nper policy\nover all worlds]
    end

    CANDIDATE_SET -->|each candidate| REPLAY_EVAL
    REPLAY_EVAL -->|per-world scores| MEAN_SCORE

    subgraph SELECTION[Selection + Safety]
        ARGMAX[winner = argmax(mean_score)]
        SAFETY[Incumbent safety check\nif winner.score < π_0.score\n  winner = π_0]
    end

    MEAN_SCORE -->|score vector| ARGMAX
    ARGMAX -->|winner candidate| SAFETY

    subgraph DEPLOYMENT[Deployment]
        DEPLOYED_POLICY[policy_{t+1} = winner\nUsed in next round's\nonline exploration]
        LEDGER_RECORD[Sovereign ledger event\ntype: POLICY_SELECTION\npayload: {winner_id, score, round}]
    end

    SAFETY -->|winner| DEPLOYED_POLICY
    SAFETY -->|winner metadata| LEDGER_RECORD

    subgraph RETIREMENT[Retirement]
        LOSER_RETIRED[Non-winner candidates\nGarbage collected\nno persistence]
        FINAL_RETURN[RunResult.final_policy\nReturned to caller\nafter all rounds]
    end

    DEPLOYED_POLICY -->|after R rounds| FINAL_RETURN
    CANDIDATE_SET -->|losers| LOSER_RETIRED

    style CANDIDATE_SET fill:#adf,stroke:#333
    style DEPLOYED_POLICY fill:#afa,stroke:#333
    style LOSER_RETIRED fill:#ffc,stroke:#333
```

### Parameter Schema
Policy parameters control the exploration behavior:
- `explore_depth: int` — maximum tree depth during online exploration
- `branching_factor: int` — proposals generated per node
- `score_threshold: float` — minimum score to expand a node
- `compute_budget: int` — maximum online execution steps

---

## 3. WORM Blocks

**Type:** 64-byte header + variable payload
**Languages:** Rust (`wasm/worm_frame.wasm`), Chisel (`languages/chisel/WormHardwareAccelerator.scala`), COBOL (`finance/cobol/LEDGWYCB`)

### Data Lineage

```mermaid
flowchart TD
    subgraph CREATION[Block Creation]
        ACH_TRIGGER[Finance event:\nACH return, treasury post]
        COBILT[COBOL COBILT-ACH-TREASURY\nBuild treasury event payload]
        LEDGWYCB_CALL[LEDGWYCB COBOL\nCall WORM write routine]
        WASM_CREATE[worm_frame.wasm:\nworm_create(block_id)\nWrite 64-byte header]
    end

    ACH_TRIGGER -->|event data| COBILT
    COBILT -->|payload bytes| LEDGWYCB_CALL
    LEDGWYCB_CALL -->|block_id, payload| WASM_CREATE

    subgraph HEADER_LAYOUT[Header Layout (64 bytes)]
        H_MAGIC[Bytes 0-3: magic 0x574F524D 'WORM']
        H_VER[Bytes 4-5: version uint16 LE]
        H_FLAGS[Bytes 6-7: flags uint16 LE]
        H_BLOCKID[Bytes 8-15: block_id uint64 LE]
        H_PREVHASH[Bytes 16-47: prev_hash SHA256 32 bytes]
        H_PAYLEN[Bytes 48-55: payload_len uint64 LE]
        H_SEAL[Bytes 56-63: seal 8 bytes\n(first 8 bytes of SHA256 seal)]
    end

    WASM_CREATE -->|header written| OPEN_BLOCK[(WORM block\nsealed=false\npayload accumulating)]

    subgraph WRITING[Payload Writing]
        WRITE_CALLS[worm_write(block_id, data)\n1+ write calls\nPayload appended]
    end

    OPEN_BLOCK -->|write calls| WRITE_CALLS
    WRITE_CALLS -->|payload grows| OPEN_BLOCK

    subgraph SEALING[Sealing]
        SEAL_TRIGGER[Finance processing complete\nor worm_seal() explicit call]
        COMPUTE_SEAL[seal = SHA256(prev_hash || payload)]
        MARK_SEALED[sealed = true\nHeader seal field updated\nNo further writes]
    end

    OPEN_BLOCK -->|seal trigger| SEAL_TRIGGER
    SEAL_TRIGGER -->|seal computation| COMPUTE_SEAL
    COMPUTE_SEAL -->|seal bytes + sealed=true| MARK_SEALED

    subgraph STORAGE[Storage]
        DB_WRITE[Write to EVENT_STORE\nPAYLOAD = WORM block bytes\nEVENT_TYPE = WORM_COMMIT]
        FILE_WRITE[Write to WORM log file\nAppend-only binary file]
        LEDGER_EVENT[Sovereign ledger Append\ntype: WORM_SEALED\npayload: {block_id, seal_hash}]
    end

    MARK_SEALED -->|sealed block| DB_WRITE
    MARK_SEALED -->|sealed block| FILE_WRITE
    MARK_SEALED -->|notification| LEDGER_EVENT

    subgraph CONSUMPTION[Consumption]
        VERIFY[worm_verify(block_id)\nRecompute seal\nVerify integrity]
        READ[worm_read(block_id, offset, len)\nRead payload portion]
        AUDIT[Audit trail reference\nblock_id cited in DecisionRecord]
    end

    MARK_SEALED -->|verification| VERIFY
    MARK_SEALED -->|read operations| READ
    LEDGER_EVENT -->|reference| AUDIT

    style MARK_SEALED fill:#afa,stroke:#333
    style OPEN_BLOCK fill:#adf,stroke:#333
```

---

## 4. Ledger Events

**Type:** `Event` (Go struct in `sovereign/`)
**Schema:** `{Seq int64, AggregateID string, EventType string, Payload []byte, OccurredAt time.Time, PrevHash [32]byte, Hash [32]byte}`

### Data Lineage

```mermaid
flowchart TD
    subgraph SOURCES[Event Sources]
        SRC_ACH[Finance: ACH transaction\ntype=ACH_RETURN, ACH_POST]
        SRC_POLICY[RSI: Policy selection\ntype=POLICY_SELECTION]
        SRC_WORM[WORM: Block sealed\ntype=WORM_SEALED]
        SRC_COMPILE[Compiler: Artifact built\ntype=COMPILE_ARTIFACT]
        SRC_PROOF[Formal: Proof accepted\ntype=PROOF_ACCEPTED]
        SRC_DECISION[Constraint harness: Decision\ntype=DECISION_FINALIZED]
    end

    subgraph CREATION[Creation — Append()]
        ACQUIRE_LOCK[Acquire write lock\nsync.RWMutex.Lock()]
        GET_SEQ[seq = len(events) + 1]
        GET_PREV[prevHash = events[-1].Hash\nor genesis_hash if first]
        BUILD_PAYLOAD[canonical_json(event body)]
        COMPUTE_HASH[Hash = SHA256(payload + prevHash)]
        ASSIGN[event.Seq = seq\nevent.PrevHash = prevHash\nevent.Hash = hash\nevent.OccurredAt = now()]
        APPEND[events = append(events, event)]
        RELEASE[Release write lock]
    end

    SRC_ACH --> ACQUIRE_LOCK
    SRC_POLICY --> ACQUIRE_LOCK
    SRC_WORM --> ACQUIRE_LOCK
    SRC_COMPILE --> ACQUIRE_LOCK
    SRC_PROOF --> ACQUIRE_LOCK
    SRC_DECISION --> ACQUIRE_LOCK

    ACQUIRE_LOCK --> GET_SEQ --> GET_PREV --> BUILD_PAYLOAD --> COMPUTE_HASH --> ASSIGN --> APPEND --> RELEASE

    RELEASE -->|event record| LEDGER[(Sovereign Ledger\nin-memory + DB\nappend-only)]

    subgraph PERSISTENCE[DB Persistence]
        SQL_INSERT[INSERT INTO EVENT_STORE\n(seq, aggregate_id, event_type,\npayload, occurred_at, prev_hash, hash)]
    end

    LEDGER -->|write-through| SQL_INSERT

    subgraph CONSUMPTION[Consumption]
        QUERY[ledger.Query(filter)\nRead lock acquired\nFilter by type/aggregate/time]
        SNAPSHOT[ledger.Snapshot(seq)\nPoint-in-time view\nEvents up to seq]
        REPLICATE[ledger.Replicate(sink)\nStream all events\nto replica]
        VERIFY[ledger.Verify()\nRecompute all hashes\nVerify chain integrity]
        MERKLE[ledger.MerkleRoot(batch)\nCompute Merkle root\nfor inclusion proof]
    end

    LEDGER -->|read operations| QUERY
    LEDGER -->|snapshot| SNAPSHOT
    LEDGER -->|replication| REPLICATE
    LEDGER -->|integrity check| VERIFY
    LEDGER -->|batch proof| MERKLE

    subgraph DOWNSTREAM[Downstream Uses]
        AUDIT_REF[Audit record references\nledger sequence number]
        WORM_SEAL[WORM seal confirmation\nlinked to ledger seq]
        PROOF_CHECK[Formal verification\nproof linked to ledger event]
    end

    QUERY --> AUDIT_REF
    QUERY --> WORM_SEAL
    VERIFY --> PROOF_CHECK

    style LEDGER fill:#adf,stroke:#333
    style COMPUTE_HASH fill:#f9f,stroke:#333
```

### Chain Invariants
- `events[0].PrevHash == genesis_hash` (hardcoded constant)
- `events[i].Hash == SHA256(canonical_json(events[i].body) + events[i].PrevHash)` for all i
- `events[i].Seq == i + 1` for all i (1-indexed, strictly monotonic)
- `events[i].OccurredAt >= events[i-1].OccurredAt` for all i > 0

---

## 5. Audit Records

**Type:** `AuditEvent` (Python dataclass in `constraint-harness/runtime/transitions.py`), `DecisionRecord` (`constraint-harness/audit/seal.py`)

### Data Lineage

```mermaid
flowchart TD
    subgraph AUDIT_EVENT_CREATION[AuditEvent Creation]
        SM_TRANSITION[StateMachine.transition(\nto_state, task_id, input_data, reason)]
        HASH_INPUT[input_hash = SHA256(repr(input_data))[:16]]
        BUILD_EVENT[AuditEvent(\nevent_type='state_transition'\nfrom_state, to_state\nexecution_id, task_id\ninput_hash, timestamp, reason\n)]
    end

    SM_TRANSITION --> HASH_INPUT --> BUILD_EVENT

    BUILD_EVENT -->|append| HISTORY[(StateMachine.history\nlist[AuditEvent]\nappend-only)]

    subgraph REVISION_TRACKING[Revision Counting]
        REV_INC[if to_state == REVISE:\n  revision_count++]
    end

    BUILD_EVENT --> REV_INC

    subgraph DECISION_RECORD_CREATION[DecisionRecord Creation — at FINALIZE/FAILED_CLOSED]
        SEAL_DECISION[seal_decision(\nexecution_id\nrequest_hash\nresult\naxiom_results\nstate_history\n)]
        COMPUTE_RECORD[DecisionRecord(\nexecution_id\nrequest_hash\nresult_hash = SHA256(canonical_json(result))\naxiom_results\nverification_results\nstate_history = list(history)\ntimestamp = time.time()\ndecision = PASS|FAILED_CLOSED\nseal = ''\n)]
        COMPUTE_SEAL[seal = SHA256(canonical_json(\nrecord_without_seal))]
        ASSIGN_SEAL[record.seal = seal]
    end

    HISTORY -->|state_history| SEAL_DECISION
    SEAL_DECISION --> COMPUTE_RECORD --> COMPUTE_SEAL --> ASSIGN_SEAL

    ASSIGN_SEAL -->|sealed record| DECISION_RECORD[(DecisionRecord\nimmutable sealed object)]

    subgraph STORAGE[Storage]
        EMBED_ENVELOPE[Embedded in DecisionEnvelope\nreturned to caller]
        LEDGER_WRITE[Written to sovereign ledger\ntype: DECISION_FINALIZED\npayload: JSON(DecisionRecord)]
        EXPORT[AuditLog.Export()\nJSON Lines format\nto file or network]
    end

    DECISION_RECORD --> EMBED_ENVELOPE
    DECISION_RECORD --> LEDGER_WRITE
    HISTORY --> EXPORT

    subgraph VERIFICATION[Verification]
        VERIFY_SEAL[Recompute seal\nCompare with stored seal]
        VERIFY_HISTORY[Verify state history\nAll transitions legal per\nLEGAL_TRANSITIONS dict]
        VERIFY_TIMESTAMPS[Check monotonic timestamps\nAuditEvent.timestamp[i] >=\nAuditEvent.timestamp[i-1]]
    end

    DECISION_RECORD --> VERIFY_SEAL
    HISTORY --> VERIFY_HISTORY
    HISTORY --> VERIFY_TIMESTAMPS

    style DECISION_RECORD fill:#afa,stroke:#333
    style COMPUTE_SEAL fill:#f9f,stroke:#333
    style HISTORY fill:#adf,stroke:#333
```

### Cryptographic Properties
- **request_hash:** SHA-256 of the raw input bytes in canonical JSON form
- **result_hash:** SHA-256 of `canonical_json(result_dict)`
- **input_hash** (per AuditEvent): SHA-256 of `repr(input_data).encode()`, truncated to 16 hex chars
- **seal:** SHA-256 of `canonical_json(asdict(record) excluding seal field)`

The seal binds: execution_id, request_hash, result_hash, all axiom results, all state transitions, and the decision outcome. Tampering with any component invalidates the seal.

---

## 6. Calibration Profiles

**Type:** JSON (Python dict) or MATLAB struct
**Sources:** `physics/julia-rwpt/RWPT.jl`, `astre-vault/astra_math_vault.m`

### Data Lineage

```mermaid
flowchart TD
    subgraph GENERATION[Profile Generation]
        RWPT_SIM[julia-rwpt/RWPT.jl\nRun particle transport simulation\nN_particles=10000, geometry=slab]
        EXTRACT_XS[Extract cross-sections\nσ_scatter, σ_absorb per energy group]
        MATLAB_SOLVER[astra_math_vault.m\nsolve_lindblad() for validation\nCompare RWPT vs analytical]
        VALIDATE[Validate: |RWPT - Lindblad| < 1e-4\nfor all energy groups]
    end

    RWPT_SIM -->|particle trajectory data| EXTRACT_XS
    EXTRACT_XS -->|raw cross-sections| MATLAB_SOLVER
    MATLAB_SOLVER -->|analytical reference| VALIDATE

    VALIDATE -->|validated profile| PROFILE_JSON[(Calibration Profile JSON\n{energy_groups: [{E_min, E_max,\nsigma_scatter, sigma_absorb,\nconfidence: float}]\nvalidation_rmse: float\ntimestamp: ISO-8601})]

    subgraph CONSUMPTION[Consumption]
        CH_CONTEXT[Constraint harness context\nPhysics-domain request\nLoaded into context dict]
        OWL_SOLVER[astre-vault/astra_owl_solver.py\nOwl:DataPropertyAssertion\nfor each energy group]
        RCC8_SPATIAL[rcc8_spatial.py\nSpatial constraints on\ngeometry regions]
        CONSTITUTION_AXIOM[Constitution axiom:\nphysics_calibrated\nPASS if profile loaded\nand validation_rmse < threshold]
    end

    PROFILE_JSON -->|load at startup| CH_CONTEXT
    PROFILE_JSON -->|facts asserted| OWL_SOLVER
    PROFILE_JSON -->|geometry bounds| RCC8_SPATIAL
    CH_CONTEXT -->|axiom check| CONSTITUTION_AXIOM

    subgraph LINEAGE[Downstream]
        METAL_CALIB[Apple Metal inference:\ntemperature parameter\ncalibrated from thermal profile]
        VSM_CALIB[VSM-2500:\nVP initial values\nseeded from calibration]
    end

    CH_CONTEXT --> METAL_CALIB
    CH_CONTEXT --> VSM_CALIB

    style PROFILE_JSON fill:#adf,stroke:#333
    style VALIDATE fill:#afa,stroke:#333
```

---

## 7. KV Cache

**Type:** Metal buffer pair (key_cache, value_cache)
**Dimensions:** `[N_layers, n_heads, max_seq_len, head_dim]` × float16

### Data Lineage

```mermaid
flowchart TD
    subgraph ALLOCATION[Allocation at Startup]
        ALLOC_KEY[MTLDevice.makeBuffer(\nbytes = N_layers × n_heads × max_seq_len × head_dim × 2\nOptions: storageModeShared)]
        ALLOC_VAL[Same dimensions for value cache]
        INIT_ZERO[Zero-initialize both buffers\nmemset(key_cache, 0, size)]
    end

    ALLOC_KEY --> KEY_BUF[(key_cache MTLBuffer\non-device memory\n≈268 MB for 3B model)]
    ALLOC_VAL --> VAL_BUF[(value_cache MTLBuffer\non-device memory\n≈268 MB for 3B model)]
    INIT_ZERO -->|zeroed| KEY_BUF
    INIT_ZERO -->|zeroed| VAL_BUF

    subgraph WRITE_PATH[Write Path — Forward Pass]
        QKV_PROJ[q_proj, k_proj, v_proj kernels\nCompute Q,K,V for current token]
        KV_UPDATE_KERNEL[kernel: kv_cache_update\nFor each layer l, head h:\n  key_cache[l, h, pos, :] = K_computed\n  val_cache[l, h, pos, :] = V_computed]
    end

    QKV_PROJ -->|K,V tensors| KV_UPDATE_KERNEL
    KV_UPDATE_KERNEL -->|write at position pos| KEY_BUF
    KV_UPDATE_KERNEL -->|write at position pos| VAL_BUF

    subgraph READ_PATH[Read Path — Attention]
        KV_READ_KERNEL[kernel: kv_cache_read\nFor each layer l, head h:\n  K_all = key_cache[l, h, 0:pos+1, :]\n  V_all = val_cache[l, h, 0:pos+1, :]]
        ATTN[attention_scores kernel\nQ · K_all^T / √head_dim\n→ attention weights]
        COMBINE[attention_combine kernel\nweights · V_all\n→ attended output]
    end

    KEY_BUF -->|read K_all| KV_READ_KERNEL
    VAL_BUF -->|read V_all| KV_READ_KERNEL
    KV_READ_KERNEL -->|K_all, V_all| ATTN
    ATTN -->|weights| COMBINE

    subgraph EVICTION[Eviction]
        EVICT_CHECK{pos >= max_seq_len?}
        SHIFT[GPU memmove:\nshift entries 1..N-1 → 0..N-2\nFree position max_seq_len-1]
    end

    KV_UPDATE_KERNEL --> EVICT_CHECK
    EVICT_CHECK -->|yes| SHIFT
    SHIFT -->|pos = max_seq_len-1| KV_UPDATE_KERNEL

    subgraph RESET[Reset]
        RESET_KV[reset_kv_cache() call\nZero both buffers\npos = 0]
        NEW_SESSION[New inference session\nFresh start]
    end

    KEY_BUF -->|clear on reset| RESET_KV
    VAL_BUF -->|clear on reset| RESET_KV
    RESET_KV -->|fresh buffers| NEW_SESSION

    style KEY_BUF fill:#adf,stroke:#333
    style VAL_BUF fill:#adf,stroke:#333
    style EVICT_CHECK fill:#ffc,stroke:#333
```

---

## 8. Tensor Buffers

**Type:** Metal buffers containing float16/float32/INT4 data
**Usage:** Apple Metal inference pipeline, GPU projection kernels

### Data Lineage

```mermaid
flowchart TD
    subgraph WEIGHT_LOADING[Weight Loading]
        SAFETENSORS[.safetensors file\nINT4 quantized weights\n+ float16 scale factors]
        WEIGHT_LOAD[Read weight file\nMap tensors to layer/head/dim]
        GPU_UPLOAD[MTLDevice.makeBuffer\nwith data pointer\nUpload to GPU VRAM]
    end

    SAFETENSORS -->|read| WEIGHT_LOAD
    WEIGHT_LOAD -->|bytes| GPU_UPLOAD
    GPU_UPLOAD --> WEIGHT_BUFS[(Weight buffers\nper layer: Wq, Wk, Wv, Wo\nWg, Wu, Wd (FFN)\nAll INT4 format)]

    subgraph DEQUANT[Dequantization On-The-Fly]
        INT4_DEQUANT[kernel: int4_dequantize\nFor group of 32 elements:\nw_f16 = int4_val × scale_f16]
        ACTIVE_WEIGHTS[(Active weight slice\nfloat16 format\nper-forward-pass)]]
    end

    WEIGHT_BUFS -->|INT4 + scales| INT4_DEQUANT
    INT4_DEQUANT -->|float16| ACTIVE_WEIGHTS

    subgraph ACTIVATION_FLOW[Activation Data Flow]
        INPUT_EMBED[Input: token_ids int32\n→ embedding float16]
        HIDDEN[(Hidden state buffer\n[seq_len, d_model] float16)]
        QKV_BUFS[(Q,K,V buffers\n[seq, n_heads, head_dim] float16)]
        ATTN_BUF[(Attention output\n[seq, d_model] float16)]
        FFN_BUF[(FFN output\n[seq, d_model] float16)]
        LOGIT_BUF[(Logits buffer\n[vocab_size] float32)]
    end

    INPUT_EMBED --> HIDDEN
    HIDDEN -->|linear proj| QKV_BUFS
    QKV_BUFS -->|attention| ATTN_BUF
    ATTN_BUF -->|residual add| HIDDEN
    HIDDEN -->|FFN| FFN_BUF
    FFN_BUF -->|residual add| HIDDEN
    HIDDEN -->|final layer| LOGIT_BUF

    ACTIVE_WEIGHTS -->|multiply| HIDDEN
    ACTIVE_WEIGHTS -->|multiply| QKV_BUFS
    ACTIVE_WEIGHTS -->|multiply| FFN_BUF

    subgraph OUTPUT[Output]
        CPU_COPY[Copy LOGIT_BUF to CPU\nMTLBuffer.contents()\nfloat32 array]
        ARGMAX[argmax or sampling\nfor next token ID]
    end

    LOGIT_BUF -->|MTLBlitCommandEncoder.copy| CPU_COPY
    CPU_COPY -->|float32[]| ARGMAX

    style WEIGHT_BUFS fill:#adf,stroke:#333
    style HIDDEN fill:#f9f,stroke:#333
    style LOGIT_BUF fill:#afa,stroke:#333
```

---

## 9. MXML Contracts

**Type:** MXML (Machine eXchange Markup Language) document
**Source:** `constraint-harness/mxml/`
**Schema:** XML-like structured document with typed fields

### Data Lineage

```mermaid
flowchart TD
    subgraph CREATION[Creation]
        CALLER_APP[Calling application\nconstructs MXML document]
        MXML_STRUCT[MXML structure:\n<mxml version='1.0'>\n  <metadata>\n    <execution_id>uuid</execution_id>\n    <provenance_hash>sha256</provenance_hash>\n    <axioms>authorization determinism</axioms>\n  </metadata>\n  <payload type='model_request'>\n    <content>...</content>\n  </payload>\n</mxml>]
    end

    CALLER_APP -->|construct| MXML_STRUCT

    subgraph VALIDATION[Validation]
        SCHEMA_VALIDATE[mxml/validator.py\nValidate against schema.py\nRequired fields: metadata.execution_id\nmetadata.provenance_hash\nmetadata.axioms\npayload.type\npayload.content]
        PARSE[mxml/parser.py\nParse XML structure\nExtract typed fields]
    end

    MXML_STRUCT -->|input bytes| SCHEMA_VALIDATE
    SCHEMA_VALIDATE -->|valid structure| PARSE
    PARSE -->|parsed MXML object| MXML_OBJ[(Parsed MXML\nPython dataclass\ntyped fields)]

    subgraph CONSTITUTION_FEED[Constitution Feed]
        EXTRACT_AXIOMS[Extract required axioms\nfrom metadata.axioms field]
        BUILD_CONTEXT[Build evaluation context:\ncontext = {agent, task_id,\nallowed_tasks, axioms,\npayload_size, format_valid: True}]
    end

    MXML_OBJ -->|axiom list| EXTRACT_AXIOMS
    MXML_OBJ -->|field values| BUILD_CONTEXT

    subgraph HARNESS_USE[Constraint Harness Use]
        SM_INPUT[Input to StateMachine\nat RECEIVE state\nHash: SHA256(canonical(payload))]
        ROUTER_INPUT[Input to Router\nfor classification\nroute to command handler]
        CMD_INPUT[Input to command handler\nexecute(context, command)]
    end

    MXML_OBJ -->|provenance hash| SM_INPUT
    MXML_OBJ -->|payload type| ROUTER_INPUT
    MXML_OBJ -->|full document| CMD_INPUT

    subgraph AUDIT_LINKAGE[Audit Linkage]
        MXML_HASH[provenance_hash field\nSHA256 of MXML payload bytes\nRecorded in AuditEvent.input_hash]
        SEAL_LINK[DecisionRecord.request_hash\n= SHA256(canonical(MXML payload))]
    end

    SM_INPUT -->|hash| MXML_HASH
    MXML_OBJ -->|payload| SEAL_LINK

    style MXML_OBJ fill:#adf,stroke:#333
    style SCHEMA_VALIDATE fill:#f9f,stroke:#333
```

---

## 10. Virtual Parameter Objects

**Type:** `VirtualParameter` (Rust struct, 128-bit aligned)
**Source:** `rust/fsl/src/sovereign_neural_saas_core.rs`, `vsm2500/`

### Data Lineage

```mermaid
flowchart TD
    subgraph CREATION[Creation]
        ALLOC_VP[vsm2500_alloc()\n128-bit aligned slot\nZeroed: 0x00000000000000000000000000000000]
        LITERAL[VP::from_bytes([u8; 16])\nConstruct from raw bytes]
        LOAD_OP[VP_LOAD opcode\nLoad from NAND# memory\ninto VP register]
    end

    ALLOC_VP --> VP_OBJ[(VirtualParameter\n128-bit, 16-byte aligned\nno float, no sign)]
    LITERAL --> VP_OBJ
    LOAD_OP --> VP_OBJ

    subgraph OPERATIONS[Algebra Operations]
        AND_OP[VP_AND: bitwise AND\n128 bits simultaneously]
        OR_OP[VP_OR: bitwise OR]
        XOR_OP[VP_XOR: bitwise XOR]
        NAND_OP[VP_NAND: ~(A AND B)\nFunctionally complete]
        NOR_OP[VP_NOR: ~(A OR B)]
        IMPL_OP[VP_IMPL: ~A OR B\nLogical implication]
        SELECT_OP[VP_SELECT:\nif popcount(A) >= popcount(B)\n  result=A else result=B\nDeterministic argmax]
    end

    VP_OBJ -->|operand| AND_OP
    VP_OBJ -->|operand| OR_OP
    VP_OBJ -->|operand| XOR_OP
    VP_OBJ -->|operand| NAND_OP
    VP_OBJ -->|operand| NOR_OP
    VP_OBJ -->|operand| IMPL_OP
    VP_OBJ -->|operand| SELECT_OP

    AND_OP -->|result VP| TAGGED_VP
    OR_OP -->|result VP| TAGGED_VP
    XOR_OP -->|result VP| TAGGED_VP
    NAND_OP -->|result VP| TAGGED_VP
    NOR_OP -->|result VP| TAGGED_VP
    IMPL_OP -->|result VP| TAGGED_VP
    SELECT_OP -->|result VP| TAGGED_VP

    subgraph PROVENANCE_TAG[Provenance Tagging]
        TAGGED_VP[(Tagged VP\nVP + 8-byte provenance tag\ntag = SHA256(op+src1+src2+result)[0:8])]
    end

    subgraph STORAGE[Storage]
        VP_STORE[VP_STORE opcode\nWrite to NAND# memory\n128-bit aligned write]
        WORM_SEAL_VP[VP committed to WORM block\nSealed after write\nImmutable forever]
        RUST_SERIAL[VP::to_bytes()\n→ [u8; 16] canonical bytes\nfor JSON or binary serialization]
    end

    TAGGED_VP -->|VP_STORE| VP_STORE
    VP_STORE -->|ledger event| WORM_SEAL_VP
    TAGGED_VP -->|serialize| RUST_SERIAL

    subgraph DOWNSTREAM[Downstream Consumption]
        H100_BRIDGE[VSM H100 SASS bridge\n__int128 CUDA variable\nLDAR.128 / NOT / AND.128]
        THEOREM_LEDGER_VP[theorem_ledger.rs\nVP algebra properties\nproved via Kani harnesses]
        ASSEMBLY_VP[assembly-120/\nNA_BINARY_OP routine\n128-bit XMM register ops]
    end

    TAGGED_VP -->|H100 path| H100_BRIDGE
    TAGGED_VP -->|proof subject| THEOREM_LEDGER_VP
    TAGGED_VP -->|assembly path| ASSEMBLY_VP

    style VP_OBJ fill:#adf,stroke:#333
    style TAGGED_VP fill:#f9f,stroke:#333
    style WORM_SEAL_VP fill:#afa,stroke:#333
```

---

## 11. Bytecode Artifacts

**Type:** `.nand` binary files (NAND# 16-bit words), `.class` files (JVM ISA), `.kl` bytecode, PTX assembly
**Sources:** `kernel-language/`, `isa-jvm/`, NAND# compilers

### Data Lineage

```mermaid
flowchart TD
    subgraph SOURCES[Source Languages]
        KL_SRC[.kl kernel language source\nBLISS/PL/M/CORAL 66 dialect]
        ISA_SRC[.isa JVM-style source\nstack machine assembly]
        PROLOG_SRC[.pl Prolog source\nCobalt compiler input]
        NAND_SRC[NAND# specification\nLean 4 / Rust definition]
    end

    subgraph COMPILATION[Compilation Pipelines]
        KL_COMPILE[kernel-language compiler:\nlex → parse → IR → regalloc\n→ emit PTX\nnvcc -ptx → .cubin]
        ISA_COMPILE[isa-jvm compiler:\nparse → IR → bytecode.py\n→ .class bytecode]
        COBALT_COMPILE[Cobalt compiler:\nDCG parse → Liquid Haskell\n→ x86-64 NASM → ELF]
        NAND_ASSEMBLE[assembly-120/ NASM:\nnasm -f elf64 → .o\nld → .nand ELF]
    end

    KL_SRC -->|kernel-language/src/| KL_COMPILE
    ISA_SRC -->|isa-jvm/compiler/| ISA_COMPILE
    PROLOG_SRC -->|cobalt-compiler/| COBALT_COMPILE
    NAND_SRC -->|assembly-120-strict-model/| NAND_ASSEMBLE

    KL_COMPILE --> PTX_ART[(PTX assembly\n.ptx file\n+ .cubin GPU binary)]
    ISA_COMPILE --> CLASS_ART[(JVM bytecode\n.class file\nMagic 0xCAFEBABE)]
    COBALT_COMPILE --> ELF_ART[(x86-64 ELF\nlinked executable)]
    NAND_ASSEMBLE --> NAND_ART[(NAND# binary\n16-bit instruction stream\n.nand file)]

    subgraph VERIFICATION[Artifact Verification]
        HASH_ARTIFACT[SHA256(artifact bytes)\nRecord in sovereign ledger\ntype: COMPILE_ARTIFACT]
        KANI_VERIFY[Kani bounded model check\nverify NAND# semantics\nagainst Rust model]
        LEAN_VERIFY[Lean 4 refinement check\nEXECUTE(LOWER(e)) == EVAL(e)]
    end

    NAND_ART -->|compute hash| HASH_ARTIFACT
    ELF_ART -->|compute hash| HASH_ARTIFACT
    NAND_ART -->|input to harness| KANI_VERIFY
    NAND_ART -->|proof subject| LEAN_VERIFY

    subgraph EXECUTION[Execution]
        NAND_EXEC[NAND# interpreter\nassembly-120-strict-model/\nCPU_FETCH_DECODE_EXECUTE]
        JVM_EXEC[isa-jvm runtime/interpreter.py\nstack-based bytecode interp]
        PTX_EXEC[nvcc + CUDA runtime\nGPU kernel execution\non SM80/SM90]
        ELF_EXEC[OS ELF loader\nx86-64 execution]
    end

    NAND_ART -->|load + execute| NAND_EXEC
    CLASS_ART -->|load + execute| JVM_EXEC
    PTX_ART -->|GPU launch| PTX_EXEC
    ELF_ART -->|OS exec| ELF_EXEC

    style PTX_ART fill:#adf,stroke:#333
    style NAND_ART fill:#adf,stroke:#333
    style HASH_ARTIFACT fill:#f9f,stroke:#333
```

---

## 12. Quantum State Vectors

**Type:** `numpy.ndarray` shape `(2^n,)` dtype `complex128`
**Source:** `quantum_computer/core/state.py`

### Data Lineage

```mermaid
flowchart TD
    subgraph INIT[Initialization]
        QS_ZERO[QuantumState(n_qubits)\n|ψ⟩ = |0...0⟩\nstate[0] = 1.0+0j\nstate[1:] = 0.0+0j]
        QS_BASIS[QuantumState.from_basis(n, basis_index)\n|ψ⟩ = |basis_index⟩\nstate[basis_index] = 1.0]
        QS_SUPERPOS[QuantumState.superposition(amplitudes)\n|ψ⟩ = Σ_i amplitudes[i]|i⟩\nwith normalization check]
    end

    QS_ZERO --> STATE_VEC[(State vector\nnumpy complex128 array\nshape: (2^n,))]
    QS_BASIS --> STATE_VEC
    QS_SUPERPOS --> STATE_VEC

    subgraph GATE_APPLICATION[Gate Application]
        SQ_GATE[Single-qubit gate U\napply_gate(U_2x2, target_qubit)\nFull unitary = I⊗...⊗U⊗...⊗I\nKronecker product expansion]
        TQ_GATE[Two-qubit gate U\napply_gate(U_4x4, [ctrl, tgt])\nFull unitary: 2^n × 2^n matrix]
        STATE_EVOLVE[|ψ'⟩ = U_full @ |ψ⟩\nnumpy matrix-vector multiply]
    end

    STATE_VEC -->|input| SQ_GATE
    STATE_VEC -->|input| TQ_GATE
    SQ_GATE --> STATE_EVOLVE
    TQ_GATE --> STATE_EVOLVE
    STATE_EVOLVE -->|new state| STATE_VEC

    subgraph MEASUREMENT[Measurement]
        PROBS[prob(|i⟩) = |state[i]|^2\nfor each basis state i]
        SAMPLE[Sample basis state i\nfrom probability distribution]
        COLLAPSE[Project: state[j] = 0 for j ≠ i\nstate[i] = 1.0 (renormalize)\nMeasurement result = i]
    end

    STATE_VEC -->|compute| PROBS
    PROBS -->|sample| SAMPLE
    SAMPLE -->|project| COLLAPSE
    COLLAPSE -->|collapsed state| STATE_VEC

    subgraph NOISE_PATH[Noise Path — Density Matrix]
        TO_DENSITY[rho = |ψ⟩⟨ψ|\nnumpy.outer(state, state.conj())\nshape: (2^n, 2^n)]
        KRAUS_APPLY[ρ' = Σ_k K_k @ ρ @ K_k^†\nfor each Kraus operator K_k]
        TRACE_PRESERVE[Assert: trace(ρ') == 1.0\nComplety positive TP check]
    end

    STATE_VEC -->|noise model| TO_DENSITY
    TO_DENSITY -->|apply Kraus| KRAUS_APPLY
    KRAUS_APPLY --> TRACE_PRESERVE
    TRACE_PRESERVE -->|mixed density matrix| RHO[(Density matrix ρ\nshape: (2^n, 2^n)\ncomplex128)]

    subgraph OUTPUT[Output and Uses]
        FIDELITY_CALC[F = |⟨target|ψ⟩|²\nor tr(ρ_target @ ρ)]
        TOMOGRAPHY[State tomography\nExpectation values\n⟨O⟩ = ⟨ψ|O|ψ⟩]
        QFLOW_OUT[QFlow circuit result\nReturned to Quipper client]
    end

    STATE_VEC --> FIDELITY_CALC
    RHO --> FIDELITY_CALC
    STATE_VEC --> TOMOGRAPHY
    STATE_VEC --> QFLOW_OUT

    style STATE_VEC fill:#adf,stroke:#333
    style RHO fill:#f9f,stroke:#333
    style COLLAPSE fill:#ffc,stroke:#333
```

---

## 13. Metabinary Frames

**Type:** Binary byte string (Lua string or bytes object)
**Source:** `lua/metabinary_codec.lua`

### Data Lineage

```mermaid
flowchart TD
    subgraph CREATION[Frame Creation]
        AST_INPUT[HE-binary AST node\nopcode + children[] + payload bytes]
        NAND_WORDS[NAND# instruction stream\nList of 16-bit words]
        WORM_PAYLOAD[WORM block payload\nBefore sealing]
    end

    subgraph ENCODE[Encoding — metabinary_codec.encode()]
        WRITE_HDR[Write 16-byte header:\nmagic=0x4D455441\nversion, flags\nnode_count, payload_length]
        WRITE_NODES[Write node records:\nFor each node:\n  opcode uint16 LE\n  child_count uint16 LE\n  child_offsets uint32[] LE\n  payload bytes]
        RECURSE_ENC[Recursively encode children\nDepth-first pre-order]
    end

    AST_INPUT -->|tree structure| WRITE_HDR
    NAND_WORDS -->|flat encoding| WRITE_HDR
    WORM_PAYLOAD -->|raw bytes| WRITE_HDR

    WRITE_HDR --> WRITE_NODES --> RECURSE_ENC

    RECURSE_ENC -->|byte string| FRAME[(Metabinary frame\nbyte string\nwire format)]

    subgraph TRANSPORT[Transport / Storage]
        WASM_MEM[wasm/ shared linear memory\nStored at region base + offset]
        FILE_WRITE[Written to .meta binary file\nfor persistence]
        LEDGER_PAYLOAD[Ledger event payload\nEVENT_STORE.PAYLOAD column]
    end

    FRAME -->|copy to WASM memory| WASM_MEM
    FRAME -->|write| FILE_WRITE
    FRAME -->|embed| LEDGER_PAYLOAD

    subgraph DECODE[Decoding — metabinary_codec.decode()]
        PARSE_HDR[Parse 16-byte header\nVerify magic=0x4D455441]
        CHECK_TRUNC[if len(bytes) < payload_length:\n  raise truncated_input_error]
        PARSE_NODES[Parse node records\nRead opcode, children, payload]
        RECURSE_DEC[Recursively decode children\nusing child offsets]
    end

    FRAME -->|decode| PARSE_HDR
    PARSE_HDR --> CHECK_TRUNC --> PARSE_NODES --> RECURSE_DEC

    RECURSE_DEC -->|reconstructed AST| AST_RECOVERED[(Recovered AST node\nor error if malformed)]

    subgraph BENCHMARK_PATH[Benchmark Path]
        NAND_DECODE_256[metabinary.nand_decode_256_words\n→ 256-entry opcode table\nVerified: PASSES in benchmarks]
        ROUNDTRIP[Full encode→decode roundtrip\nStatus: FAILS (wire format bug\nin serializer)]
    end

    FRAME -->|nand decode path| NAND_DECODE_256
    FRAME -->|roundtrip test| ROUNDTRIP

    style FRAME fill:#adf,stroke:#333
    style CHECK_TRUNC fill:#faa,stroke:#333
    style NAND_DECODE_256 fill:#afa,stroke:#333
    style ROUNDTRIP fill:#ffc,stroke:#333
```

---

## 14. Theorem Records

**Type:** `TheoremRecord` (Rust struct in `rust/fsl/src/theorem_ledger.rs`)
**Schema:** `{theorem_id: str, statement: str, proof_backend: str, verification_timestamp: i64, proof_hash: str}`

### Data Lineage

```mermaid
flowchart TD
    subgraph PROOF_SOURCES[Proof Sources]
        LEAN4_PROOF[Lean 4 proof\nZero-sorry compilation]
        COQ_PROOF[Coq proof\nAll Qed, no Admitted]
        KANI_HARNESS[Kani harness\ncargo kani success]
        SPARK_PROOF[SPARK Ada\nGNAT-SPARK flow proof]
        ISABELLE_PROOF[Isabelle/HOL\nAll goals discharged]
    end

    subgraph RECORD_CREATION[Record Creation]
        BUILD_RECORD[TheoremRecord::new(\ntheorem_id=uuid\nstatement=theorem_text\nproof_backend='Lean4'|'Coq'|'Kani'|...\nverification_timestamp=unix_ms\n)]
        COMPUTE_PROOF_HASH[proof_hash = SHA256(\ncanonical_json(record_without_hash))]
        ASSIGN_HASH[record.proof_hash = proof_hash]
    end

    LEAN4_PROOF -->|proof result| BUILD_RECORD
    COQ_PROOF -->|proof result| BUILD_RECORD
    KANI_HARNESS -->|verification result| BUILD_RECORD
    SPARK_PROOF -->|proof result| BUILD_RECORD
    ISABELLE_PROOF -->|proof result| BUILD_RECORD

    BUILD_RECORD --> COMPUTE_PROOF_HASH --> ASSIGN_HASH

    ASSIGN_HASH -->|sealed record| THEOREM_LEDGER[(TheoremLedger\nVec<TheoremRecord>\nappend-only)]

    subgraph INTEGRITY[Integrity Verification]
        VERIFY_ALL[TheoremLedger::verify_integrity()\nFor each record:\n  recompute hash\n  compare with stored hash\n  verify monotonic timestamps]
        INTEGRITY_OK[All records valid]
        INTEGRITY_FAIL[Hash mismatch\nIntegrityError raised]
    end

    THEOREM_LEDGER -->|verify| VERIFY_ALL
    VERIFY_ALL -->|pass| INTEGRITY_OK
    VERIFY_ALL -->|fail| INTEGRITY_FAIL

    subgraph CONSUMPTION[Consumption]
        CONSTITUTION_LOAD[Load into constraint harness\nconstitution as TRUE axioms\n'theorem_proved:X' → PASS]
        LEAN_VERIFY[Lean 4 can import theorem\nstatement as axiom\n(after external verification)]
        REPORT[CI report: N theorems proved\nListed in VERIFICATION.md]
    end

    THEOREM_LEDGER -->|proved axioms| CONSTITUTION_LOAD
    THEOREM_LEDGER -->|axiom list| LEAN_VERIFY
    THEOREM_LEDGER -->|summary| REPORT

    style THEOREM_LEDGER fill:#adf,stroke:#333
    style INTEGRITY_OK fill:#afa,stroke:#333
    style INTEGRITY_FAIL fill:#faa,stroke:#333
```

---

## 15. Benchmark Results

**Type:** JSON (`benchmarks/rsi_lua/results/latest.json`), Markdown (`results/SUMMARY.md`)

### Data Lineage

```mermaid
flowchart TD
    subgraph INPUT[Benchmark Inputs]
        DREAM_RSI_CODE[dream_rsi/ package\nAll Python modules]
        LUA_CODE[lua/ Lua modules\nmetabinary, metabinary_complete, etc.]
        SOURCE_HASHES[SHA-256 of each source file\nRecorded for reproducibility]
    end

    subgraph EXECUTION[Benchmark Execution — run.py]
        PATCH_UUID[Patch uuid.uuid4\nCounter-based for reproducibility]
        RSI_WORKLOADS[RSI workloads × 9:\nRounds {1,10,50} × Revisions {0,4,8}\nUsing RSIOrchestrator + DreamRSI]
        REPLAY_WORKLOADS[Replay workloads × 3:\nWorlds {1,10,100} × 63-node tree]
        SERIAL_WORKLOADS[Serialization workloads × 2:\nJSON + JSONL roundtrip\nfor 63-node tree]
        LUA_WORKLOADS[Lua workloads:\nheader_pack, serialize\nnand_decode_256, query_leaf]
        TIMING[time.perf_counter_ns()\n9 iterations per workload\nDiscard first 2\nReport min/median/max of 7]
    end

    DREAM_RSI_CODE -->|imports| RSI_WORKLOADS
    LUA_CODE -->|subprocess| LUA_WORKLOADS
    PATCH_UUID -->|deterministic IDs| RSI_WORKLOADS
    PATCH_UUID -->|deterministic IDs| REPLAY_WORKLOADS

    RSI_WORKLOADS --> TIMING
    REPLAY_WORKLOADS --> TIMING
    SERIAL_WORKLOADS --> TIMING
    LUA_WORKLOADS --> TIMING

    subgraph RESULT_OBJECTS[Result Objects]
        RESULT_DICT[Per-workload result dict:\n{name, median_ms, min_ms, max_ms\nraw_samples: [7 floats]\nunit: 'ms' or 'µs'}]
        LATEST_JSON[latest.json:\n{timestamp, python_version\nplatform_info\nsource_sha256s: {file: hash}\nresults: [result_dicts]}]
    end

    TIMING -->|7-sample stats| RESULT_DICT
    SOURCE_HASHES -->|embed| LATEST_JSON
    RESULT_DICT -->|embed| LATEST_JSON

    subgraph AGGREGATION[Aggregation — summarize.py]
        READ_JSON[Read results/latest.json]
        GENERATE_MD[Generate SUMMARY.md\nMarkdown tables\nRSI section + Lua section]
        CORRECTNESS[lua_audit.lua results\n5 pass, 18 fail\nknown limitations table]
    end

    LATEST_JSON -->|read| READ_JSON
    READ_JSON -->|tables| GENERATE_MD
    CORRECTNESS -->|embed| GENERATE_MD

    GENERATE_MD -->|write| SUMMARY_MD[(results/SUMMARY.md\nHuman-readable\nbenchmark summary)]

    subgraph DOWNSTREAM[Downstream Use]
        CI_BADGE[CI: extract median for\nperformance regression check]
        DOCS[Referenced from\nREADME.md + docs/LIBRARY_INDEX.md]
        AUDIT[Audit: source_sha256s\nverify no benchmark tampering]
    end

    SUMMARY_MD --> DOCS
    LATEST_JSON --> CI_BADGE
    LATEST_JSON --> AUDIT

    style LATEST_JSON fill:#adf,stroke:#333
    style SUMMARY_MD fill:#afa,stroke:#333
```

---

## 16. Decision Seals

**Type:** `DecisionRecord` (Python dataclass, `constraint-harness/audit/seal.py`)

### Data Lineage

```mermaid
flowchart TD
    subgraph INPUT_COLLECTION[Input Collection]
        EXEC_ID[execution_id\nUUID string\nfrom StateMachine init]
        REQ_HASH[request_hash\nSHA256(canonical_json(request_payload))]
        RESULT_DATA[result dict\nfrom command execution]
        AXIOM_RESULTS[axiom_results\nList of AxiomResult objects\nfrom constitution evaluation]
        STATE_HISTORY[state_history\nList of AuditEvent objects\nfrom StateMachine.history]
    end

    subgraph CONSTRUCTION[Construction — seal_decision()]
        RESULT_HASH[result_hash = hash_record(result)\n= SHA256(canonical_json(result))]
        BUILD_DR[DecisionRecord(\nexecution_id=...\nrequest_hash=...\nresult_hash=...\naxiom_results=...\nverification_results=[]\nstate_history=...\ntimestamp=time.time()\ndecision=PASS|FAILED_CLOSED\nseal=''\n)]
        COMPUTE_SEAL_STEP[record.compute_seal()\npayload = asdict(record)\npayload.pop('seal')\nrecord.seal = SHA256(canonical_json(payload))]
    end

    EXEC_ID --> BUILD_DR
    REQ_HASH --> BUILD_DR
    RESULT_DATA --> RESULT_HASH --> BUILD_DR
    AXIOM_RESULTS --> BUILD_DR
    STATE_HISTORY --> BUILD_DR
    BUILD_DR --> COMPUTE_SEAL_STEP

    COMPUTE_SEAL_STEP -->|sealed record| SEALED_DR[(DecisionRecord\nwith seal ≠ ''\nSHA-256 committed\nimmutable)]

    subgraph EMBEDDING[Embedding in Responses]
        DECISION_ENVELOPE[DecisionEnvelope\n(constraint harness output)\nIncludes reference to DecisionRecord]
        API_RESPONSE[API response body\nJSON serialized DecisionRecord\nReturned to caller]
    end

    SEALED_DR -->|embed| DECISION_ENVELOPE
    SEALED_DR -->|serialize| API_RESPONSE

    subgraph PERSISTENCE[Persistence]
        LEDGER_STORE[Sovereign ledger event\ntype: DECISION_FINALIZED\npayload: JSON(DecisionRecord)]
        AUDIT_EXPORT[AuditLog.Export() output\nJSON Lines format]
    end

    SEALED_DR -->|ledger append| LEDGER_STORE
    SEALED_DR -->|export| AUDIT_EXPORT

    subgraph VERIFICATION[External Verification]
        RECOMPUTE_SEAL[Verifier recomputes:\npayload = asdict(record)\npayload.pop('seal')\ncomputed = SHA256(canonical_json(payload))\nVerify: computed == record.seal]
        SEAL_VALID[Seal valid: record unmodified]
        SEAL_INVALID[Seal invalid: record tampered]
    end

    SEALED_DR -->|verify| RECOMPUTE_SEAL
    RECOMPUTE_SEAL -->|match| SEAL_VALID
    RECOMPUTE_SEAL -->|mismatch| SEAL_INVALID

    style SEALED_DR fill:#afa,stroke:#333
    style COMPUTE_SEAL_STEP fill:#f9f,stroke:#333
    style SEAL_VALID fill:#afa,stroke:#333
    style SEAL_INVALID fill:#faa,stroke:#333
```

---

## 17. Constitution Axiom Sets

**Type:** Python set/list of axiom names, evaluated into `AxiomResult` objects
**Source:** `constraint-harness/constitution/constitution.py`

### Data Lineage

```mermaid
flowchart TD
    subgraph DEFINITION[Axiom Definition Sources]
        MXML_AXIOMS[MXML document\nmetadata.axioms field\ne.g. 'authorization determinism provenance']
        CONFIG_DEFAULT[config/base.yaml\ndefault_axioms list]
        THEOREM_AXIOMS[theorem_ledger.rs\nProved theorems as additional\nboolean axioms]
    end

    subgraph LOADING[Loading at Request Time]
        PARSE_AXIOMS[Parse axiom string\nor list from MXML]
        MERGE_DEFAULTS[Merge with defaults\nif axioms field missing or empty\ncontext.get('axioms', DEFAULT_SET)]
        LOAD_THEOREMS[Load proved theorems\nAdd as 'theorem_proved:X' = True axioms]
    end

    MXML_AXIOMS -->|requested axioms| PARSE_AXIOMS
    CONFIG_DEFAULT -->|fallback| MERGE_DEFAULTS
    THEOREM_AXIOMS -->|proved facts| LOAD_THEOREMS

    PARSE_AXIOMS --> AXIOM_SET[(Axiom set\nList[str]\nfor this request)]
    MERGE_DEFAULTS --> AXIOM_SET
    LOAD_THEOREMS --> AXIOM_SET

    subgraph EVALUATION[Evaluation — evaluate_constitution()]
        FOR_EACH[For each axiom name in set]
        AUTH_EVAL['authorization':\ncheck agent in allowed_tasks]
        DET_EVAL['determinism':\nhash check]
        PROV_EVAL['provenance':\nformat check]
        SCOPE_EVAL['scope_limit':\nsize check]
        FMT_EVAL['format_validity':\nMXML schema check]
        CUSTOM_EVAL['custom_X':\ncustom evaluator hook]
    end

    AXIOM_SET -->|iterate| FOR_EACH
    FOR_EACH --> AUTH_EVAL
    FOR_EACH --> DET_EVAL
    FOR_EACH --> PROV_EVAL
    FOR_EACH --> SCOPE_EVAL
    FOR_EACH --> FMT_EVAL
    FOR_EACH --> CUSTOM_EVAL

    subgraph RESULTS[Results]
        AXIOM_RESULT_LIST[List[AxiomResult]\nEach: {name, status, evidence, hard}]
        CONSTITUTION_DECISION[ConstitutionalDecision\n{status, axiom_results, reason, may_revise}]
    end

    AUTH_EVAL -->|AxiomResult| AXIOM_RESULT_LIST
    DET_EVAL -->|AxiomResult| AXIOM_RESULT_LIST
    PROV_EVAL -->|AxiomResult| AXIOM_RESULT_LIST
    SCOPE_EVAL -->|AxiomResult| AXIOM_RESULT_LIST
    FMT_EVAL -->|AxiomResult| AXIOM_RESULT_LIST
    CUSTOM_EVAL -->|AxiomResult| AXIOM_RESULT_LIST

    AXIOM_RESULT_LIST -->|aggregate| CONSTITUTION_DECISION

    subgraph DOWNSTREAM[Downstream Use]
        SM_TRANSITION[StateMachine.transition\nbased on ConstitutionalDecision.status]
        AUDIT_EMBED[Embedded in DecisionRecord.axiom_results\nfor audit trail]
        REVISE_SIGNAL[If may_revise=True:\nStateMachine → REVISE state]
    end

    CONSTITUTION_DECISION -->|PASS/REVISE/FAILED_CLOSED| SM_TRANSITION
    CONSTITUTION_DECISION -->|axiom_results| AUDIT_EMBED
    CONSTITUTION_DECISION -->|may_revise| REVISE_SIGNAL

    style AXIOM_SET fill:#adf,stroke:#333
    style CONSTITUTION_DECISION fill:#f9f,stroke:#333
```

---

## 18. Assembly Module Interfaces

**Type:** Symbol export tables, documented in ASM header comments
**Source:** `assembly-120-strict-model/`

### Data Lineage

```mermaid
flowchart TD
    subgraph DEFINITION[Interface Definition]
        ASM_HEADER[ASM module header comments:\nMODULE name\nEXPORTED SYMBOLS list\nIMPORTED SYMBOLS list\nLOC count (exact)\nINTERFACE VERSION]
        FORMAL_SPEC[Lean 4 specification:\nFunction signature + postcondition\nfor each exported symbol]
    end

    subgraph IMPLEMENTATION[Implementation]
        ASM_CODE[Assembly source code\n.asm file\nExact LOC enforced]
        NASM_ASSEMBLE[nasm -f elf64 module.asm\n→ module.o ELF object]
    end

    ASM_HEADER -->|interface contract| FORMAL_SPEC
    ASM_CODE -->|assemble| NASM_ASSEMBLE

    NASM_ASSEMBLE --> OBJ_FILE[(module.o ELF object\nexported symbol table)]

    subgraph VERIFICATION[Interface Verification]
        SYMBOL_CHECK[nm module.o | grep -E 'EXPORTED_SYMBOL'\nVerify all declared exports present]
        LOC_CHECK[wc -l module.asm\nVerify exact LOC count]
        LEAN_VERIFY[Lean 4 proof:\nFor each exported symbol:\nBehavior matches spec]
    end

    OBJ_FILE -->|symbol table| SYMBOL_CHECK
    ASM_CODE -->|LOC| LOC_CHECK
    FORMAL_SPEC -->|proof input| LEAN_VERIFY

    subgraph LINKING[Linking]
        LINK_STEP[ld -o nand_exec module.o ...\nAll 120 modules linked\ninto single executable]
        LINK_CHECK[Verify: no undefined symbols\nAll imports resolved]
    end

    OBJ_FILE -->|link| LINK_STEP
    LINK_STEP --> LINK_CHECK

    subgraph CONSUMPTION[Consumption]
        LAYER2_CALLS[Layer 2 compilers call\nassembly module functions\nvia symbol table]
        PROOF_AXIOMS[Lean 4 proofs use assembly\nbehavior as axioms:\nassume NA_BINARY_OP_spec]
        DIAG_FRAMEWORK[Module 20 (diagnostics)\ncalls all other modules\nvia DIAG_STATUS_ADDR protocol]
    end

    LINK_CHECK -->|verified executable| LAYER2_CALLS
    LEAN_VERIFY -->|proved behaviors| PROOF_AXIOMS
    OBJ_FILE -->|diagnostic calls| DIAG_FRAMEWORK

    style OBJ_FILE fill:#adf,stroke:#333
    style LEAN_VERIFY fill:#afa,stroke:#333
    style SYMBOL_CHECK fill:#f9f,stroke:#333
```

---

## 19. Schema Events (ORC + Extended)

**Type:** DB rows in IBM Db2 tables (`schema/ORC_SCHEMA.sql`, `schema/schema-extended.sql`)

### Data Lineage

```mermaid
flowchart TD
    subgraph ORC_CREATION[ORC Task Creation]
        CH_SCHEDULER[Constraint harness scheduler\nscheduler/dag.py:\nNew task from DAG]
        ORC_INSERT[INSERT INTO ORC_SCHEMA.ORCTASK\n(TASKID, SOURCE, CHANNEL, BACKEND\nPAYLOAD, STATUS='NEW')]
    end

    CH_SCHEDULER -->|task spec| ORC_INSERT
    ORC_INSERT --> ORCTASK_ROW[(ORCTASK row\nSTATUS=NEW)]

    subgraph ORC_LIFECYCLE[ORC Task Lifecycle]
        PICKUP[Scheduler picks up task\nUPDATE STATUS='RUNNING']
        COMPLETE[Task done\nUPDATE STATUS='DONE']
        FAIL_RETRY[Task failed\nRETRY_COUNT++\nSTATUS='NEW'\nNEXT_ATTEMPT_TS=backoff]
        FAIL_FINAL[Max retries\nSTATUS='FAILED']
        AUDIT_INSERT[INSERT INTO ORCAUD\n(TASKID, EVENT_CODE, EVENT_TS, DETAIL)]
    end

    ORCTASK_ROW --> PICKUP --> COMPLETE
    PICKUP --> FAIL_RETRY --> ORCTASK_ROW
    PICKUP --> FAIL_FINAL
    COMPLETE --> AUDIT_INSERT
    FAIL_RETRY --> AUDIT_INSERT
    FAIL_FINAL --> AUDIT_INSERT

    subgraph EVENT_STORE_CREATION[Extended Schema — Event Store]
        FINANCE_EVT[Finance layer generates event\nACH_RETURN, TREASURY_POST etc.]
        RSI_EVT[RSI layer generates event\nPOLICY_SELECTION etc.]
        ES_INSERT[INSERT INTO EVENT_STORE\n(EVENT_TYPE, AGGREGATE_ID\nPAYLOAD, OCCURRED_AT, SEQUENCE_NUM)]
    end

    FINANCE_EVT --> ES_INSERT
    RSI_EVT --> ES_INSERT
    ES_INSERT --> ES_ROW[(EVENT_STORE row\nSEQUENCE_NUM unique\nmonotonic)]

    subgraph RAIL_FLOW[Rail Submission Flow]
        RAIL_SUB_INSERT[INSERT INTO RAIL_SUBMISSIONS\n(RAIL_CODE, PAYMENT_ID\nSTATUS='CREATED')]
        SUBMIT_ACH[UPDATE STATUS='SUBMITTED'\nEXTERNAL_REF=fed_tracking_id]
        NOTIF_RECEIVED[INSERT INTO RAIL_NOTIFICATIONS\n(SUBMISSION_ID, TYPE='SETTLEMENT'\nPAYLOAD=settlement_details)]
        SETTLE[UPDATE RAIL_SUBMISSIONS\nSTATUS='SETTLED']
    end

    ES_ROW -->|payment event| RAIL_SUB_INSERT
    RAIL_SUB_INSERT --> SUBMIT_ACH --> NOTIF_RECEIVED --> SETTLE

    subgraph CONSUMPTION[Data Consumption]
        RPGLE_QUERY[RPGLE end-of-day batch\nSELECT * FROM ORCTASK\nWHERE STATUS='DONE'\nAND CREATED_TS >= EOD_START]
        GO_REPLAY[Go ledger_replay.wasm\nSELECT * FROM EVENT_STORE\nORDER BY SEQUENCE_NUM]
        RECONCILE[Scala/ZIO reconciliation\nJOIN RAIL_SUBMISSIONS + RAIL_NOTIFICATIONS\nBalance check]
    end

    ORCTASK_ROW --> RPGLE_QUERY
    ES_ROW --> GO_REPLAY
    SETTLE --> RECONCILE

    style ORCTASK_ROW fill:#adf,stroke:#333
    style ES_ROW fill:#adf,stroke:#333
    style SETTLE fill:#afa,stroke:#333
```

---

## 20. GPU Projection Frames

**Type:** GPU buffers containing 3D→2D projection data
**Source:** `gpu/kernels/gpu_projection_kernels.cu`, `gpu/projection_engine.cpp`

### Data Lineage

```mermaid
flowchart TD
    subgraph INPUT[Graph Input]
        NODE_POSITIONS[Node positions\n3D coordinates [x, y, z] float32\nOne per graph node]
        EDGE_LIST[Edge list\n[(node_i, node_j)] pairs\nOne per graph edge]
        VIEW_MATRIX[Camera/view matrix\n4×4 perspective transform\nfloat32 uniform]
    end

    subgraph GPU_UPLOAD[Host → GPU Transfer]
        ALLOC_NODE_BUF[cudaMalloc(node_buffer\nn_nodes × 3 × sizeof(float))]
        ALLOC_EDGE_BUF[cudaMalloc(edge_buffer\nn_edges × 2 × sizeof(int))]
        ALLOC_2D_BUF[cudaMalloc(projected_2d_buffer\nn_nodes × 2 × sizeof(float))]
        ALLOC_DEPTH_BUF[cudaMalloc(depth_buffer\nn_nodes × sizeof(float))]
        UPLOAD[cudaMemcpy Host→Device\nfor all input buffers]
    end

    NODE_POSITIONS -->|cudaMemcpy| ALLOC_NODE_BUF
    EDGE_LIST -->|cudaMemcpy| ALLOC_EDGE_BUF
    VIEW_MATRIX -->|constant memory| UPLOAD

    ALLOC_NODE_BUF --> NODE_GPU[(node_buffer GPU)]
    ALLOC_EDGE_BUF --> EDGE_GPU[(edge_buffer GPU)]
    ALLOC_2D_BUF --> PROJ_BUF[(projected_2d_buffer GPU)]
    ALLOC_DEPTH_BUF --> DEPTH_BUF[(depth_buffer GPU)]

    subgraph KERNEL_PIPELINE[GPU Kernel Pipeline]
        PERSPECTIVE[kernel: kernel_perspective_project\nGrid: ceil(n_nodes/256) blocks\n256 threads/block\nFor each node i (thread):\n  p_2d = ViewMatrix × p_3d\n  projected_2d[i] = p_2d.xy / p_2d.w\n  depth_buffer[i] = p_2d.z / p_2d.w]

        DEPTH_SORT[kernel: kernel_depth_sort\nBitonic sort on depth_buffer\nSort keys: float\nSort values: node_index\nResult: back-to-front render order]

        EDGE_TESS[kernel: kernel_edge_tessellate\nFor each edge (ctrl0, ctrl1):\n  Compute Bézier control points\n  Tessellate into 16 segments\n  Output: 16 line segments per edge]

        OCCLUSION[kernel: kernel_occlusion_cull\nFor each node:\n  Test bounding sphere vs 6 frustum planes\n  Set visibility flag = 0 or 1]
    end

    NODE_GPU -->|3D coords| PERSPECTIVE
    VIEW_MATRIX -->|constant| PERSPECTIVE
    PERSPECTIVE -->|2D + depth| PROJ_BUF
    PERSPECTIVE -->|depth values| DEPTH_BUF

    DEPTH_BUF -->|sort input| DEPTH_SORT
    DEPTH_SORT -->|sorted order| SORT_BUF[(Sorted node index buffer\ndepth order)]

    EDGE_GPU -->|edge pairs| EDGE_TESS
    PROJ_BUF -->|2D endpoints| EDGE_TESS
    EDGE_TESS -->|polylines| SEGMENT_BUF[(Tessellated segment buffer\nn_edges × 16 line segments)]

    PROJ_BUF -->|2D bounds| OCCLUSION
    OCCLUSION -->|visibility flags| VIS_BUF[(Visibility flag buffer\nbool per node)]

    subgraph DOWNLOAD[GPU → Host Transfer]
        DOWNLOAD_2D[cudaMemcpy projected_2d Device→Host]
        DOWNLOAD_SORT[cudaMemcpy sorted_order Device→Host]
        DOWNLOAD_SEGS[cudaMemcpy segments Device→Host]
        DOWNLOAD_VIS[cudaMemcpy visibility Device→Host]
    end

    PROJ_BUF -->|sync + copy| DOWNLOAD_2D
    SORT_BUF -->|sync + copy| DOWNLOAD_SORT
    SEGMENT_BUF -->|sync + copy| DOWNLOAD_SEGS
    VIS_BUF -->|sync + copy| DOWNLOAD_VIS

    subgraph HOST_USE[Host-Side Use]
        WEBSERVER[Phase 7 visualization WebSocket server\nStream projected coordinates\nto browser client]
        RENDER[WebGL/Canvas rendering\nDraw nodes at projected_2d positions\nDraw segment polylines\nBack-to-front via sorted_order\nSkip occluded nodes]
    end

    DOWNLOAD_2D -->|2D coords| WEBSERVER
    DOWNLOAD_SORT -->|render order| WEBSERVER
    DOWNLOAD_SEGS -->|edge geometry| WEBSERVER
    DOWNLOAD_VIS -->|visibility| WEBSERVER
    WEBSERVER -->|JSON over WebSocket| RENDER

    style NODE_GPU fill:#adf,stroke:#333
    style PROJ_BUF fill:#f9f,stroke:#333
    style WEBSERVER fill:#afa,stroke:#333
```

---

*End of DATA_FLOW.md*
