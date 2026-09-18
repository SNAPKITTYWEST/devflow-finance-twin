       IDENTIFICATION DIVISION.
       PROGRAM-ID. ACHRTRN.
       AUTHOR.     JESSICA+COPILOT.
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. IBM-Z.
       OBJECT-COMPUTER. IBM-Z.

       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT ACHITEM-FILE ASSIGN TO ACHITEM
               ORGANIZATION IS INDEXED
               ACCESS MODE IS DYNAMIC
               RECORD KEY IS AI-KEY
               FILE STATUS IS AI-STATUS.

           SELECT ACHRETLOG-FILE ASSIGN TO ACHRETLOG
               ORGANIZATION IS INDEXED
               ACCESS MODE IS DYNAMIC
               RECORD KEY IS AR-KEY
               FILE STATUS IS AR-STATUS.

       DATA DIVISION.
       FILE SECTION.

       FD  ACHITEM-FILE.
       01  ACHITEM-REC.
           05 AI-KEY.
              10 AI-COMPANY            PIC X(03).
              10 AI-BATCH-ID           PIC X(10).
              10 AI-ENTRY-ID           PIC X(15).
           05 AI-RAIL-CODE             PIC X(08).
           05 AI-ORIG-TRACE-NO         PIC X(15).
           05 AI-ORIG-DFI              PIC X(09).
           05 AI-ORIG-ACCOUNT          PIC X(17).
           05 AI-ORIG-AMOUNT           PIC S9(13)V99 COMP-3.
           05 AI-ORIG-DRCR-FLAG        PIC X(01). *> 'D' or 'C'
           05 AI-CURRENCY              PIC X(03).
           05 AI-STATE                 PIC X(12). *> NEW/POSTED/SETTLED/RETURNED/RETURN_POSTED/CLOSED
           05 AI-SETTLEMENT-DATE       PIC X(08). *> YYYYMMDD
           05 AI-ORIG-EFF-DATE         PIC X(08).
           05 AI-ORIG-ENTRY-DESC       PIC X(10).
           05 AI-ORIG-SEC-CODE         PIC X(03).
           05 AI-ORIG-ENTRY-CLASS      PIC X(03).
           05 AI-ORIG-ADDENDA          PIC X(94).
           05 AI-RETURN-REASON         PIC X(03). *> NACHA R01/R03/etc
           05 AI-RETURN-TS             PIC X(26). *> ISO TS
           05 AI-RETURN-USER           PIC X(10).
           05 AI-RETURN-CHANNEL        PIC X(08).
           05 AI-RETURN-LEDGER-SEQ     PIC 9(09).
           05 AI-LAST-UPD-TS           PIC X(26).

       FD  ACHRETLOG-FILE.
       01  ACHRETLOG-REC.
           05 AR-KEY.
              10 AR-COMPANY            PIC X(03).
              10 AR-BATCH-ID           PIC X(10).
              10 AR-ENTRY-ID           PIC X(15).
              10 AR-LOG-SEQ            PIC 9(09).
           05 AR-EVENT-CODE            PIC X(12). *> RET_REQ/RET_FAIL/RET_POST/RET_CLOSE
           05 AR-EVENT-TS              PIC X(26).
           05 AR-USER-ID               PIC X(10).
           05 AR-CHANNEL               PIC X(08).
           05 AR-REASON-CODE           PIC X(03).
           05 AR-DETAIL                PIC X(256).

       WORKING-STORAGE SECTION.

       01  WS-PROGRAM-NAME            PIC X(08) VALUE 'ACHRTRN'.
       01  WS-RUN-MODE                PIC X(01) VALUE 'B'. *> B=batch, O=online

       01  AI-STATUS                  PIC X(02) VALUE SPACES.
       01  AR-STATUS                  PIC X(02) VALUE SPACES.

       01  WS-RETURN-REQUEST.
           05 WR-COMPANY              PIC X(03).
           05 WR-BATCH-ID             PIC X(10).
           05 WR-ENTRY-ID             PIC X(15).
           05 WR-USER-ID              PIC X(10).
           05 WR-CHANNEL              PIC X(08).
           05 WR-REASON-CODE          PIC X(03).

       01  WS-RETURN-RESPONSE.
           05 WRS-SUCCESS             PIC X(01). *> 'Y' or 'N'
           05 WRS-ERROR-CODE          PIC X(08).
           05 WRS-ERROR-MSG           PIC X(80).
           05 WRS-LEDGER-SEQ          PIC 9(09).

       01  WS-TIMESTAMP               PIC X(26).
       01  WS-LOG-SEQ                 PIC 9(09) VALUE 0.

       01  WS-STATE-TARGET            PIC X(12).

       01  WS-REASON-VALID            PIC X(01) VALUE 'N'.

       01  WS-RETURNABLE-STATE        PIC X(12).

       01  WS-ABEND-FLAG              PIC X(01) VALUE 'N'.

       01  WS-DISPLAY-MSG             PIC X(80).

       01  FILLER REDEFINES WS-TIMESTAMP.
           05 WS-TS-YYYY              PIC X(04).
           05 WS-TS-MM                PIC X(02).
           05 WS-TS-DD                PIC X(02).
           05 WS-TS-T                 PIC X(01).
           05 WS-TS-HH                PIC X(02).
           05 WS-TS-MI                PIC X(02).
           05 WS-TS-SS                PIC X(02).
           05 WS-TS-DOT               PIC X(01).
           05 WS-TS-MSEC              PIC X(03).
           05 WS-TS-Z                 PIC X(01).
           05 WS-TS-OFFSET            PIC X(06).

       01  WS-REASON-TABLE.
           05 WS-REASON-ENTRY OCCURS 20 TIMES INDEXED BY REASON-IDX.
              10 WS-REASON-CODE       PIC X(03).
              10 WS-REASON-DESC       PIC X(40).

       01  WS-INIT-REASONS-SW         PIC X(01) VALUE 'N'.

       LINKAGE SECTION.
       01  LK-RETURN-REQUEST.
           05 LK-COMPANY              PIC X(03).
           05 LK-BATCH-ID             PIC X(10).
           05 LK-ENTRY-ID             PIC X(15).
           05 LK-USER-ID              PIC X(10).
           05 LK-CHANNEL              PIC X(08).
           05 LK-REASON-CODE          PIC X(03).

       01  LK-RETURN-RESPONSE.
           05 LK-SUCCESS              PIC X(01).
           05 LK-ERROR-CODE           PIC X(08).
           05 LK-ERROR-MSG            PIC X(80).
           05 LK-LEDGER-SEQ           PIC 9(09).

       PROCEDURE DIVISION USING LK-RETURN-REQUEST LK-RETURN-RESPONSE.

       MAIN-SECTION.
           PERFORM INIT-SECTION
           PERFORM LOAD-REQUEST
           PERFORM PROCESS-RETURN
           PERFORM BUILD-RESPONSE
           GOBACK.

       INIT-SECTION.
           IF WS-INIT-REASONS-SW = 'N'
              PERFORM INIT-REASON-TABLE
              MOVE 'Y' TO WS-INIT-REASONS-SW
           END-IF

           MOVE 'N' TO WRS-SUCCESS
           MOVE SPACES TO WRS-ERROR-CODE WRS-ERROR-MSG
           MOVE ZEROES TO WRS-LEDGER-SEQ

           OPEN I-O ACHITEM-FILE
           IF AI-STATUS NOT = '00'
              MOVE 'Y' TO WS-ABEND-FLAG
              MOVE 'FILEOPEN' TO WRS-ERROR-CODE
              MOVE 'ACHITEM open failed' TO WRS-ERROR-MSG
              PERFORM ABEND-SECTION
           END-IF

           OPEN I-O ACHRETLOG-FILE
           IF AR-STATUS NOT = '00'
              MOVE 'Y' TO WS-ABEND-FLAG
              MOVE 'FILEOPEN' TO WRS-ERROR-CODE
              MOVE 'ACHRETLOG open failed' TO WRS-ERROR-MSG
              PERFORM ABEND-SECTION
           END-IF

           PERFORM GET-CURRENT-TIMESTAMP.

       LOAD-REQUEST.
           MOVE LK-COMPANY     TO WR-COMPANY
           MOVE LK-BATCH-ID    TO WR-BATCH-ID
           MOVE LK-ENTRY-ID    TO WR-ENTRY-ID
           MOVE LK-USER-ID     TO WR-USER-ID
           MOVE LK-CHANNEL     TO WR-CHANNEL
           MOVE LK-REASON-CODE TO WR-REASON-CODE.

       PROCESS-RETURN.
           PERFORM LOAD-ACH-ITEM
           IF WRS-ERROR-CODE NOT = SPACES
              PERFORM LOG-RETURN-FAIL
              EXIT PARAGRAPH
           END-IF

           PERFORM VALIDATE-RETURN-ELIGIBILITY
           IF WRS-ERROR-CODE NOT = SPACES
              PERFORM LOG-RETURN-FAIL
              EXIT PARAGRAPH
           END-IF

           PERFORM APPLY-STATE-TRANSITION
           IF WRS-ERROR-CODE NOT = SPACES
              PERFORM LOG-RETURN-FAIL
              EXIT PARAGRAPH
           END-IF

           PERFORM PERSIST-ACH-ITEM
           IF WRS-ERROR-CODE NOT = SPACES
              PERFORM LOG-RETURN-FAIL
              EXIT PARAGRAPH
           END-IF

           PERFORM LOG-RETURN-SUCCESS.

       BUILD-RESPONSE.
           MOVE WRS-SUCCESS    TO LK-SUCCESS
           MOVE WRS-ERROR-CODE TO LK-ERROR-CODE
           MOVE WRS-ERROR-MSG  TO LK-ERROR-MSG
           MOVE WRS-LEDGER-SEQ TO LK-LEDGER-SEQ.

       LOAD-ACH-ITEM.
           MOVE WR-COMPANY  TO AI-COMPANY
           MOVE WR-BATCH-ID TO AI-BATCH-ID
           MOVE WR-ENTRY-ID TO AI-ENTRY-ID

           READ ACHITEM-FILE
               INVALID KEY
                   MOVE 'NOTFOUND' TO WRS-ERROR-CODE
                   MOVE 'ACH item not found' TO WRS-ERROR-MSG
               NOT INVALID KEY
                   CONTINUE
           END-READ.

       VALIDATE-RETURN-ELIGIBILITY.
           IF WRS-ERROR-CODE NOT = SPACES
              EXIT PARAGRAPH
           END-IF

           *> Only SETTLED or POSTED items can be returned
           IF AI-STATE = 'SETTLED'
              MOVE 'SETTLED' TO WS-RETURNABLE-STATE
           ELSE
              IF AI-STATE = 'POSTED'
                 MOVE 'POSTED' TO WS-RETURNABLE-STATE
              ELSE
                 MOVE 'BADSTATE' TO WRS-ERROR-CODE
                 MOVE 'Item state not returnable: ' TO WRS-ERROR-MSG
                 STRING AI-STATE DELIMITED BY SIZE
                        INTO WRS-ERROR-MSG
                 EXIT PARAGRAPH
              END-IF
           END-IF

           *> Prevent double return
           IF AI-STATE = 'RETURNED'
              MOVE 'ALREADYRT' TO WRS-ERROR-CODE
              MOVE 'Item already returned' TO WRS-ERROR-MSG
              EXIT PARAGRAPH
           END-IF

           *> Validate reason code
           PERFORM CHECK-REASON-CODE
           IF WS-REASON-VALID NOT = 'Y'
              MOVE 'BADREASN' TO WRS-ERROR-CODE
              MOVE 'Invalid return reason code' TO WRS-ERROR-MSG
              EXIT PARAGRAPH
           END-IF.

       APPLY-STATE-TRANSITION.
           IF WRS-ERROR-CODE NOT = SPACES
              EXIT PARAGRAPH
           END-IF

           *> State machine:
           *> SETTLED -> RETURNED
           *> POSTED  -> RETURNED
           MOVE 'RETURNED' TO WS-STATE-TARGET

           MOVE WS-STATE-TARGET TO AI-STATE
           MOVE WR-REASON-CODE  TO AI-RETURN-REASON
           MOVE WR-USER-ID      TO AI-RETURN-USER
           MOVE WR-CHANNEL      TO AI-RETURN-CHANNEL
           MOVE WS-TIMESTAMP    TO AI-RETURN-TS
           MOVE WS-TIMESTAMP    TO AI-LAST-UPD-TS.

           *> Ledger seq will be filled by downstream posting engine
           MOVE ZEROES TO AI-RETURN-LEDGER-SEQ.

       PERSIST-ACH-ITEM.
           REWRITE ACHITEM-REC
               INVALID KEY
                   MOVE 'DBERR' TO WRS-ERROR-CODE
                   MOVE 'ACH item rewrite failed' TO WRS-ERROR-MSG
               NOT INVALID KEY
                   CONTINUE
           END-REWRITE.

       LOG-RETURN-FAIL.
           PERFORM NEXT-LOG-SEQ
           MOVE WR-COMPANY   TO AR-COMPANY
           MOVE WR-BATCH-ID  TO AR-BATCH-ID
           MOVE WR-ENTRY-ID  TO AR-ENTRY-ID
           MOVE WS-LOG-SEQ   TO AR-LOG-SEQ
           MOVE 'RET_FAIL'   TO AR-EVENT-CODE
           MOVE WS-TIMESTAMP TO AR-EVENT-TS
           MOVE WR-USER-ID   TO AR-USER-ID
           MOVE WR-CHANNEL   TO AR-CHANNEL
           MOVE WR-REASON-CODE TO AR-REASON-CODE
           MOVE SPACES       TO AR-DETAIL

           STRING 'Return failed: '
                  WRS-ERROR-CODE DELIMITED BY SIZE
                  ' - ' DELIMITED BY SIZE
                  WRS-ERROR-MSG DELIMITED BY SIZE
                  INTO AR-DETAIL
           END-STRING

           WRITE ACHRETLOG-REC
               INVALID KEY
                   CONTINUE
           END-WRITE.

       LOG-RETURN-SUCCESS.
           MOVE 'Y' TO WRS-SUCCESS
           MOVE 'OK' TO WRS-ERROR-CODE
           MOVE 'Return accepted' TO WRS-ERROR-MSG

           PERFORM NEXT-LOG-SEQ
           MOVE WR-COMPANY   TO AR-COMPANY
           MOVE WR-BATCH-ID  TO AR-BATCH-ID
           MOVE WR-ENTRY-ID  TO AR-ENTRY-ID
           MOVE WS-LOG-SEQ   TO AR-LOG-SEQ
           MOVE 'RET_REQ'    TO AR-EVENT-CODE
           MOVE WS-TIMESTAMP TO AR-EVENT-TS
           MOVE WR-USER-ID   TO AR-USER-ID
           MOVE WR-CHANNEL   TO AR-CHANNEL
           MOVE WR-REASON-CODE TO AR-REASON-CODE
           MOVE SPACES       TO AR-DETAIL

           STRING 'Return requested; state='
                  AI-STATE DELIMITED BY SIZE
                  ' reason=' DELIMITED BY SIZE
                  WR-REASON-CODE DELIMITED BY SIZE
                  INTO AR-DETAIL
           END-STRING

           WRITE ACHRETLOG-REC
               INVALID KEY
                   CONTINUE
           END-WRITE.

       CHECK-REASON-CODE.
           MOVE 'N' TO WS-REASON-VALID
           SET REASON-IDX TO 1
           PERFORM VARYING REASON-IDX FROM 1 BY 1
                   UNTIL REASON-IDX > 20
              IF WS-REASON-CODE (REASON-IDX) = WR-REASON-CODE
                 MOVE 'Y' TO WS-REASON-VALID
                 EXIT PERFORM
              END-IF
           END-PERFORM.

       INIT-REASON-TABLE.
           MOVE 'R01' TO WS-REASON-CODE (1)
           MOVE 'Insufficient funds' TO WS-REASON-DESC (1)

           MOVE 'R03' TO WS-REASON-CODE (2)
           MOVE 'No account/Unable to locate' TO WS-REASON-DESC (2)

           MOVE 'R04' TO WS-REASON-CODE (3)
           MOVE 'Invalid account number' TO WS-REASON-DESC (3)

           MOVE 'R07' TO WS-REASON-CODE (4)
           MOVE 'Authorization revoked' TO WS-REASON-DESC (4)

           MOVE 'R08' TO WS-REASON-CODE (5)
           MOVE 'Payment stopped' TO WS-REASON-DESC (5)

           MOVE 'R10' TO WS-REASON-CODE (6)
           MOVE 'Customer advises not authorized' TO WS-REASON-DESC (6)

           MOVE 'R29' TO WS-REASON-CODE (7)
           MOVE 'Corporate customer advises not authorized' TO WS-REASON-DESC (7)

           *> Remaining entries left blank; extend as needed.

       NEXT-LOG-SEQ.
           ADD 1 TO WS-LOG-SEQ.

       GET-CURRENT-TIMESTAMP.
           *> Stub: in production, call system service or LE routine
           MOVE '20260908T192700.000Z+0000' TO WS-TIMESTAMP.

       ABEND-SECTION.
           IF WS-ABEND-FLAG = 'Y'
              DISPLAY 'ACHRTRN ABEND: ' WRS-ERROR-CODE ' ' WRS-ERROR-MSG
              GOBACK
           END-IF.
