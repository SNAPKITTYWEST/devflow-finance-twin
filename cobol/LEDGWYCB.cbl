       IDENTIFICATION DIVISION.
       PROGRAM-ID. LEDGWYCB.
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       DATA DIVISION.
       WORKING-STORAGE SECTION.

       01 REQ-BLOCK.
           05 REQ-COMPANY        PIC X(3).
           05 REQ-LEDGER-DATE    PIC X(8).
           05 REQ-LEDGER-SEQ     PIC X(9).
           05 REQ-USER-ID        PIC X(10).
           05 REQ-REASON-CODE    PIC X(4).
           05 REQ-CHANNEL        PIC X(8).
           05 REQ-RAIL-CODE      PIC X(8).
           05 REQ-RESERVED       PIC X(78).

       01 RSP-BLOCK.
           05 RSP-SUCCESS        PIC X(1).
           05 RSP-ERROR-CODE     PIC X(8).
           05 RSP-ERROR-MSG      PIC X(80).
           05 RSP-NEW-LEDGER-SEQ PIC X(9).
           05 RSP-RESERVED       PIC X(30).

       LINKAGE SECTION.
       01 LK-REQ-BYTES         PIC X(128).
       01 LK-RSP-BYTES         PIC X(128).

       PROCEDURE DIVISION USING LK-REQ-BYTES LK-RSP-BYTES.
       MAIN-LOGIC.
           MOVE LK-REQ-BYTES TO REQ-BLOCK.

           *> Unpack and validate
           IF REQ-COMPANY = SPACES
              MOVE 'N' TO RSP-SUCCESS
              MOVE 'BADREQ' TO RSP-ERROR-CODE
              MOVE 'Missing company' TO RSP-ERROR-MSG
              MOVE SPACES TO RSP-NEW-LEDGER-SEQ
              MOVE RSP-BLOCK TO LK-RSP-BYTES
              GOBACK
           END-IF

           *> Placeholder: call internal COBOL/DB2 posting routine
           *> Here we simulate success and return a new ledger seq
           MOVE 'Y' TO RSP-SUCCESS
           MOVE 'OK' TO RSP-ERROR-CODE
           MOVE 'Reversal posted' TO RSP-ERROR-MSG
           MOVE '000001234' TO RSP-NEW-LEDGER-SEQ

           MOVE RSP-BLOCK TO LK-RSP-BYTES
           GOBACK.
