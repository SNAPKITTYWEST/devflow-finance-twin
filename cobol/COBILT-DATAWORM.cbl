      ******************************************************************
      * COBILT-DATAWORM
      * DATALOG STORAGE ENGINE
      * DATAWORM REPLACES SQL PERSISTENCE
      * REXX -> COBOL -> DATALOG -> DATAWORM
      * NO SQL / NO ASSEMBLER
      ******************************************************************

       IDENTIFICATION DIVISION.
       PROGRAM-ID. COBILT-DATAWORM.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       SOURCE-COMPUTER. IBM-I.
       OBJECT-COMPUTER. IBM-I.

       DATA DIVISION.
       WORKING-STORAGE SECTION.

       01 DW-CONTEXT.
           05 DW-STATUS PIC X(16).
           05 DW-RETURN PIC S9(9) COMP-3.
           05 DW-ERROR PIC X(128).
           05 DW-NAMESPACE PIC X(64).
           05 DW-STORE PIC X(64).
           05 DW-SEQUENCE PIC 9(18).

       01 DW-FACT.
           05 DW-F-PREDICATE PIC X(64).
           05 DW-F-ARG1 PIC X(128).
           05 DW-F-ARG2 PIC X(128).
           05 DW-F-ARG3 PIC X(128).
           05 DW-F-ARG4 PIC X(128).
           05 DW-F-STATE PIC X(16).
           05 DW-F-SEQUENCE PIC 9(18).
           05 DW-F-HASH PIC X(64).

       01 DW-RULE.
           05 DW-R-HEAD PIC X(64).
           05 DW-R-BODY PIC X(512).
           05 DW-R-PRIORITY PIC 9(6).
           05 DW-R-STATE PIC X(16).

       01 DW-BINDING.
           05 DW-B-NAME PIC X(64).
           05 DW-B-VALUE PIC X(128).
           05 DW-B-BOUND PIC X.
           05 DW-B-DEPTH PIC 9(6).

       01 DW-INDEX.
           05 DW-I-PREDICATE PIC X(64).
           05 DW-I-ARGUMENT PIC X(128).
           05 DW-I-SEQUENCE PIC 9(18).
           05 DW-I-FOUND PIC X.

       01 DW-JOURNAL.
           05 DW-J-TYPE PIC X(16).
           05 DW-J-OBJECT PIC X(64).
           05 DW-J-SEQUENCE PIC 9(18).
           05 DW-J-PREV-HASH PIC X(64).
           05 DW-J-HASH PIC X(64).
           05 DW-J-STATE PIC X(16).

       01 DW-QUERY.
           05 DW-Q-PREDICATE PIC X(64).
           05 DW-Q-A PIC X(128).
           05 DW-Q-B PIC X(128).
           05 DW-Q-C PIC X(128).
           05 DW-Q-D PIC X(128).
           05 DW-Q-RESULT PIC X.
           05 DW-Q-MATCHES PIC 9(9).

       01 DW-TRANSACTION.
           05 DW-T-ID PIC X(64).
           05 DW-T-STATE PIC X(16).
           05 DW-T-START PIC 9(18).
           05 DW-T-END PIC 9(18).
           05 DW-T-FACT-COUNT PIC 9(9).
           05 DW-T-RULE-COUNT PIC 9(9).

       01 DW-STACK.
           05 DW-S-DEPTH PIC 9(6).
           05 DW-S-MAX PIC 9(6).
           05 DW-S-STATE PIC X(16).

       01 DW-REXX.
           05 DW-RX-COMMAND PIC X(64).
           05 DW-RX-PAYLOAD PIC X(512).
           05 DW-RX-RESULT PIC X(512).

       PROCEDURE DIVISION.

       DW-INITIALIZE.
           MOVE 'READY' TO DW-STATUS
           MOVE ZERO TO DW-RETURN
           MOVE ZERO TO DW-SEQUENCE
           MOVE ZERO TO DW-S-DEPTH
           MOVE 999999 TO DW-S-MAX
           MOVE SPACES TO DW-ERROR
           MOVE SPACES TO DW-Q-RESULT
           MOVE ZERO TO DW-Q-MATCHES.

       DW-OPEN.
           PERFORM DW-INITIALIZE
           MOVE 'DATAWORM' TO DW-STORE
           MOVE 'DATALOG' TO DW-NAMESPACE
           MOVE 'OPEN' TO DW-STATUS
           PERFORM DW-JOURNAL-OPEN.

       DW-CLOSE.
           PERFORM DW-JOURNAL-CLOSE
           MOVE 'CLOSED' TO DW-STATUS.

       DW-BEGIN.
           ADD 1 TO DW-SEQUENCE
           MOVE 'ACTIVE' TO DW-T-STATE
           MOVE DW-SEQUENCE TO DW-T-START
           MOVE ZERO TO DW-T-FACT-COUNT
           MOVE ZERO TO DW-T-RULE-COUNT.

       DW-COMMIT.
           ADD 1 TO DW-SEQUENCE
           MOVE DW-SEQUENCE TO DW-T-END
           MOVE 'COMMITTED' TO DW-T-STATE
           PERFORM DW-JOURNAL-COMMIT
           MOVE 'COMMITTED' TO DW-STATUS.

       DW-ROLLBACK.
           MOVE 'ROLLED-BACK' TO DW-T-STATE
           PERFORM DW-JOURNAL-ROLLBACK
           MOVE 'ROLLED-BACK' TO DW-STATUS.

       DW-ASSERT.
           PERFORM DW-FACT-VALIDATE
           IF DW-STATUS = 'VALID'
               ADD 1 TO DW-SEQUENCE
               MOVE DW-SEQUENCE TO DW-F-SEQUENCE
               MOVE 'ACTIVE' TO DW-F-STATE
               PERFORM DW-FACT-HASH
               PERFORM DW-FACT-STORE
               PERFORM DW-INDEX-FACT
               PERFORM DW-JOURNAL-FACT
               ADD 1 TO DW-T-FACT-COUNT
               MOVE 'STORED' TO DW-STATUS
           ELSE
               MOVE 'REJECTED' TO DW-STATUS
           END-IF.

       DW-FACT-VALIDATE.
           MOVE 'VALID' TO DW-STATUS
           IF DW-F-PREDICATE = SPACES
               MOVE 'REJECTED' TO DW-STATUS
           END-IF
           IF DW-F-ARG1 = SPACES
               MOVE 'REJECTED' TO DW-STATUS
           END-IF.

       DW-FACT-HASH.
           MOVE SPACES TO DW-F-HASH
           STRING
               DW-F-PREDICATE
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

       DW-INDEX-FACT.
           MOVE DW-F-PREDICATE TO DW-I-PREDICATE
           MOVE DW-F-ARG1 TO DW-I-ARGUMENT
           MOVE DW-F-SEQUENCE TO DW-I-SEQUENCE
           MOVE 'Y' TO DW-I-FOUND.

       DW-JOURNAL-FACT.
           MOVE 'ASSERT' TO DW-J-TYPE
           MOVE DW-F-PREDICATE TO DW-J-OBJECT
           MOVE DW-F-SEQUENCE TO DW-J-SEQUENCE
           MOVE DW-F-HASH TO DW-J-HASH
           MOVE 'COMMITTED' TO DW-J-STATE.

       DW-RETRACT.
           PERFORM DW-FACT-LOCATE
           IF DW-I-FOUND = 'Y'
               MOVE 'RETRACTED' TO DW-F-STATE
               PERFORM DW-JOURNAL-RETRACT
               MOVE 'RETRACTED' TO DW-STATUS
           ELSE
               MOVE 'NOT-FOUND' TO DW-STATUS
           END-IF.

       DW-FACT-LOCATE.
           MOVE 'N' TO DW-I-FOUND
           IF DW-I-PREDICATE = DW-F-PREDICATE
               IF DW-I-ARGUMENT = DW-F-ARG1
                   MOVE 'Y' TO DW-I-FOUND
               END-IF
           END-IF.

       DW-QUERY.
           MOVE 'N' TO DW-Q-RESULT
           MOVE ZERO TO DW-Q-MATCHES
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
               MOVE 'STACK-OVERFLOW' TO DW-STATUS
               SUBTRACT 1 FROM DW-S-DEPTH
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
           ADD 1 TO DW-S-DEPTH
           IF DW-S-DEPTH > DW-S-MAX
               MOVE 'STACK-OVERFLOW' TO DW-STATUS
               SUBTRACT 1 FROM DW-S-DEPTH
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

       DW-RULE-STORE.
           IF DW-R-HEAD = SPACES
               MOVE 'REJECTED' TO DW-STATUS
           ELSE
               ADD 1 TO DW-SEQUENCE
               MOVE 'ACTIVE' TO DW-R-STATE
               ADD 1 TO DW-T-RULE-COUNT
               PERFORM DW-JOURNAL-RULE
               MOVE 'STORED' TO DW-STATUS
           END-IF.

       DW-RULE-MATCH.
           MOVE 'N' TO DW-Q-RESULT
           IF DW-R-HEAD = DW-Q-PREDICATE
               MOVE 'Y' TO DW-Q-RESULT
               MOVE 'MATCH' TO DW-STATUS
           ELSE
               MOVE 'NOMATCH' TO DW-STATUS
           END-IF.

       DW-RULE-EXECUTE.
           PERFORM DW-RULE-MATCH
           IF DW-Q-RESULT = 'Y'
               PERFORM DW-CHOICE
               PERFORM DW-UNIFY
               IF DW-Q-RESULT = 'Y'
                   MOVE 'RULE-SATISFIED' TO DW-STATUS
               ELSE
                   PERFORM DW-BACKTRACK
               END-IF
           END-IF.

       DW-JOURNAL-OPEN.
           MOVE 'OPEN' TO DW-J-TYPE
           ADD 1 TO DW-SEQUENCE
           MOVE DW-SEQUENCE TO DW-J-SEQUENCE.

       DW-JOURNAL-CLOSE.
           MOVE 'CLOSE' TO DW-J-TYPE
           ADD 1 TO DW-SEQUENCE
           MOVE DW-SEQUENCE TO DW-J-SEQUENCE.

       DW-JOURNAL-COMMIT.
           MOVE 'COMMIT' TO DW-J-TYPE
           ADD 1 TO DW-SEQUENCE
           MOVE DW-SEQUENCE TO DW-J-SEQUENCE
           MOVE 'COMMITTED' TO DW-J-STATE.

       DW-JOURNAL-ROLLBACK.
           MOVE 'ROLLBACK' TO DW-J-TYPE
           ADD 1 TO DW-SEQUENCE
           MOVE DW-SEQUENCE TO DW-J-SEQUENCE
           MOVE 'ROLLED-BACK' TO DW-J-STATE.

       DW-JOURNAL-RETRACT.
           MOVE 'RETRACT' TO DW-J-TYPE
           ADD 1 TO DW-SEQUENCE
           MOVE DW-SEQUENCE TO DW-J-SEQUENCE
           MOVE 'RETRACTED' TO DW-J-STATE.

       DW-JOURNAL-RULE.
           MOVE 'RULE' TO DW-J-TYPE
           ADD 1 TO DW-SEQUENCE
           MOVE DW-SEQUENCE TO DW-J-SEQUENCE
           MOVE DW-R-HEAD TO DW-J-OBJECT
           MOVE 'STORED' TO DW-J-STATE.

       DW-REXX-DISPATCH.
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
                   PERFORM DW-QUERY
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
                   PERFORM DW-RULE-STORE
               WHEN 'EXECUTE'
                   PERFORM DW-RULE-EXECUTE
               WHEN 'COMMIT'
                   PERFORM DW-COMMIT
               WHEN 'ROLLBACK'
                   PERFORM DW-ROLLBACK
               WHEN 'CLOSE'
                   PERFORM DW-CLOSE
               WHEN OTHER
                   PERFORM DW-FAIL-CLOSED
           END-EVALUATE.

       DW-FAIL-CLOSED.
           MOVE 'FAILED' TO DW-STATUS
           MOVE 999999 TO DW-RETURN
           MOVE 'UNKNOWN-DATAWORM-COMMAND' TO DW-ERROR.

       DW-EXPORT-RESULT.
           MOVE DW-STATUS TO DW-RX-RESULT
           STRING
               DW-STATUS
               '|'
               DW-SEQUENCE
               '|'
               DW-Q-RESULT
               '|'
               DW-Q-MATCHES
               DELIMITED BY SIZE
               INTO DW-RX-RESULT
           END-STRING.

       DW-VERIFY-JOURNAL.
           IF DW-J-SEQUENCE = ZERO
               MOVE 'INVALID' TO DW-STATUS
           ELSE
               IF DW-J-STATE = SPACES
                   MOVE 'INVALID' TO DW-STATUS
               ELSE
                   MOVE 'VALID' TO DW-STATUS
               END-IF
           END-IF.

       DW-VERIFY-FACT.
           IF DW-F-PREDICATE = SPACES
               MOVE 'INVALID' TO DW-STATUS
           ELSE
               IF DW-F-HASH = SPACES
                   MOVE 'INVALID' TO DW-STATUS
               ELSE
                   MOVE 'VALID' TO DW-STATUS
               END-IF
           END-IF.

       DW-VERIFY-RULE.
           IF DW-R-HEAD = SPACES
               MOVE 'INVALID' TO DW-STATUS
           ELSE
               IF DW-R-BODY = SPACES
                   MOVE 'INVALID' TO DW-STATUS
               ELSE
                   MOVE 'VALID' TO DW-STATUS
               END-IF
           END-IF.

       DW-RESET-QUERY.
           MOVE SPACES TO DW-Q-PREDICATE
           MOVE SPACES TO DW-Q-A
           MOVE SPACES TO DW-Q-B
           MOVE SPACES TO DW-Q-C
           MOVE SPACES TO DW-Q-D
           MOVE SPACES TO DW-Q-RESULT
           MOVE ZERO TO DW-Q-MATCHES.

       DW-RESET-BINDINGS.
           MOVE ZERO TO DW-S-DEPTH
           MOVE 'CLEAR' TO DW-S-STATE
           MOVE 'READY' TO DW-STATUS.

       DW-RESET-TRANSACTION.
           MOVE ZERO TO DW-T-FACT-COUNT
           MOVE ZERO TO DW-T-RULE-COUNT
           MOVE ZERO TO DW-T-START
           MOVE ZERO TO DW-T-END
           MOVE 'IDLE' TO DW-T-STATE.

       DW-SNAPSHOT.
           ADD 1 TO DW-SEQUENCE
           MOVE DW-SEQUENCE TO DW-J-SEQUENCE
           MOVE 'SNAPSHOT' TO DW-J-TYPE
           MOVE 'SNAPSHOT' TO DW-J-STATE.

       DW-RESTORE.
           IF DW-J-SEQUENCE > ZERO
               MOVE 'RESTORED' TO DW-STATUS
           ELSE
               MOVE 'NO-SNAPSHOT' TO DW-STATUS
           END-IF.

       DW-END.
           PERFORM DW-RESET-QUERY
           PERFORM DW-RESET-BINDINGS
           MOVE 'READY' TO DW-STATUS.

       END PROGRAM COBILT-DATAWORM.
