**free
ctl-opt dftactgrp(*no) actgrp('AGHENTS') bnddir('PRPGBNDDIR') option(*srcstmt : *nodebugio);

/**********************************************************************
 AGHENTSC - Agent Scheduler (RPGLE)
 - Manages scheduled and recurring agent tasks
 - Drives ORCGHSTROTR via task queue
 - Implements:
    * Cron-like schedule evaluation
    * One-shot deferred tasks
    * Schedule lifecycle (pause, resume, delete)
    * Audit trail for schedule events
**********************************************************************/

/* Files */
dcl-f AGSCHED   usage(*update : *input : *output) keyed extfile('AGSCHED') usropn;
dcl-f AGSCHEDAUD usage(*output) keyed extfile('AGSCHEDAUD') usropn;

/* PRPG glue: call orchestrator to enqueue a task */
dcl-pr PRPG_SendMessage extpgm('PRPG_SENDMSG');
  pChannel char(32) const;
  pPayload char(1024) const;
  pLen packed(9:0) const;
  pStatus char(8);
end-pr;

/* Schedule record */
dcl-ds SchedRec qualified;
  SchedId        packed(15:0);
  AgentName      char(32);
  CronExpr       char(64);  // simple: "MMHHDDMoDy" pattern or blank for one-shot
  NextRunTs      timestamp;
  IntervalSec    packed(9:0);
  Enabled        char(1);   // 'Y' or 'N'
  Backend        char(16);
  Payload        char(1024);
  PayloadLen     packed(9:0);
  LastRunTs      timestamp;
  LastStatus     char(8);
  RunCount       packed(9:0);
  MaxRuns        packed(9:0);  // 0 = unlimited
  CreatedTs      timestamp;
  UpdatedTs      timestamp;
end-ds;

/* Audit record */
dcl-ds SchedAudRec qualified;
  SchedId        packed(15:0);
  AuditSeq       packed(9:0);
  EventCode      char(8);   // SCHED_ADD, SCHED_RUN, SCHED_FAIL, SCHED_DEL, SCHED_PAUSE, SCHED_RESUME
  EventTs        timestamp;
  Detail         char(256);
end-ds;

/* Config */
dcl-ds SchedConfig qualified inz;
  PollIntervalSec packed(5:0) inz(30);
  MaxConcurrent   packed(3:0) inz(10);
end-ds;

/* Prototype: public entry */
dcl-pr AgentSchedulerMain extpgm('AGHENTSC');
end-pr;

dcl-pr ScheduleAdd extpgm(*proc) ind;
  pAgentName char(32) const;
  pCronExpr char(64) const;
  pIntervalSec packed(9:0) const;
  pBackend char(16) const;
  pPayload char(1024) const;
  pPayloadLen packed(9:0) const;
  pSchedId packed(15:0);
end-pr;

dcl-pr ScheduleRun extpgm(*proc) ind;
  pSchedId packed(15:0) const;
end-pr;

dcl-pr ScheduleDelete extpgm(*proc) ind;
  pSchedId packed(15:0) const;
end-pr;

dcl-pr SchedulePause extpgm(*proc) ind;
  pSchedId packed(15:0) const;
end-pr;

dcl-pr ScheduleResume extpgm(*proc) ind;
  pSchedId packed(15:0) const;
end-pr;

/* Log audit */
dcl-proc WriteSchedAudit;
  dcl-pi *n;
    pSchedId packed(15:0) const;
    pEvent char(8) const;
    pDetail char(256) const;
  end-pi;

  SchedAudRec.SchedId = pSchedId;
  SchedAudRec.AuditSeq = 0; // identity/trigger
  SchedAudRec.EventCode = pEvent;
  SchedAudRec.EventTs = %timestamp();
  SchedAudRec.Detail = pDetail;

  AGSCHEDAUD.SchedId = SchedAudRec.SchedId;
  AGSCHEDAUD.AuditSeq = SchedAudRec.AuditSeq;
  AGSCHEDAUD.EventCode = SchedAudRec.EventCode;
  AGSCHEDAUD.EventTs = SchedAudRec.EventTs;
  AGSCHEDAUD.Detail = SchedAudRec.Detail;
  write AGSCHEDAUD;
end-proc;

/* Evaluate simple cron: returns *on if schedule should run at given ts */
dcl-proc EvalCronSimple;
  dcl-pi *n ind;
    pCronExpr char(64) const;
    pTs timestamp const;
  end-pi;

  /* Simple cron: "MMHHDDMoDy" — each 2-char field is "xx" for any,
     or numeric. For simplicity we only check minute and hour. */
  dcl-s cronMin  char(2);
  dcl-s cronHour char(2);
  dcl-s tsMin    char(2);
  dcl-s tsHour   char(2);

  if %len(%trim(pCronExpr)) < 4;
    return *on; // invalid cron => always run (one-shot style)
  endif;

  cronMin  = %subst(pCronExpr:1:2);
  cronHour = %subst(pCronExpr:3:2);

  tsMin  = %char(%subdt(pTs:*MIN));
  tsHour = %char(%subdt(pTs:*HOUR));

  // pad with leading zero
  if %len(%trim(tsMin)) < 2;
    tsMin = '0' + %trim(tsMin);
  endif;
  if %len(%trim(tsHour)) < 2;
    tsHour = '0' + %trim(tsHour);
  endif;

  if cronMin <> 'xx' and cronMin <> tsMin;
    return *off;
  endif;
  if cronHour <> 'xx' and cronHour <> tsHour;
    return *off;
  endif;

  return *on;
end-proc;

