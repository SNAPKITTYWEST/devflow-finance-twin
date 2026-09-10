% Mercury backend: post_entry / ledger_post

:- type drcr ---> d ; c.

:- pred ledger_entry(string, string, int, float, drcr).
:- mode ledger_entry(in, in, in, out, out) is semidet.

:- pred post_entry(string, string, int, float, drcr, float).
:- mode post_entry(in, in, in, in, in, out) is det.

post_entry(Company, Date, Seq, Amount, DrCr, NewAmount) :-
    ( if ledger_entry(Company, Date, Seq, OldAmount, DrCr) then
        NewAmount = OldAmount + Amount
    else
        NewAmount = Amount
    ).
