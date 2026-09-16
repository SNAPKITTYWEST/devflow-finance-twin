PROGRAM ledger_post.

FILE ledger USING LEDGER
    KEY company(3), date(8), seq(9).

RECORD entry IN ledger (
    company   CHAR(3),
    date      CHAR(8),
    seq       NUM(9),
    amount    NUM(15,2),
    drcr      CHAR(1)
).

PROC post_entry(company, date, seq, amount, drcr) IS
    READ entry(company, date, seq) IF NOTFOUND THEN
        NEW entry(company, date, seq, amount, drcr).
        WRITE entry.
    ELSE
        entry.amount := entry.amount + amount.
        WRITE entry.
    ENDIF.
ENDPROC.
