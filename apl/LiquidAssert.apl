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

â ================================================================
â LIQUIDAPL FLOW ASSERTION LIBRARY
â ================================================================
â File: LiquidAssert.apl
â Purpose: deterministic tensor-state integrity assertions
â Style: Dyalog APL
â ================================================================
â
â Convention:
â   âº = configuration / thresholds
â   âµ = tensor / state
â
â Configuration vectors commonly use:
â   [epsilon chiMax]
â
â The library is intentionally assertion-oriented.
â ================================================================

âŽ•IOâ†1
âŽ•MLâ†1

â ----------------------------------------------------------------
â 001  CONSTANTS
â ----------------------------------------------------------------

LiquidVersionâ†'1.0.0'
DefaultEpsilonâ†1EÂ¯10
DefaultChiMaxâ†64
DefaultNormTargetâ†1
DefaultTraceEpsilonâ†1EÂ¯10
DefaultEnergyEpsilonâ†1EÂ¯10

â ----------------------------------------------------------------
â 002  BASIC NUMERIC PREDICATES
â ----------------------------------------------------------------

IsFiniteâ†{
    vâ†âµ
    ^/((v=v)âˆ¨(vâ‰ v))
}

IsScalarâ†{
    1=â‰¢â´âµ
}

IsVectorâ†{
    1=â‰¢â´âµ
}

IsArrayâ†{
    0<â‰¢â´âµ
}

HasElementsâ†{
    0<â‰¢,âµ
}

AllNonNegativeâ†{
    ^/0â‰¤,âµ
}

AllPositiveâ†{
    ^/0<,âµ
}

Withinâ†{
    (âº[1]â‰¤âµ)^âµâ‰¤âº[2]
}

Nearâ†{
    |âº[1]-âµâ‰¤âº[2]
}

â ----------------------------------------------------------------
â 003  NORM PRIMITIVES
â ----------------------------------------------------------------

NormSqâ†{
    +/ ,âµ Ã— âµ
}

NormL2â†{
    *0.5 Ã— âŸ NormSq âµ
}

NormL1â†{
    +/|,âµ
}

NormInfâ†{
    âŒˆ/|,âµ
}

NormTargetErrorâ†{
    |(NormL2 âµ)-âº
}

NormalizeL2â†{
    sâ†NormL2 âµ
    s=0:âµ
    âµÃ·s
}

â ----------------------------------------------------------------
â 004  SHAPE PRIMITIVES
â ----------------------------------------------------------------

Rankâ†{
    â‰¢â´âµ
}

Shapeâ†{
    â´âµ
}

ElementCountâ†{
    Ã—/â´âµ
}

MaxDimensionâ†{
    0=â‰¢â´âµ:0
    âŒˆ/â´âµ
}

MinDimensionâ†{
    0=â‰¢â´âµ:0
    âŒŠ/â´âµ
}

DimensionAtâ†{
    âºâŠƒâ´âµ
}

ShapeProductâ†{
    Ã—/âµ
}

SameShapeâ†{
    (â´âº)â‰¡â´âµ
}

CompatibleShapeâ†{
    aâ†â´âº
    bâ†â´âµ
    aâ‰¡b
}

â ----------------------------------------------------------------
â 005  ASSERTION CORE
â ----------------------------------------------------------------

Assertâ†{
    condition messageâ†âº
    condition:
        âµ
    âŽ•SIGNAL 11
}

AssertTrueâ†{
    condition messageâ†âº
    condition:
        1
    âŽ•SIGNAL 11
}

AssertFalseâ†{
    condition messageâ†âº
    ~condition:
        1
    âŽ•SIGNAL 11
}

AssertNearâ†{
    epsilon expected actualâ†âº
    (|expected-actual)â‰¤epsilon:
        actual
    âŽ•SIGNAL 11
}

AssertShapeâ†{
    expected actualâ†âº
    (expectedâ‰¡â´actual):
        actual
    âŽ•SIGNAL 11
}

AssertRankâ†{
    expected actualâ†âº
    (expected=Rank actual):
        actual
    âŽ•SIGNAL 11
}

â ----------------------------------------------------------------
â 006  LIQUID FLOW ASSERTION
â ----------------------------------------------------------------

LiquidAssertâ†{
    eps chiMaxâ†âº
    stateâ†âµ

    normSqâ†NormSq state
    normValâ†*0.5 Ã— âŸ normSq

    âŽ•Assert (|normVal-1.0)<eps

    maxDimensionâ†MaxDimension state
    âŽ•Assert maxDimensionâ‰¤chiMax

    state
}

LiquidAssertReportâ†{
    eps chiMaxâ†âº
    stateâ†âµ
    nsâ†NormSq state
    nvâ†*0.5 Ã— âŸ ns
    mdâ†MaxDimension state
    (nv md ((|nv-1)â‰¤eps) (mdâ‰¤chiMax))
}

