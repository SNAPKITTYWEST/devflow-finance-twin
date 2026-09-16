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
