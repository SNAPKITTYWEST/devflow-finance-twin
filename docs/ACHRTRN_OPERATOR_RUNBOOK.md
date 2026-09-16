# ACHRTRN Operator Runbook

**Purpose**  
Run, monitor, and recover the `ACHRTRN` COBOL return-processor on z/OS. Use this as the single-page operational checklist for on-call and batch operators.

---

## Quick facts
- **Program**: `ACHRTRN`  
- **Files**: `ACHITEM-FILE` (KSDS/DB2 table), `ACHRETLOG-FILE` (KSDS/DB2 table)  
- **Run modes**: Batch (`WS-RUN-MODE = 'B'`) or Online (`'O'`)  
- **Success indicator**: `LK-SUCCESS = 'Y'` in linkage response; job RC = 0  
- **Common error codes**: `NOTFOUND`, `BADSTATE`, `ALREADYRT`, `BADREASN`, `DBERR`, `FILEOPEN`

---

## Preflight checks (before job start)
- **Verify datasets**: `LISTCAT` or `IDCAMS LISTCAT` for VSAM KSDS; `DSN` for DB2.  
- **Confirm file status**: Ensure `ACHITEM` and `ACHRETLOG` are accessible and not in REORG/RECOVERY.  
- **Time source**: NTP sync on system; confirm `GET-CURRENT-TIMESTAMP` replacement is available.  
- **Backups**: Confirm last DB2 backup or VSAM backup snapshot exists and note timestamp.

---

## Run sample JCL
Save as `ACHRTRN.JCL` and submit via JES. Replace dataset names with production names.

```jcl
//ACHRTRN JOB (ACCT),'ACH RETURN',CLASS=A,MSGCLASS=X,NOTIFY=&SYSUID
//STEP01   EXEC PGM=ACHRTRN,PARM='B'
//STEPLIB  DD  DSN=PROD.LOADLIB,DISP=SHR
//ACHITEM   DD  DSN=PROD.ACHITEM.KSDS,DISP=SHR
//ACHRETLOG DD  DSN=PROD.ACHRETLOG.KSDS,DISP=SHR
//SYSOUT    DD  SYSOUT=*
//SYSPRINT  DD  SYSOUT=*
//SYSIN     DD  *
  (optional control data)
/*
```

**Submit**: `SUBMIT 'USER.ACHRTRN.JCL'` or via SDSF/ISPF.

---

## Monitoring during run
- **SDSF**: `ST` to view job status; `H` to hold; `O` to view output.  
- **Check job log**: Look for `FILEOPEN`, `DBERR`, or `ABEND` messages.  
- **Check ACHRETLOG**: confirm `RET_REQ` or `RET_FAIL` entries written. Use DB2 query or IDCAMS REPRO to extract sample records.  
- **Metrics**: monitor `RET_FAIL` rate and reason codes; alert if > threshold.

---

## Common failures and recovery steps

### 1. FILEOPEN on startup
- **Symptom**: `AI-STATUS` or `AR-STATUS` not `'00'`; job aborts early.  
- **Action**:
  1. Check dataset availability: `LISTCAT` / `TSO LISTDS 'PROD.ACHITEM.KSDS'`.
  2. If VSAM locked, run `IDCAMS REPRO` or contact storage team to release locks.
  3. If DB2, check DB2 subsystem and active utilities; restart DB2 if required.
  4. Re-submit job after confirming dataset is accessible.

### 2. NOTFOUND for item
- **Symptom**: `WRS-ERROR-CODE = NOTFOUND`.  
- **Action**:
  1. Verify request keys (company, batch, entry) in caller payload.
  2. If caller error, return `LK-SUCCESS='N'` with `NOTFOUND`.
  3. If data inconsistency suspected, run a targeted lookup and reconcile with upstream systems.

### 3. BADSTATE or ALREADYRT
- **Symptom**: Business validation failure.  
- **Action**:
  1. Inspect `ACHITEM` record state and `ACHRETLOG` history.
  2. If legitimate duplicate, inform caller; no DB change required.
  3. If state mismatch due to out-of-order processing, escalate to application owner for reconciliation.

### 4. DBERR on REWRITE
- **Symptom**: `WRS-ERROR-CODE = DBERR`.  
- **Action**:
  1. Check DB2/VSAM error codes in job log. Note SQLCODE or VSAM RC.
  2. If transient (lock timeout), retry the transaction after short backoff.
  3. If persistent, restore from backup or run recovery utility; escalate to DBA.
  4. If partial update occurred, run compensating transaction or manual fix and record in `ACHRETLOG`.

### 5. ABEND or system failure
- **Action**:
  1. Capture JES job output and ABEND code. Use `SDSF` or `DISPLAY` to collect dump.
  2. If core dump, notify system programmer and provide jobname, step, and SYSABEND.
  3. Re-run job after root cause fixed. If mid-batch, use restart logic (see Restart section).

---

## Restart and reprocessing
- **Checkpointing**: If job supports restart, supply restart parameter in PARM or SYSIN. If not:
  - **Manual reprocess**: identify unprocessed requests via `ACHRETLOG` gaps or application queue.
  - **Idempotency**: ensure callers use idempotency keys to avoid duplicate debits.
- **Re-run window**: Reprocess failed items only after confirming no downstream posting occurred (ledger seq = 0).

---

## Emergency recovery playbook
1. **Stop new runs**: Hold scheduled job class in JES (`SDSF` hold) to prevent further processing.  
2. **Isolate**: If corruption suspected, take affected datasets offline (DISP=MOD to new dataset) and mount backup.  
3. **Restore**: Restore VSAM cluster or DB2 table from last good backup.  
4. **Validate**: Run integrity checks on restored data (record counts, checksums).  
5. **Replay**: Reprocess queued return requests from inbound queue or logs. Use idempotency to avoid duplicates.  
6. **Post-mortem**: Document root cause, corrective actions, and update runbook.

---

## Operational tips
- **Sanitize logs**: Mask account numbers in `AR-DETAIL` (store last 4 digits only).  
- **Timestamps**: Ensure `GET-CURRENT-TIMESTAMP` uses NTP-synced source.  
- **Backups**: Verify daily backups and test restores monthly.  
- **Alerting**: Configure alerts for `FILEOPEN`, `DBERR`, and `RET_FAIL` spikes.

---

## Useful commands and queries

```
TSO LISTDS 'PROD.ACHITEM.KSDS'
IDCAMS LISTCAT — //STEP EXEC PGM=IDCAMS with LISTCAT control statements
SDSF: ST (status)  H (hold)  O (output)  S (select job)
DB2: -DISPLAY DATABASE(*)
     SELECT * FROM ACHITEM WHERE company='ABC' AND batch_id='...'
```

---

## Contacts and escalation
- **Application owner**: Payments Ops (oncall) — Pager: +1-555-0100  
- **DBA**: DB2 Team — Pager: +1-555-0200  
- **Storage/System**: z/OS Systems — Pager: +1-555-0300  
- **Security**: InfoSec — Pager: +1-555-0400

---

## Change log and runbook maintenance
- **Update owner**: Payments Ops team.  
- **Review cadence**: Quarterly review and after any incident.  
- **Versioning**: Record runbook version and date at top of operational runbook.
