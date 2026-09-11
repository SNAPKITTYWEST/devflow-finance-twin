â ========================================================================
â SOVEREIGN LEVIATHAN NODE LICENSE
â License-ID: SL-AGPL3-001 | Covenant-Version: 1.0
â Copyright (C) 2026 SnapKittyWest. Ahmad Ali Parr, Bel Esprit D'Accord Irrevocable Trust.
â ========================================================================
â
â This file is a covered work under the GNU Affero General Public License,
â version 3, together with the Sovereign Leviathan additional terms.
â
â Hark, though this node be but a spark,
â Its covenant endureth through the dark.
â
â Ignorantia juris non excusat.
â ========================================================================

â --- Exec interpreter (returns state successFlag) ---
Exec â† {
    state â† âº
    blob ip evidence â† âµ

    :If ip â‰¥ â‰¢blob
        (state 1)
    :Return
    :EndIf

    op â† blob[ip]

    :Select op
    :Case 0
        (state 1)

    :Case 1
        x â† blob[ip+1]
        Exec (state + x) (blob ip+2 evidence)

    :Case 2
        x â† blob[ip+1]
        Exec (state Ã— x) (blob ip+2 evidence)

    :Case 3
        n â† blob[ip+1]
        sub â† blob[(ip+2) + â³n]
        subState success â† Exec state (sub 0 evidence)
        :If success = 0
            (subState 0)
        :Else
            Exec subState (blob ip+2+n evidence)
        :EndIf

    :Case 4
        Exec (Contract state) (blob ip+1 evidence)

    :Case 9
        cid â† blob[ip+1] â check id index into checkRegistry
        checkFn â† checkRegistry[cid]
        pass â† checkFn ( ( (cid=3) / (evidence.gap) ) , state ) â pass evidence and state
        :If pass = 0
            (state 0)
        :Else
            Exec state (blob ip+2 evidence)
        :EndIf

    :Else
        (state 0)
    :EndSelect
}

â --- Contract function (Taylor-like) ---
Contract â† {
    a â† âµ
    r â† 0.5
    r Ã— a Ã· (1+â³â‰¢a)
}

â --- Braid encoding for A01 (using check ids) ---
Ïƒ1 â† 1 3
Ïƒ2 â† 2 2
Ïƒ3inv â† 9 0      â OS gate id 0
Ïƒ4 â† 3 3 1 2 0
Ïƒ5 â† 1 5
Ïƒ6inv â† 9 1      â Vacuum gate id 1
Ïƒ7 â† 2 3
Ïƒ8 â† 4
Ïƒ9inv â† 9 2      â Correlation decay id 2
Ïƒ10 â† 3 2 1 4

B_blob â† Ïƒ1,Ïƒ2,Ïƒ3inv,Ïƒ4,Ïƒ5,Ïƒ6inv,Ïƒ7,Ïƒ8,Ïƒ9inv,Ïƒ10

â --- Run braid with evidence ---
initState â† 10 8 6 4 2
state success â† Exec initState (B_blob 0 evidence)

LEDGER_STATE â† 'LOCKED'
:If success = 1
    LEDGER_STATE â† 'UNLOCKED'
:EndIf

LEDGER_STATE