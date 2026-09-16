**free
ctl-opt
  dftactgrp(*no)
  actgrp('LEDGER')
  bnddir('LEDGERBNDDIR')
  option(*srcstmt : *nodebugio)
  alwnull(*usrctl);

/*********************************************************************/
/*  LEDREVSRV - Ledger Reversal Service Program                      */
/*                                                                   */
/*  Responsibilities:                                                */
/*   - Validate original ledger entry for reversal eligibility       */
/*   - Enforce idempotency (no double reversal)                      */
/*   - Create balanced reversal entry                                */
/*   - Persist reversal + audit trail                                */
/*   - Return status + error codes to caller                         */
/*********************************************************************/

/*-------------------------------------------------------------------*/
/*  Data structures: external formats for LEDGER and LEDGER_AUD      */
/*-------------------------------------------------------------------*/

dcl-f LEDGER    keyed usage(*update : *input : *output)
                extdesc('LEDGER') extfile('LEDGER')
                usropn;

dcl-f LEDGER_AUD keyed usage(*output)
                extdesc('LEDGER_AUD') extfile('LEDGER_AUD')
                usropn;

/* Key structure for LEDGER (example) */
dcl-ds dsLedgerKey qualified;
  Company        char(3);
  LedgerDate     char(8);   // YYYYMMDD
  LedgerSeq      packed(9:0);
end-ds;

/* Core ledger record (simplified example) */
dcl-ds dsLedgerRec qualified;
  Company        char(3);
  LedgerDate     char(8);
  LedgerSeq      packed(9:0);
  TxnId          char(36);
  TxnType        char(4);
  DrCrFlag       char(1);   // 'D' or 'C'
  Amount         packed(15:2);
  Currency       char(3);
  Status         char(1);   // 'N'=Normal, 'R'=Reversed, 'X'=Cancelled
  ParentSeq      packed(9:0); // link to original if this is reversal
  BookTs         timestamp;
  PostTs         timestamp;
  Channel        char(8);
  RailCode       char(8);
  UserId         char(10);
  ReversalCode   char(4);   // reason code
  ReversalTs     timestamp;
end-ds;

/* Audit record */
dcl-ds dsAuditRec qualified;
  Company        char(3);
  LedgerDate     char(8);
  LedgerSeq      packed(9:0);
  AuditSeq       packed(9:0);
  EventCode      char(8);   // 'REV_REQ','REV_POST','REV_FAIL'
  EventTs        timestamp;
  TxnId          char(36);
  UserId         char(10);
  ReasonCode     char(4);
  Detail         char(256);
end-ds;

/*-------------------------------------------------------------------*/
/*  Public API: LED_ReverseEntry                                     */
/*-------------------------------------------------------------------*/

/* Request structure */
dcl-ds dsReverseReq qualified;
  Company        char(3);
  LedgerDate     char(8);
  LedgerSeq      packed(9:0);
  UserId         char(10);
  ReasonCode     char(4);
  Channel        char(8);
end-ds;

/* Response structure */
dcl-ds dsReverseRsp qualified;
  Success        ind;
  ErrorCode      char(8);   // 'OK','NOTFOUND','ALREADYREV','BADSTATE','DBERR','VALERR'
  ErrorMsg       char(128);
  NewLedgerSeq   packed(9:0);
end-ds;

/* Prototype */
dcl-pr LED_ReverseEntry extpgm('LEDREVSRV');
  pReq        likeds(dsReverseReq) const;
  pRsp        likeds(dsReverseRsp);
end-pr;

/* Implementation */
dcl-pi LED_ReverseEntry;
  pReq        likeds(dsReverseReq) const;
  pRsp        likeds(dsReverseRsp);
end-pi;

/*-------------------------------------------------------------------*/
/*  Local procedures                                                 */
/*-------------------------------------------------------------------*/

dcl-proc InitResponse;
  dcl-pi *n;
    req        likeds(dsReverseReq) const;
    rsp        likeds(dsReverseRsp);
  end-pi;

  rsp.Success    = *off;
  rsp.ErrorCode  = 'OK';
  rsp.ErrorMsg   = *blanks;
  rsp.NewLedgerSeq = 0;
end-proc;

