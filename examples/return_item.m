% Mercury backend: return_item

:- type state ---> new ; posted ; settled ; returned.

:- pred achitem(string, string, string, state, float, string).
:- mode achitem(in, in, in, out, out, out) is semidet.

:- pred return_item(string, string, string, string, state).
:- mode return_item(in, in, in, in, out) is det.

return_item(C, B, E, Reason, NewState) :-
    ( if achitem(C, B, E, State, _Amt, _OldReason) then
        ( if (State = posted ; State = settled) then
            ( if State = returned then
                % error path could be separate predicate
                NewState = returned
              else
                NewState = returned
            )
          else
            NewState = State
        )
      else
        % notfound case; again, better as separate predicate
        NewState = new
    ).
