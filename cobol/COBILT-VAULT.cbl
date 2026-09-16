      *> ================================================================
      *> COBILT VAULT LIBRARY
      *> Deterministic COBOL Logic Vault
      *> REXX orchestration / RPGLE bridge / Logic / COBOL / DB2
      *> ================================================================
       IDENTIFICATION DIVISION.
       PROGRAM-ID. COBILT-VAULT.
       AUTHOR. COBILT-SYSTEM.
       INSTALLATION. IBM-I.
       DATE-WRITTEN. 2026-09-07.
       SECURITY. FAIL-CLOSED.
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. IBM-I.
       OBJECT-COMPUTER. IBM-I.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT VAULT-LEDGER ASSIGN TO DATABASE-VAULT.
       DATA DIVISION.
       FILE SECTION.
       FD  VAULT-LEDGER.
       01  VAULT-RECORD.
           05 VR-KEY              PIC X(64).
           05 VR-TYPE             PIC X(16).
           05 VR-STATE            PIC X(16).
           05 VR-VALUE            PIC X(256).
           05 VR-HASH             PIC X(64).
           05 VR-SEQUENCE         PIC 9(18).
           05 VR-OWNER            PIC X(32).
           05 VR-TIMESTAMP        PIC X(32).
           05 VR-AUTHORITY        PIC X(64).
       WORKING-STORAGE SECTION.
       01  VAULT-CONTEXT.
           05 VC-STATUS           PIC X(16).
           05 VC-ERROR            PIC X(128).
           05 VC-KEY              PIC X(64).
           05 VC-VALUE            PIC X(256).
           05 VC-HASH             PIC X(64).
           05 VC-PREV-HASH        PIC X(64).
           05 VC-SEQUENCE         PIC 9(18).
           05 VC-AUTHORITY        PIC X(64).
           05 VC-PREDICATE        PIC X(64).
           05 VC-ARGUMENT-1       PIC X(128).
           05 VC-ARGUMENT-2       PIC X(128).
           05 VC-ARGUMENT-3       PIC X(128).
           05 VC-BINDING-COUNT    PIC 9(4).
           05 VC-CHOICE-POINT     PIC 9(4).
           05 VC-BACKTRACK-DEPTH   PIC 9(4).
       01  LOGIC-FACT.
           05 LF-PREDICATE        PIC X(64).
           05 LF-ARG1             PIC X(128).
           05 LF-ARG2             PIC X(128).
           05 LF-ARG3             PIC X(128).
           05 LF-VALID            PIC X.
       01  LOGIC-RULE.
           05 LR-HEAD             PIC X(64).
           05 LR-BODY             PIC X(256).
           05 LR-PRIORITY         PIC 9(4).
           05 LR-VALID            PIC X.
       01  LOGIC-BINDING.
           05 LB-NAME             PIC X(64).
           05 LB-VALUE            PIC X(128).
           05 LB-BOUND            PIC X.
       01  TRANSACTION-CONTEXT.
           05 TC-ID               PIC X(32).
           05 TC-OPERATION        PIC X(32).
           05 TC-AMOUNT           PIC S9(13)V99.
           05 TC-CURRENCY         PIC X(3).
           05 TC-ACTOR            PIC X(64).
           05 TC-RESULT           PIC X(16).
           05 TC-CODE             PIC 9(8).
       01  BRIDGE-CONTEXT.
           05 BC-COMMAND          PIC X(128).
           05 BC-RESPONSE         PIC X(256).
           05 BC-RETURN-CODE      PIC S9(9) COMP-5.
           05 BC-RPGLE-FLAG       PIC X.
           05 BC-REXX-FLAG        PIC X.
           05 BC-COBOL-FLAG       PIC X.
       01  VAULT-CONSTANTS.
           05 STATUS-READY        PIC X(16) VALUE IS READY.
           05 STATUS-COMMIT       PIC X(16) VALUE IS COMMITTED.
           05 STATUS-REJECT       PIC X(16) VALUE IS REJECTED.
           05 STATUS-ERROR        PIC X(16) VALUE IS ERROR.
           05 STATUS-BACKTRACK    PIC X(16) VALUE IS BACKTRACK.
           05 STATUS-UNBOUND      PIC X(16) VALUE IS UNBOUND.
           05 TRUE-FLAG           PIC X VALUE IS Y.
           05 FALSE-FLAG          PIC X VALUE IS N.
           05 ZERO-SEQUENCE       PIC 9(18) VALUE ZERO.
           05 MAX-BACKTRACK       PIC 9(4) VALUE 9999.
       LINKAGE SECTION.
       01  LK-REQUEST.
           05 LK-COMMAND          PIC X(32).
           05 LK-KEY              PIC X(64).
           05 LK-VALUE            PIC X(256).
           05 LK-ACTOR            PIC X(64).
           05 LK-ARG1             PIC X(128).
           05 LK-ARG2             PIC X(128).
           05 LK-ARG3             PIC X(128).
       01  LK-RESPONSE.
           05 LK-STATUS           PIC X(16).
           05 LK-CODE             PIC 9(8).
           05 LK-MESSAGE          PIC X(256).
           05 LK-HASH             PIC X(64).
           05 LK-SEQUENCE         PIC 9(18).
       PROCEDURE DIVISION USING LK-REQUEST LK-RESPONSE.
       MAIN-ENTRY.
           PERFORM INITIALIZE-VAULT.
           PERFORM DISPATCH-COMMAND.
           PERFORM FINALIZE-VAULT.
           GOBACK.
       INITIALIZE-VAULT.
           MOVE STATUS-READY TO VC-STATUS.
           MOVE SPACES TO VC-ERROR.
           MOVE SPACES TO VC-HASH.
           MOVE SPACES TO VC-PREV-HASH.
           MOVE ZERO TO VC-SEQUENCE.
           MOVE ZERO TO VC-BINDING-COUNT.
           MOVE ZERO TO VC-CHOICE-POINT.
           MOVE ZERO TO VC-BACKTRACK-DEPTH.
           MOVE FALSE-FLAG TO BC-RPGLE-FLAG.
           MOVE FALSE-FLAG TO BC-REXX-FLAG.
           MOVE FALSE-FLAG TO BC-COBOL-FLAG.
           MOVE ZERO TO LK-CODE.
           MOVE SPACES TO LK-MESSAGE.
           MOVE SPACES TO LK-HASH.
           MOVE ZERO TO LK-SEQUENCE.
       DISPATCH-COMMAND.
           EVALUATE LK-COMMAND
               WHEN VAULT-OPEN
                   PERFORM VAULT-OPEN-OPERATION
               WHEN VAULT-READ
                   PERFORM VAULT-READ-OPERATION
               WHEN VAULT-WRITE
                   PERFORM VAULT-WRITE-OPERATION
               WHEN VAULT-ASSERT
                   PERFORM VAULT-ASSERT-OPERATION
               WHEN VAULT-QUERY
                   PERFORM LOGIC-QUERY
               WHEN VAULT-UNIFY
                   PERFORM LOGIC-UNIFY
               WHEN VAULT-BACKTRACK
                   PERFORM LOGIC-BACKTRACK
               WHEN VAULT-COMMIT
                   PERFORM VAULT-COMMIT-OPERATION
               WHEN VAULT-ROLLBACK
                   PERFORM VAULT-ROLLBACK-OPERATION
               WHEN BRIDGE-REXX
                   PERFORM PROCESS-REXX-COMMAND
               WHEN BRIDGE-RPGLE
                   PERFORM PROCESS-RPGLE-COMMAND
               WHEN BRIDGE-COBOL
                   PERFORM PROCESS-COBOL-COMMAND
               WHEN OTHER
                   PERFORM COMMAND-REJECT.
       VAULT-OPEN-OPERATION.
           MOVE STATUS-READY TO LK-STATUS.
           MOVE 00000001 TO LK-CODE.
           MOVE VAULT-OPEN TO LK-MESSAGE.
           PERFORM LOAD-VAULT-CONTEXT.
       VAULT-READ-OPERATION.
           MOVE LK-KEY TO VC-KEY.
           PERFORM READ-VAULT-RECORD.
           IF VC-STATUS = STATUS-ERROR
               PERFORM READ-FAILURE
           ELSE
               MOVE STATUS-READY TO LK-STATUS
               MOVE 00000002 TO LK-CODE
               MOVE VC-VALUE TO LK-MESSAGE
               MOVE VC-HASH TO LK-HASH
           END-IF.
       VAULT-WRITE-OPERATION.
           MOVE LK-KEY TO VC-KEY.
           MOVE LK-VALUE TO VC-VALUE.
           MOVE LK-ACTOR TO VC-AUTHORITY.
           PERFORM VALIDATE-AUTHORITY.
           IF VC-STATUS NOT = STATUS-ERROR
               PERFORM CALCULATE-VAULT-HASH
               PERFORM APPEND-VAULT-RECORD
               MOVE STATUS-COMMIT TO LK-STATUS
               MOVE 00000003 TO LK-CODE
               MOVE VC-HASH TO LK-HASH
           ELSE
               MOVE STATUS-REJECT TO LK-STATUS
               MOVE 00000013 TO LK-CODE
           END-IF.
       VAULT-ASSERT-OPERATION.
           MOVE LK-ARG1 TO LF-PREDICATE.
           MOVE LK-ARG2 TO LF-ARG1.
           MOVE LK-ARG3 TO LF-ARG2.
           MOVE TRUE-FLAG TO LF-VALID.
           PERFORM LOGIC-EVALUATE-FACT.
           IF LF-VALID = TRUE-FLAG
               MOVE STATUS-COMMIT TO LK-STATUS
               MOVE 00000004 TO LK-CODE
           ELSE
               MOVE STATUS-REJECT TO LK-STATUS
               MOVE 00000014 TO LK-CODE
           END-IF.
       LOGIC-QUERY.
           MOVE LK-ARG1 TO VC-PREDICATE.
           MOVE LK-ARG2 TO VC-ARGUMENT-1.
           MOVE LK-ARG3 TO VC-ARGUMENT-2.
           PERFORM LOGIC-RESOLVE-PREDICATE.
           IF VC-STATUS = STATUS-COMMIT
               MOVE STATUS-COMMIT TO LK-STATUS
               MOVE 00000005 TO LK-CODE
           ELSE
               MOVE STATUS-REJECT TO LK-STATUS
               MOVE 00000015 TO LK-CODE
           END-IF.
       LOGIC-UNIFY.
           MOVE LK-ARG1 TO VC-ARGUMENT-1.
           MOVE LK-ARG2 TO VC-ARGUMENT-2.
           PERFORM UNIFY-TERMS.
           IF VC-STATUS = STATUS-COMMIT
               MOVE STATUS-COMMIT TO LK-STATUS
               MOVE 00000006 TO LK-CODE
           ELSE
               MOVE STATUS-REJECT TO LK-STATUS
               MOVE 00000016 TO LK-CODE
           END-IF.
       LOGIC-BACKTRACK.
           ADD 1 TO VC-BACKTRACK-DEPTH.
           IF VC-BACKTRACK-DEPTH > MAX-BACKTRACK
               MOVE STATUS-ERROR TO VC-STATUS
               MOVE 00000017 TO LK-CODE
               MOVE STATUS-ERROR TO LK-STATUS
           ELSE
               PERFORM RESTORE-CHOICE-POINT
               MOVE STATUS-BACKTRACK TO LK-STATUS
               MOVE 00000007 TO LK-CODE
           END-IF.
       LOGIC-EVALUATE-FACT.
           IF LF-PREDICATE = SPACES
               MOVE FALSE-FLAG TO LF-VALID
               EXIT PARAGRAPH
           END-IF.
           IF LF-ARG1 = SPACES
               MOVE FALSE-FLAG TO LF-VALID
               EXIT PARAGRAPH
           END-IF.
           MOVE TRUE-FLAG TO LF-VALID.
       LOGIC-RESOLVE-PREDICATE.
           PERFORM SEARCH-FACT-BASE.
           IF LF-VALID = TRUE-FLAG
               MOVE STATUS-COMMIT TO VC-STATUS
           ELSE
               PERFORM SEARCH-RULE-BASE
           END-IF.
       UNIFY-TERMS.
           IF VC-ARGUMENT-1 = VC-ARGUMENT-2
               MOVE STATUS-COMMIT TO VC-STATUS
               ADD 1 TO VC-BINDING-COUNT
           ELSE
               IF VC-ARGUMENT-1 = SPACES
                   MOVE VC-ARGUMENT-2 TO VC-ARGUMENT-1
                   MOVE STATUS-COMMIT TO VC-STATUS
               ELSE
                   IF VC-ARGUMENT-2 = SPACES
                       MOVE VC-ARGUMENT-1 TO VC-ARGUMENT-2
                       MOVE STATUS-COMMIT TO VC-STATUS
                   ELSE
                       MOVE STATUS-REJECT TO VC-STATUS
                   END-IF
               END-IF
           END-IF.
       SEARCH-FACT-BASE.
           MOVE FALSE-FLAG TO LF-VALID.
           IF VC-PREDICATE NOT = SPACES
               IF VC-ARGUMENT-1 NOT = SPACES
                   MOVE TRUE-FLAG TO LF-VALID
               END-IF
           END-IF.
       SEARCH-RULE-BASE.
           IF VC-PREDICATE = SPACES
               MOVE STATUS-REJECT TO VC-STATUS
           ELSE
               PERFORM CREATE-CHOICE-POINT
               PERFORM APPLY-RULE
           END-IF.
       CREATE-CHOICE-POINT.
           ADD 1 TO VC-CHOICE-POINT.
           MOVE VC-CHOICE-POINT TO VC-BACKTRACK-DEPTH.
       APPLY-RULE.
           IF VC-PREDICATE = SPACES
               MOVE STATUS-REJECT TO VC-STATUS
           ELSE
               MOVE STATUS-COMMIT TO VC-STATUS
           END-IF.
       RESTORE-CHOICE-POINT.
           IF VC-CHOICE-POINT > ZERO
               SUBTRACT 1 FROM VC-CHOICE-POINT
           END-IF.
           IF VC-BACKTRACK-DEPTH > ZERO
               SUBTRACT 1 FROM VC-BACKTRACK-DEPTH
           END-IF.
       VALIDATE-AUTHORITY.
           IF VC-AUTHORITY = SPACES
               MOVE STATUS-ERROR TO VC-STATUS
               MOVE AUTHORITY-REQUIRED TO VC-ERROR
           ELSE
               MOVE STATUS-READY TO VC-STATUS
           END-IF.
       CALCULATE-VAULT-HASH.
           MOVE VC-PREV-HASH TO VC-HASH.
           STRING
               VC-KEY
               VC-VALUE
               VC-AUTHORITY
               VC-HASH
               DELIMITED BY SIZE
               INTO VC-HASH.
           PERFORM HASH-NORMALIZE.
       HASH-NORMALIZE.
           INSPECT VC-HASH
               REPLACING ALL SPACE BY ZERO.
       APPEND-VAULT-RECORD.
           ADD 1 TO VC-SEQUENCE.
           MOVE VC-KEY TO VR-KEY.
           MOVE VAULT-ENTRY TO VR-TYPE.
           MOVE STATUS-COMMIT TO VR-STATE.
           MOVE VC-VALUE TO VR-VALUE.
           MOVE VC-HASH TO VR-HASH.
           MOVE VC-SEQUENCE TO VR-SEQUENCE.
           MOVE VC-AUTHORITY TO VR-AUTHORITY.
           MOVE CURRENT-DATE TO VR-TIMESTAMP.
           MOVE VC-HASH TO VC-PREV-HASH.
       READ-VAULT-RECORD.
           MOVE SPACES TO VC-VALUE.
           MOVE SPACES TO VC-HASH.
           MOVE STATUS-READY TO VC-STATUS.
       LOAD-VAULT-CONTEXT.
           MOVE ZERO TO VC-SEQUENCE.
           MOVE SPACES TO VC-PREV-HASH.
       PROCESS-REXX-COMMAND.
           MOVE TRUE-FLAG TO BC-REXX-FLAG.
           MOVE LK-ARG1 TO BC-COMMAND.
           PERFORM BRIDGE-DISPATCH.
       PROCESS-RPGLE-COMMAND.
           MOVE TRUE-FLAG TO BC-RPGLE-FLAG.
           MOVE LK-ARG1 TO BC-COMMAND.
           PERFORM BRIDGE-DISPATCH.
       PROCESS-COBOL-COMMAND.
           MOVE TRUE-FLAG TO BC-COBOL-FLAG.
           MOVE LK-ARG1 TO BC-COMMAND.
       BRIDGE-DISPATCH.
           MOVE BRIDGE-ACCEPTED TO BC-RESPONSE.
           MOVE 0 TO BC-RETURN-CODE.
       COMMAND-REJECT.
           MOVE STATUS-ERROR TO LK-STATUS.
           MOVE 00009999 TO LK-CODE.
           MOVE COMMAND-REJECTED TO LK-MESSAGE.
       READ-FAILURE.
           MOVE STATUS-ERROR TO LK-STATUS.
           MOVE 00009998 TO LK-CODE.
           MOVE READ-FAILED TO LK-MESSAGE.
       VAULT-COMMIT-OPERATION.
           PERFORM VALIDATE-AUTHORITY.
           IF VC-STATUS = STATUS-ERROR
               MOVE STATUS-REJECT TO LK-STATUS
               MOVE 00009997 TO LK-CODE
           ELSE
               MOVE STATUS-COMMIT TO LK-STATUS
               MOVE 00000008 TO LK-CODE
               MOVE VC-SEQUENCE TO LK-SEQUENCE
           END-IF.
       VAULT-ROLLBACK-OPERATION.
           PERFORM RESTORE-CHOICE-POINT.
           MOVE STATUS-BACKTRACK TO LK-STATUS.
           MOVE 00000009 TO LK-CODE.
       FINALIZE-VAULT.
           IF VC-STATUS = STATUS-ERROR
               MOVE STATUS-ERROR TO LK-STATUS
           END-IF.
      *> ================================================================
      *> PREDICATE PRIMITIVES
      *> ================================================================
       PRED-EXISTS.
           IF VC-KEY = SPACES
               MOVE FALSE-FLAG TO LF-VALID
           ELSE
               MOVE TRUE-FLAG TO LF-VALID
           END-IF.
       PRED-EQUAL.
           IF VC-ARGUMENT-1 = VC-ARGUMENT-2
               MOVE TRUE-FLAG TO LF-VALID
           ELSE
               MOVE FALSE-FLAG TO LF-VALID
           END-IF.
       PRED-NOT-EQUAL.
           IF VC-ARGUMENT-1 NOT = VC-ARGUMENT-2
               MOVE TRUE-FLAG TO LF-VALID
           ELSE
               MOVE FALSE-FLAG TO LF-VALID
           END-IF.
       PRED-PRESENT.
           IF VC-VALUE NOT = SPACES
               MOVE TRUE-FLAG TO LF-VALID
           ELSE
               MOVE FALSE-FLAG TO LF-VALID
           END-IF.
       PRED-AUTHORIZED.
           PERFORM VALIDATE-AUTHORITY.
           IF VC-STATUS NOT = STATUS-ERROR
               MOVE TRUE-FLAG TO LF-VALID
           ELSE
               MOVE FALSE-FLAG TO LF-VALID
           END-IF.
      *> ================================================================
      *> RULE ENGINE
      *> ================================================================
       RULE-ACCEPT.
           MOVE TRUE-FLAG TO LR-VALID.
           MOVE STATUS-COMMIT TO VC-STATUS.
       RULE-REJECT.
           MOVE FALSE-FLAG TO LR-VALID.
           MOVE STATUS-REJECT TO VC-STATUS.
       RULE-CHAIN.
           PERFORM LOGIC-EVALUATE-FACT.
           IF LF-VALID = TRUE-FLAG
               PERFORM RULE-ACCEPT
           ELSE
               PERFORM RULE-REJECT
           END-IF.
       RULE-AND.
           IF VC-ARGUMENT-1 NOT = SPACES
               IF VC-ARGUMENT-2 NOT = SPACES
                   MOVE STATUS-COMMIT TO VC-STATUS
               ELSE
                   MOVE STATUS-REJECT TO VC-STATUS
               END-IF
           ELSE
               MOVE STATUS-REJECT TO VC-STATUS
           END-IF.
       RULE-OR.
           IF VC-ARGUMENT-1 NOT = SPACES
               MOVE STATUS-COMMIT TO VC-STATUS
           ELSE
               IF VC-ARGUMENT-2 NOT = SPACES
                   MOVE STATUS-COMMIT TO VC-STATUS
               ELSE
                   MOVE STATUS-REJECT TO VC-STATUS
               END-IF
           END-IF.
       RULE-NOT.
           IF VC-ARGUMENT-1 = SPACES
               MOVE STATUS-COMMIT TO VC-STATUS
           ELSE
               MOVE STATUS-REJECT TO VC-STATUS
           END-IF.
      *> ================================================================
      *> TRANSACTION GATE
      *> ================================================================
       TRANSACTION-BEGIN.
           MOVE LK-KEY TO TC-ID.
           MOVE TRANSACTION-BEGIN TO TC-OPERATION.
           MOVE PENDING TO TC-RESULT.
           MOVE ZERO TO TC-CODE.
       TRANSACTION-VALIDATE.
           PERFORM PRED-AUTHORIZED.
           IF LF-VALID = FALSE-FLAG
               MOVE STATUS-REJECT TO TC-RESULT
               MOVE 00000021 TO TC-CODE
           ELSE
               PERFORM LOGIC-QUERY
               IF LK-STATUS = STATUS-COMMIT
                   MOVE STATUS-COMMIT TO TC-RESULT
                   MOVE 00000022 TO TC-CODE
               ELSE
                   MOVE STATUS-REJECT TO TC-RESULT
                   MOVE 00000023 TO TC-CODE
               END-IF
           END-IF.
       TRANSACTION-COMMIT.
           IF TC-RESULT = STATUS-COMMIT
               PERFORM VAULT-COMMIT-OPERATION
           ELSE
               PERFORM VAULT-ROLLBACK-OPERATION
           END-IF.
       TRANSACTION-ROLLBACK.
           MOVE STATUS-REJECT TO TC-RESULT.
           PERFORM VAULT-ROLLBACK-OPERATION.
      *> ================================================================
      *> RPGLE BRIDGE CONTRACT
      *> ================================================================
       RPGLE-REQUEST.
           MOVE TRUE-FLAG TO BC-RPGLE-FLAG.
           MOVE RPGLE-REQUEST TO BC-COMMAND.
           PERFORM BRIDGE-DISPATCH.
       RPGLE-READ.
           MOVE VAULT-READ TO LK-COMMAND.
           PERFORM DISPATCH-COMMAND.
       RPGLE-WRITE.
           MOVE VAULT-WRITE TO LK-COMMAND.
           PERFORM DISPATCH-COMMAND.
       RPGLE-QUERY.
           MOVE VAULT-QUERY TO LK-COMMAND.
           PERFORM DISPATCH-COMMAND.
       RPGLE-COMMIT.
           MOVE VAULT-COMMIT TO LK-COMMAND.
           PERFORM DISPATCH-COMMAND.
      *> ================================================================
      *> REXX ORCHESTRATION CONTRACT
      *> ================================================================
       REXX-DISPATCH.
           MOVE TRUE-FLAG TO BC-REXX-FLAG.
           EVALUATE BC-COMMAND
               WHEN REXX-OPEN
                   MOVE VAULT-OPEN TO LK-COMMAND
               WHEN REXX-READ
                   MOVE VAULT-READ TO LK-COMMAND
               WHEN REXX-WRITE
                   MOVE VAULT-WRITE TO LK-COMMAND
               WHEN REXX-QUERY
                   MOVE VAULT-QUERY TO LK-COMMAND
               WHEN REXX-COMMIT
                   MOVE VAULT-COMMIT TO LK-COMMAND
               WHEN OTHER
                   MOVE UNKNOWN TO LK-COMMAND
           END-EVALUATE.
           PERFORM DISPATCH-COMMAND.
      *> ================================================================
      *> DETERMINISTIC VALIDATION
      *> ================================================================
       VALIDATE-KEY.
           IF LK-KEY = SPACES
               MOVE STATUS-ERROR TO VC-STATUS
               MOVE KEY-REQUIRED TO VC-ERROR
           ELSE
               MOVE STATUS-READY TO VC-STATUS
           END-IF.
       VALIDATE-VALUE.
           IF LK-VALUE = SPACES
               MOVE STATUS-ERROR TO VC-STATUS
               MOVE VALUE-REQUIRED TO VC-ERROR
           ELSE
               MOVE STATUS-READY TO VC-STATUS
           END-IF.
       VALIDATE-REQUEST.
           PERFORM VALIDATE-KEY.
           IF VC-STATUS NOT = STATUS-ERROR
               PERFORM VALIDATE-VALUE
           END-IF.
      *> ================================================================
      *> FACT ASSERTION
      *> ================================================================
       ASSERT-FACT.
           MOVE LK-ARG1 TO LF-PREDICATE.
           MOVE LK-ARG2 TO LF-ARG1.
           MOVE LK-ARG3 TO LF-ARG2.
           MOVE TRUE-FLAG TO LF-VALID.
           PERFORM VALIDATE-KEY.
           IF VC-STATUS = STATUS-ERROR
               MOVE FALSE-FLAG TO LF-VALID
           ELSE
               MOVE TRUE-FLAG TO LF-VALID
           END-IF.
       ASSERT-RULE.
           MOVE LK-ARG1 TO LR-HEAD.
           MOVE LK-ARG2 TO LR-BODY.
           MOVE 0001 TO LR-PRIORITY.
           MOVE TRUE-FLAG TO LR-VALID.
      *> ================================================================
      *> UNIFICATION STACK
      *> ================================================================
       PUSH-BINDING.
           ADD 1 TO VC-BINDING-COUNT.
           MOVE LK-ARG1 TO LB-NAME.
           MOVE LK-ARG2 TO LB-VALUE.
           MOVE TRUE-FLAG TO LB-BOUND.
       POP-BINDING.
           IF VC-BINDING-COUNT > ZERO
               SUBTRACT 1 FROM VC-BINDING-COUNT
           END-IF.
       CLEAR-BINDINGS.
           MOVE ZERO TO VC-BINDING-COUNT.
       UNIFY-VARIABLE.
           IF LB-BOUND = TRUE-FLAG
               MOVE LB-VALUE TO VC-ARGUMENT-1
               MOVE STATUS-COMMIT TO VC-STATUS
           ELSE
               MOVE STATUS-UNBOUND TO VC-STATUS
           END-IF.
      *> ================================================================
      *> CHOICE POINT CONTROL
      *> ================================================================
       CHOICE-PUSH.
           ADD 1 TO VC-CHOICE-POINT.
           MOVE VC-BINDING-COUNT TO VC-BACKTRACK-DEPTH.
       CHOICE-POP.
           IF VC-CHOICE-POINT > ZERO
               SUBTRACT 1 FROM VC-CHOICE-POINT
           END-IF.
       CHOICE-CLEAR.
           MOVE ZERO TO VC-CHOICE-POINT.
           MOVE ZERO TO VC-BACKTRACK-DEPTH.
      *> ================================================================
      *> DB2 TRANSACTION SEMANTICS
      *> ================================================================
       DB2-READ.
           PERFORM VALIDATE-KEY.
           IF VC-STATUS NOT = STATUS-ERROR
               PERFORM READ-VAULT-RECORD
           END-IF.
       DB2-INSERT.
           PERFORM VALIDATE-REQUEST.
           IF VC-STATUS NOT = STATUS-ERROR
               PERFORM CALCULATE-VAULT-HASH
               PERFORM APPEND-VAULT-RECORD
           END-IF.
       DB2-COMMIT.
           PERFORM VALIDATE-AUTHORITY.
           IF VC-STATUS NOT = STATUS-ERROR
               MOVE STATUS-COMMIT TO VC-STATUS
           END-IF.
       DB2-ROLLBACK.
           PERFORM RESTORE-CHOICE-POINT.
           MOVE STATUS-BACKTRACK TO VC-STATUS.
      *> ================================================================
      *> VAULT INTEGRITY
      *> ================================================================
       VERIFY-SEQUENCE.
           IF VC-SEQUENCE < ZERO
               MOVE STATUS-ERROR TO VC-STATUS
           ELSE
               MOVE STATUS-READY TO VC-STATUS
           END-IF.
       VERIFY-HASH.
           IF VC-HASH = SPACES
               MOVE STATUS-ERROR TO VC-STATUS
           ELSE
               MOVE STATUS-READY TO VC-STATUS
           END-IF.
       VERIFY-AUTHORITY.
           PERFORM VALIDATE-AUTHORITY.
           IF VC-STATUS = STATUS-ERROR
               MOVE STATUS-REJECT TO LK-STATUS
           ELSE
               MOVE STATUS-COMMIT TO LK-STATUS
           END-IF.
       VERIFY-ENTRY.
           PERFORM VERIFY-SEQUENCE.
           IF VC-STATUS NOT = STATUS-ERROR
               PERFORM VERIFY-HASH
           END-IF.
           IF VC-STATUS NOT = STATUS-ERROR
               PERFORM VERIFY-AUTHORITY
           END-IF.
      *> ================================================================
      *> TERMINAL RETURN
      *> ================================================================
       RETURN-SUCCESS.
           MOVE STATUS-COMMIT TO LK-STATUS.
           MOVE ZERO TO LK-CODE.
       RETURN-FAILURE.
           MOVE STATUS-ERROR TO LK-STATUS.
           MOVE 99999999 TO LK-CODE.
       END PROGRAM COBILT-VAULT.
