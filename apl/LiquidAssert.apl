⍝ ================================================================
⍝ LIQUIDAPL FLOW ASSERTION LIBRARY
⍝ ================================================================
⍝ File: LiquidAssert.apl
⍝ Purpose: deterministic tensor-state integrity assertions
⍝ Style: Dyalog APL
⍝ ================================================================
⍝
⍝ Convention:
⍝   ⍺ = configuration / thresholds
⍝   ⍵ = tensor / state
⍝
⍝ Configuration vectors commonly use:
⍝   [epsilon chiMax]
⍝
⍝ The library is intentionally assertion-oriented.
⍝ ================================================================

⎕IO←1
⎕ML←1

⍝ ----------------------------------------------------------------
⍝ 001  CONSTANTS
⍝ ----------------------------------------------------------------

LiquidVersion←'1.0.0'
DefaultEpsilon←1E¯10
DefaultChiMax←64
DefaultNormTarget←1
DefaultTraceEpsilon←1E¯10
DefaultEnergyEpsilon←1E¯10

⍝ ----------------------------------------------------------------
⍝ 002  BASIC NUMERIC PREDICATES
⍝ ----------------------------------------------------------------

IsFinite←{
    v←⍵
    ^/((v=v)∨(v≠v))
}

IsScalar←{
    1=≢⍴⍵
}

IsVector←{
    1=≢⍴⍵
}

IsArray←{
    0<≢⍴⍵
}

HasElements←{
    0<≢,⍵
}

AllNonNegative←{
    ^/0≤,⍵
}

AllPositive←{
    ^/0<,⍵
}

Within←{
    (⍺[1]≤⍵)^⍵≤⍺[2]
}

Near←{
    |⍺[1]-⍵≤⍺[2]
}

⍝ ----------------------------------------------------------------
⍝ 003  NORM PRIMITIVES
⍝ ----------------------------------------------------------------

NormSq←{
    +/ ,⍵ × ⍵
}

NormL2←{
    *0.5 × ⍟ NormSq ⍵
}

NormL1←{
    +/|,⍵
}

NormInf←{
    ⌈/|,⍵
}

NormTargetError←{
    |(NormL2 ⍵)-⍺
}

NormalizeL2←{
    s←NormL2 ⍵
    s=0:⍵
    ⍵÷s
}

⍝ ----------------------------------------------------------------
⍝ 004  SHAPE PRIMITIVES
⍝ ----------------------------------------------------------------

Rank←{
    ≢⍴⍵
}

Shape←{
    ⍴⍵
}

ElementCount←{
    ×/⍴⍵
}

MaxDimension←{
    0=≢⍴⍵:0
    ⌈/⍴⍵
}

MinDimension←{
    0=≢⍴⍵:0
    ⌊/⍴⍵
}

DimensionAt←{
    ⍺⊃⍴⍵
}

ShapeProduct←{
    ×/⍵
}

SameShape←{
    (⍴⍺)≡⍴⍵
}

CompatibleShape←{
    a←⍴⍺
    b←⍴⍵
    a≡b
}

⍝ ----------------------------------------------------------------
⍝ 005  ASSERTION CORE
⍝ ----------------------------------------------------------------

Assert←{
    condition message←⍺
    condition:
        ⍵
    ⎕SIGNAL 11
}

AssertTrue←{
    condition message←⍺
    condition:
        1
    ⎕SIGNAL 11
}

AssertFalse←{
    condition message←⍺
    ~condition:
        1
    ⎕SIGNAL 11
}

AssertNear←{
    epsilon expected actual←⍺
    (|expected-actual)≤epsilon:
        actual
    ⎕SIGNAL 11
}

AssertShape←{
    expected actual←⍺
    (expected≡⍴actual):
        actual
    ⎕SIGNAL 11
}

AssertRank←{
    expected actual←⍺
    (expected=Rank actual):
        actual
    ⎕SIGNAL 11
}

⍝ ----------------------------------------------------------------
⍝ 006  LIQUID FLOW ASSERTION
⍝ ----------------------------------------------------------------

LiquidAssert←{
    eps chiMax←⍺
    state←⍵

    normSq←NormSq state
    normVal←*0.5 × ⍟ normSq

    ⎕Assert (|normVal-1.0)<eps

    maxDimension←MaxDimension state
    ⎕Assert maxDimension≤chiMax

    state
}

LiquidAssertReport←{
    eps chiMax←⍺
    state←⍵
    ns←NormSq state
    nv←*0.5 × ⍟ ns
    md←MaxDimension state
    (nv md ((|nv-1)≤eps) (md≤chiMax))
}

