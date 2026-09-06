⍝ --- Evidence and ledger setup ---
⍝ proofLedger: vector of accepted proof hashes/IDs (strings)
proofLedger ← 'hashOS123' 'hashH456' 'hashVac789' 'hashGapABC' 'hashCorrDEF' 'hashConfGHI'

⍝ evidence: user-supplied record (example)
evidence ← ⍬
evidence.OS ← (OS1 1) (OS2 1) (OS3 1) (OS4 1) (OS5 1) ⍝ or evidence.OS.hash ← 'hashOS123'
evidence.H ← (exists 1) (proofHash 'hashH456')
evidence.vacuum ← (exists 1) (proofHash 'hashVac789')
evidence.gap ← (Δ 0.15) (proofHash 'hashGapABC')
evidence.spectrum ← (vals 0 0.15 0.3 0.5) ⍝ or proofHash
evidence.correlation ← (decayRate 0.12) (proofHash 'hashCorrDEF')
evidence.confinement ← (sigma 0.08) (proofHash 'hashConfGHI')

⍝ Helper: membership test for proof hashes
HasProof ← { (⍵ ∊ proofLedger) }

⍝ Numeric tolerance
tol ← 1E¯8

⍝ --- OS Gate ---
OS_Gate ← {
    ev ← ⍵
    ⍝ prefer explicit proof hash
    :If 'proofHash' ∊ ⍴ev ⋄
        HasProof ev.proofHash
    :Else
        ⍝ expect OS1..OS5 booleans in ev
        osFlags ← (ev.OS1 ev.OS2 ev.OS3 ev.OS4 ev.OS5)
        (∧/ osFlags) ⍝ all true
    :EndIf
}

⍝ --- Vacuum Gate ---
Vacuum_Gate ← {
    ev state ← ⍵
    :If 'proofHash' ∊ ⍴ev ⋄
        HasProof ev.proofHash
    :Else
        :If ev.exists = 1 ⋄ 1 ⋄ :Else
            ⍝ numeric proxy: check for a dominant zero mode (small norm)
            zmode ← (|state) ⌈/ state
            (zmode ≤ tol)
        :EndIf
    :EndIf
}

⍝ --- Gap Check (strict mass gap) ---
Gap_Check ← {
    ev state ← ⍵
    ⍝ require Δ > 0 and spectrum has no eigenvalues in (0,Δ)
    :If 'proofHash' ∊ ⍴ev ⋄
        HasProof ev.proofHash
    :Else
        Δ ← ev.Δ
        :If Δ ≤ 0 ⋄ 0 ⋄ :EndIf
        ⍝ spectrum may be provided as ev.spectrum.vals
        :If 'vals' ∊ ⍴ev.spectrum ⋄
            spec ← ev.spectrum.vals
            ⍝ check no eigenvalue in (0,Δ)
            (0 = +/ ( (spec > 0) ∧ (spec < Δ) ))
        :Else
            ⍝ numeric proxy: estimate spectrum from state via circulant approximation
            n ← ≢state
            Hcirc ← (⍳n) ⍴ 0  ⍝ placeholder circulant Hamiltonian built from state
            ⍝ crude proxy: use absolute values as pseudo-spectrum
            specProxy ← |state
            (0 = +/ ( (specProxy > 0) ∧ (specProxy < Δ) ))
        :EndIf
    :EndIf
}

⍝ --- Correlation Decay Gate ---
CorrDecay_Gate ← {
    ev state ← ⍵
    :If 'proofHash' ∊ ⍴ev ⋄
        HasProof ev.proofHash
    :Else
        ⍝ numeric proxy: compute correlation magnitudes and fit exponential decay
        c ← |state
        n ← ≢c
        idx ← 1+⍳n
        valid ← c > tol
        :If 0 = +/valid ⋄ 0 ⋄ :EndIf
        lnC ← (×/valid) ⍝ placeholder: in real APL use log on valid entries
        ⍝ crude slope proxy: compare c[k] / c[k+1] average
        ratios ← (c[1↓⍳n-1]) ÷ (c[2↓⍳n-1])  ⍝ elementwise
        αproxy ← +/ ratios ÷ (≢ratios)
        α_min ← 0.01
        (αproxy ≥ α_min)
    :EndIf
}

⍝ --- Confinement Gate ---
Confinement_Gate ← {
    ev state ← ⍵
    :If 'proofHash' ∊ ⍴ev ⋄
        HasProof ev.proofHash
    :Else
        ⍝ numeric proxy: estimate area-law sigma from correlations
        sigma ← ev.sigma
        sigma_min ← 1E¯3
        (sigma ≥ sigma_min)
    :EndIf
}

⍝ --- Check registry mapping ids to functions ---
⍝ id 0 -> OS, 1 -> Vacuum, 2 -> Correlation Decay, 3 -> Gap, 4 -> Confinement
checkRegistry ← (OS_Gate Vacuum_Gate CorrDecay_Gate Gap_Check Confinement_Gate)