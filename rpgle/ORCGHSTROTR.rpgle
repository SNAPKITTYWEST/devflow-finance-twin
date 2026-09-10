**free
ctl-opt dftactgrp(*no) actgrp('ORCGHST') bnddir('PRPGBNDDIR') option(*srcstmt : *nodebugio);

/**********************************************************************
 ORCGHSTROTR - Orchestration Host (RPG Agent)
 - Replaces Python orchestrator with RPG service program
 - Uses PRPG glue for transport and backend invocation
 - Implements:
    * Task queue ingestion
    * Funnel IR dispatcher (minimal)
    * Backend adapters (COBOL, Prolog, Mercury)
    * Retry/backoff, idempotency, audit
    * Config-driven routing
**********************************************************************/

/* Files (assumed DB2/physical files exist) */
dcl-f ORCLOG    usage(*update : *output) keyed extfile('ORCLOG') usropn;
dcl-f ORCAUD    usage(*output) keyed extfile('ORCAUD') usropn;
dcl-f ORCTASK   usage(*update : *input : *output) keyed extfile('ORCTASK') usropn;

/* PRPG glue prototypes (replace with actual binding names) */
dcl-pr PRPG_SendMessage extpgm('PRPG_SENDMSG');
  pChannel char(32) const;
  pPayload char(1024) const;
  pLen packed(9:0) const;
  pStatus char(8);
end-pr;

dcl-pr PRPG_ReceiveMessage extpgm('PRPG_RECVMSG');
  pChannel char(32) const;
  pOutPayload char(1024);
  pOutLen packed(9:0);
  pStatus char(8);
end-pr;

dcl-pr PRPG_CallBackend extpgm('PRPG_CALLBACK');
  pBackend char(16) const;
  pReq char(1024) const;
  pReqLen packed(9:0) const;
  pRsp char(1024);
  pRspLen packed(9:0);
  pStatus char(8);
end-pr;

/* Local prototypes for orchestrator logic */
dcl-pr OrchestratorMain extpgm('ORCGHSTROTR_MAIN');
end-pr;

dcl-pr Init extpgm(*proc);
end-pr;

dcl-pr Shutdown extpgm(*proc);
end-pr;

dcl-pr PollTaskQueue extpgm(*proc);
end-pr;

dcl-pr ProcessTask extpgm(*proc);
  pTaskRec likeds(TaskRec) const;
end-pr;

dcl-pr DispatchToBackend extpgm(*proc) ind;
  pBackend char(16) const;
  pIrPayload char(1024) const;
  pIrLen packed(9:0) const;
  pOutRsp char(1024);
  pOutLen packed(9:0);
end-pr;

dcl-pr WriteAudit extpgm(*proc);
  pTaskId packed(15:0) const;
  pEvent char(8) const;
  pDetail char(256) const;
end-pr;

dcl-pr LogMsg extpgm(*proc);
  pLevel char(6) const;
  pMsg char(256) const;
end-pr;

/* Task record layout (for ORCTASK file) */
dcl-ds TaskRec qualified;
  TaskId        packed(15:0);
  CreatedTs     timestamp;
  Source        char(32);
  Channel       char(32);
  Backend       char(16);
  Payload       char(1024);
  PayloadLen    packed(9:0);
  Status        char(8);   // NEW, INPROG, DONE, FAIL
  RetryCount    packed(5:0);
  NextAttemptTs timestamp;
  LastError     char(128);
end-ds;

/* In-memory small queue for batching */
dcl-ds TaskQueue dim(100) qualified inz;
  TaskQueue_TaskId packed(15:0) dim(100);
  TaskQueue_Count packed(5:0) inz(0);
end-ds;

/* Config (simple, could be loaded from file or DB) */
dcl-ds OrcConfig qualified inz;
  DefaultBackend char(16) inz('COBOL');
  MaxRetries     packed(3:0) inz(5);
  BaseBackoffSec packed(5:0) inz(10);
end-ds;

