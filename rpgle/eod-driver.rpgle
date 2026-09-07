**free
ctl-opt dftactgrp(*no) actgrp('EOD') option(*srcstmt:*nodebugio);

dcl-f EOD_RUNS keyed usage(*update) extdesc('EOD_RUNS');
dcl-f ACH_BATCHES keyed usage(*update) extdesc('ACH_BATCHES');
dcl-f ERROR_QUEUE keyed usage(*output) extdesc('ERROR_QUEUE');

dcl-s runId packed(15:0);
dcl-s runDate date;
dcl-s sqlState char(5);

dcl-proc EODDrive;
  dcl-pi *n;
  end-pi;

  runDate = %date();

  exec sql set option commit = *chg, usingsqlca = *yes;

  exec sql
    insert into EOD_RUNS (RUN_DATE, STARTED_AT, STATUS)
    values (:runDate, current_timestamp, 'RUNNING');

  exec sql select RUN_ID into :runId from EOD_RUNS
    where STARTED_AT = (select max(STARTED_AT) from EOD_RUNS);

  // 1. Finalize pending journals older than today
  callp FinalizePendingJournals(runDate:runId);

  // 2. Age holds
  callp AgeHolds(runDate:runId);

  // 3. Post settlement notifications from rail notifications
  callp PostRailSettlements(runDate:runId);

  // 4. Run reconciliation
  callp RunReconciliation(runDate:runId);

  exec sql
    update EOD_RUNS set FINISHED_AT = current_timestamp, STATUS = 'COMPLETED'
     where RUN_ID = :runId;

  commit;
end-proc;

dcl-proc FinalizePendingJournals;
  dcl-pi *n;
    pRunDate date const;
    pRunId packed(15:0) const;
  end-pi;

  dcl-s jId packed(15:0);
  exec sql
    declare C_J cursor for
      select JOURNAL_ID from JOURNALS
       where STATUS = 'PENDING' and EFFECTIVE_DATE <= :pRunDate
       for update;

  exec sql open C_J;
  dou sqlcode <> 0;
     exec sql fetch C_J into :jId;
     if sqlcode <> 0; leave; endif;
     callp PostJournalById(jId);
  enddo;
  exec sql close C_J;
end-proc;

dcl-proc AgeHolds;
  dcl-pi *n;
    pRunDate date const;
    pRunId packed(15:0) const;
  end-pi;

  exec sql
    update HOLDS set STATUS = 'EXPIRED', RELEASED_AT = current_timestamp
     where STATUS = 'ACTIVE' and RELEASED_AT <= :pRunDate;

  if sqlcode <> 0;
     LogError('EOD':'AGE_HOLDS':pRunId:sqlstate);
     rollback;
     return;
  endif;
end-proc;

dcl-proc PostRailSettlements;
  dcl-pi *n;
    pRunDate date const;
    pRunId packed(15:0) const;
  end-pi;

  dcl-s notifId packed(15:0);
  exec sql
    declare C_R cursor for
      select NOTIF_ID from RAIL_NOTIFICATIONS
       where TYPE = 'SETTLEMENT' and RECEIVED_AT <= current_timestamp
       for update;

  exec sql open C_R;
  dou sqlcode <> 0;
     exec sql fetch C_R into :notifId;
     if sqlcode <> 0; leave; endif;
     callp ApplyRailSettlement(notifId);
  enddo;
  exec sql close C_R;
end-proc;

dcl-proc RunReconciliation;
  dcl-pi *n;
    pRunDate date const;
    pRunId packed(15:0) const;
  end-pi;

  callp ReconcileDay(pRunDate:pRunId);
end-proc;