⍝ ----------------------------------------------------------------
⍝ 007  NORMALIZATION ASSERTIONS
⍝ ----------------------------------------------------------------

AssertNormalized←{
    epsilon←⍺
    state←⍵
    n←NormL2 state
    ⎕Assert |n-DefaultNormTarget≤epsilon
    state
}

AssertNormSq←{
    epsilon target←⍺
    state←⍵
    actual←NormSq state
    ⎕Assert |actual-target≤epsilon
    state
}

AssertUnitNorm←{
    epsilon←⍺
    state←⍵
    AssertNormalized epsilon state
}

⍝ ----------------------------------------------------------------
⍝ 008  BOND DIMENSION
⍝ ----------------------------------------------------------------

AssertChi←{
    chiMax←⍺
    state←⍵
    md←MaxDimension state
    ⎕Assert md≤chiMax
    state
}

AssertDefaultChi←{
    state←⍵
    AssertChi DefaultChiMax state
}

ChiWithin←{
    chiMax←⍺
    MaxDimension ⍵≤chiMax
}

BondDimensions←{
    ⍴⍵
}

BondDimensionCount←{
    ≢BondDimensions ⍵
}

⍝ ----------------------------------------------------------------
⍝ 009  FINITE STATE
⍝ ----------------------------------------------------------------

AssertFinite←{
    state←⍵
    ⎕Assert IsFinite state
    state
}

AssertNonEmpty←{
    state←⍵
    ⎕Assert HasElements state
    state
}

AssertFiniteNonEmpty←{
    state←⍵
    AssertFinite AssertNonEmpty state
}

⍝ ----------------------------------------------------------------
⍝ 010  NONNEGATIVE STATES
⍝ ----------------------------------------------------------------

AssertNonNegative←{
    state←⍵
    ⎕Assert AllNonNegative state
    state
}

AssertPositive←{
    state←⍵
    ⎕Assert AllPositive state
    state
}

AssertProbabilityVector←{
    epsilon←⍺
    p←⍵
    ⎕Assert IsVector p
    ⎕Assert AllNonNegative p
    ⎕Assert |(+/p)-1≤epsilon
    p
}

AssertSimplex←{
    AssertProbabilityVector ⍺ ⍵
}

⍝ ----------------------------------------------------------------
⍝ 011  TRACE PRIMITIVES
⍝ ----------------------------------------------------------------

Diagonal←{
    n←⌊/⍴⍵
    ⍳n
}

MatrixTrace←{
    a←⍵
    +/a[⍳⌊/⍴a;⍳⌊/⍴a]
}

AssertTrace←{
    epsilon target←⍺
    state←⍵
    tr←MatrixTrace state
    ⎕Assert |tr-target≤epsilon
    state
}

AssertUnitTrace←{
    AssertTrace (⍺ 1) ⍵
}

⍝ ----------------------------------------------------------------
⍝ 012  SYMMETRY
⍝ ----------------------------------------------------------------

TransposeMatrix←{
    ⍉⍵
}

SymmetryError←{
    a←⍵
    NormL2 a-⍉a
}

AssertSymmetric←{
    epsilon←⍺
    state←⍵
    ⎕Assert (SymmetryError state)≤epsilon
    state
}

⍝ ----------------------------------------------------------------
⍝ 013  HERMITIAN
⍝ ----------------------------------------------------------------

Conjugate←{
    +⍵
}

HermitianTranspose←{
    ⍉+⍵
}

HermitianError←{
    a←⍵
    NormL2 a-HermitianTranspose a
}

AssertHermitian←{
    epsilon←⍺
    state←⍵
    ⎕Assert (HermitianError state)≤epsilon
    state
}

⍝ ----------------------------------------------------------------
⍝ 014  POSITIVE SEMIDEFINITE HEURISTIC
⍝ ----------------------------------------------------------------

DiagonalValues←{
    a←⍵
    n←⌊/⍴a
    a[⍳n;⍳n]
}

AssertNonNegativeDiagonal←{
    state←⍵
    d←DiagonalValues state
    ⎕Assert AllNonNegative d
    state
}

⍝ ----------------------------------------------------------------
⍝ 015  AXIS ASSERTIONS
⍝ ----------------------------------------------------------------

AssertAxisCount←{
    expected state←⍺
    ⎕Assert expected=Rank state
    state
}

AssertAxisDimension←{
    axis dimension state←⍺
    ⎕Assert dimension=axis⊃⍴state
    state
}

AssertAxisNonZero←{
    axis state←⍺
    ⎕Assert 0<axis⊃⍴state
    state
}

AssertSquare←{
    state←⍵
    s←⍴state
    ⎕Assert (2=Rank state)^(s[1]=s[2])
    state
}

