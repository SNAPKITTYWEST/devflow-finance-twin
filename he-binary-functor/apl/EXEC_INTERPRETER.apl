⍝ --- Exec interpreter (returns state successFlag) ---
Exec ← {
    state ← ⍺
    blob ip evidence ← ⍵

    :If ip ≥ ≢blob
        (state 1)
    :Return
    :EndIf

    op ← blob[ip]

    :Select op
    :Case 0
        (state 1)

    :Case 1
        x ← blob[ip+1]
        Exec (state + x) (blob ip+2 evidence)

    :Case 2
        x ← blob[ip+1]
        Exec (state × x) (blob ip+2 evidence)

    :Case 3
        n ← blob[ip+1]
        sub ← blob[(ip+2) + ⍳n]
        subState success ← Exec state (sub 0 evidence)
        :If success = 0
            (subState 0)
        :Else
            Exec subState (blob ip+2+n evidence)
        :EndIf

    :Case 4
        Exec (Contract state) (blob ip+1 evidence)

    :Case 9
        cid ← blob[ip+1] ⍝ check id index into checkRegistry
        checkFn ← checkRegistry[cid]
        pass ← checkFn ( ( (cid=3) / (evidence.gap) ) , state ) ⍝ pass evidence and state
        :If pass = 0
            (state 0)
        :Else
            Exec state (blob ip+2 evidence)
        :EndIf

    :Else
        (state 0)
    :EndSelect
}

⍝ --- Contract function (Taylor-like) ---
Contract ← {
    a ← ⍵
    r ← 0.5
    r × a ÷ (1+⍳≢a)
}

⍝ --- Braid encoding for A01 (using check ids) ---
σ1 ← 1 3
σ2 ← 2 2
σ3inv ← 9 0      ⍝ OS gate id 0
σ4 ← 3 3 1 2 0
σ5 ← 1 5
σ6inv ← 9 1      ⍝ Vacuum gate id 1
σ7 ← 2 3
σ8 ← 4
σ9inv ← 9 2      ⍝ Correlation decay id 2
σ10 ← 3 2 1 4

B_blob ← σ1,σ2,σ3inv,σ4,σ5,σ6inv,σ7,σ8,σ9inv,σ10

⍝ --- Run braid with evidence ---
initState ← 10 8 6 4 2
state success ← Exec initState (B_blob 0 evidence)

LEDGER_STATE ← 'LOCKED'
:If success = 1
    LEDGER_STATE ← 'UNLOCKED'
:EndIf

LEDGER_STATE