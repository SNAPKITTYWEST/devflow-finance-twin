% ========================================================================
% SOVEREIGN LEVIATHAN NODE LICENSE
% License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
% Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
% ========================================================================
%
% This file is a covered work under the GNU Affero General Public License,
% version 3, together with the Sovereign Leviathan additional terms.
%
% Hark, though this node be but a spark,
% Its covenant endureth through the dark.
%
% Ignorantia juris non excusat.
% ========================================================================

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