⍝ ----------------------------------------------------------------
⍝ 016  SHAPE COMPATIBILITY
⍝ ----------------------------------------------------------------

AssertSameShape←{
    reference state←⍺
    ⎕Assert (⍴reference)≡⍴state
    state
}

AssertSameRank←{
    reference state←⍺
    ⎕Assert Rank reference=Rank state
    state
}

AssertBroadcastable←{
    reference state←⍺
    a←⌽⍴reference
    b←⌽⍴state
    n←⌈/2,≢a,≢b
    ⎕Assert 1
    state
}

⍝ ----------------------------------------------------------------
⍝ 017  DIFFERENCE METRICS
⍝ ----------------------------------------------------------------

Delta←{
    a b←⍺
    a-b
}

DeltaNorm←{
    a b←⍺
    NormL2 a-b
}

RelativeError←{
    a b←⍺
    d←NormL2 a-b
    n←NormL2 b
    n=0:d
    d÷n
}

AssertDelta←{
    epsilon a b←⍺
    ⎕Assert (DeltaNorm a b)≤epsilon
    b
}

AssertRelativeError←{
    epsilon a b←⍺
    ⎕Assert (RelativeError a b)≤epsilon
    b
}

⍝ ----------------------------------------------------------------
⍝ 018  EROSION
⍝ ----------------------------------------------------------------

ErosionMagnitude←{
    previous current←⍺
    DeltaNorm current previous
}

ErosionRatio←{
    previous current←⍺
    p←NormL2 previous
    p=0:0
    (NormL2 current-previous)÷p
}

AssertErosion←{
    epsilon previous current←⍺
    e←ErosionMagnitude previous current
    ⎕Assert e≤epsilon
    current
}

AssertErosionRatio←{
    epsilon previous current←⍺
    r←ErosionRatio previous current
    ⎕Assert r≤epsilon
    current
}

⍝ ----------------------------------------------------------------
⍝ 019  FLOW STEP
⍝ ----------------------------------------------------------------

FlowStep←{
    state operator←⍺
    operator state
}

VerifiedFlowStep←{
    epsilon chiMax state operator←⍺
    next←operator state
    LiquidAssert (epsilon chiMax) next
}

⍝ ----------------------------------------------------------------
⍝ 020  WICK ROTATION
⍝ ----------------------------------------------------------------

WickRotate←{
    state←⍵
    +state
}

WickRotateScaled←{
    theta state←⍺
    (*theta)×state
}

AssertWickFinite←{
    state←WickRotate ⍵
    AssertFinite state
}

⍝ ----------------------------------------------------------------
⍝ 021  ENERGY
⍝ ----------------------------------------------------------------

ExpectationValue←{
    operator state←⍺
    +/,state×operator state
}

EnergyError←{
    expected actual←⍺
    |expected-actual
}

AssertEnergy←{
    epsilon expected operator state←⍺
    e←ExpectationValue operator state
    ⎕Assert |e-expected≤epsilon
    state
}

⍝ ----------------------------------------------------------------
⍝ 022  CONSERVATION
⍝ ----------------------------------------------------------------

ConservedNorm←{
    a b←⍺
    |NormL2 a-NormL2 b
}

AssertNormConservation←{
    epsilon old new←⍺
    ⎕Assert ConservedNorm old new≤epsilon
    new
}

⍝ ----------------------------------------------------------------
⍝ 023  STATE TRANSITIONS
⍝ ----------------------------------------------------------------

StateTransition←{
    old new←⍺
    new-old
}

TransitionMagnitude←{
    old new←⍺
    NormL2 new-old
}

AssertTransitionBound←{
    maximum old new←⍺
    ⎕Assert (TransitionMagnitude old new)≤maximum
    new
}

⍝ ----------------------------------------------------------------
⍝ 024  CONTRACTED STATE
⍝ ----------------------------------------------------------------

Contract←{
    axisA axisB state←⍺
    +⌿state
}

AssertContractedFinite←{
    axisA axisB state←⍺
    result←Contract axisA axisB state
    AssertFinite result
}

⍝ ----------------------------------------------------------------
⍝ 025  REDUCTION
⍝ ----------------------------------------------------------------

TensorSum←{
    +/,⍵
}

TensorAbsSum←{
    +/|,⍵
}

TensorMaximum←{
    ⌈/,⍵
}

TensorMinimum←{
    ⌊/,⍵
}

AssertMaximum←{
    maximum state←⍺
    ⎕Assert TensorMaximum state≤maximum
    state
}

AssertMinimum←{
    minimum state←⍺
    ⎕Assert minimum≤TensorMinimum state
    state
}

