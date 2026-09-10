% Prolog backend: post_entry / ledger_post

% Facts
achitem(company(C), batch(B), entry(E),
        state(State), amount(Amt), reason(Reason)).

% Return eligibility
returnable_state(posted).
returnable_state(settled).

already_returned(returned).

% Operation semantics
return_item(C, B, E, Reason, NewState) :-
    achitem(company(C), batch(B), entry(E),
            state(State), amount(Amt), reason(_)),
    returnable_state(State),
    \+ already_returned(State),
    NewState = returned.

% Error cases as separate predicates or tagged results
return_item_error(C, B, E, Reason, notfound) :-
    \+ achitem(company(C), batch(B), entry(E), _, _, _).

return_item_error(C, B, E, Reason, badstate) :-
    achitem(company(C), batch(B), entry(E),
            state(State), _, _),
    \+ returnable_state(State).

return_item_error(C, B, E, Reason, alreadyrt) :-
    achitem(company(C), batch(B), entry(E),
            state(State), _, _),
    already_returned(State).