â ----------------------------------------------------------------
â 007  NORMALIZATION ASSERTIONS
â ----------------------------------------------------------------

AssertNormalizedâ†{
    epsilonâ†âº
    stateâ†âµ
    nâ†NormL2 state
    âŽ•Assert |n-DefaultNormTargetâ‰¤epsilon
    state
}

AssertNormSqâ†{
    epsilon targetâ†âº
    stateâ†âµ
    actualâ†NormSq state
    âŽ•Assert |actual-targetâ‰¤epsilon
    state
}

AssertUnitNormâ†{
    epsilonâ†âº
    stateâ†âµ
    AssertNormalized epsilon state
}

â ----------------------------------------------------------------
â 008  BOND DIMENSION
â ----------------------------------------------------------------

AssertChiâ†{
    chiMaxâ†âº
    stateâ†âµ
    mdâ†MaxDimension state
    âŽ•Assert mdâ‰¤chiMax
    state
}

AssertDefaultChiâ†{
    stateâ†âµ
    AssertChi DefaultChiMax state
}

ChiWithinâ†{
    chiMaxâ†âº
    MaxDimension âµâ‰¤chiMax
}

BondDimensionsâ†{
    â´âµ
}

BondDimensionCountâ†{
    â‰¢BondDimensions âµ
}

â ----------------------------------------------------------------
â 009  FINITE STATE
â ----------------------------------------------------------------

AssertFiniteâ†{
    stateâ†âµ
    âŽ•Assert IsFinite state
    state
}

AssertNonEmptyâ†{
    stateâ†âµ
    âŽ•Assert HasElements state
    state
}

AssertFiniteNonEmptyâ†{
    stateâ†âµ
    AssertFinite AssertNonEmpty state
}

â ----------------------------------------------------------------
â 010  NONNEGATIVE STATES
â ----------------------------------------------------------------

AssertNonNegativeâ†{
    stateâ†âµ
    âŽ•Assert AllNonNegative state
    state
}

AssertPositiveâ†{
    stateâ†âµ
    âŽ•Assert AllPositive state
    state
}

AssertProbabilityVectorâ†{
    epsilonâ†âº
    pâ†âµ
    âŽ•Assert IsVector p
    âŽ•Assert AllNonNegative p
    âŽ•Assert |(+/p)-1â‰¤epsilon
    p
}

AssertSimplexâ†{
    AssertProbabilityVector âº âµ
}

â ----------------------------------------------------------------
â 011  TRACE PRIMITIVES
â ----------------------------------------------------------------

Diagonalâ†{
    nâ†âŒŠ/â´âµ
    â³n
}

MatrixTraceâ†{
    aâ†âµ
    +/a[â³âŒŠ/â´a;â³âŒŠ/â´a]
}

AssertTraceâ†{
    epsilon targetâ†âº
    stateâ†âµ
    trâ†MatrixTrace state
    âŽ•Assert |tr-targetâ‰¤epsilon
    state
}

AssertUnitTraceâ†{
    AssertTrace (âº 1) âµ
}

â ----------------------------------------------------------------
â 012  SYMMETRY
â ----------------------------------------------------------------

TransposeMatrixâ†{
    â‰âµ
}

SymmetryErrorâ†{
    aâ†âµ
    NormL2 a-â‰a
}

AssertSymmetricâ†{
    epsilonâ†âº
    stateâ†âµ
    âŽ•Assert (SymmetryError state)â‰¤epsilon
    state
}

â ----------------------------------------------------------------
â 013  HERMITIAN
â ----------------------------------------------------------------

Conjugateâ†{
    +âµ
}

HermitianTransposeâ†{
    â‰+âµ
}

HermitianErrorâ†{
    aâ†âµ
    NormL2 a-HermitianTranspose a
}

AssertHermitianâ†{
    epsilonâ†âº
    stateâ†âµ
    âŽ•Assert (HermitianError state)â‰¤epsilon
    state
}

â ----------------------------------------------------------------
â 014  POSITIVE SEMIDEFINITE HEURISTIC
â ----------------------------------------------------------------

DiagonalValuesâ†{
    aâ†âµ
    nâ†âŒŠ/â´a
    a[â³n;â³n]
}

AssertNonNegativeDiagonalâ†{
    stateâ†âµ
    dâ†DiagonalValues state
    âŽ•Assert AllNonNegative d
    state
}

â ----------------------------------------------------------------
â 015  AXIS ASSERTIONS
â ----------------------------------------------------------------

AssertAxisCountâ†{
    expected stateâ†âº
    âŽ•Assert expected=Rank state
    state
}

AssertAxisDimensionâ†{
    axis dimension stateâ†âº
    âŽ•Assert dimension=axisâŠƒâ´state
    state
}