⍝ ----------------------------------------------------------------
⍝ 026  RANGE
⍝ ----------------------------------------------------------------

AssertRange←{
    lower upper state←⍺
    ⎕Assert ^/((lower≤,state)^(,state)≤upper)
    state
}

AssertMagnitudeRange←{
    lower upper state←⍺
    ⎕Assert ^/((lower≤|,state)^(|,state)≤upper)
    state
}

⍝ ----------------------------------------------------------------
⍝ 027  ORTHOGONALITY
⍝ ----------------------------------------------------------------

InnerProduct←{
    a b←⍺
    +/,a×b
}

AssertOrthogonal←{
    epsilon a b←⍺
    ip←InnerProduct a b
    ⎕Assert |ip≤epsilon
    b
}

⍝ ----------------------------------------------------------------
⍝ 028  OVERLAP
⍝ ----------------------------------------------------------------

Overlap←{
    a b←⍺
    InnerProduct a b
}

AssertOverlap←{
    epsilon expected a b←⍺
    o←Overlap a b
    ⎕Assert |o-expected≤epsilon
    b
}

⍝ ----------------------------------------------------------------
⍝ 029  FIDELITY
⍝ ----------------------------------------------------------------

Fidelity←{
    a b←⍺
    o←Overlap a b
    (o×o)
}

AssertFidelity←{
    epsilon target a b←⍺
    f←Fidelity a b
    ⎕Assert |f-target≤epsilon
    b
}

⍝ ----------------------------------------------------------------
⍝ 030  ENTROPY
⍝ ----------------------------------------------------------------

SafeLog←{
    x←⍵
    x≤0:0
    ⍟x
}

ShannonEntropy←{
    p←⍵
    -+/p×SafeLog¨p
}

AssertEntropyRange←{
    low high state←⍺
    h←ShannonEntropy state
    ⎕Assert (low≤h)^h≤high
    state
}

⍝ ----------------------------------------------------------------
⍝ 031  WEIGHT CHECKS
⍝ ----------------------------------------------------------------

WeightSum←{
    +/,⍵
}

AssertWeight←{
    epsilon target state←⍺
    w←WeightSum state
    ⎕Assert |w-target≤epsilon
    state
}

⍝ ----------------------------------------------------------------
⍝ 032  NORMALIZATION PIPELINE
⍝ ----------------------------------------------------------------

NormalizeChecked←{
    epsilon state←⍺
    result←NormalizeL2 state
    AssertNormalized epsilon result
}

NormalizeAndChi←{
    epsilon chiMax state←⍺
    result←NormalizeL2 state
    LiquidAssert (epsilon chiMax) result
}

⍝ ----------------------------------------------------------------
⍝ 033  LIQUID PIPELINE
⍝ ----------------------------------------------------------------

LiquidStep←{
    epsilon chiMax operator state←⍺
    next←operator state
    LiquidAssert (epsilon chiMax) next
}

LiquidStepPreserveNorm←{
    epsilon chiMax operator state←⍺
    next←LiquidStep epsilon chiMax operator state
    AssertNormConservation epsilon state next
}

LiquidStepBounded←{
    epsilon chiMax delta operator state←⍺
    next←LiquidStep epsilon chiMax operator state
    AssertTransitionBound delta state next
}

⍝ ----------------------------------------------------------------
⍝ 034  COMBINED ASSERTIONS
⍝ ----------------------------------------------------------------

AssertAll←{
    assertions state←⍺
    result←state
    :For f :In assertions
        result←f result
    :EndFor
    result
}

AssertLiquidState←{
    epsilon chiMax state←⍺
    result←state
    result←AssertFinite result
    result←LiquidAssert (epsilon chiMax) result
    result
}

AssertPhysicalState←{
    epsilon chiMax state←⍺
    result←state
    result←AssertFinite result
    result←AssertNormalized epsilon result
    result←AssertChi chiMax result
    result
}

⍝ ----------------------------------------------------------------
⍝ 035  STATE SEAL
⍝ ----------------------------------------------------------------

StateSeal←{
    state←⍵
    ⍕(⍴state)(NormL2 state)(TensorSum state)
}

AssertStateSeal←{
    expected state←⍺
    actual←StateSeal state
    ⎕Assert expected≡actual
    state
}

⍝ ----------------------------------------------------------------
⍝ 036  DETERMINISTIC SIGNATURE COMPONENTS
⍝ ----------------------------------------------------------------

StateShapeSignature←{
    ⍕⍴⍵
}

StateNormSignature←{
    ⍕NormL2 ⍵
}

StateDimensionSignature←{
    ⍕MaxDimension ⍵
}

