# Unified Binary Layer Interface Specification

## Overview

This specification defines a unified, polyglot API for binary validation and construction across C, Rust, and Go. All three language bindings use the same interface contracts, error semantics, and AST predicate mapping.

**Design Principle**: Fail-closed everywhere. All validation functions return explicit status codes; no implicit successes.

---

## 1. Common Interfaces & Error Handling

### Error Code Registry (Universal across all languages)

```
SUCCESS              = 0x00000000
ERR_INVALID_MAGIC    = 0xE0000001
ERR_INVALID_VERSION  = 0xE0000002
ERR_VALIDATION_FAIL  = 0xE0000003
ERR_UNSAFE_VARIABLE  = 0xE0000004
ERR_UNDEFINED_PRED   = 0xE0000005
ERR_NEGATIVE_CYCLE   = 0xE0000006
ERR_AGGREGATE_INVALID = 0xE0000007
ERR_TYPE_MISMATCH    = 0xE0000008
ERR_BOUNDS_VIOLATED  = 0xE0000009
ERR_MEMORY_ALLOC     = 0xE000000A
ERR_SERIALIZATION    = 0xE000000B
ERR_DESERIALIZATION  = 0xE000000C
ERR_INTEROP_MISMATCH = 0xE000000D
```

### Status Result Type (All languages implement this pattern)

**C**:
```c
typedef struct {
    int32_t code;           // Error code
    char *message;          // Human-readable error
    void *result;           // Opaque result handle (NULL on failure)    
    uint64_t metadata;      // Validation metadata (flags, counts)
} BinaryResult;
```

**Rust**:
```rust
pub type BinaryResult<T> = Result<T, BinaryError>;

pub struct BinaryError {
    pub code: i32,
    pub message: String,
    pub metadata: u64,
}
```

**Go**:
```go
type BinaryResult struct {
    Code     int32
    Message  string
    Result   interface{}  // Type-specific result
    Metadata uint64
}

func (br *BinaryResult) IsErr() bool {
    return br.Code != SUCCESS
}
```

---

## 2. AST Predicate Validation Mapping

Every AST kind has a corresponding validation predicate. Validation is **cascading** (parent validates children).

### Core AST Predicates

| AST Kind | Validation Predicate | Constraints |
|----------|---------------------|-------------|
| `AST_MODULE` | `validate_module(name, decls, routines)` | name != empty; decls/routines form DAG |
| `AST_ROUTINE` | `validate_routine(name, params, locals, body)` | name != empty; params/locals disjoint; body well-formed |
| `AST_BLOCK` | `validate_block(stmts)` | all stmts valid; no dead code after return/exit |
| `AST_DECL` | `validate_decl(name, type, storage)` | name != empty; type valid; storage class legal |
| `AST_ASSIGN` | `validate_assign(lhs, rhs)` | lhs addressable; types compatible |
| `AST_IF` | `validate_if(cond, then_b, else_b)` | cond predicate; branches valid; no unsafe jumps |
| `AST_WHILE` | `validate_while(cond, body)` | cond predicate; body valid; loop-invariant safe |
| `AST_FOR` | `validate_for(init, cond, step, body)` | init/step assign; cond predicate; body valid |
| `AST_RETURN` | `validate_return(expr)` | expr type matches routine return type |
| `AST_PARALLEL` | `validate_parallel(width, body)` | width > 0; body thread-safe; no implicit sync |
| `AST_CALL` | `validate_call(fn, args)` | fn defined; arg types match; no forward refs |
| `AST_CAST` | `validate_cast(expr, to)` | expr type → to type legal; width safe |
| `AST_BITFIELD` | `validate_bitfield(expr, offset, width)` | offset + width ≤ bit width of expr |
| `AST_NUMBER` | `validate_number(value, is_float)` | value in range; float precision OK |
| `AST_IDENT` | `validate_ident(name)` | name != empty; defined in scope |
| `AST_BINARY` | `validate_binary(op, left, right)` | op valid; left/right type-compatible |

### Semantic Predicates (derived from AST shape)

| Predicate | Definition | Fail Condition |
|-----------|-----------|-----------------|
| `safe_var_usage(rule)` | All head variables appear in positive body | Head var ∉ positive body |
| `no_undefined_pred(predicate, arity)` | Predicate is defined somewhere | Predicate ∉ KB and not builtin |
| `no_negative_cycle(pred_graph)` | No negative edges in cycles | Cycle contains negation |
| `valid_aggregate(agg_op, bounds, cond)` | Aggregate syntax valid | Invalid op/bounds or undefined condition |
| `type_consistent(term1, term2)` | Types unify | Type conflict after substitution |
| `memory_safe(ptr, offset, width)` | Address valid | Out-of-bounds or null deref |

---

## 3. Builder Pattern (Polyglot)

All builders follow this contract:
1. **Fluent interface** (method chaining)
2. **Lazy validation** (only on finalize)
3. **Fail-closed** (early exit on constraint violation)
4. **Metadata capture** (validation reason codes)

### Builder Architecture (pseudo-code)