AssertAxisNonZeroâ†{
    axis stateâ†âº
    âŽ•Assert 0<axisâŠƒâ´state
    state
}

AssertSquareâ†{
    stateâ†âµ
    sâ†â´state
    âŽ•Assert (2=Rank state)^(s[1]=s[2])
    state
}

â ----------------------------------------------------------------
â 016  SHAPE COMPATIBILITY
â ----------------------------------------------------------------

AssertSameShapeâ†{
    reference stateâ†âº
    âŽ•Assert (â´reference)â‰¡â´state
    state
}

AssertSameRankâ†{
    reference stateâ†âº
    âŽ•Assert Rank reference=Rank state
    state
}

AssertBroadcastableâ†{
    reference stateâ†âº
    aâ†âŒ½â´reference
    bâ†âŒ½â´state
    nâ†âŒˆ/2,â‰¢a,â‰¢b
    âŽ•Assert 1
    state
}

â ----------------------------------------------------------------
â 017  DIFFERENCE METRICS
â ----------------------------------------------------------------

Deltaâ†{
    a bâ†âº
    a-b
}

DeltaNormâ†{
    a bâ†âº
    NormL2 a-b
}

RelativeErrorâ†{
    a bâ†âº
    dâ†NormL2 a-b
    nâ†NormL2 b
    n=0:d
    dÃ·n
}

AssertDeltaâ†{
    epsilon a bâ†âº
    âŽ•Assert (DeltaNorm a b)â‰¤epsilon
    b
}

AssertRelativeErrorâ†{
    epsilon a bâ†âº
    âŽ•Assert (RelativeError a b)â‰¤epsilon
    b
}

â ----------------------------------------------------------------
â 018  EROSION
â ----------------------------------------------------------------

ErosionMagnitudeâ†{
    previous currentâ†âº
    DeltaNorm current previous
}

ErosionRatioâ†{
    previous currentâ†âº
    pâ†NormL2 previous
    p=0:0
    (NormL2 current-previous)Ã·p
}

AssertErosionâ†{
    epsilon previous currentâ†âº
    eâ†ErosionMagnitude previous current
    âŽ•Assert eâ‰¤epsilon
    current
}

AssertErosionRatioâ†{
    epsilon previous currentâ†âº
    râ†ErosionRatio previous current
    âŽ•Assert râ‰¤epsilon
    current
}

â ----------------------------------------------------------------
â 019  FLOW STEP
â ----------------------------------------------------------------

FlowStepâ†{
    state operatorâ†âº
    operator state
}

VerifiedFlowStepâ†{
    epsilon chiMax state operatorâ†âº
    nextâ†operator state
    LiquidAssert (epsilon chiMax) next
}

â ----------------------------------------------------------------
â 020  WICK ROTATION
â ----------------------------------------------------------------

WickRotateâ†{
    stateâ†âµ
    +state
}

WickRotateScaledâ†{
    theta stateâ†âº
    (*theta)Ã—state
}

AssertWickFiniteâ†{
    stateâ†WickRotate âµ
    AssertFinite state
}

â ----------------------------------------------------------------
â 021  ENERGY
â ----------------------------------------------------------------

ExpectationValueâ†{
    operator stateâ†âº
    +/,stateÃ—operator state
}

EnergyErrorâ†{
    expected actualâ†âº
    |expected-actual
}

AssertEnergyâ†{
    epsilon expected operator stateâ†âº
    eâ†ExpectationValue operator state
    âŽ•Assert |e-expectedâ‰¤epsilon
    state
}

â ----------------------------------------------------------------
â 022  CONSERVATION
â ----------------------------------------------------------------

ConservedNormâ†{
    a bâ†âº
    |NormL2 a-NormL2 b
}

AssertNormConservationâ†{
    epsilon old newâ†âº
    âŽ•Assert ConservedNorm old newâ‰¤epsilon
    new
}

â ----------------------------------------------------------------
â 023  STATE TRANSITIONS
â ----------------------------------------------------------------

StateTransitionâ†{
    old newâ†âº
    new-old
}

TransitionMagnitudeâ†{
    old newâ†âº
    NormL2 new-old
}

AssertTransitionBoundâ†{
    maximum old newâ†âº
    âŽ•Assert (TransitionMagnitude old new)â‰¤maximum
    new
}

â ----------------------------------------------------------------
â 024  CONTRACTED STATE
â ----------------------------------------------------------------

Contractâ†{
    axisA axisB stateâ†âº
    +âŒ¿state
}

AssertContractedFiniteâ†{
    axisA axisB stateâ†âº
    resultâ†Contract axisA axisB state
    AssertFinite result
}

â ----------------------------------------------------------------
â 025  REDUCTION
â ----------------------------------------------------------------

TensorSumâ†{
    +/,âµ
}

TensorAbsSumâ†{
    +/|,âµ
}

TensorMaximumâ†{
    âŒˆ/,âµ
}