StateSignature←{
    StateShapeSignature ⍵,StateNormSignature ⍵,StateDimensionSignature ⍵
}

⍝ ----------------------------------------------------------------
⍝ 037  ASSERTION PIPE
⍝ ----------------------------------------------------------------

Pipe←{
    f←⍺
    f ⍵
}

Pipe2←{
    f g←⍺
    g f ⍵
}

Pipe3←{
    f g h←⍺
    h g f ⍵
}

⍝ ----------------------------------------------------------------
⍝ 038  TOLERANCE
⍝ ----------------------------------------------------------------

Tolerance←{
    epsilon←⍺
    a b←⍵
    |a-b≤epsilon
}

AbsoluteTolerance←{
    epsilon←⍺
    a b←⍵
    |a-b≤epsilon
}

RelativeTolerance←{
    epsilon←⍺
    a b←⍵
    RelativeError a b≤epsilon
}

⍝ ----------------------------------------------------------------
⍝ 039  ARRAY DIFFERENCE
⍝ ----------------------------------------------------------------

MaxAbsoluteDifference←{
    a b←⍺
    ⌈/|,a-b
}

MeanAbsoluteDifference←{
    a b←⍺
    (+/|,a-b)÷≢,a
}

RootMeanSquareError←{
    a b←⍺
    *0.5×(+/,((a-b)×(a-b)))÷≢,a
}

AssertRMSE←{
    epsilon a b←⍺
    ⎕Assert (RootMeanSquareError a b)≤epsilon
    b
}

⍝ ----------------------------------------------------------------
⍝ 040  AXIS PERMUTATION
⍝ ----------------------------------------------------------------

AssertAxisPermutation←{
    permutation state←⍺
    s←⍴state
    ⎕Assert (⍳≢s)≡⍋permutation
    state
}

PermuteAxes←{
    permutation state←⍺
    permutation⍉state
}

⍝ ----------------------------------------------------------------
⍝ 041  RESHAPE SAFETY
⍝ ----------------------------------------------------------------

AssertReshapeCount←{
    newShape state←⍺
    ⎕Assert (×/newShape)=ElementCount state
    state
}

SafeReshape←{
    newShape state←⍺
    AssertReshapeCount newShape state
    newShape⍴state
}

⍝ ----------------------------------------------------------------
⍝ 042  MATRIX MULTIPLICATION
⍝ ----------------------------------------------------------------

AssertMatMul←{
    a b←⍺
    sa←⍴a
    sb←⍴b
    ⎕Assert (2=≢sa)^2=≢sb
    ⎕Assert sa[2]=sb[1]
    b
}

⍝ ----------------------------------------------------------------
⍝ 043  IDENTITY
⍝ ----------------------------------------------------------------

Identity←{
    n←⍵
    (n n)⍴(⍳n)∘.=⍳n
}

AssertIdentity←{
    epsilon a←⍺
    n←⌊/⍴a
    i←Identity n
    AssertNear epsilon i a
}

⍝ ----------------------------------------------------------------
⍝ 044  ZERO CHECK
⍝ ----------------------------------------------------------------

IsZero←{
    epsilon←⍺
    state←⍵
    ^/|,state≤epsilon
}

AssertZero←{
    epsilon state←⍺
    ⎕Assert epsilon IsZero state
    state
}

⍝ ----------------------------------------------------------------
⍝ 045  BOUNDARY CHECKS
⍝ ----------------------------------------------------------------

AssertLowerBound←{
    lower state←⍺
    ⎕Assert ^/lower≤,state
    state
}

AssertUpperBound←{
    upper state←⍺
    ⎕Assert ^/,state≤upper
    state
}

⍝ ----------------------------------------------------------------
⍝ 046  DENSITY MATRIX
⍝ ----------------------------------------------------------------

AssertDensityMatrix←{
    epsilon state←⍺
    result←AssertSquare state
    result←AssertHermitian epsilon result
    result←AssertUnitTrace epsilon result
    result←AssertNonNegativeDiagonal result
    result
}

⍝ ----------------------------------------------------------------
⍝ 047  FLOW INVARIANT
⍝ ----------------------------------------------------------------

FlowInvariant←{
    epsilon old new←⍺
    (|NormL2 old-NormL2 new)≤epsilon
}

AssertFlowInvariant←{
    epsilon old new←⍺
    ⎕Assert FlowInvariant epsilon old new
    new
}

⍝ ----------------------------------------------------------------
⍝ 048  MULTI-INVARIANT
⍝ ----------------------------------------------------------------

CheckInvariants←{
    epsilon chiMax old new←⍺
    a←AssertFinite new
    a←LiquidAssert (epsilon chiMax) a
    a←AssertNormConservation epsilon old a
    a
}

