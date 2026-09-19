# finance/ — Entry Program Manifest

This directory contains the polyglot finance layer of the Sovereign Treasury Engine.
Each sub-directory owns one language's sources. The files listed below are the primary
entry programs; supporting modules and copy-books are described in each sub-directory.

---

## COBOL (`cobol/`)

| File | Role |
|------|------|
| `ACHRTRN.cbl` | ACH transaction origination and validation entry program |
| `COBILT-ACH-TREASURY.cbl` | Production library layer bridging ACH origination to the treasury pipeline |
| `COBILT-DATAWORM.cbl` | DataWorm datalog storage-engine interface (replaces SQL persistence) |
| `COBILT-VAULT.cbl` | Deterministic logic vault — immutable record commitment routines |
| `COBILT_DATAWORM_TREASURY.cob` | Combined DataWorm + Treasury integration batch driver |
| `LEDGER_POST.cbl` | General-ledger posting entry program |
| `LEDGWYCB.cbl` | Ledger wire COBOL — outbound wire-transfer ledger handler |
| `worm_bridge.cob` | WORM bridge protocol — writes append-only WORM commit records |

---

## C# (`csharp/`)

| File | Role |
|------|------|
| `LedgerGateway.cs` | Managed ledger gateway: P/Invoke bridge to native WORM library |
| `RtpRailAdapter.cs` | Real-Time Payments (RTP) rail adapter implementing `IPaymentRailAdapter` |

---

## PL/I (`pli/`)

| File | Role |
|------|------|
| `functor_worm.pli` | Functor pipeline — higher-order composition of WORM write operations |
| `treasury_ledger.pli` | Canonical treasury ledger entry with ALIGNED/FIXED record layouts |
| `treasury_records.pli` | PL/I record declarations and DSECT-style structures for treasury data |

---

## RPGLE (`rpgle/`)

| File | Role |
|------|------|
| `eod-driver.rpgle` | End-of-day batch driver — sequences EOD_RUNS and ACH_BATCHES file processing |
| `AGHENTSC.rpgle` | Agent transaction scheduler — deferred one-shot task dispatch |
| `FNLIRTR.rpgle` | Financial IR transfer — routes financial intermediate representation records |
| `FNLIR_TEST.rpgle` | FNLIR unit test harness |
| `FNLIR_TEST_YAJL.rpgle` | FNLIR test harness with YAJL JSON parsing integration |
| `JsonExtractField.rpgle` | JSON field extraction utility used by downstream programs |
| `LEDGWYRPG.rpgle` | Ledger wire RPGLE — RPG counterpart to the COBOL wire-ledger program |
| `LEDREVSRV.rpgle` | Ledger review service — serves ledger reversal and correction requests |
| `ORCGHSTROTR.rpgle` | Orchestrator ghost router — routes inter-program calls via binding directory |

---

## Scala (`scala/`)

| File | Role |
|------|------|
| `SovereignTreasuryPipeline.scala` | Core Akka-streams / functional pipeline for treasury event processing |
| `SovereignTreasuryZIO.scala` | ZIO-effect variant of the treasury pipeline for purely functional execution |
| `build.sbt` | SBT build descriptor for the Scala sub-project |