/* ScheduleAdd: create a new schedule entry */
dcl-proc ScheduleAdd;
  dcl-pi *n ind;
    pAgentName char(32) const;
    pCronExpr char(64) const;
    pIntervalSec packed(9:0) const;
    pBackend char(16) const;
    pPayload char(1024) const;
    pPayloadLen packed(9:0) const;
    pSchedId packed(15:0);
  end-pi;

  dcl-s newId packed(15:0);

  // simple ID: timestamp low bits
  newId = %int(%char(%timestamp():*ISO) : 15);
  pSchedId = newId;

  AGSCHED.SchedId = newId;
  AGSCHED.AgentName = pAgentName;
  AGSCHED.CronExpr = pCronExpr;
  AGSCHED.NextRunTs = %timestamp();
  AGSCHED.IntervalSec = pIntervalSec;
  AGSCHED.Enabled = 'Y';
  AGSCHED.Backend = pBackend;
  AGSCHED.Payload = pPayload;
  AGSCHED.PayloadLen = pPayloadLen;
  AGSCHED.LastRunTs = %timestamp('0001-01-01-00.00.00.000000');
  AGSCHED.LastStatus = 'PENDING';
  AGSCHED.RunCount = 0;
  AGSCHED.MaxRuns = 0;
  AGSCHED.CreatedTs = %timestamp();
  AGSCHED.UpdatedTs = %timestamp();

  write AGSCHED;

  WriteSchedAudit(newId : 'SCHED_ADD' : 'Agent=' + %trim(pAgentName));

  return *on;
end-proc;

/* ScheduleRun: trigger immediate execution of a schedule */
dcl-proc ScheduleRun;
  dcl-pi *n ind;
    pSchedId packed(15:0) const;
  end-pi;

  AGSCHED.SchedId = pSchedId;
  chain AGSCHED.SchedId AGSCHED;
  if not %found(AGSCHED);
    return *off;
  endif;

  if AGSCHED.Enabled <> 'Y';
    return *off;
  endif;

  // enqueue task via PRPG
  dcl-s status char(8);
  PRPG_SendMessage('ORCHESTRATOR' : AGSCHED.Payload : AGSCHED.PayloadLen : status);

  if status = 'OK';
    AGSCHED.LastRunTs = %timestamp();
    AGSCHED.LastStatus = 'RUNNING';
    AGSCHED.RunCount = AGSCHED.RunCount + 1;
    AGSCHED.UpdatedTs = %timestamp();

    // compute next run
    if AGSCHED.IntervalSec > 0;
      AGSCHED.NextRunTs = %timestamp() + %seconds(AGSCHED.IntervalSec);
    endif;

    update AGSCHED;
    WriteSchedAudit(pSchedId : 'SCHED_RUN' : 'Enqueued OK');
    return *on;
  else;
    AGSCHED.LastStatus = 'FAIL';
    AGSCHED.UpdatedTs = %timestamp();
    update AGSCHED;
    WriteSchedAudit(pSchedId : 'SCHED_FAIL' : 'PRPG enqueue failed');
    return *off;
  endif;

end-proc;

/* ScheduleDelete: remove a schedule */
dcl-proc ScheduleDelete;
  dcl-pi *n ind;
    pSchedId packed(15:0) const;
  end-pi;

  AGSCHED.SchedId = pSchedId;
  chain AGSCHED.SchedId AGSCHED;
  if not %found(AGSCHED);
    return *off;
  endif;

  delete AGSCHED;
  WriteSchedAudit(pSchedId : 'SCHED_DEL' : 'Deleted');
  return *on;
end-proc;

/* SchedulePause: disable a schedule */
dcl-proc SchedulePause;
  dcl-pi *n ind;
    pSchedId packed(15:0) const;
  end-pi;

  AGSCHED.SchedId = pSchedId;
  chain AGSCHED.SchedId AGSCHED;
  if not %found(AGSCHED);
    return *off;
  endif;

  AGSCHED.Enabled = 'N';
  AGSCHED.UpdatedTs = %timestamp();
  update AGSCHED;
  WriteSchedAudit(pSchedId : 'SCHED_PAUSE' : 'Paused');
  return *on;
end-proc;

/* ScheduleResume: re-enable a schedule */
dcl-proc ScheduleResume;
  dcl-pi *n ind;
    pSchedId packed(15:0) const;
  end-pi;

  AGSCHED.SchedId = pSchedId;
  chain AGSCHED.SchedId AGSCHED;
  if not %found(AGSCHED);
    return *off;
  endif;

  AGSCHED.Enabled = 'Y';
  AGSCHED.UpdatedTs = %timestamp();
  update AGSCHED;
  WriteSchedAudit(pSchedId : 'SCHED_RESUME' : 'Resumed');
  return *on;
end-proc;

/* Main loop: poll schedule file, evaluate, run due schedules */
dcl-proc AgentSchedulerMain;
  dcl-pi *n;
  end-pi;

  open AGSCHED;
  open AGSCHEDAUD;

  dow '1' = '1';
    // scan all schedules
    read AGSCHED;
    dow not %eof(AGSCHED);
      if AGSCHED.Enabled = 'Y'
         and AGSCHED.NextRunTs <= %timestamp()
         and (AGSCHED.MaxRuns = 0 or AGSCHED.RunCount < AGSCHED.MaxRuns);

        // evaluate cron (if present)
        if %len(%trim(AGSCHED.CronExpr)) > 0;
          if not EvalCronSimple(AGSCHED.CronExpr : %timestamp());
            // not due by cron; skip (next run stays at interval)
            // no update needed
          else;
            ScheduleRun(AGSCHED.SchedId);
          endif;
        else;
          // one-shot or interval: run if past due
          ScheduleRun(AGSCHED.SchedId);
        endif;
      endif;

      read AGSCHED;
    enddo;

    // sleep
    callp sleep(SchedConfig.PollIntervalSec);
  enddo;

  *inlr = *on;
end-proc;