TensorMinimumâ†{
    âŒŠ/,âµ
}

AssertMaximumâ†{
    maximum stateâ†âº
    âŽ•Assert TensorMaximum stateâ‰¤maximum
    state
}

AssertMinimumâ†{
    minimum stateâ†âº
    âŽ•Assert minimumâ‰¤TensorMinimum state
    state
}

â ----------------------------------------------------------------
â 026  RANGE
â ----------------------------------------------------------------

AssertRangeâ†{
    lower upper stateâ†âº
    âŽ•Assert ^/((lowerâ‰¤,state)^(,state)â‰¤upper)
    state
}

AssertMagnitudeRangeâ†{
    lower upper stateâ†âº
    âŽ•Assert ^/((lowerâ‰¤|,state)^(|,state)â‰¤upper)
    state
}

â ----------------------------------------------------------------
â 027  ORTHOGONALITY
â ----------------------------------------------------------------

InnerProductâ†{
    a bâ†âº
    +/,aÃ—b
}

AssertOrthogonalâ†{
    epsilon a bâ†âº
    ipâ†InnerProduct a b
    âŽ•Assert |ipâ‰¤epsilon
    b
}

â ----------------------------------------------------------------
â 028  OVERLAP
â ----------------------------------------------------------------

Overlapâ†{
    a bâ†âº
    InnerProduct a b
}

AssertOverlapâ†{
    epsilon expected a bâ†âº
    oâ†Overlap a b
    âŽ•Assert |o-expectedâ‰¤epsilon
    b
}

â ----------------------------------------------------------------
â 029  FIDELITY
â ----------------------------------------------------------------

Fidelityâ†{
    a bâ†âº
    oâ†Overlap a b
    (oÃ—o)
}

AssertFidelityâ†{
    epsilon target a bâ†âº
    fâ†Fidelity a b
    âŽ•Assert |f-targetâ‰¤epsilon
    b
}

â ----------------------------------------------------------------
â 030  ENTROPY
â ----------------------------------------------------------------

SafeLogâ†{
    xâ†âµ
    xâ‰¤0:0
    âŸx
}

ShannonEntropyâ†{
    pâ†âµ
    -+/pÃ—SafeLogÂ¨p
}

AssertEntropyRangeâ†{
    low high stateâ†âº
    hâ†ShannonEntropy state
    âŽ•Assert (lowâ‰¤h)^hâ‰¤high
    state
}

â ----------------------------------------------------------------
â 031  WEIGHT CHECKS
â ----------------------------------------------------------------

WeightSumâ†{
    +/,âµ
}

AssertWeightâ†{
    epsilon target stateâ†âº
    wâ†WeightSum state
    âŽ•Assert |w-targetâ‰¤epsilon
    state
}

â ----------------------------------------------------------------
â 032  NORMALIZATION PIPELINE
â ----------------------------------------------------------------

NormalizeCheckedâ†{
    epsilon stateâ†âº
    resultâ†NormalizeL2 state
    AssertNormalized epsilon result
}

NormalizeAndChiâ†{
    epsilon chiMax stateâ†âº
    resultâ†NormalizeL2 state
    LiquidAssert (epsilon chiMax) result
}

â ----------------------------------------------------------------
â 033  LIQUID PIPELINE
â ----------------------------------------------------------------

LiquidStepâ†{
    epsilon chiMax operator stateâ†âº
    nextâ†operator state
    LiquidAssert (epsilon chiMax) next
}

LiquidStepPreserveNormâ†{
    epsilon chiMax operator stateâ†âº
    nextâ†LiquidStep epsilon chiMax operator state
    AssertNormConservation epsilon state next
}

LiquidStepBoundedâ†{
    epsilon chiMax delta operator stateâ†âº
    nextâ†LiquidStep epsilon chiMax operator state
    AssertTransitionBound delta state next
}

â ----------------------------------------------------------------
â 034  COMBINED ASSERTIONS
â ----------------------------------------------------------------

AssertAllâ†{
    assertions stateâ†âº
    resultâ†state
    :For f :In assertions
        resultâ†f result
    :EndFor
    result
}

AssertLiquidStateâ†{
    epsilon chiMax stateâ†âº
    resultâ†state
    resultâ†AssertFinite result
    resultâ†LiquidAssert (epsilon chiMax) result
    result
}

AssertPhysicalStateâ†{
    epsilon chiMax stateâ†âº
    resultâ†state
    resultâ†AssertFinite result
    resultâ†AssertNormalized epsilon result
    resultâ†AssertChi chiMax result
    result
}

â ----------------------------------------------------------------
â 035  STATE SEAL
â ----------------------------------------------------------------

StateSealâ†{
    stateâ†âµ
    â•(â´state)(NormL2 state)(TensorSum state)
}

