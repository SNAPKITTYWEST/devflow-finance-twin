       IDENTIFICATION DIVISION.
       PROGRAM-ID. ACHRTRN.

       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT ACHITEM-FILE ASSIGN TO ACHITEM
               ORGANIZATION IS INDEXED
               ACCESS MODE IS DYNAMIC
               RECORD KEY IS AI-KEY
               FILE STATUS IS AI-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD  ACHITEM-FILE.
       01  ACHITEM-REC.
           05 AI-COMPANY   PIC X(03).
           05 AI-BATCH     PIC X(10).
           05 AI-ENTRY     PIC X(15).
           05 AI-STATE     PIC X(12).
           05 AI-AMOUNT    PIC S9(13)V99 COMP-3.
           05 AI-REASON    PIC X(03).

       WORKING-STORAGE SECTION.
       01  AI-STATUS      PIC X(02).

       LINKAGE SECTION.
       01  LK-COMPANY     PIC X(03).
       01  LK-BATCH       PIC X(10).
       01  LK-ENTRY       PIC X(15).
       01  LK-REASON      PIC X(03).
       01  LK-ERR-CODE    PIC X(08).
       01  LK-ERR-MSG     PIC X(80).

       PROCEDURE DIVISION USING LK-COMPANY LK-BATCH LK-ENTRY LK-REASON
                                 LK-ERR-CODE LK-ERR-MSG.

       MAIN-SECTION.
           MOVE LK-COMPANY TO AI-COMPANY
           MOVE LK-BATCH   TO AI-BATCH
           MOVE LK-ENTRY   TO AI-ENTRY

           READ ACHITEM-FILE
               INVALID KEY
                   MOVE 'NOTFOUND' TO LK-ERR-CODE
                   MOVE 'ACH item not found' TO LK-ERR-MSG
                   GOBACK
           END-READ

           IF AI-STATE NOT = 'POSTED'
              AND AI-STATE NOT = 'SETTLED'
               MOVE 'BADSTATE' TO LK-ERR-CODE
               MOVE 'Item state not returnable' TO LK-ERR-MSG
               GOBACK
           END-IF

           IF AI-STATE = 'RETURNED'
               MOVE 'ALREADYRT' TO LK-ERR-CODE
               MOVE 'Item already returned' TO LK-ERR-MSG
               GOBACK
           END-IF

           MOVE 'RETURNED' TO AI-STATE
           MOVE LK-REASON TO AI-REASON

           REWRITE ACHITEM-REC
               INVALID KEY
                   MOVE 'DBERR' TO LK-ERR-CODE
                   MOVE 'Rewrite failed' TO LK-ERR-MSG
                   GOBACK
           END-REWRITE

           MOVE 'OK' TO LK-ERR-CODE
           MOVE 'Return accepted' TO LK-ERR-MSG
           GOBACK.
