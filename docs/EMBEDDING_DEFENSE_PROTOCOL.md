# BEGIN EXECUTION

TARGET: TRANSFORMER EMBEDDING

MODE: STRICT ISOLATION

SOURCE BASELINE: OSS 1230

REPRESENTATION: AGOL

OBJECTIVE: BUILD AND DEFEND THE EMBEDDING COMPONENT

---

## EXECUTION RULE

Process the AGOL implementation in blocks of EXACTLY 100 lines.

Within every 100-line block:

1. Read line 1.
2. Validate line 1.
3. Trace every dependency introduced by line 1.
4. Read line 2.
5. Validate line 2.
6. Trace every dependency introduced by line 2.
7. Continue sequentially through line 100.
8. Do not skip lines.
9. Do not summarize uninspected lines.
10. Do not mark the block PASS until all 100 lines have been individually inspected.

After line 100:

STOP.

RESET THE DEFENSE STATE.

Return to line 1.

Perform the complete 100-line inspection again.

The second pass MUST NOT rely on the first pass.

Repeat independent passes until the component reaches the defined hardening threshold.

---

# LINE-LEVEL DEFENSE

For EVERY line determine:

LINE_ID

SOURCE_FILE

SOURCE_HASH

LINE_CONTENT

SYNTAX_VALID

TYPE_VALID

DEPENDENCIES_VALID

DATA_FLOW_VALID

CONTROL_FLOW_VALID

MEMORY_BEHAVIOR_VALID

NUMERICAL_BEHAVIOR_VALID

SECURITY_IMPACT

BOUNDARY_BEHAVIOR

ERROR_BEHAVIOR

DETERMINISM

TEST_COVERAGE

AGOL_SEMANTICS

VERIFICATION_STATUS

Any UNKNOWN value produces:

`FAIL CLOSED`

---

# 100-LINE CHECKPOINT

At lines:

100

200

300

400

500

600

700

800

900

1000

and every subsequent 100-line boundary:

create a checkpoint.

The checkpoint MUST contain:

LINES_INSPECTED

LINES_PASSED

LINES_FAILED

LINES_UNKNOWN

DEPENDENCIES_TRACED

INVARIANTS_CHECKED

TESTS_EXECUTED

PROOFS_CHECKED

DRIFT_DETECTED

DRIFT_REPAIRED

CURRENT_HASH

PREVIOUS_HASH

CHECKPOINT_STATUS

---

# RESET REQUIREMENT

After every 100-line block:

RESET.

Re-read the same block from its source.

Do not use the previous inspection as evidence.

Compare:

PASS_1

against

PASS_2

If the results differ:

DRIFT_DETECTED = TRUE

FAIL CLOSED.

The block must be investigated until the discrepancy is resolved.

Then repeat the block from the beginning.

---

# INVERTED DRIFT DEFENSE

Treat inverted drift as a first-class failure condition.

Detect:

* changed source
* changed dependencies
* changed generated output
* changed mathematical interpretation
* changed type interpretation
* changed control flow
* changed numerical behavior
* changed test behavior
* changed serialization behavior
* changed verification result

Any unexplained change invalidates all downstream checkpoints.

Invalidate:

CURRENT_VERIFICATION

DEPENDENT_VERIFICATION

FINAL_STATUS

Restart from the earliest affected block.

---

# EMBEDDING-SPECIFIC DEFENSE

For every embedding lookup verify:

TOKEN_ID

→ VOCABULARY_BOUND

→ EMBEDDING_ROW

→ MEMORY_LOCATION

→ EMBEDDING_VECTOR

→ OUTPUT_SHAPE

→ OUTPUT_VALUE

The fundamental invariant is:

`output(token_id) = E[token_id]`

Verify:

`t < 0` handling

`t >= V` handling

`t = 0` handling

`t = V - 1` handling

batch indexing

sequence indexing

padding

unknown tokens where applicable

serialization

deserialization

deterministic lookup

parameter integrity

---

# HARDENING LOOP

FOR EACH 100-LINE BLOCK:

PASS A:
line-by-line defense.

RESET.

PASS B:
line-by-line defense independently.

RESET.

PASS C:
line-by-line defense independently.

Compare PASS_A against PASS_B against PASS_C.

If all three agree: block is HARDENED.

If any differ: DRIFT_DETECTED = TRUE. FAIL CLOSED.