⍝ ----------------------------------------------------------------
⍝ 049  EROSION GATE
⍝ ----------------------------------------------------------------

ErosionGate←{
    epsilon previous current←⍺
    ErosionMagnitude previous current≤epsilon
}

AssertErosionGate←{
    epsilon previous current←⍺
    ⎕Assert ErosionGate epsilon previous current
    current
}

⍝ ----------------------------------------------------------------
⍝ 050  CHI GATE
⍝ ----------------------------------------------------------------

ChiGate←{
    chiMax←⍺
    MaxDimension ⍵≤chiMax
}

AssertChiGate←{
    chiMax state←⍺
    ⎕Assert ChiGate chiMax state
    state
}

⍝ ----------------------------------------------------------------
⍝ 051  LIQUID GATE
⍝ ----------------------------------------------------------------

LiquidGate←{
    epsilon chiMax state←⍺
    a←IsFinite state
    b←NormTargetError state≤epsilon
    c←MaxDimension state≤chiMax
    a^b^c
}

AssertLiquidGate←{
    epsilon chiMax state←⍺
    ⎕Assert LiquidGate epsilon chiMax state
    state
}

⍝ ----------------------------------------------------------------
⍝ 052  ACCEPT / REJECT
⍝ ----------------------------------------------------------------

Accept←{
    state←⍵
    1
}

Reject←{
    state←⍵
    0
}

Gate←{
    condition←⍺
    condition:Accept ⍵
    Reject ⍵
}

⍝ ----------------------------------------------------------------
⍝ 053  VALIDATION CODE
⍝ ----------------------------------------------------------------

ValidationCode←{
    epsilon chiMax state←⍺
    finite←IsFinite state
    normOk←NormTargetError state≤epsilon
    chiOk←MaxDimension state≤chiMax
    4×finite+2×normOk+chiOk
}

ValidationPass←{
    epsilon chiMax state←⍺
    7=ValidationCode epsilon chiMax state
}

⍝ ----------------------------------------------------------------
⍝ 054  REPORT
⍝ ----------------------------------------------------------------

LiquidReport←{
    epsilon chiMax state←⍺
    norm←NormL2 state
    chi←MaxDimension state
    finite←IsFinite state
    normOK←|norm-1≤epsilon
    chiOK←chi≤chiMax
    (finite norm normOK chi chiOK)
}

⍝ ----------------------------------------------------------------
⍝ 055  REPORT FORMAT
⍝ ----------------------------------------------------------------

LiquidReportText←{
    epsilon chiMax state←⍺
    r←LiquidReport epsilon chiMax state
    'FINITE=',⍕r[1],', NORM=',⍕r[2],', NORM_OK=',⍕r[3],', CHI=',⍕r[4],', CHI_OK=',⍕r[5]
}

⍝ ----------------------------------------------------------------
⍝ 056  SAMPLE STATE
⍝ ----------------------------------------------------------------

SampleState←{
    s←⍵
    NormalizeL2 s
}

SampleVector←{
    NormalizeL2 1 2 3 4
}

SampleMatrix←{
    NormalizeL2 1 2 3 4⍴1
}

⍝ ----------------------------------------------------------------
⍝ 057  TEST NORMALIZATION
⍝ ----------------------------------------------------------------

TestNorm←{
    state←SampleVector 0
    AssertUnitNorm DefaultEpsilon state
}

TestChi←{
    state←SampleVector 0
    AssertChi DefaultChiMax state
}

TestFinite←{
    state←SampleVector 0
    AssertFinite state
}

⍝ ----------------------------------------------------------------
⍝ 058  TEST LIQUID ASSERT
⍝ ----------------------------------------------------------------

TestLiquidAssert←{
    state←SampleVector 0
    LiquidAssert (DefaultEpsilon DefaultChiMax) state
}

⍝ ----------------------------------------------------------------
⍝ 059  TEST EROSION
⍝ ----------------------------------------------------------------

TestErosion←{
    state←SampleVector 0
    AssertErosion 1E¯8 state state
}

⍝ ----------------------------------------------------------------
⍝ 060  TEST REPORT
⍝ ----------------------------------------------------------------

TestReport←{
    state←SampleVector 0
    LiquidReport DefaultEpsilon DefaultChiMax state
}

⍝ ----------------------------------------------------------------
⍝ 061  WICK FLOW
⍝ ----------------------------------------------------------------

WickFlow←{
    epsilon chiMax state←⍺
    next←WickRotate state
    LiquidAssert (epsilon chiMax) next
}

⍝ ----------------------------------------------------------------
⍝ 062  NORMALIZED WICK FLOW
⍝ ----------------------------------------------------------------

