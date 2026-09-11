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