/* Simple JSON-ish helpers (very small, not full JSON) */
dcl-proc JsonGetField;
  dcl-pi *n char(1024);
    pJson char(1024) const;
    pField char(64) const;
  end-pi;
  dcl-s pos int(10);
  dcl-s start int(10);
  dcl-s val char(1024);
  pos = %scan('"' + %trim(pField) + '"' : pJson);
  if pos = 0;
    return *blanks;
  endif;
  start = %scan(':' : %subst(pJson : pos));
  if start = 0;
    return *blanks;
  endif;
  start = pos + start;
  val = %subst(pJson : start + 1 : 200);
  // crude: return until comma or closing brace
  dcl-s endpos int(10);
  endpos = %scan(',' : val);
  if endpos = 0;
    endpos = %scan('}' : val);
  endif;
  if endpos = 0;
    endpos = %len(%trim(val));
  endif;
  return %trim(%subst(val : 1 : endpos - 1));
end-proc;

/* Utility: current timestamp string */
dcl-proc TsStr char(26);
  dcl-pi *n char(26);
  end-pi;
  return %char(%timestamp());
end-proc;

/* Init: open files, log startup */
dcl-proc Init;
  dcl-pi *n;
  end-pi;
  open ORCTASK;
  open ORCLOG;
  open ORCAUD;
  LogMsg('INFO' : 'ORCGHSTROTR starting up at ' + TsStr());
end-proc;

/* Shutdown */
dcl-proc Shutdown;
  dcl-pi *n;
  end-pi;
  LogMsg('INFO' : 'ORCGHSTROTR shutting down at ' + TsStr());
  *inlr = *on;
end-proc;

/* Main entry */
dcl-proc OrchestratorMain;
  dcl-pi *n;
  end-pi;

  Init();

  // Main loop: poll task queue and process tasks
  dow '1' = '1';
    PollTaskQueue();
    // process up to N tasks in memory queue
    dow TaskQueue_Count > 0;
      dcl-s idx int(5);
      idx = TaskQueue_Count;
      // load task record from file by TaskId
      TaskRec.TaskId = TaskQueue_TaskId(idx);
      chain TaskRec.TaskId ORCTASK;
      if %found(ORCTASK);
        // process
        ProcessTask(TaskRec);
      else;
        // missing, remove from queue
        TaskQueue_Count = TaskQueue_Count - 1;
      endif;
      // shift queue down
      if TaskQueue_Count > 0;
        for i = idx to TaskQueue_Count by -1;
          TaskQueue_TaskId(i) = TaskQueue_TaskId(i+1);
        endfor;
      endif;
    enddo;

    // sleep/backoff (simple)
    callp sleep(2);
  enddo;

  Shutdown();
end-proc;

/* PollTaskQueue: read ORCTASK for NEW or scheduled tasks */
dcl-proc PollTaskQueue;
  dcl-pi *n;
  end-pi;

  dcl-s rc int(10);
  // simple keyed read: read next NEW or scheduled task
  // We'll scan sequentially for simplicity
  read ORCTASK;
  dow not %eof(ORCTASK);
    // map file fields into TaskRec
    TaskRec.TaskId = ORCTASK.TaskId;
    TaskRec.CreatedTs = ORCTASK.CreatedTs;
    TaskRec.Source = ORCTASK.Source;
    TaskRec.Channel = ORCTASK.Channel;
    TaskRec.Backend = ORCTASK.Backend;
    TaskRec.Payload = ORCTASK.Payload;
    TaskRec.PayloadLen = ORCTASK.PayloadLen;
    TaskRec.Status = ORCTASK.Status;
    TaskRec.RetryCount = ORCTASK.RetryCount;
    TaskRec.NextAttemptTs = ORCTASK.NextAttemptTs;
    TaskRec.LastError = ORCTASK.LastError;

    // eligible?
    if TaskRec.Status = 'NEW' or (TaskRec.Status = 'FAIL' and TaskRec.RetryCount < OrcConfig.MaxRetries and TaskRec.NextAttemptTs <= %timestamp());
      // enqueue if space
      if TaskQueue_Count < %elem(TaskQueue_TaskId);
        TaskQueue_Count = TaskQueue_Count + 1;
        TaskQueue_TaskId(TaskQueue_Count) = TaskRec.TaskId;
      endif;
    endif;

    read ORCTASK;
  enddo;

end-proc;

