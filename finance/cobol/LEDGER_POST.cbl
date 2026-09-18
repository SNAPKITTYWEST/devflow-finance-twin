       IDENTIFICATION DIVISION.
       PROGRAM-ID. LEDGER_POST.

       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT LEDGER-FILE ASSIGN TO LEDGER
               ORGANIZATION IS INDEXED
               ACCESS MODE IS DYNAMIC
               RECORD KEY IS LG-KEY
               FILE STATUS IS LG-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD LEDGER-FILE.
       01 LEDGER-REC.
          05 LG-COMPANY   PIC X(03).
          05 LG-DATE      PIC X(08).
          05 LG-SEQ       PIC 9(09).
          05 LG-AMOUNT    PIC S9(15)V99 COMP-3.
          05 LG-DRCR      PIC X(01).

       WORKING-STORAGE SECTION.
       01 LG-STATUS       PIC X(02).

       PROCEDURE DIVISION.

       POST-ENTRY-SECTION.
           *> parameters mapped via LINKAGE or wrapper
           READ LEDGER-FILE
               INVALID KEY
                   MOVE PARAM-COMPANY TO LG-COMPANY
                   MOVE PARAM-DATE    TO LG-DATE
                   MOVE PARAM-SEQ     TO LG-SEQ
                   MOVE PARAM-AMOUNT  TO LG-AMOUNT
                   MOVE PARAM-DRCR    TO LG-DRCR
                   WRITE LEDGER-REC
               NOT INVALID KEY
                   ADD PARAM-AMOUNT TO LG-AMOUNT
                   WRITE LEDGER-REC
           END-READ.
           GOBACK.
