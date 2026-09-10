PROGRAM ach_return.

FILE achitem USING ACHITEM
    KEY company(3), batch(10), entry(15).

RECORD item IN achitem (
    company   CHAR(3),
    batch     CHAR(10),
    entry     CHAR(15),
    state     ENUM(NEW, POSTED, SETTLED, RETURNED),
    amount    NUM(13,2),
    reason    CHAR(3)
).

PROC return_item(company, batch, entry, reason) IS
    LOAD item(company, batch, entry) AS it
        IF NOTFOUND THEN
            FAIL "NOTFOUND";
        ENDIF;

    IF it.state NOT IN (POSTED, SETTLED) THEN
        FAIL "BADSTATE";
    ENDIF;

    IF it.state = RETURNED THEN
        FAIL "ALREADYRT";
    ENDIF;

    it.state  := RETURNED;
    it.reason := reason;

    SAVE it;
ENDPROC.
