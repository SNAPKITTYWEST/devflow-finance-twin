      ******************************************************************
      * COBILT-DATAWORM-TREASURY
      * PRODUCTION STORAGE / LOGIC / ACH SUPPORT LIBRARY
      * REXX ORCHESTRATOR -> COBOL -> DATAWORM
      * NO SQL / NO ASSEMBLER
      ******************************************************************
       IDENTIFICATION DIVISION.
       PROGRAM-ID. COBILT-DATAWORM-TREASURY.
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. IBM-I.
       OBJECT-COMPUTER. IBM-I.
       DATA DIVISION.
       WORKING-STORAGE SECTION.

       01  DW-CONTEXT.
           05 DW-STATUS             PIC X(16).
           05 DW-CODE               PIC S9(9) COMP-3.
           05 DW-ERROR              PIC X(128).
           05 DW-NAMESPACE          PIC X(64).
           05 DW-SEQUENCE           PIC 9(18).
           05 DW-EPOCH              PIC 9(18).

       01  DW-FACT.
           05 DW-F-PREDICATE        PIC X(64).
           05 DW-F-ARG1             PIC X(128).
           05 DW-F-ARG2             PIC X(128).
           05 DW-F-ARG3             PIC X(128).
           05 DW-F-ARG4             PIC X(128).
           05 DW-F-STATE            PIC X(16).
           05 DW-F-SEQUENCE         PIC 9(18).
           05 DW-F-HASH             PIC X(64).

       01  DW-RULE.
           05 DW-R-HEAD             PIC X(64).
           05 DW-R-BODY             PIC X(512).
           05 DW-R-PRIORITY         PIC 9(6).
           05 DW-R-STATE            PIC X(16).

       01  DW-BINDING.
           05 DW-B-NAME             PIC X(64).
           05 DW-B-VALUE            PIC X(128).
           05 DW-B-BOUND            PIC X.
           05 DW-B-DEPTH            PIC 9(6).

       01  DW-QUERY.
           05 DW-Q-PREDICATE        PIC X(64).
           05 DW-Q-A                PIC X(128).
           05 DW-Q-B                PIC X(128).
           05 DW-Q-C                PIC X(128).
           05 DW-Q-RESULT           PIC X.
           05 DW-Q-MATCHES          PIC 9(9).

       01  DW-INDEX.
           05 DW-I-PREDICATE        PIC X(64).
           05 DW-I-ARGUMENT         PIC X(128).
           05 DW-I-SEQUENCE         PIC 9(18).
           05 DW-I-STATE            PIC X(16).

       01  DW-JOURNAL.
           05 DW-J-TYPE             PIC X(16).
           05 DW-J-OBJECT           PIC X(64).
           05 DW-J-SEQUENCE         PIC 9(18).
           05 DW-J-PREV-HASH        PIC X(64).
           05 DW-J-HASH             PIC X(64).
           05 DW-J-STATE            PIC X(16).

       01  DW-TXN.
           05 DW-T-ID               PIC X(64).
           05 DW-T-STATE            PIC X(16).
           05 DW-T-START            PIC 9(18).
           05 DW-T-END              PIC 9(18).
           05 DW-T-FACTS            PIC 9(9).
           05 DW-T-RULES            PIC 9(9).

       01  DW-STACK.
           05 DW-S-DEPTH            PIC 9(6).
           05 DW-S-MAX              PIC 9(6).
           05 DW-S-CHOICE           PIC 9(6).

       01  DW-REXX.
           05 DW-RX-COMMAND         PIC X(64).
           05 DW-RX-PAYLOAD         PIC X(1024).
           05 DW-RX-RESULT          PIC X(1024).

       01  ACH-FACT.
           05 AF-BATCH-ID           PIC X(40).
           05 AF-ENTRY-ID           PIC X(40).
           05 AF-TRACE              PIC X(40).
           05 AF-AMOUNT             PIC S9(15)V99 COMP-3.
           05 AF-SEC                PIC X(3).
           05 AF-DIRECTION          PIC X(6).
           05 AF-STATE              PIC X(16).

       01  TREASURY-FACT.
           05 TF-ACCOUNT            PIC X(40).
           05 TF-LEDGER             PIC S9(15)V99 COMP-3.
           05 TF-AVAILABLE          PIC S9(15)V99 COMP-3.
           05 TF-PENDING            PIC S9(15)V99 COMP-3.
           05 TF-CURRENCY           PIC X(3).

       PROCEDURE DIVISION.

       DW-ENTRY.
           PERFORM DW-INITIALIZE
           PERFORM DW-DISPATCH
           PERFORM DW-RETURN
           GOBACK.

       DW-INITIALIZE.
           MOVE 'READY' TO DW-STATUS
           MOVE ZERO TO DW-CODE
           MOVE ZERO TO DW-SEQUENCE
           MOVE ZERO TO DW-EPOCH
           MOVE ZERO TO DW-S-DEPTH
           MOVE ZERO TO DW-S-CHOICE
           MOVE 999999 TO DW-S-MAX
           MOVE SPACES TO DW-ERROR
           MOVE SPACES TO DW-Q-RESULT
           MOVE ZERO TO DW-Q-MATCHES.

       DW-DISPATCH.
           EVALUATE DW-RX-COMMAND
               WHEN 'OPEN'
                   PERFORM DW-OPEN
               WHEN 'BEGIN'
                   PERFORM DW-BEGIN
               WHEN 'ASSERT'
                   PERFORM DW-ASSERT
               WHEN 'RETRACT'
                   PERFORM DW-RETRACT
               WHEN 'QUERY'
                   PERFORM DW-QUERY-EXECUTE
               WHEN 'UNIFY'
                   PERFORM DW-UNIFY
               WHEN 'BIND'
                   PERFORM DW-BIND
               WHEN 'UNBIND'
                   PERFORM DW-UNBIND
               WHEN 'CHOICE'
                   PERFORM DW-CHOICE
               WHEN 'BACKTRACK'
                   PERFORM DW-BACKTRACK
               WHEN 'RULE'
                   PERFORM DW-RULE
               WHEN 'EXECUTE'
                   PERFORM DW-RULE-EXECUTE
               WHEN 'SNAPSHOT'
                   PERFORM DW-SNAPSHOT
               WHEN 'RESTORE'
                   PERFORM DW-RESTORE
               WHEN 'COMMIT'
                   PERFORM DW-COMMIT
               WHEN 'ROLLBACK'
                   PERFORM DW-ROLLBACK
               WHEN 'ACH-ASSERT'
                   PERFORM ACH-ASSERT
               WHEN 'ACH-QUERY'
                   PERFORM ACH-QUERY
               WHEN 'FUNDS-ASSERT'
                   PERFORM FUNDS-ASSERT
               WHEN 'FUNDS-QUERY'
                   PERFORM FUNDS-QUERY
               WHEN OTHER
                   PERFORM DW-FAIL
           END-EVALUATE.

       DW-OPEN.
           MOVE 'DATAWORM' TO DW-NAMESPACE
           ADD 1 TO DW-SEQUENCE
           MOVE DW-SEQUENCE TO DW-EPOCH
           MOVE 'OPEN' TO DW-J-TYPE
           MOVE 'READY' TO DW-STATUS.

       DW-BEGIN.
           ADD 1 TO DW-SEQUENCE
           MOVE DW-SEQUENCE TO DW-T-START
           MOVE 'ACTIVE' TO DW-T-STATE
           MOVE ZERO TO DW-T-FACTS
           MOVE ZERO TO DW-T-RULES
           MOVE 'ACTIVE' TO DW-STATUS.

       DW-COMMIT.
           ADD 1 TO DW-SEQUENCE
           MOVE DW-SEQUENCE TO DW-T-END
           MOVE 'COMMITTED' TO DW-T-STATE
           PERFORM DW-JOURNAL-COMMIT
           MOVE 'COMMITTED' TO DW-STATUS.

       DW-ROLLBACK.
           ADD 1 TO DW-SEQUENCE
           MOVE 'ROLLED-BACK' TO DW-T-STATE
           PERFORM DW-JOURNAL-ROLLBACK
           MOVE 'ROLLED-BACK' TO DW-STATUS.

       DW-ASSERT.
           PERFORM DW-VALIDATE-FACT
           IF DW-STATUS = 'VALID'
               ADD 1 TO DW-SEQUENCE
               MOVE DW-SEQUENCE TO DW-F-SEQUENCE
               MOVE 'ACTIVE' TO DW-F-STATE
               PERFORM DW-FACT-HASH
               PERFORM DW-FACT-STORE
               PERFORM DW-INDEX
               PERFORM DW-JOURNAL-FACT
               ADD 1 TO DW-T-FACTS
               MOVE 'STORED' TO DW-STATUS
           ELSE
               MOVE 'REJECTED' TO DW-STATUS
           END-IF.

       DW-VALIDATE-FACT.
           MOVE 'VALID' TO DW-STATUS
           IF DW-F-PREDICATE = SPACES
               MOVE 'REJECTED' TO DW-STATUS
           END-IF
           IF DW-F-ARG1 = SPACES
               MOVE 'REJECTED' TO DW-STATUS
           END-IF.

       DW-FACT-HASH.
           MOVE SPACES TO DW-F-HASH
           STRING DW-F-PREDICATE
                  DW-F-ARG1
                  DW-F-ARG2
                  DW-F-ARG3
                  DW-F-ARG4
                  DW-F-SEQUENCE
                  DELIMITED BY SIZE
                  INTO DW-F-HASH
           END-STRING.

       DW-FACT-STORE.
           CONTINUE.

       DW-INDEX.
           MOVE DW-F-PREDICATE TO DW-I-PREDICATE
           MOVE DW-F-ARG1 TO DW-I-ARGUMENT
           MOVE DW-F-SEQUENCE TO DW-I-SEQUENCE
           MOVE 'ACTIVE' TO DW-I-STATE.

       DW-RETRACT.
           PERFORM DW-LOCATE
           IF DW-I-STATE = 'ACTIVE'
               MOVE 'RETRACTED' TO DW-F-STATE
               PERFORM DW-JOURNAL-RETRACT
               MOVE 'RETRACTED' TO DW-STATUS
           ELSE
               MOVE 'NOT-FOUND' TO DW-STATUS
           END-IF.

       DW-LOCATE.
           MOVE 'NONE' TO DW-I-STATE
           IF DW-F-PREDICATE = DW-I-PREDICATE
               IF DW-F-ARG1 = DW-I-ARGUMENT
                   MOVE 'ACTIVE' TO DW-I-STATE
               END-IF
           END-IF.

       DW-QUERY-EXECUTE.
           MOVE ZERO TO DW-Q-MATCHES
           MOVE 'N' TO DW-Q-RESULT
           PERFORM DW-QUERY-INDEX
           IF DW-Q-MATCHES > ZERO
               MOVE 'Y' TO DW-Q-RESULT
               MOVE 'MATCH' TO DW-STATUS
           ELSE
               MOVE 'NOMATCH' TO DW-STATUS
           END-IF.

       DW-QUERY-INDEX.
           IF DW-Q-PREDICATE = DW-I-PREDICATE
               IF DW-Q-A = SPACES
                   ADD 1 TO DW-Q-MATCHES
               ELSE
                   IF DW-Q-A = DW-I-ARGUMENT
                       ADD 1 TO DW-Q-MATCHES
                   END-IF
               END-IF
           END-IF.

       DW-UNIFY.
           IF DW-Q-A = DW-Q-B
               MOVE 'Y' TO DW-Q-RESULT
           ELSE
               IF DW-Q-A = SPACES
                   MOVE DW-Q-B TO DW-Q-A
                   MOVE 'Y' TO DW-Q-RESULT
               ELSE
                   IF DW-Q-B = SPACES
                       MOVE DW-Q-A TO DW-Q-B
                       MOVE 'Y' TO DW-Q-RESULT
                   ELSE
                       MOVE 'N' TO DW-Q-RESULT
                   END-IF
               END-IF
           END-IF.

       DW-BIND.
           ADD 1 TO DW-S-DEPTH
           IF DW-S-DEPTH > DW-S-MAX
               SUBTRACT 1 FROM DW-S-DEPTH
               MOVE 'STACK-OVERFLOW' TO DW-STATUS
           ELSE
               MOVE DW-Q-A TO DW-B-NAME
               MOVE DW-Q-B TO DW-B-VALUE
               MOVE 'Y' TO DW-B-BOUND
               MOVE DW-S-DEPTH TO DW-B-DEPTH
               MOVE 'BOUND' TO DW-STATUS
           END-IF.

       DW-UNBIND.
           IF DW-S-DEPTH > ZERO
               SUBTRACT 1 FROM DW-S-DEPTH
           END-IF
           MOVE 'UNBOUND' TO DW-STATUS.

       DW-CHOICE.
           ADD 1 TO DW-S-CHOICE
           ADD 1 TO DW-S-DEPTH
           IF DW-S-DEPTH > DW-S-MAX
               SUBTRACT 1 FROM DW-S-DEPTH
               MOVE 'STACK-OVERFLOW' TO DW-STATUS
           ELSE
               MOVE 'CHOICE' TO DW-S-STATE
               MOVE 'READY' TO DW-STATUS
           END-IF.

       DW-BACKTRACK.
           IF DW-S-DEPTH > ZERO
               SUBTRACT 1 FROM DW-S-DEPTH
               MOVE 'BACKTRACK' TO DW-S-STATE
               MOVE 'READY' TO DW-STATUS
           ELSE
               MOVE 'NO-CHOICE' TO DW-STATUS
           END-IF.

       DW-RULE.
           IF DW-R-HEAD = SPACES
               MOVE 'REJECTED' TO DW-STATUS
           ELSE
               ADD 1 TO DW-SEQUENCE
               MOVE 'ACTIVE' TO DW-R-STATE
               ADD 1 TO DW-T-RULES
               PERFORM DW-JOURNAL-RULE
               MOVE 'STORED' TO DW-STATUS
           END-IF.

       DW-RULE-EXECUTE.
           IF DW-R-HEAD = DW-Q-PREDICATE
               PERFORM DW-CHOICE
               PERFORM DW-UNIFY
               IF DW-Q-RESULT = 'Y'
                   MOVE 'RULE-SATISFIED' TO DW-STATUS
               ELSE
                   PERFORM DW-BACKTRACK
               END-IF
           ELSE
               MOVE 'RULE-NOMATCH' TO DW-STATUS
           END-IF.

       ACH-ASSERT.
           MOVE 'ach_entry' TO DW-F-PREDICATE
           MOVE AF-ENTRY-ID TO DW-F-ARG1
           MOVE AF-BATCH-ID TO DW-F-ARG2
           MOVE AF-TRACE TO DW-F-ARG3
           MOVE AF-AMOUNT TO DW-F-ARG4
           PERFORM DW-ASSERT
           MOVE DW-STATUS TO AF-STATE.

       ACH-QUERY.
           MOVE 'ach_entry' TO DW-Q-PREDICATE
           MOVE AF-ENTRY-ID TO DW-Q-A
           PERFORM DW-QUERY-EXECUTE
           IF DW-Q-RESULT = 'Y'
               MOVE 'FOUND' TO AF-STATE
           ELSE
               MOVE 'NOT-FOUND' TO AF-STATE
           END-IF.

       FUNDS-ASSERT.
           MOVE 'treasury_funds' TO DW-F-PREDICATE
           MOVE TF-ACCOUNT TO DW-F-ARG1
           MOVE TF-LEDGER TO DW-F-ARG2
           MOVE TF-AVAILABLE TO DW-F-ARG3
           MOVE TF-PENDING TO DW-F-ARG4
           PERFORM DW-ASSERT.

       FUNDS-QUERY.
           MOVE 'treasury_funds' TO DW-Q-PREDICATE
           MOVE TF-ACCOUNT TO DW-Q-A
           PERFORM DW-QUERY-EXECUTE.

       DW-JOURNAL-FACT.
           MOVE 'ASSERT' TO DW-J-TYPE
           MOVE DW-F-PREDICATE TO DW-J-OBJECT
           MOVE DW-F-SEQUENCE TO DW-J-SEQUENCE
           MOVE DW-F-HASH TO DW-J-HASH
           MOVE 'COMMITTED' TO DW-J-STATE.

       DW-JOURNAL-RETRACT.
           MOVE 'RETRACT' TO DW-J-TYPE
           MOVE DW-F-PREDICATE TO DW-J-OBJECT
           ADD 1 TO DW-SEQUENCE
           MOVE DW-SEQUENCE TO DW-J-SEQUENCE
           MOVE 'RETRACTED' TO DW-J-STATE.

       DW-JOURNAL-RULE.
           MOVE 'RULE' TO DW-J-TYPE
           MOVE DW-R-HEAD TO DW-J-OBJECT
           MOVE DW-SEQUENCE TO DW-J-SEQUENCE
           MOVE 'STORED' TO DW-J-STATE.

       DW-JOURNAL-COMMIT.
           MOVE 'COMMIT' TO DW-J-TYPE
           MOVE DW-SEQUENCE TO DW-J-SEQUENCE
           MOVE 'COMMITTED' TO DW-J-STATE.

       DW-JOURNAL-ROLLBACK.
           MOVE 'ROLLBACK' TO DW-J-TYPE
           MOVE DW-SEQUENCE TO DW-J-SEQUENCE
           MOVE 'ROLLED-BACK' TO DW-J-STATE.

       DW-SNAPSHOT.
           ADD 1 TO DW-SEQUENCE
           MOVE DW-SEQUENCE TO DW-EPOCH
           MOVE 'SNAPSHOT' TO DW-J-TYPE
           MOVE 'READY' TO DW-STATUS.

       DW-RESTORE.
           IF DW-EPOCH > ZERO
               MOVE DW-EPOCH TO DW-SEQUENCE
               MOVE 'RESTORED' TO DW-STATUS
           ELSE
               MOVE 'NO-SNAPSHOT' TO DW-STATUS
           END-IF.

       DW-REXX.
           EVALUATE DW-RX-COMMAND
               WHEN 'ASSERT-ACH'
                   PERFORM ACH-ASSERT
               WHEN 'QUERY-ACH'
                   PERFORM ACH-QUERY
               WHEN 'ASSERT-FUNDS'
                   PERFORM FUNDS-ASSERT
               WHEN 'QUERY-FUNDS'
                   PERFORM FUNDS-QUERY
               WHEN 'COMMIT'
                   PERFORM DW-COMMIT
               WHEN 'ROLLBACK'
                   PERFORM DW-ROLLBACK
               WHEN OTHER
                   PERFORM DW-FAIL
           END-EVALUATE
           PERFORM DW-RETURN.

       DW-FAIL.
           MOVE 'FAILED' TO DW-STATUS
           MOVE 999999 TO DW-CODE
           MOVE 'DATAWORM-OPERATION-REJECTED' TO DW-ERROR.

       DW-RETURN.
           STRING DW-STATUS
                  '|'
                  DW-SEQUENCE
                  '|'
                  DW-Q-RESULT
                  '|'
                  DW-Q-MATCHES
                  DELIMITED BY SIZE
                  INTO DW-RX-RESULT
           END-STRING.

       END PROGRAM COBILT-DATAWORM-TREASURY.
