% Prolog backend: return_item / ach_return

return_item(Item, Reason, ResultItem, ok) :-
    returnable(Item),
    Item = item(C,B,E,state(State),Amt,_),
    State \= returned,
    ResultItem = item(C,B,E,state(returned),Amt,Reason).

return_item(Item, Reason, Item, error(alreadyrt)) :-
    Item = item(_,_,_,state(returned),_,_).

return_item(Item, Reason, Item, error(badstate)) :-
    Item = item(_,_,_,state(State),_,_),
    \+ (State = posted ; State = settled).

returnable(Item) :-
    Item = item(_, _, _, state(State), _, _),
    (State = posted ; State = settled).

item(company(C), batch(B), entry(E),
     state(State), amount(Amt), reason(Reason)).