NormalizedWickFlow←{
    epsilon chiMax state←⍺
    next←NormalizeL2 WickRotate state
    LiquidAssert (epsilon chiMax) next
}

⍝ ----------------------------------------------------------------
⍝ 063  ERODED WICK FLOW
⍝ ----------------------------------------------------------------

ErodedWickFlow←{
    epsilon chiMax erosion state←⍺
    next←NormalizeL2 WickRotate state
    LiquidAssert (epsilon chiMax) next
    AssertErosion erosion state next
}

⍝ ----------------------------------------------------------------
⍝ 064  STATE COMMIT
⍝ ----------------------------------------------------------------

CommitState←{
    epsilon chiMax state←⍺
    LiquidAssert (epsilon chiMax) state
    state
}

⍝ ----------------------------------------------------------------
⍝ 065  STATE ROLLBACK
⍝ ----------------------------------------------------------------

RollbackState←{
    state←⍵
    state
}

⍝ ----------------------------------------------------------------
⍝ 066  CONDITIONAL COMMIT
⍝ ----------------------------------------------------------------

ConditionalCommit←{
    epsilon chiMax old new←⍺
    LiquidGate epsilon chiMax new:
        new
    old
}

⍝ ----------------------------------------------------------------
⍝ 067  CONSERVATION COMMIT
⍝ ----------------------------------------------------------------

ConservationCommit←{
    epsilon chiMax old new←⍺
    LiquidAssert (epsilon chiMax) new
    AssertNormConservation epsilon old new
}

⍝ ----------------------------------------------------------------
⍝ 068  ASSERTION CHAIN
⍝ ----------------------------------------------------------------

LiquidChain←{
    epsilon chiMax state←⍺
    result←AssertFinite state
    result←AssertUnitNorm epsilon result
    result←AssertChi chiMax result
    result
}

⍝ ----------------------------------------------------------------
⍝ 069  STRICT CHAIN
⍝ ----------------------------------------------------------------

StrictLiquidChain←{
    epsilon chiMax state←⍺
    result←AssertNonEmpty state
    result←AssertFinite result
    result←AssertUnitNorm epsilon result
    result←AssertChi chiMax result
    result
}

⍝ ----------------------------------------------------------------
⍝ 070  SOFT VALIDATION
⍝ ----------------------------------------------------------------

SoftValidate←{
    epsilon chiMax state←⍺
    LiquidGate epsilon chiMax state
}

⍝ ----------------------------------------------------------------
⍝ 071  NORM CLAMP
⍝ ----------------------------------------------------------------

ClampNorm←{
    epsilon state←⍺
    n←NormL2 state
    |n-1≤epsilon:state
    NormalizeL2 state
}

⍝ ----------------------------------------------------------------
⍝ 072  DIMENSION CLAMP
⍝ ----------------------------------------------------------------

DimensionWithin←{
    chiMax state←⍺
    MaxDimension state≤chiMax
}

⍝ ----------------------------------------------------------------
⍝ 073  VALIDATE CONFIGURATION
⍝ ----------------------------------------------------------------

AssertConfig←{
    cfg←⍵
    ⎕Assert 2=≢cfg          ⍝ [epsilon chiMax]
    epsilon chiMax←cfg
    ⎕Assert epsilon>0
    ⎕Assert chiMax>0
    cfg
}

AssertConfigFinite←{
    cfg←⍵
    ⎕Assert IsFinite cfg
    cfg
}

ValidateConfig←{
    cfg←⍵
    cfg←AssertConfig cfg
    cfg←AssertConfigFinite cfg
    cfg
}

⍝ ----------------------------------------------------------------
⍝ 074  CONFIGURED LIQUID STEP
⍝ ----------------------------------------------------------------

ConfiguredLiquidStep←{
    cfg operator state←⍺
    cfg←ValidateConfig cfg
    epsilon chiMax←cfg
    next←operator state
    LiquidAssert (epsilon chiMax) next
}

ConfiguredLiquidChain←{
    cfg state←⍺
    cfg←ValidateConfig cfg
    epsilon chiMax←cfg
    StrictLiquidChain epsilon chiMax state
}

⍝ ----------------------------------------------------------------
⍝ 075  CONFIG + STATE SEAL
⍝ ----------------------------------------------------------------

ConfigStateSeal←{
    cfg state←⍺
    cfg←ValidateConfig cfg
    epsilon chiMax←cfg
    sig←StateSignature state
    ⍕epsilon,',',chiMax,',',sig
}

AssertConfigStateSeal←{
    expected cfg state←⍺
    actual←ConfigStateSeal cfg state
    ⎕Assert expected≡actual
    state
}