AssertStateSealâ†{
    expected stateâ†âº
    actualâ†StateSeal state
    âŽ•Assert expectedâ‰¡actual
    state
}

â ----------------------------------------------------------------
â 036  DETERMINISTIC SIGNATURE COMPONENTS
â ----------------------------------------------------------------

StateShapeSignatureâ†{
    â•â´âµ
}

StateNormSignatureâ†{
    â•NormL2 âµ
}

StateDimensionSignatureâ†{
    â•MaxDimension âµ
}

StateSignatureâ†{
    StateShapeSignature âµ,StateNormSignature âµ,StateDimensionSignature âµ
}

â ----------------------------------------------------------------
â 037  ASSERTION PIPE
â ----------------------------------------------------------------

Pipeâ†{
    fâ†âº
    f âµ
}

Pipe2â†{
    f gâ†âº
    g f âµ
}

Pipe3â†{
    f g hâ†âº
    h g f âµ
}

â ----------------------------------------------------------------
â 038  TOLERANCE
â ----------------------------------------------------------------

Toleranceâ†{
    epsilonâ†âº
    a bâ†âµ
    |a-bâ‰¤epsilon
}

AbsoluteToleranceâ†{
    epsilonâ†âº
    a bâ†âµ
    |a-bâ‰¤epsilon
}

RelativeToleranceâ†{
    epsilonâ†âº
    a bâ†âµ
    RelativeError a bâ‰¤epsilon
}

â ----------------------------------------------------------------
â 039  ARRAY DIFFERENCE
â ----------------------------------------------------------------

MaxAbsoluteDifferenceâ†{
    a bâ†âº
    âŒˆ/|,a-b
}

MeanAbsoluteDifferenceâ†{
    a bâ†âº
    (+/|,a-b)Ã·â‰¢,a
}

RootMeanSquareErrorâ†{
    a bâ†âº
    *0.5Ã—(+/,((a-b)Ã—(a-b)))Ã·â‰¢,a
}

AssertRMSEâ†{
    epsilon a bâ†âº
    âŽ•Assert (RootMeanSquareError a b)â‰¤epsilon
    b
}

â ----------------------------------------------------------------
â 040  AXIS PERMUTATION
â ----------------------------------------------------------------

AssertAxisPermutationâ†{
    permutation stateâ†âº
    sâ†â´state
    âŽ•Assert (â³â‰¢s)â‰¡â‹permutation
    state
}

PermuteAxesâ†{
    permutation stateâ†âº
    permutationâ‰state
}

â ----------------------------------------------------------------
â 041  RESHAPE SAFETY
â ----------------------------------------------------------------

AssertReshapeCountâ†{
    newShape stateâ†âº
    âŽ•Assert (Ã—/newShape)=ElementCount state
    state
}

SafeReshapeâ†{
    newShape stateâ†âº
    AssertReshapeCount newShape state
    newShapeâ´state
}

â ----------------------------------------------------------------
â 042  MATRIX MULTIPLICATION
â ----------------------------------------------------------------

AssertMatMulâ†{
    a bâ†âº
    saâ†â´a
    sbâ†â´b
    âŽ•Assert (2=â‰¢sa)^2=â‰¢sb
    âŽ•Assert sa[2]=sb[1]
    b
}

â ----------------------------------------------------------------
â 043  IDENTITY
â ----------------------------------------------------------------

Identityâ†{
    nâ†âµ
    (n n)â´(â³n)âˆ˜.=â³n
}

AssertIdentityâ†{
    epsilon aâ†âº
    nâ†âŒŠ/â´a
    iâ†Identity n
    AssertNear epsilon i a
}

â ----------------------------------------------------------------
â 044  ZERO CHECK
â ----------------------------------------------------------------

IsZeroâ†{
    epsilonâ†âº
    stateâ†âµ
    ^/|,stateâ‰¤epsilon
}

AssertZeroâ†{
    epsilon stateâ†âº
    âŽ•Assert epsilon IsZero state
    state
}

â ----------------------------------------------------------------
â 045  BOUNDARY CHECKS
â ----------------------------------------------------------------

AssertLowerBoundâ†{
    lower stateâ†âº
    âŽ•Assert ^/lowerâ‰¤,state
    state
}

AssertUpperBoundâ†{
    upper stateâ†âº
    âŽ•Assert ^/,stateâ‰¤upper
    state
}

â ----------------------------------------------------------------
â 046  DENSITY MATRIX
â ----------------------------------------------------------------

AssertDensityMatrixâ†{
    epsilon stateâ†âº
    resultâ†AssertSquare state
    resultâ†AssertHermitian epsilon result
    resultâ†AssertUnitTrace epsilon result
    resultâ†AssertNonNegativeDiagonal result
    result
}

â ----------------------------------------------------------------
â 047  FLOW INVARIANT
â ----------------------------------------------------------------

