      ******************************************************************
      * COBILT-ACH-TREASURY
      * Production Library Layer
      * REXX -> COBOL -> LOGIC -> DB2 -> External ACH Adapter
      * Banking credentials/configuration remain outside this library.
      * No assembler dependency.
      ******************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. COBILT-ACH-TREASURY.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. IBM-I.
       OBJECT-COMPUTER. IBM-I.

       DATA DIVISION.
       WORKING-STORAGE SECTION.

       01 WS-ENGINE.
           05 WS-STATUS PIC X(16).
           05 WS-RETURN-CODE PIC S9(9) COMP-3.
           05 WS-ERROR-CODE PIC X(16).
           05 WS-ERROR-TEXT PIC X(128).
           05 WS-SEQUENCE PIC 9(18).
           05 WS-RETRY-COUNT PIC 9(4).

       01 WS-BATCH.
           05 WS-BATCH-ID PIC X(40).
           05 WS-BATCH-STATUS PIC X(16).
           05 WS-ENTRY-COUNT PIC 9(10).
           05 WS-BATCH-TOTAL PIC S9(15)V99 COMP-3.
           05 WS-CONTROL-TOTAL PIC S9(15)V99 COMP-3.
           05 WS-ENTRY-HASH PIC X(64).
           05 WS-EFFECTIVE-DATE PIC 9(8).
           05 WS-SETTLEMENT-DATE PIC 9(8).

       01 WS-ENTRY.
           05 WS-ENTRY-ID PIC X(40).
           05 WS-TRACE-ID PIC X(40).
           05 WS-ROUTING-ID PIC X(9).
           05 WS-ACCOUNT-ID PIC X(40).
           05 WS-ACCOUNT-TYPE PIC X(4).
           05 WS-ENTRY-CODE PIC X(3).
           05 WS-SEC-CODE PIC X(3).
           05 WS-ENTRY-AMOUNT PIC S9(15)V99 COMP-3.
           05 WS-ENTRY-DIRECTION PIC X(6).
           05 WS-ENTRY-STATE PIC X(16).
           05 WS-ADDENDA-COUNT PIC 9(4).

       01 WS-ORCHESTRATOR.
           05 WS-REXX-COMMAND PIC X(32).
           05 WS-REXX-PAYLOAD PIC X(1024).
           05 WS-REXX-RESULT PIC X(1024).
           05 WS-REXX-RETURN PIC S9(9) COMP-3.

       01 WS-LOGIC.
           05 WS-PREDICATE PIC X(48).
           05 WS-TERM-A PIC X(128).
           05 WS-TERM-B PIC X(128).
           05 WS-TERM-C PIC X(128).
           05 WS-TRUTH PIC X.
           05 WS-CHOICE-POINT PIC 9(6).
           05 WS-BINDING-DEPTH PIC 9(6).

       01 WS-FUNDS.
           05 WS-LEDGER-BALANCE PIC S9(15)V99 COMP-3.
           05 WS-AVAILABLE-BALANCE PIC S9(15)V99 COMP-3.
           05 WS-PENDING-DEBITS PIC S9(15)V99 COMP-3.
           05 WS-PENDING-CREDITS PIC S9(15)V99 COMP-3.
           05 WS-REQUESTED-AMOUNT PIC S9(15)V99 COMP-3.

       01 WS-IDEMPOTENCY.
           05 WS-IDEMPOTENCY-KEY PIC X(80).
           05 WS-IDEMPOTENCY-HIT PIC X.
           05 WS-ORIGINAL-BATCH PIC X(40).
           05 WS-ORIGINAL-ENTRY PIC X(40).

       01 WS-AUDIT.
           05 WS-AUDIT-SEQUENCE PIC 9(18).
           05 WS-AUDIT-TYPE PIC X(24).
           05 WS-AUDIT-OBJECT PIC X(64).
           05 WS-AUDIT-HASH PIC X(64).
           05 WS-AUDIT-PREV-HASH PIC X(64).
           05 WS-AUDIT-RESULT PIC X(16).

       01 WS-ACH-FORMAT.
           05 WS-RECORD-CODE PIC X.
           05 WS-ACH-RECORD PIC X(94).
           05 WS-ACH-LENGTH PIC 9(4).

       01 WS-FUNCTION.
           05 WS-FUNCTOR PIC X(32).
           05 WS-FUNCTOR-INPUT PIC X(256).
           05 WS-FUNCTOR-OUTPUT PIC X(256).
           05 WS-FUNCTOR-RESULT PIC X(16).

       01 WS-RECON.
           05 WS-EXPECTED-TOTAL PIC S9(15)V99 COMP-3.
           05 WS-ACTUAL-TOTAL PIC S9(15)V99 COMP-3.
           05 WS-EXPECTED-COUNT PIC 9(10).
           05 WS-ACTUAL-COUNT PIC 9(10).
           05 WS-RECON-STATE PIC X(16).

       01 WS-CONSTANTS.
           05 C-READY PIC X(16) VALUE 'READY'.
           05 C-VALID PIC X(16) VALUE 'VALID'.
           05 C-REJECTED PIC X(16) VALUE 'REJECTED'.
           05 C-QUEUED PIC X(16) VALUE 'QUEUED'.
           05 C-SUBMITTED PIC X(16) VALUE 'SUBMITTED'.
           05 C-SETTLED PIC X(16) VALUE 'SETTLED'.
           05 C-FAILED PIC X(16) VALUE 'FAILED'.
           05 C-RECONCILED PIC X(16) VALUE 'RECONCILED'.
           05 C-EXCEPTION PIC X(16) VALUE 'EXCEPTION'.
           05 C-YES PIC X VALUE 'Y'.
           05 C-NO PIC X VALUE 'N'.

       LINKAGE SECTION.

       01 LK-REQUEST.
           05 LK-OPERATION PIC X(32).
           05 LK-BATCH-ID PIC X(40).
           05 LK-ENTRY-ID PIC X(40).
           05 LK-PAYLOAD PIC X(1024).

       01 LK-RESPONSE.
           05 LK-STATUS PIC X(16).
           05 LK-CODE PIC S9(9) COMP-3.
           05 LK-MESSAGE PIC X(256).
           05 LK-OBJECT-ID PIC X(64).

       PROCEDURE DIVISION USING LK-REQUEST LK-RESPONSE.

       MAIN-ENTRY.
           PERFORM INITIALIZE-LIBRARY
           PERFORM DISPATCH-OPERATION
           PERFORM RETURN-RESULT
           GOBACK.

       INITIALIZE-LIBRARY.
           MOVE C-READY TO WS-STATUS
           MOVE ZERO TO WS-RETURN-CODE
           MOVE ZERO TO WS-SEQUENCE
           MOVE ZERO TO WS-RETRY-COUNT
           MOVE C-NO TO WS-IDEMPOTENCY-HIT
           MOVE C-NO TO WS-TRUTH
           MOVE ZERO TO WS-CHOICE-POINT
           MOVE ZERO TO WS-BINDING-DEPTH.

       DISPATCH-OPERATION.
           EVALUATE LK-OPERATION
               WHEN 'CREATE-BATCH'
                   PERFORM BATCH-CREATE
               WHEN 'ADD-ENTRY'
                   PERFORM BATCH-ADD-ENTRY
               WHEN 'VALIDATE-ENTRY'
                   PERFORM ENTRY-VALIDATE
               WHEN 'VALIDATE-BATCH'
                   PERFORM BATCH-VALIDATE
               WHEN 'CHECK-FUNDS'
                   PERFORM FUNCTOR-FUNDS
               WHEN 'ROUTE-PAYMENT'
                   PERFORM FUNCTOR-ROUTE
               WHEN 'GENERATE-ACH'
                   PERFORM ACH-GENERATE
               WHEN 'SUBMIT'
                   PERFORM ACH-SUBMIT
               WHEN 'SETTLE'
                   PERFORM BATCH-SETTLE
               WHEN 'RECONCILE'
                   PERFORM BATCH-RECONCILE
               WHEN 'QUERY'
                   PERFORM LOGIC-QUERY
               WHEN 'UNIFY'
                   PERFORM LOGIC-UNIFY
               WHEN 'BACKTRACK'
                   PERFORM LOGIC-BACKTRACK
               WHEN 'ROLLBACK'
                   PERFORM TRANSACTION-ROLLBACK
               WHEN 'COMMIT'
                   PERFORM TRANSACTION-COMMIT
               WHEN OTHER
                   PERFORM FAIL-CLOSED
           END-EVALUATE.

       BATCH-CREATE.
           MOVE LK-BATCH-ID TO WS-BATCH-ID
           MOVE 'OPEN' TO WS-BATCH-STATUS
           MOVE ZERO TO WS-ENTRY-COUNT
           MOVE ZERO TO WS-BATCH-TOTAL
           MOVE ZERO TO WS-CONTROL-TOTAL
           MOVE ZERO TO WS-SEQUENCE
           PERFORM AUDIT-BATCH-CREATE
           MOVE C-READY TO WS-STATUS.

       BATCH-ADD-ENTRY.
           PERFORM LOAD-ENTRY
           PERFORM ENTRY-VALIDATE
           IF WS-STATUS = C-VALID
               PERFORM IDEMPOTENCY-CHECK
               IF WS-IDEMPOTENCY-HIT = C-NO
                   ADD 1 TO WS-ENTRY-COUNT
                   ADD WS-ENTRY-AMOUNT TO WS-BATCH-TOTAL
                   ADD WS-ENTRY-AMOUNT TO WS-CONTROL-TOTAL
                   MOVE C-QUEUED TO WS-ENTRY-STATE
                   PERFORM AUDIT-ENTRY
               ELSE
                   MOVE C-REJECTED TO WS-STATUS
               END-IF
           END-IF.

       LOAD-ENTRY.
           MOVE LK-ENTRY-ID TO WS-ENTRY-ID
           MOVE LK-PAYLOAD TO WS-FUNCTOR-INPUT.

       ENTRY-VALIDATE.
           MOVE C-VALID TO WS-STATUS
           IF WS-ENTRY-ID = SPACES
               MOVE C-REJECTED TO WS-STATUS
           END-IF
           IF WS-ROUTING-ID = SPACES
               MOVE C-REJECTED TO WS-STATUS
           END-IF
           IF WS-ACCOUNT-ID = SPACES
               MOVE C-REJECTED TO WS-STATUS
           END-IF
           IF WS-ENTRY-AMOUNT <= ZERO
               MOVE C-REJECTED TO WS-STATUS
           END-IF
           IF WS-SEC-CODE = SPACES
               MOVE C-REJECTED TO WS-STATUS
           END-IF
           IF WS-ENTRY-DIRECTION NOT = 'DEBIT'
              AND WS-ENTRY-DIRECTION NOT = 'CREDIT'
               MOVE C-REJECTED TO WS-STATUS
           END-IF.

       BATCH-VALIDATE.
           MOVE C-VALID TO WS-STATUS
           IF WS-ENTRY-COUNT = ZERO
               MOVE C-REJECTED TO WS-STATUS
           END-IF
           IF WS-BATCH-TOTAL NOT = WS-CONTROL-TOTAL
               MOVE C-REJECTED TO WS-STATUS
           END-IF
           PERFORM LOGIC-BATCH-PREDICATE
           IF WS-TRUTH NOT = C-YES
               MOVE C-REJECTED TO WS-STATUS
           END-IF.

       LOGIC-BATCH-PREDICATE.
           MOVE 'batch_valid' TO WS-PREDICATE
           MOVE WS-ENTRY-COUNT TO WS-TERM-A
           MOVE WS-BATCH-TOTAL TO WS-TERM-B
           MOVE WS-CONTROL-TOTAL TO WS-TERM-C
           MOVE C-NO TO WS-TRUTH
           IF WS-ENTRY-COUNT > ZERO
               IF WS-BATCH-TOTAL = WS-CONTROL-TOTAL
                   MOVE C-YES TO WS-TRUTH
               END-IF
           END-IF.

       IDEMPOTENCY-CHECK.
           MOVE C-NO TO WS-IDEMPOTENCY-HIT
           IF WS-IDEMPOTENCY-KEY NOT = SPACES
               PERFORM IDEMPOTENCY-LOOKUP
           END-IF.

       IDEMPOTENCY-LOOKUP.
           CONTINUE.

       FUNCTOR-FUNDS.
           MOVE 'funds_available' TO WS-FUNCTOR
           MOVE WS-ENTRY-AMOUNT TO WS-REQUESTED-AMOUNT
           PERFORM TREASURY-FUNDS-READ
           IF WS-AVAILABLE-BALANCE >= WS-REQUESTED-AMOUNT
               MOVE C-VALID TO WS-FUNCTOR-RESULT
           ELSE
               MOVE C-REJECTED TO WS-FUNCTOR-RESULT
           END-IF.

       TREASURY-FUNDS-READ.
           CONTINUE.

       FUNCTOR-ROUTE.
           MOVE 'payment_route' TO WS-FUNCTOR
           IF WS-ROUTING-ID NOT = SPACES
               MOVE C-VALID TO WS-FUNCTOR-RESULT
           ELSE
               MOVE C-REJECTED TO WS-FUNCTOR-RESULT
           END-IF.

       ACH-GENERATE.
           PERFORM BATCH-VALIDATE
           IF WS-STATUS = C-VALID
               PERFORM ACH-FILE-HEADER
               PERFORM ACH-BATCH-HEADER
               PERFORM ACH-ENTRY-DETAIL
               PERFORM ACH-BATCH-CONTROL
               PERFORM ACH-FILE-CONTROL
           ELSE
               MOVE C-REJECTED TO WS-STATUS
           END-IF.

       ACH-FILE-HEADER.
           MOVE '1' TO WS-RECORD-CODE
           MOVE 94 TO WS-ACH-LENGTH.

       ACH-BATCH-HEADER.
           MOVE '5' TO WS-RECORD-CODE
           MOVE 94 TO WS-ACH-LENGTH.

       ACH-ENTRY-DETAIL.
           MOVE '6' TO WS-RECORD-CODE
           MOVE 94 TO WS-ACH-LENGTH.

       ACH-BATCH-CONTROL.
           MOVE '8' TO WS-RECORD-CODE
           MOVE 94 TO WS-ACH-LENGTH.

       ACH-FILE-CONTROL.
           MOVE '9' TO WS-RECORD-CODE
           MOVE 94 TO WS-ACH-LENGTH
           MOVE C-VALID TO WS-STATUS.

       ACH-SUBMIT.
           PERFORM BATCH-VALIDATE
           IF WS-STATUS = C-VALID
               PERFORM FUNCTOR-FUNDS
           END-IF
           IF WS-FUNCTOR-RESULT = C-VALID
               PERFORM EXTERNAL-ACH-ADAPTER
           ELSE
               MOVE C-REJECTED TO WS-STATUS
           END-IF.

       EXTERNAL-ACH-ADAPTER.
           MOVE C-SUBMITTED TO WS-BATCH-STATUS
           MOVE C-SUBMITTED TO WS-STATUS
           PERFORM AUDIT-SUBMISSION.

       BATCH-SETTLE.
           IF WS-BATCH-STATUS = C-SUBMITTED
               MOVE C-SETTLED TO WS-BATCH-STATUS
               MOVE C-SETTLED TO WS-STATUS
               PERFORM AUDIT-SETTLEMENT
           ELSE
               MOVE C-REJECTED TO WS-STATUS
           END-IF.

       BATCH-RECONCILE.
           MOVE WS-BATCH-TOTAL TO WS-EXPECTED-TOTAL
           MOVE WS-BATCH-TOTAL TO WS-ACTUAL-TOTAL
           MOVE WS-ENTRY-COUNT TO WS-EXPECTED-COUNT
           MOVE WS-ENTRY-COUNT TO WS-ACTUAL-COUNT
           IF WS-EXPECTED-TOTAL = WS-ACTUAL-TOTAL
              AND WS-EXPECTED-COUNT = WS-ACTUAL-COUNT
               MOVE C-RECONCILED TO WS-RECON-STATE
               MOVE C-RECONCILED TO WS-STATUS
           ELSE
               MOVE C-EXCEPTION TO WS-RECON-STATE
               MOVE C-REJECTED TO WS-STATUS
           END-IF.

       LOGIC-QUERY.
           MOVE LK-PAYLOAD TO WS-PREDICATE
           MOVE C-NO TO WS-TRUTH
           EVALUATE WS-PREDICATE
               WHEN 'batch_valid'
                   PERFORM LOGIC-BATCH-PREDICATE
               WHEN 'payment_valid'
                   PERFORM LOGIC-PAYMENT-PREDICATE
               WHEN 'funds_available'
                   PERFORM LOGIC-FUNDS-PREDICATE
               WHEN 'authorized'
                   PERFORM LOGIC-AUTH-PREDICATE
               WHEN OTHER
                   MOVE C-NO TO WS-TRUTH
           END-EVALUATE
           IF WS-TRUTH = C-YES
               MOVE C-VALID TO WS-STATUS
           ELSE
               MOVE C-REJECTED TO WS-STATUS
           END-IF.

       LOGIC-PAYMENT-PREDICATE.
           MOVE C-NO TO WS-TRUTH
           IF WS-ENTRY-ID NOT = SPACES
              AND WS-ENTRY-AMOUNT > ZERO
              AND WS-ACCOUNT-ID NOT = SPACES
               MOVE C-YES TO WS-TRUTH
           END-IF.

       LOGIC-FUNDS-PREDICATE.
           MOVE C-NO TO WS-TRUTH
           IF WS-AVAILABLE-BALANCE >= WS-REQUESTED-AMOUNT
               MOVE C-YES TO WS-TRUTH
           END-IF.

       LOGIC-AUTH-PREDICATE.
           MOVE C-NO TO WS-TRUTH
           IF WS-ENTRY-ID NOT = SPACES
               MOVE C-YES TO WS-TRUTH
           END-IF.

       LOGIC-UNIFY.
           IF WS-TERM-A = WS-TERM-B
               MOVE C-YES TO WS-TRUTH
           ELSE
               IF WS-TERM-A = SPACES
                   MOVE WS-TERM-B TO WS-TERM-A
                   MOVE C-YES TO WS-TRUTH
               ELSE
                   IF WS-TERM-B = SPACES
                       MOVE WS-TERM-A TO WS-TERM-B
                       MOVE C-YES TO WS-TRUTH
                   ELSE
                       MOVE C-NO TO WS-TRUTH
                   END-IF
               END-IF
           END-IF.

       LOGIC-BACKTRACK.
           IF WS-CHOICE-POINT > ZERO
               SUBTRACT 1 FROM WS-CHOICE-POINT
               MOVE C-READY TO WS-STATUS
           ELSE
               MOVE C-REJECTED TO WS-STATUS
           END-IF.

       TRANSACTION-COMMIT.
           PERFORM DB2-COMMIT
           MOVE C-READY TO WS-STATUS.

       TRANSACTION-ROLLBACK.
           PERFORM DB2-ROLLBACK
           MOVE C-REJECTED TO WS-STATUS.

       DB2-COMMIT.
           EXEC SQL
               COMMIT
           END-EXEC.

       DB2-ROLLBACK.
           EXEC SQL
               ROLLBACK
           END-EXEC.

       AUDIT-BATCH-CREATE.
           ADD 1 TO WS-AUDIT-SEQUENCE
           MOVE 'BATCH-CREATE' TO WS-AUDIT-TYPE
           MOVE WS-BATCH-ID TO WS-AUDIT-OBJECT.

       AUDIT-ENTRY.
           ADD 1 TO WS-AUDIT-SEQUENCE
           MOVE 'ENTRY' TO WS-AUDIT-TYPE
           MOVE WS-ENTRY-ID TO WS-AUDIT-OBJECT.

       AUDIT-SUBMISSION.
           ADD 1 TO WS-AUDIT-SEQUENCE
           MOVE 'SUBMISSION' TO WS-AUDIT-TYPE
           MOVE WS-BATCH-ID TO WS-AUDIT-OBJECT.

       AUDIT-SETTLEMENT.
           ADD 1 TO WS-AUDIT-SEQUENCE
           MOVE 'SETTLEMENT' TO WS-AUDIT-TYPE
           MOVE WS-BATCH-ID TO WS-AUDIT-OBJECT.

       FAIL-CLOSED.
           MOVE C-FAILED TO WS-STATUS
           MOVE 'UNKNOWN_OPERATION' TO WS-ERROR-CODE
           MOVE 999999 TO WS-RETURN-CODE
           MOVE 'OPERATION_REJECTED' TO WS-ERROR-TEXT.

       RETURN-RESULT.
           MOVE WS-STATUS TO LK-STATUS
           MOVE WS-RETURN-CODE TO LK-CODE
           MOVE WS-BATCH-ID TO LK-OBJECT-ID
           IF WS-ERROR-TEXT NOT = SPACES
               MOVE WS-ERROR-TEXT TO LK-MESSAGE
           ELSE
               MOVE WS-STATUS TO LK-MESSAGE
           END-IF.

       END PROGRAM COBILT-ACH-TREASURY.