/* ProcessTask: core orchestration for a single task */
dcl-proc ProcessTask;
  dcl-pi *n;
    pTaskRec likeds(TaskRec) const;
  end-pi;

  dcl-s backend char(16);
  dcl-s payload char(1024);
  dcl-s payloadLen packed(9:0);
  dcl-s status char(8);
  dcl-s outRsp char(1024);
  dcl-s outLen packed(9:0);
  dcl-s prpgStatus char(8);

  // mark INPROG
  TaskRec.Status = 'INPROG';
  update ORCTASK;

  // determine backend
  backend = %trim(TaskRec.Backend);
  if backend = *blanks;
    backend = OrcConfig.DefaultBackend;
  endif;

  payload = TaskRec.Payload;
  payloadLen = TaskRec.PayloadLen;

  // idempotency: check audit for prior success (simple scan)
  // (In production, use a proper idempotency store)
  chain TaskRec.TaskId ORCAUD;
  if %found(ORCAUD);
    // if there is a success audit, skip
    if ORCAUD.EventCode = 'TASK_OK';
      // mark DONE
      TaskRec.Status = 'DONE';
      update ORCTASK;
      return;
    endif;
  endif;

  // dispatch
  if not DispatchToBackend(backend : payload : payloadLen : outRsp : outLen);
    // failed to call backend
    TaskRec.Status = 'FAIL';
    TaskRec.RetryCount = TaskRec.RetryCount + 1;
    TaskRec.LastError = 'BACKEND_CALL_FAIL';
    // schedule next attempt
    TaskRec.NextAttemptTs = %timestamp() + %seconds(OrcConfig.BaseBackoffSec * TaskRec.RetryCount);
    update ORCTASK;
    WriteAudit(TaskRec.TaskId : 'TASK_FAIL' : 'Backend call failed');
    LogMsg('ERROR' : 'Task ' + %char(TaskRec.TaskId) + ' backend call failed');
    return;
  endif;

  // interpret backend response (assume JSON-like "status":"ok" or "status":"error")
  dcl-s rspStatus char(8);
  rspStatus = JsonGetField(outRsp : 'status');
  if %trim(rspStatus) = 'ok';
    TaskRec.Status = 'DONE';
    update ORCTASK;
    WriteAudit(TaskRec.TaskId : 'TASK_OK' : 'Completed successfully');
    LogMsg('INFO' : 'Task ' + %char(TaskRec.TaskId) + ' completed OK');
  else;
    TaskRec.Status = 'FAIL';
    TaskRec.RetryCount = TaskRec.RetryCount + 1;
    TaskRec.LastError = JsonGetField(outRsp : 'error');
    TaskRec.NextAttemptTs = %timestamp() + %seconds(OrcConfig.BaseBackoffSec * TaskRec.RetryCount);
    update ORCTASK;
    WriteAudit(TaskRec.TaskId : 'TASK_FAIL' : %trim(TaskRec.LastError));
    LogMsg('WARN' : 'Task ' + %char(TaskRec.TaskId) + ' failed: ' + %trim(TaskRec.LastError));
  endif;

end-proc;

/* DispatchToBackend: call PRPG glue to invoke backend */
dcl-proc DispatchToBackend;
  dcl-pi *n ind;
    pBackend char(16) const;
    pIrPayload char(1024) const;
    pIrLen packed(9:0) const;
    pOutRsp char(1024);
    pOutLen packed(9:0);
  end-pi;

  dcl-s status char(8);
  dcl-s rspLen packed(9:0);

  // choose transport: PRPG_CallBackend
  PRPG_CallBackend(%trim(pBackend) : pIrPayload : pIrLen : pOutRsp : rspLen : status);

  if status = 'OK';
    pOutLen = rspLen;
    return *on;
  else;
    pOutLen = 0;
    return *off;
  endif;

end-proc;

/* WriteAudit: append to ORCAUD */
dcl-proc WriteAudit;
  dcl-pi *n;
    pTaskId packed(15:0) const;
    pEvent char(8) const;
    pDetail char(256) const;
  end-pi;

  dcl-s audSeq packed(9:0) inz(0);

  ORCAUD.TaskId = pTaskId;
  ORCAUD.AuditSeq = audSeq;
  ORCAUD.EventCode = pEvent;
  ORCAUD.EventTs = %timestamp();
  ORCAUD.Detail = pDetail;
  write ORCAUD;