FlowInvariantâ†{
    epsilon old newâ†âº
    (|NormL2 old-NormL2 new)â‰¤epsilon
}

AssertFlowInvariantâ†{
    epsilon old newâ†âº
    âŽ•Assert FlowInvariant epsilon old new
    new
}

â ----------------------------------------------------------------
â 048  MULTI-INVARIANT
â ----------------------------------------------------------------

CheckInvariantsâ†{
    epsilon chiMax old newâ†âº
    aâ†AssertFinite new
    aâ†LiquidAssert (epsilon chiMax) a
    aâ†AssertNormConservation epsilon old a
    a
}

â ----------------------------------------------------------------
â 049  EROSION GATE
â ----------------------------------------------------------------

ErosionGateâ†{
    epsilon previous currentâ†âº
    ErosionMagnitude previous currentâ‰¤epsilon
}

AssertErosionGateâ†{
    epsilon previous currentâ†âº
    âŽ•Assert ErosionGate epsilon previous current
    current
}

â ----------------------------------------------------------------
â 050  CHI GATE
â ----------------------------------------------------------------

ChiGateâ†{
    chiMaxâ†âº
    MaxDimension âµâ‰¤chiMax
}

AssertChiGateâ†{
    chiMax stateâ†âº
    âŽ•Assert ChiGate chiMax state
    state
}

â ----------------------------------------------------------------
â 051  LIQUID GATE
â ----------------------------------------------------------------

LiquidGateâ†{
    epsilon chiMax stateâ†âº
    aâ†IsFinite state
    bâ†NormTargetError stateâ‰¤epsilon
    câ†MaxDimension stateâ‰¤chiMax
    a^b^c
}

AssertLiquidGateâ†{
    epsilon chiMax stateâ†âº
    âŽ•Assert LiquidGate epsilon chiMax state
    state
}

â ----------------------------------------------------------------
â 052  ACCEPT / REJECT
â ----------------------------------------------------------------

Acceptâ†{
    stateâ†âµ
    1
}

Rejectâ†{
    stateâ†âµ
    0
}

Gateâ†{
    conditionâ†âº
    condition:Accept âµ
    Reject âµ
}

â ----------------------------------------------------------------
â 053  VALIDATION CODE
â ----------------------------------------------------------------

ValidationCodeâ†{
    epsilon chiMax stateâ†âº
    finiteâ†IsFinite state
    normOkâ†NormTargetError stateâ‰¤epsilon
    chiOkâ†MaxDimension stateâ‰¤chiMax
    4Ã—finite+2Ã—normOk+chiOk
}

ValidationPassâ†{
    epsilon chiMax stateâ†âº
    7=ValidationCode epsilon chiMax state
}

â ----------------------------------------------------------------
â 054  REPORT
â ----------------------------------------------------------------

LiquidReportâ†{
    epsilon chiMax stateâ†âº
    normâ†NormL2 state
    chiâ†MaxDimension state
    finiteâ†IsFinite state
    normOKâ†|norm-1â‰¤epsilon
    chiOKâ†chiâ‰¤chiMax
    (finite norm normOK chi chiOK)
}

â ----------------------------------------------------------------
â 055  REPORT FORMAT
â ----------------------------------------------------------------

LiquidReportTextâ†{
    epsilon chiMax stateâ†âº
    râ†LiquidReport epsilon chiMax state
    'FINITE=',â•r[1],', NORM=',â•r[2],', NORM_OK=',â•r[3],', CHI=',â•r[4],', CHI_OK=',â•r[5]
}

â ----------------------------------------------------------------
â 056  SAMPLE STATE
â ----------------------------------------------------------------

SampleStateâ†{
    sâ†âµ
    NormalizeL2 s
}

SampleVectorâ†{
    NormalizeL2 1 2 3 4
}

SampleMatrixâ†{
    NormalizeL2 1 2 3 4â´1
}

â ----------------------------------------------------------------
â 057  TEST NORMALIZATION
â ----------------------------------------------------------------

TestNormâ†{
    stateâ†SampleVector 0
    AssertUnitNorm DefaultEpsilon state
}

TestChiâ†{
    stateâ†SampleVector 0
    AssertChi DefaultChiMax state
}

TestFiniteâ†{
    stateâ†SampleVector 0
    AssertFinite state
}

â ----------------------------------------------------------------
â 058  TEST LIQUID ASSERT
â ----------------------------------------------------------------

TestLiquidAssertâ†{
    stateâ†SampleVector 0
    LiquidAssert (DefaultEpsilon DefaultChiMax) state
}

â ----------------------------------------------------------------
â 059  TEST EROSION
â ----------------------------------------------------------------

TestErosionâ†{
    stateâ†SampleVector 0
    AssertErosion 1EÂ¯8 state state
}

â ----------------------------------------------------------------
â 060  TEST REPORT
â ----------------------------------------------------------------

