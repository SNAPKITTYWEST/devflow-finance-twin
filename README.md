# devflow-finance-twin

> Sovereign BaaS ledger stack — IBM i authoritative core, C# API layer, COBOL FSL state machines, RPGLE posting engine.

## Architecture

```
C# REST API
  └── LedgerGateway / CobolGateway (binary struct marshal → IBM i program call)
        └── COBOL FSL Supervisors (TXN-FSL / ACH-FSL / RTP-FSL / LEDGER-GATEWAY)
              └── RPGLE Programs (POSTTRAN / REVTRAN / ADJTRAN / EOD / TREASURY)
                    └── DB2 for i (authoritative double-entry ledger)
```

---

## Repository Layout

| Folder | Contents |
|---|---|
|  | IBM i COBOL programs |
|  | IBM i RPGLE programs (free-form) |
|  | DB2 for i DDL |
|  | C# API, gateways, rail adapters |
|  | Full BaaS architecture reference |

---

## COBOL Programs

### 
Deterministic IBM i logic vault. Prolog-style unification, backtracking, choice points.  
Operations: 

### 
Production ACH batch/entry lifecycle library.  
REXX → COBOL → Logic → DB2 → External ACH Adapter. No assembler dependency.  
Operations: 

State machine: 

### 
Datalog storage engine — replaces SQL persistence entirely.  
No SQL. No assembler. REXX → COBOL → Datalog → DATAWORM.  
Operations: 

---

## RPGLE Programs

### 
End-of-day orchestration driver. Runs on IBM i.  
Steps: FinalizePendingJournals → AgeHolds → PostRailSettlements → ReconcileDay  
Writes to , drives , , .

---

## Schema

### 
Extended DB2 for i DDL (supplements  core schema):

| Table | Purpose |
|---|---|
|  | Replayable event log (binary payload, sequence-keyed) |
|  | ACH / RTP / FedNow / Wire submission tracking |
|  | Inbound rail notifications (SETTLEMENT / RETURN / ACK) |
|  | End-of-day run log with status + summary |
|  | Concurrency harness output (double-entry invariant checks) |

---

## C# Layer

### 
RTP/FedNow rail adapter. Implements .  
Persists to  + . On SETTLEMENT notification, calls  COBOL program via binary  marshal.  
Emits events to  after every operation.

---

## BaaS Reference ()

Full IBM i ledger core:

- **DB2 Schema** — CUSTOMERS, ENTITIES, ACCOUNTS, LEDGERS, JOURNALS, JOURNAL_LINES, TRANSACTIONS, BALANCES, HOLDS, PAYMENT_RAILS, PAYMENTS, ACH_BATCHES, ACH_ENTRIES, SETTLEMENTS, RECONCILIATIONS, FEES, IDEMPOTENCY_KEYS, AUDIT_EVENTS, ERROR_QUEUE, DOMAIN_EVENTS, EVENT_OUTBOX, TREASURY_ACCOUNTS, TREASURY_POSITIONS, RTP_RAILS, RTP_INSTRUCTIONS
- **RPGLE** — PostTransaction, ReverseTransaction, AdjustTransaction, UpdateBalance, ComputeTreasuryPositions, RunEndOfDay
- **COBOL FSL** — TXN-FSL-SUPERVISOR, ACH-FSL-SUPERVISOR, ACH-FSL, RTP-FSL, LEDGER-GATEWAY
- **C#** — LedgerService, LedgerGateway, CobolGateway, TransactionsController, PaymentsController, TreasuryController, IdempotencyMiddleware, Db2EventPublisher, ConcurrencyInvariantHarness

---

## Invariants



---

## License

Apache-2.0