dcl-proc LoadOriginalEntry;
  dcl-pi *n ind;
    req        likeds(dsReverseReq) const;
    rec        likeds(dsLedgerRec);
  end-pi;

  dsLedgerKey.Company    = req.Company;
  dsLedgerKey.LedgerDate = req.LedgerDate;
  dsLedgerKey.LedgerSeq  = req.LedgerSeq;

  chain dsLedgerKey LEDGER;
  if not %found(LEDGER);
    return *off;
  endif;

  rec.Company      = LEDGER.Company;
  rec.LedgerDate   = LEDGER.LedgerDate;
  rec.LedgerSeq    = LEDGER.LedgerSeq;
  rec.TxnId        = LEDGER.TxnId;
  rec.TxnType      = LEDGER.TxnType;
  rec.DrCrFlag     = LEDGER.DrCrFlag;
  rec.Amount       = LEDGER.Amount;
  rec.Currency     = LEDGER.Currency;
  rec.Status       = LEDGER.Status;
  rec.ParentSeq    = LEDGER.ParentSeq;
  rec.BookTs       = LEDGER.BookTs;
  rec.PostTs       = LEDGER.PostTs;
  rec.Channel      = LEDGER.Channel;
  rec.RailCode     = LEDGER.RailCode;
  rec.UserId       = LEDGER.UserId;
  rec.ReversalCode = LEDGER.ReversalCode;
  rec.ReversalTs   = LEDGER.ReversalTs;

  return *on;
end-proc;

dcl-proc ValidateReversalEligibility;
  dcl-pi *n ind;
    origRec    likeds(dsLedgerRec) const;
    rsp        likeds(dsReverseRsp);
  end-pi;

  select;
  when origRec.Status = 'R';
    rsp.ErrorCode = 'ALREADYREV';
    rsp.ErrorMsg  = 'Entry already reversed.';
    return *off;

  when origRec.Status = 'X';
    rsp.ErrorCode = 'BADSTATE';
    rsp.ErrorMsg  = 'Entry cancelled; reversal not allowed.';
    return *off;

  other;
    // OK for now; you can add more rules (age, rail, etc.)
  endsl;

  if origRec.Amount = 0;
    rsp.ErrorCode = 'VALERR';
    rsp.ErrorMsg  = 'Zero-amount entry cannot be reversed.';
    return *off;
  endif;

  return *on;
end-proc;

dcl-proc BuildReversalEntry;
  dcl-pi *n;
    req        likeds(dsReverseReq) const;
    origRec    likeds(dsLedgerRec) const;
    revRec     likeds(dsLedgerRec);
  end-pi;

  revRec = origRec;

  // New sequence will be assigned by DB trigger or separate allocator
  revRec.LedgerSeq    = 0;
  revRec.ParentSeq    = origRec.LedgerSeq;
  revRec.Status       = 'N';
  revRec.ReversalCode = req.ReasonCode;
  revRec.ReversalTs   = %timestamp();

  // Flip DR/CR and keep amount
  select;
  when origRec.DrCrFlag = 'D';
    revRec.DrCrFlag = 'C';
  when origRec.DrCrFlag = 'C';
    revRec.DrCrFlag = 'D';
  other;
    // Unknown flag; caller should have validated, but we guard anyway
    revRec.DrCrFlag = origRec.DrCrFlag;
  endsl;

  // Channel/User for reversal
  revRec.Channel = req.Channel;
  revRec.UserId  = req.UserId;

end-proc;

dcl-proc PersistReversal;
  dcl-pi *n ind;
    revRec     likeds(dsLedgerRec);
    newSeq     packed(9:0);
  end-pi;

  monitor;
    // Write reversal entry
    LEDGER.Company      = revRec.Company;
    LEDGER.LedgerDate   = revRec.LedgerDate;
    LEDGER.LedgerSeq    = revRec.LedgerSeq; // 0 if auto-assigned
    LEDGER.TxnId        = revRec.TxnId;
    LEDGER.TxnType      = revRec.TxnType;
    LEDGER.DrCrFlag     = revRec.DrCrFlag;
    LEDGER.Amount       = revRec.Amount;
    LEDGER.Currency     = revRec.Currency;
    LEDGER.Status       = revRec.Status;
    LEDGER.ParentSeq    = revRec.ParentSeq;
    LEDGER.BookTs       = %timestamp();
    LEDGER.PostTs       = %timestamp();
    LEDGER.Channel      = revRec.Channel;
    LEDGER.RailCode     = revRec.RailCode;
    LEDGER.UserId       = revRec.UserId;
    LEDGER.ReversalCode = revRec.ReversalCode;
    LEDGER.ReversalTs   = revRec.ReversalTs;

    write LEDGER;

    // If sequence is assigned by identity/trigger, re-read
    dsLedgerKey.Company    = LEDGER.Company;
    dsLedgerKey.LedgerDate = LEDGER.LedgerDate;
    dsLedgerKey.LedgerSeq  = LEDGER.LedgerSeq;

    chain dsLedgerKey LEDGER;
    if %found(LEDGER);
      newSeq = LEDGER.LedgerSeq;
    else;
      newSeq = revRec.LedgerSeq;
    endif;

    return *on;

  on-error;
    return *off;
  endmon;

end-proc;