end-proc;

/* LogMsg: write to ORCLOG */
dcl-proc LogMsg;
  dcl-pi *n;
    pLevel char(6) const;
    pMsg char(256) const;
  end-pi;

  ORCLOG.LogTs = %timestamp();
  ORCLOG.Level = pLevel;
  ORCLOG.Message = pMsg;
  write ORCLOG;

end-proc;

/* Small sleep wrapper (call OS sleep) */
dcl-pr sleep extpgm('sleep');
  seconds int(10) const;
end-pr;

/* ---------------------------------------------------------------------
   Example: Local backend adapter (COBOL backend via PRPG glue)
   You can also implement local direct calls to RPGLE/CALLP if backends
   are service programs in the same LPAR.
   --------------------------------------------------------------------- */

dcl-proc LocalCobolAdapter;
  dcl-pi *n ind;
    pReq char(1024) const;
    pReqLen packed(9:0) const;
    pRsp char(1024);
    pRspLen packed(9:0);
  end-pi;

  dcl-s status char(8);

  // call PRPG glue to invoke COBOL program LEDGWYCB or LEDGWYRPG
  PRPG_CallBackend('COBOL' : pReq : pReqLen : pRsp : pRspLen : status);

  if status = 'OK';
    return *on;
  else;
    return *off;
  endif;

end-proc;

/* ---------------------------------------------------------------------
   Minimal Funnel IR dispatcher (parse a tiny IR and route)
   IR format (compact JSON-like):
   { "op":"return_item", "backend":"COBOL", "payload":{...} }
   --------------------------------------------------------------------- */

dcl-proc ParseIrAndRoute;
  dcl-pi *n ind;
    pPayload char(1024) const;
    pPayloadLen packed(9:0) const;
    pBackend char(16);
    pOp char(64);
  end-pi;

  dcl-s op char(64);
  dcl-s backend char(16);

  op = JsonGetField(pPayload : 'op');
  backend = JsonGetField(pPayload : 'backend');
  if op = *blanks;
    op = 'unknown';
  endif;
  if backend = *blanks;
    backend = OrcConfig.DefaultBackend;
  endif;

  pBackend = backend;
  pOp = op;

  return *on;
end-proc;

/* ---------------------------------------------------------------------
   Example: Task enqueue helper (could be called by external programs)
   Accepts a JSON payload and writes ORCTASK record with NEW status
   --------------------------------------------------------------------- */
dcl-proc EnqueueTask;
  dcl-pi *n;
    pSource char(32) const;
    pChannel char(32) const;
    pBackend char(16) const;
    pPayload char(1024) const;
    pPayloadLen packed(9:0) const;
    pOutTaskId packed(15:0);
  end-pi;

  dcl-s newId packed(15:0);
  dcl-s rc int(10);

  // simple id allocator: use timestamp low bits
  newId = %int(%char(%timestamp():*ISO) : 15);
  ORCTASK.TaskId = newId;
  ORCTASK.CreatedTs = %timestamp();
  ORCTASK.Source = pSource;
  ORCTASK.Channel = pChannel;
  ORCTASK.Backend = pBackend;
  ORCTASK.Payload = pPayload;
  ORCTASK.PayloadLen = pPayloadLen;
  ORCTASK.Status = 'NEW';
  ORCTASK.RetryCount = 0;
  ORCTASK.NextAttemptTs = %timestamp();
  ORCTASK.LastError = *blanks;

  write ORCTASK;

  pOutTaskId = newId;

end-proc;

/* ---------------------------------------------------------------------
   Example: Simple admin entry to trigger a single task processing
   Useful for debugging and unit tests
   --------------------------------------------------------------------- */
dcl-proc AdminProcessOne;
  dcl-pi *n;
    pTaskId packed(15:0) const;
  end-pi;

  TaskRec.TaskId = pTaskId;
  chain TaskRec.TaskId ORCTASK;
  if %found(ORCTASK);
    ProcessTask(TaskRec);
  endif;

end-proc;

/* ---------------------------------------------------------------------
   End of service program
   --------------------------------------------------------------------- */

*inlr = *on;
return;