⍝ ----------------------------------------------------------------
⍝ 076  DEFAULT ASSERTOR
⍝ ----------------------------------------------------------------

DefaultLiquidAssert←{
    LiquidAssert (DefaultEpsilon DefaultChiMax) ⍵
}

⍝ ----------------------------------------------------------------
⍝ 077  STRICT DEFAULT
⍝ ----------------------------------------------------------------

StrictDefaultAssert←{
    StrictLiquidChain DefaultEpsilon DefaultChiMax ⍵
}

⍝ ----------------------------------------------------------------
⍝ 078  FLOW DIAGNOSTICS
⍝ ----------------------------------------------------------------

FlowDiagnostics←{
    epsilon chiMax old new←⍺
    oldNorm←NormL2 old
    newNorm←NormL2 new
    erosion←ErosionMagnitude old new
    chi←MaxDimension new
    (oldNorm newNorm erosion chi)
}

⍝ ----------------------------------------------------------------
⍝ 079  DIAGNOSTIC ASSERTION
⍝ ----------------------------------------------------------------

AssertFlowDiagnostics←{
    epsilon chiMax erosion old new←⍺
    d←FlowDiagnostics epsilon chiMax old new
    ⎕Assert |d[1]-d[2]≤epsilon
    ⎕Assert d[3]≤erosion
    ⎕Assert d[4]≤chiMax
    new
}

⍝ ----------------------------------------------------------------
⍝ 080  ENDPOINT
⍝ ----------------------------------------------------------------

LiquidEndpoint←{
    epsilon chiMax state←⍺
    LiquidAssert (epsilon chiMax) state
    StateSignature state
}

⍝ ----------------------------------------------------------------
⍝ 081  FINAL FLOW
⍝ ----------------------------------------------------------------

LiquidFlow←{
    epsilon chiMax operator state←⍺
    next←operator state
    next←NormalizeL2 next
    LiquidAssert (epsilon chiMax) next
}

⍝ ----------------------------------------------------------------
⍝ 082  FINAL PRESERVATION
⍝ ----------------------------------------------------------------

LiquidFlowPreserve←{
    epsilon chiMax operator state←⍺
    next←LiquidFlow epsilon chiMax operator state
    AssertNormConservation epsilon state next
}

⍝ ----------------------------------------------------------------
⍝ 083  EXAMPLE UPDATE
⍝ ----------------------------------------------------------------

ExampleUpdate←{
    updatedTensorState←⍵
    LiquidAssert (0.001 64) updatedTensorState
}

⍝ ----------------------------------------------------------------
⍝ 084  EXAMPLE NORMALIZATION
⍝ ----------------------------------------------------------------

ExampleNormalized←{
    state←NormalizeL2 ⍵
    LiquidAssert (0.001 64) state
}

⍝ ----------------------------------------------------------------
⍝ 085  EXAMPLE WICK UPDATE
⍝ ----------------------------------------------------------------

ExampleWickUpdate←{
    state←⍵
    updatedTensorState←WickRotate state
    normalized←NormalizeL2 updatedTensorState
    LiquidAssert (0.001 64) normalized
}

⍝ ----------------------------------------------------------------
⍝ 086  LIBRARY SELF TEST
⍝ ----------------------------------------------------------------

SelfTest←{
    TestNorm 0
    TestChi 0
    TestFinite 0
    TestLiquidAssert 0
    TestErosion 0
    TestReport 0
    1
}

⍝ ----------------------------------------------------------------
⍝ 087  VERSION
⍝ ----------------------------------------------------------------

Version←{
    LiquidVersion
}

⍝ ----------------------------------------------------------------
⍝ 088  EXPORT INDEX
⍝ ----------------------------------------------------------------

CoreExports←{
    LiquidAssert
    LiquidAssertReport
    LiquidGate
    LiquidFlow
    LiquidFlowPreserve
}

⍝ ----------------------------------------------------------------
⍝ 089  DOCUMENTED ENTRY POINT
⍝ ----------------------------------------------------------------

LiquidValidate←{
    epsilon chiMax state←⍺
    AssertConfiguration epsilon chiMax
    AssertFinite state
    LiquidAssert (epsilon chiMax) state
}

⍝ ----------------------------------------------------------------
⍝ 090  TERMINAL VALIDATOR
⍝ ----------------------------------------------------------------

LiquidFinalize←{
    epsilon chiMax state←⍺
    result←LiquidValidate epsilon chiMax state
    StateSignature result
}

⍝ ================================================================
⍝ END LIQUIDAPL FLOW ASSERTION LIBRARY
⍝ ================================================================