dcl-proc MarkOriginalAsReversed;
  dcl-pi *n ind;
    origRec    likeds(dsLedgerRec);
    reason     char(4) const;
  end-pi;

  dsLedgerKey.Company    = origRec.Company;
  dsLedgerKey.LedgerDate = origRec.LedgerDate;
  dsLedgerKey.LedgerSeq  = origRec.LedgerSeq;

  chain dsLedgerKey LEDGER;
  if not %found(LEDGER);
    return *off;
  endif;

  LEDGER.Status       = 'R';
  LEDGER.ReversalCode = reason;
  LEDGER.ReversalTs   = %timestamp();

  update LEDGER;

  return *on;
end-proc;

dcl-proc WriteAuditEvent;
  dcl-pi *n ind;
    company     char(3) const;
    ledgerDate  char(8) const;
    ledgerSeq   packed(9:0) const;
    eventCode   char(8) const;
    userId      char(10) const;
    reasonCode  char(4) const;
    detail      char(256) const;
  end-pi;

  monitor;
    dsAuditRec.Company    = company;
    dsAuditRec.LedgerDate = ledgerDate;
    dsAuditRec.LedgerSeq  = ledgerSeq;
    dsAuditRec.AuditSeq   = 0; // identity/trigger or separate allocator
    dsAuditRec.EventCode  = eventCode;
    dsAuditRec.EventTs    = %timestamp();
    dsAuditRec.TxnId      = *blanks;
    dsAuditRec.UserId     = userId;
    dsAuditRec.ReasonCode = reasonCode;
    dsAuditRec.Detail     = detail;

    LEDGER_AUD.Company    = dsAuditRec.Company;
    LEDGER_AUD.LedgerDate = dsAuditRec.LedgerDate;
    LEDGER_AUD.LedgerSeq  = dsAuditRec.LedgerSeq;
    LEDGER_AUD.AuditSeq   = dsAuditRec.AuditSeq;
    LEDGER_AUD.EventCode  = dsAuditRec.EventCode;
    LEDGER_AUD.EventTs    = dsAuditRec.EventTs;
    LEDGER_AUD.TxnId      = dsAuditRec.TxnId;
    LEDGER_AUD.UserId     = dsAuditRec.UserId;
    LEDGER_AUD.ReasonCode = dsAuditRec.ReasonCode;
    LEDGER_AUD.Detail     = dsAuditRec.Detail;

    write LEDGER_AUD;

    return *on;

  on-error;
    return *off;
  endmon;

end-proc;

/*-------------------------------------------------------------------*/
/*  Main entry: LED_ReverseEntry                                     */
/*-------------------------------------------------------------------*/

dcl-s origRec likeds(dsLedgerRec);
dcl-s revRec  likeds(dsLedgerRec);
dcl-s newSeq  packed(9:0);

InitResponse(pReq : pRsp);

/* Open files once per call; you can move to *INZSR if you prefer */
open LEDGER;
open LEDGER_AUD;

/* Load original entry */
if not LoadOriginalEntry(pReq : origRec);
  pRsp.ErrorCode = 'NOTFOUND';
  pRsp.ErrorMsg  = 'Original ledger entry not found.';
  WriteAuditEvent(pReq.Company : pReq.LedgerDate : pReq.LedgerSeq :
                  'REV_FAIL' : pReq.UserId : pReq.ReasonCode :
                  'Reversal failed: NOTFOUND');
  return;
endif;

/* Validate eligibility */
if not ValidateReversalEligibility(origRec : pRsp);
  WriteAuditEvent(pReq.Company : pReq.LedgerDate : pReq.LedgerSeq :
                  'REV_FAIL' : pReq.UserId : pReq.ReasonCode :
                  'Reversal failed: ' + %trim(pRsp.ErrorCode));
  return;
endif;

/* Build reversal entry */
BuildReversalEntry(pReq : origRec : revRec);

/* Persist reversal */
if not PersistReversal(revRec : newSeq);
  pRsp.ErrorCode = 'DBERR';
  pRsp.ErrorMsg  = 'Database error persisting reversal.';
  WriteAuditEvent(pReq.Company : pReq.LedgerDate : pReq.LedgerSeq :
                  'REV_FAIL' : pReq.UserId : pReq.ReasonCode :
                  'Reversal failed: DBERR');
  return;
endif;

/* Mark original as reversed */
if not MarkOriginalAsReversed(origRec : pReq.ReasonCode);
  // We already created reversal; flag but don't roll back here
  WriteAuditEvent(pReq.Company : pReq.LedgerDate : pReq.LedgerSeq :
                  'REV_FAIL' : pReq.UserId : pReq.ReasonCode :
                  'Original not marked reversed after reversal.');
endif;

/* Success path */
pRsp.Success      = *on;
pRsp.ErrorCode    = 'OK';
pRsp.ErrorMsg     = 'Reversal completed.';
pRsp.NewLedgerSeq = newSeq;

WriteAuditEvent(pReq.Company : pReq.LedgerDate : pReq.LedgerSeq :
                'REV_POST' : pReq.UserId : pReq.ReasonCode :
                'Reversal posted; new seq=' + %editc(newSeq : 'X'));

*inlr = *on;
return;
