       IDENTIFICATION DIVISION.
       PROGRAM-ID. LEDGWYCB.
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. IBM-I.
       OBJECT-COMPUTER. IBM-I.

       DATA DIVISION.
       WORKING-STORAGE SECTION.

       01  WS-REQ-BLOCK-LEN          PIC 9(04) COMP VALUE 128.
       01  WS-RSP-BLOCK-LEN          PIC 9(04) COMP VALUE 128.

       01  WS-REQ-BLOCK.
           05 WR-COMPANY             PIC X(03).
           05 WR-LEDGER-DATE         PIC X(08).
           05 WR-LEDGER-SEQ          PIC X(09).
           05 WR-USER-ID             PIC X(10).
           05 WR-REASON-CODE         PIC X(04).
           05 WR-CHANNEL             PIC X(08).
           05 WR-RAIL-CODE           PIC X(08).
           05 WR-RESERVED            PIC X(78).

       01  WS-RSP-BLOCK.
           05 WS-SUCCESS             PIC X(01).
           05 WS-ERROR-CODE          PIC X(08).
           05 WS-ERROR-MSG           PIC X(80).
           05 WS-NEW-LEDGER-SEQ      PIC X(09).
           05 WS-RSP-RESERVED        PIC X(30).

       01  WS-RPG-REQ.
           05 RQ-COMPANY             PIC X(03).
           05 RQ-LEDGER-DATE         PIC X(08).
           05 RQ-LEDGER-SEQ          PIC 9(09).
           05 RQ-USER-ID             PIC X(10).
           05 RQ-REASON-CODE         PIC X(04).
           05 RQ-CHANNEL             PIC X(08).

       01  WS-RPG-RSP.
           05 RS-SUCCESS             PIC X(01).
           05 RS-ERROR-CODE          PIC X(08).
           05 RS-ERROR-MSG           PIC X(128).
           05 RS-NEW-LEDGER-SEQ      PIC 9(09).

       LINKAGE SECTION.
       01  LK-REQ-BLOCK.
           05 LK-REQ-BYTES           PIC X(128).

       01  LK-RSP-BLOCK.
           05 LK-RSP-BYTES           PIC X(128).

       PROCEDURE DIVISION USING LK-REQ-BLOCK LK-RSP-BLOCK.

       MAIN-SECTION.
           PERFORM UNPACK-REQUEST
           PERFORM CALL-RPG-LEDGER
           PERFORM PACK-RESPONSE
           GOBACK.

       UNPACK-REQUEST.
           MOVE LK-REQ-BYTES TO WS-REQ-BLOCK

           MOVE WR-COMPANY     TO RQ-COMPANY
           MOVE WR-LEDGER-DATE TO RQ-LEDGER-DATE

           *> ASCII numeric to COMP-3/COMP integer; here simple numeric
           MOVE FUNCTION NUMVAL(WR-LEDGER-SEQ) TO RQ-LEDGER-SEQ

           MOVE WR-USER-ID     TO RQ-USER-ID
           MOVE WR-REASON-CODE TO RQ-REASON-CODE
           MOVE WR-CHANNEL     TO RQ-CHANNEL.

       CALL-RPG-LEDGER.
           CALL 'LEDREVSRV'
                USING RQ-COMPANY
                      RQ-LEDGER-DATE
                      RQ-LEDGER-SEQ
                      RQ-USER-ID
                      RQ-REASON-CODE
                      RQ-CHANNEL
                      RS-SUCCESS
                      RS-ERROR-CODE
                      RS-ERROR-MSG
                      RS-NEW-LEDGER-SEQ.

       PACK-RESPONSE.
           IF RS-SUCCESS = 'Y'
              MOVE 'Y' TO WS-SUCCESS
           ELSE
              MOVE 'N' TO WS-SUCCESS
           END-IF

           MOVE RS-ERROR-CODE TO WS-ERROR-CODE
           MOVE RS-ERROR-MSG  TO WS-ERROR-MSG

           MOVE RS-NEW-LEDGER-SEQ TO WS-NEW-LEDGER-SEQ

           MOVE SPACES TO WS-RSP-RESERVED

           MOVE WS-RSP-BLOCK TO LK-RSP-BYTES.