TestReportâ†{
    stateâ†SampleVector 0
    LiquidReport DefaultEpsilon DefaultChiMax state
}

â ----------------------------------------------------------------
â 061  WICK FLOW
â ----------------------------------------------------------------

WickFlowâ†{
    epsilon chiMax stateâ†âº
    nextâ†WickRotate state
    LiquidAssert (epsilon chiMax) next
}

â ----------------------------------------------------------------
â 062  NORMALIZED WICK FLOW
â ----------------------------------------------------------------

NormalizedWickFlowâ†{
    epsilon chiMax stateâ†âº
    nextâ†NormalizeL2 WickRotate state
    LiquidAssert (epsilon chiMax) next
}

â ----------------------------------------------------------------
â 063  ERODED WICK FLOW
â ----------------------------------------------------------------

ErodedWickFlowâ†{
    epsilon chiMax erosion stateâ†âº
    nextâ†NormalizeL2 WickRotate state
    LiquidAssert (epsilon chiMax) next
    AssertErosion erosion state next
}

â ----------------------------------------------------------------
â 064  STATE COMMIT
â ----------------------------------------------------------------

CommitStateâ†{
    epsilon chiMax stateâ†âº
    LiquidAssert (epsilon chiMax) state
    state
}

â ----------------------------------------------------------------
â 065  STATE ROLLBACK
â ----------------------------------------------------------------

RollbackStateâ†{
    stateâ†âµ
    state
}

â ----------------------------------------------------------------
â 066  CONDITIONAL COMMIT
â ----------------------------------------------------------------

ConditionalCommitâ†{
    epsilon chiMax old newâ†âº
    LiquidGate epsilon chiMax new:
        new
    old
}

â ----------------------------------------------------------------
â 067  CONSERVATION COMMIT
â ----------------------------------------------------------------

ConservationCommitâ†{
    epsilon chiMax old newâ†âº
    LiquidAssert (epsilon chiMax) new
    AssertNormConservation epsilon old new
}

â ----------------------------------------------------------------
â 068  ASSERTION CHAIN
â ----------------------------------------------------------------

LiquidChainâ†{
    epsilon chiMax stateâ†âº
    resultâ†AssertFinite state
    resultâ†AssertUnitNorm epsilon result
    resultâ†AssertChi chiMax result
    result
}

â ----------------------------------------------------------------
â 069  STRICT CHAIN
â ----------------------------------------------------------------

StrictLiquidChainâ†{
    epsilon chiMax stateâ†âº
    resultâ†AssertNonEmpty state
    resultâ†AssertFinite result
    resultâ†AssertUnitNorm epsilon result
    resultâ†AssertChi chiMax result
    result
}

â ----------------------------------------------------------------
â 070  SOFT VALIDATION
â ----------------------------------------------------------------

SoftValidateâ†{
    epsilon chiMax stateâ†âº
    LiquidGate epsilon chiMax state
}

â ----------------------------------------------------------------
â 071  NORM CLAMP
â ----------------------------------------------------------------

ClampNormâ†{
    epsilon stateâ†âº
    nâ†NormL2 state
    |n-1â‰¤epsilon:state
    NormalizeL2 state
}

â ----------------------------------------------------------------
â 072  DIMENSION CLAMP
â ----------------------------------------------------------------

DimensionWithinâ†{
    chiMax stateâ†âº
    MaxDimension stateâ‰¤chiMax
}

â ----------------------------------------------------------------
â 073  VALIDATE CONFIGURATION
â ----------------------------------------------------------------

AssertConfigâ†{
    cfgâ†âµ
    âŽ•Assert 2=â‰¢cfg          â [epsilon chiMax]
    epsilon chiMaxâ†cfg
    âŽ•Assert epsilon>0
    âŽ•Assert chiMax>0
    cfg
}

AssertConfigFiniteâ†{
    cfgâ†âµ
    âŽ•Assert IsFinite cfg
    cfg
}

ValidateConfigâ†{
    cfgâ†âµ
    cfgâ†AssertConfig cfg
    cfgâ†AssertConfigFinite cfg
    cfg
}

â ----------------------------------------------------------------
â 074  CONFIGURED LIQUID STEP
â ----------------------------------------------------------------

ConfiguredLiquidStepâ†{
    cfg operator stateâ†âº
    cfgâ†ValidateConfig cfg
    epsilon chiMaxâ†cfg
    nextâ†operator state
    LiquidAssert (epsilon chiMax) next
}

ConfiguredLiquidChainâ†{
    cfg stateâ†âº
    cfgâ†ValidateConfig cfg
    epsilon chiMaxâ†cfg
    StrictLiquidChain epsilon chiMax state
}

â ----------------------------------------------------------------
â 075  CONFIG + STATE SEAL
â ----------------------------------------------------------------