```
class BinaryBuilder {
    private internal_state: UnvalidatedAST
    private constraints: ValidationRule[]
    private error_log: BinaryError[]
    
    fn add_predicate(name, arity):
        -> if (name.empty? || arity < 0)
           -> error(ERR_VALIDATION_FAIL, "predicate name/arity invalid")
        -> self.internal_state.predicates.insert(name/arity)
        -> return self  // Fluent
    
    fn add_rule(head, body):
        -> result = validate_rule_shape(head, body)
        -> if (result.code != SUCCESS)
           -> error_log.push(result)
           -> return self  // Continue to collect errors
        -> internal_state.rules.push(head, body)
        -> return self
    
    fn finalize():
        -> if (error_log.size() > 0)
           -> return Err(error_log[0])  // Fail-closed
        -> return validate_semantics(internal_state)
        -> if errors
           -> return Err(first_error)
        -> return Ok(BinaryAST)
}
```

### Concrete Builders

**C**: `BinaryBuilder_t` with function pointers
**Rust**: Generic `BinaryBuilder<T: Validatable>` 
**Go**: Interface-based `Builder` with methods

---

## 4. Interop Layer Specification (C ↔ Rust ↔ Go)

### FFI Binding Rules

1. **Only opaque handles cross language boundaries**
   - C ←→ Rust: Rust allocates, C holds `*mut c_void`
   - Rust ↔ Go: Go calls Rust via CGO wrapper
   - All handles must be explicitly freed in owning language

2. **Validation status always explicit**
   ```c
   // C side
   BinaryResult_t result = binary_validate_rust_ast(rust_handle);
   if (result.code != SUCCESS) {
       // Handle error deterministically
       binary_free_handle(rust_handle);
       return result.code;
   }
   ```

3. **Serialization for language boundaries**
   - Use Turing header + marshaled AST
   - SHA-256 integrity check on every crossing
   - No shared memory (copy on cross-boundary)

### Serialization Format (all languages)

```
[8 bytes ] Turing Header (magic + version)
[4 bytes ] AST Kind
[4 bytes ] Payload Length N
[N bytes ] Marshaled AST (kind-specific)
[32 bytes] SHA-256(payload)
```

---

## 5. Validation Checklist (AST Predicate → Code Mapping)

### Phase 1: Structural Validation

- [ ] `validate_magic_header()` → checks magic == 0x5455524E
- [ ] `validate_version()` → checks version == 0x0001
- [ ] `validate_ast_kind()` → AST kind in legal range
- [ ] `validate_type_consistency()` → all Type ptrs non-null or explicitly VOID

### Phase 2: Symbol Validation

- [ ] `collect_defined_predicates()` → scan all rule heads, build definition set
- [ ] `check_undefined_predicates()` → every body predicate in definitions ∪ builtins
- [ ] `validate_scoping()` → all variables declared before use
- [ ] `check_storage_classes()` → storage class valid for declaration context

### Phase 3: Safety Validation

- [ ] `check_safe_variables()` → head vars ⊆ positive body vars
- [ ] `check_memory_safety()` → no out-of-bounds bitfield access
- [ ] `check_type_unification()` → assignments type-safe
- [ ] `validate_casts()` → explicit casts width-safe

### Phase 4: Semantics Validation

- [ ] `detect_negative_cycles()` → DFS on dependency graph, flag negation edges
- [ ] `validate_aggregate_syntax()` → agg op ∈ {count,sum,min,max}; bounds sensible
- [ ] `check_recursion_strategy()` → left-recursive rules flagged (warn)
- [ ] `validate_choice_rules()` → no choice rule in body; at most one choice per head

### Phase 5: Binary Validation

- [ ] `verify_sha256()` → hash field matches marshaled payload
- [ ] `verify_encoding_alignment()` → no padding gaps; big-endian respected
- [ ] `check_header_consistency()` → magic/version compatible

---

## 6. Error Context Propagation

Every validation error includes:

```
{
  error_code:    <from registry above>
  source_file:   <filename or "interop">
  line_number:   <0 if not applicable>
  column:        <0 if not applicable>
  failing_node:  <AST kind or predicate name>
  message:       <human-readable>
  suggestion:    <how to fix>
  metadata:      {
    phase:       <1-5 as above>
    recovered:   <bool: can validation continue?>
  }
}
```

**Fail-Closed Contract**: If `recovered == false`, validation stops immediately.

---

## 7. Builder Finalization Contract

Before returning a finalized AST, all builders **must** execute this sequence:

```
1. Structural validation (Phase 1)
2. Symbol validation (Phase 2)
3. Safety validation (Phase 3)
4. Semantics validation (Phase 4)
5. Binary validation (Phase 5)
6. Interop consistency check (if crossing language boundary)
7. Return either:
   - BinaryResult { code: SUCCESS, result: ValidatedAST }
   - BinaryResult { code: ERR_XXX, result: NULL, error_log: [...] }
```

No partial results. No undefined behavior.

---

## 8. Language-Specific Normalization

### C
- All functions return `int32_t` status code
- Output params via pointer args
- Memory owned by caller (all allocations explicit)

### Rust
- Return `Result<T, BinaryError>`
- Ownership tracked at compile-time
- No unsafe code in validation hot path

### Go
- Return `(*BinaryResult, error)` tuple
- Defer cleanup via `defer binary.FreeHandle(h)`
- Panic only on memory exhaustion

---

## References

- **Turing Binary Foundation**: `turing_binary_foundation.go`
- **AST Definition**: `kernel-language/include/ast.h`
- **ASP Validator**: `asp/semantics/validator.go`
- **Semantic Checker**: `asp/semantics/checker.go`
