**free
ctl-opt dftactgrp(*no) actgrp('LEDGER') option(*srcstmt : *nodebugio);

/* 128-byte request/response blocks */

dcl-ds dsReqBlock qualified;
  Company      char(3);
  LedgerDate   char(8);
  LedgerSeqChr char(9);
  UserId       char(10);
  ReasonCode   char(4);
  Channel      char(8);
  RailCode     char(8);
  Reserved     char(78);
end-ds;

dcl-ds dsRspBlock qualified;
  Success      char(1);
  ErrorCode    char(8);
  ErrorMsg     char(80);
  NewSeqChr    char(9);
  Reserved     char(30);
end-ds;

/* Existing reversal API structures */

dcl-ds dsReverseReq qualified;
  Company      char(3);
  LedgerDate   char(8);
  LedgerSeq    packed(9:0);
  UserId       char(10);
  ReasonCode   char(4);
  Channel      char(8);
end-ds;

dcl-ds dsReverseRsp qualified;
  Success      ind;
  ErrorCode    char(8);
  ErrorMsg     char(128);
  NewLedgerSeq packed(9:0);
end-ds;

dcl-pr LED_ReverseEntry extpgm('LEDREVSRV');
  pReq likeds(dsReverseReq) const;
  pRsp likeds(dsReverseRsp);
end-pr;

/* Binary gateway entry */

dcl-pr LEDGWYRPG extpgm('LEDGWYRPG');
  pReqBlock char(128) const;
  pRspBlock char(128);
end-pr;

dcl-pi LEDGWYRPG;
  pReqBlock char(128) const;
  pRspBlock char(128);
end-pi;

dcl-s nSeq packed(9:0);

/* Unpack request block */
dsReqBlock = pReqBlock;

dsReverseReq.Company    = dsReqBlock.Company;
dsReverseReq.LedgerDate = dsReqBlock.LedgerDate;
dsReverseReq.UserId     = dsReqBlock.UserId;
dsReverseReq.ReasonCode = dsReqBlock.ReasonCode;
dsReverseReq.Channel    = dsReqBlock.Channel;

/* Convert ASCII numeric sequence */
if %check('0123456789' : dsReqBlock.LedgerSeqChr) = 0;
  nSeq = %int(%dec(dsReqBlock.LedgerSeqChr : 9 : 0));
else;
  nSeq = 0;
endif;

dsReverseReq.LedgerSeq = nSeq;

/* Call core reversal engine */
LED_ReverseEntry(dsReverseReq : dsReverseRsp);

/* Pack response block */
if dsReverseRsp.Success;
  dsRspBlock.Success = 'Y';
else;
  dsRspBlock.Success = 'N';
endif;

dsRspBlock.ErrorCode = dsReverseRsp.ErrorCode;
dsRspBlock.ErrorMsg  = %subst(dsReverseRsp.ErrorMsg : 1 : 80);

dsRspBlock.NewSeqChr = %editc(dsReverseRsp.NewLedgerSeq : 'X');
dsRspBlock.Reserved  = *blanks;

/* Return as 128-byte char */
pRspBlock = %subst(%char(dsRspBlock) : 1 : 128);

*inlr = *on;
return;