ConfigStateSealâ†{
    cfg stateâ†âº
    cfgâ†ValidateConfig cfg
    epsilon chiMaxâ†cfg
    sigâ†StateSignature state
    â•epsilon,',',chiMax,',',sig
}

AssertConfigStateSealâ†{
    expected cfg stateâ†âº
    actualâ†ConfigStateSeal cfg state
    âŽ•Assert expectedâ‰¡actual
    state
}

â ----------------------------------------------------------------
â 076  DEFAULT ASSERTOR
â ----------------------------------------------------------------

DefaultLiquidAssertâ†{
    LiquidAssert (DefaultEpsilon DefaultChiMax) âµ
}

â ----------------------------------------------------------------
â 077  STRICT DEFAULT
â ----------------------------------------------------------------

StrictDefaultAssertâ†{
    StrictLiquidChain DefaultEpsilon DefaultChiMax âµ
}

â ----------------------------------------------------------------
â 078  FLOW DIAGNOSTICS
â ----------------------------------------------------------------

FlowDiagnosticsâ†{
    epsilon chiMax old newâ†âº
    oldNormâ†NormL2 old
    newNormâ†NormL2 new
    erosionâ†ErosionMagnitude old new
    chiâ†MaxDimension new
    (oldNorm newNorm erosion chi)
}

â ----------------------------------------------------------------
â 079  DIAGNOSTIC ASSERTION
â ----------------------------------------------------------------

AssertFlowDiagnosticsâ†{
    epsilon chiMax erosion old newâ†âº
    dâ†FlowDiagnostics epsilon chiMax old new
    âŽ•Assert |d[1]-d[2]â‰¤epsilon
    âŽ•Assert d[3]â‰¤erosion
    âŽ•Assert d[4]â‰¤chiMax
    new
}

â ----------------------------------------------------------------
â 080  ENDPOINT
â ----------------------------------------------------------------

LiquidEndpointâ†{
    epsilon chiMax stateâ†âº
    LiquidAssert (epsilon chiMax) state
    StateSignature state
}

â ----------------------------------------------------------------
â 081  FINAL FLOW
â ----------------------------------------------------------------

LiquidFlowâ†{
    epsilon chiMax operator stateâ†âº
    nextâ†operator state
    nextâ†NormalizeL2 next
    LiquidAssert (epsilon chiMax) next
}

â ----------------------------------------------------------------
â 082  FINAL PRESERVATION
â ----------------------------------------------------------------

LiquidFlowPreserveâ†{
    epsilon chiMax operator stateâ†âº
    nextâ†LiquidFlow epsilon chiMax operator state
    AssertNormConservation epsilon state next
}

â ----------------------------------------------------------------
â 083  EXAMPLE UPDATE
â ----------------------------------------------------------------

ExampleUpdateâ†{
    updatedTensorStateâ†âµ
    LiquidAssert (0.001 64) updatedTensorState
}

â ----------------------------------------------------------------
â 084  EXAMPLE NORMALIZATION
â ----------------------------------------------------------------

ExampleNormalizedâ†{
    stateâ†NormalizeL2 âµ
    LiquidAssert (0.001 64) state
}

â ----------------------------------------------------------------
â 085  EXAMPLE WICK UPDATE
â ----------------------------------------------------------------

ExampleWickUpdateâ†{
    stateâ†âµ
    updatedTensorStateâ†WickRotate state
    normalizedâ†NormalizeL2 updatedTensorState
    LiquidAssert (0.001 64) normalized
}

â ----------------------------------------------------------------
â 086  LIBRARY SELF TEST
â ----------------------------------------------------------------

SelfTestâ†{
    TestNorm 0
    TestChi 0
    TestFinite 0
    TestLiquidAssert 0
    TestErosion 0
    TestReport 0
    1
}

â ----------------------------------------------------------------
â 087  VERSION
â ----------------------------------------------------------------

Versionâ†{
    LiquidVersion
}

â ----------------------------------------------------------------
â 088  EXPORT INDEX
â ----------------------------------------------------------------

CoreExportsâ†{
    LiquidAssert
    LiquidAssertReport
    LiquidGate
    LiquidFlow
    LiquidFlowPreserve
}

â ----------------------------------------------------------------
â 089  DOCUMENTED ENTRY POINT
â ----------------------------------------------------------------

LiquidValidateâ†{
    epsilon chiMax stateâ†âº
    AssertConfiguration epsilon chiMax
    AssertFinite state
    LiquidAssert (epsilon chiMax) state
}

â ----------------------------------------------------------------
â 090  TERMINAL VALIDATOR
â ----------------------------------------------------------------

LiquidFinalizeâ†{
    epsilon chiMax stateâ†âº
    resultâ†LiquidValidate epsilon chiMax state
    StateSignature result
}

â ================================================================
â END LIQUIDAPL FLOW ASSERTION LIBRARY
â ================================================================
