/*
 * polyglot_builder.h
 *
 * Unified C header for polyglot AST builders (C, Rust, Go backends).
 * Implements fail-closed validation with explicit error handling.
 * All builders share this interface contract.
 */

#ifndef POLYGLOT_BUILDER_H
#define POLYGLOT_BUILDER_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * COMMON ERROR CODES (Universal across all languages)
 * ============================================================ */

#define SUCCESS                 0x00000000
#define ERR_INVALID_MAGIC       0xE0000001
#define ERR_INVALID_VERSION     0xE0000002
#define ERR_VALIDATION_FAIL     0xE0000003
#define ERR_UNSAFE_VARIABLE     0xE0000004
#define ERR_UNDEFINED_PRED      0xE0000005
#define ERR_NEGATIVE_CYCLE      0xE0000006
#define ERR_AGGREGATE_INVALID   0xE0000007
#define ERR_TYPE_MISMATCH       0xE0000008
#define ERR_BOUNDS_VIOLATED     0xE0000009
#define ERR_MEMORY_ALLOC        0xE000000A
#define ERR_SERIALIZATION       0xE000000B
#define ERR_DESERIALIZATION     0xE000000C
#define ERR_INTEROP_MISMATCH    0xE000000D

/* ============================================================
 * RESULT TYPE (Fail-Closed Pattern)
 * ============================================================ */

typedef struct {
    int32_t   code;           /* Error code (0 = SUCCESS) */
    char     *message;        /* Human-readable error message */
    void     *result;         /* Opaque result handle (NULL on failure) */
    uint64_t  metadata;       /* Validation metadata: phase | flags | counts */
} BinaryResult_t;

/* Result metadata field bitpacking:
 * [63:56] = validation phase (1-5)
 * [55:48] = recovery flag (1 = can continue, 0 = fatal)
 * [47:32] = error count
 * [31:16] = warning count
 * [15:0]  = reserved
 */

#define PHASE_SHIFT       56
#define RECOVERY_SHIFT    48
#define ERROR_COUNT_SHIFT 32

static inline uint8_t metadata_phase(uint64_t m) {
    return (m >> PHASE_SHIFT) & 0xFF;
}

static inline uint8_t metadata_recovery(uint64_t m) {
    return (m >> RECOVERY_SHIFT) & 0xFF;
}

static inline uint16_t metadata_error_count(uint64_t m) {
    return (m >> ERROR_COUNT_SHIFT) & 0xFFFF;
}

static inline uint16_t metadata_warning_count(uint64_t m) {
    return m & 0xFFFF;
}

/* ============================================================
 * BUILDER INTERFACE (Abstract)
 * ============================================================ */

typedef struct {
    const char *name;          /* Builder name for debugging */
    uint32_t    language_tag;  /* 'C   ', 'Rust', 'Go  ' */
    void       *state;         /* Opaque builder state */
} BinaryBuilder_t;

/* Language tags */
#define LANG_C       0x4320202020  /* "C   " */
#define LANG_RUST    0x52757374    /* "Rust" */
#define LANG_GO      0x476F2020    /* "Go  " */

/* ============================================================
 * BUILDER LIFECYCLE
 * ============================================================ */

/*
 * binary_builder_new(language_tag)
 * Create a new builder for the given language backend.
 * Returns a builder with internal state initialized.
 */
BinaryBuilder_t *binary_builder_new(uint32_t language_tag);

/*
 * binary_builder_add_predicate(builder, name, arity)
 * Add a predicate definition to the builder.
 * Returns the builder (fluent interface) or NULL on fatal error.
 */
BinaryBuilder_t *binary_builder_add_predicate(
    BinaryBuilder_t *builder,
    const char      *name,
    int32_t          arity
);

/*
 * binary_builder_add_rule(builder, head, body)
 * Add a rule (head :- body) to the builder.
 * head and body are opaque AST handles from prior operations.
 * Returns the builder (fluent interface) or NULL on fatal error.
 */
BinaryBuilder_t *binary_builder_add_rule(
    BinaryBuilder_t *builder,
    void            *head,
    void            *body
);

/*
 * binary_builder_add_constraint(builder, constraint_ast)
 * Add a constraint (:- body) to the builder.
 */
BinaryBuilder_t *binary_builder_add_constraint(
    BinaryBuilder_t *builder,
    void            *constraint_ast
);

/*
 * binary_builder_add_choice_rule(builder, choice_head, body)
 * Add a choice rule ({a; b; c} :- body) to the builder.
 * choice_head is a disjunctive head AST.
 */
BinaryBuilder_t *binary_builder_add_choice_rule(
    BinaryBuilder_t *builder,
    void            *choice_head,
    void            *body
);

/*
 * binary_builder_finalize(builder)
 * Execute complete validation pipeline and return result.
 * Validation phases:
 *   1. Structural (magic, version, AST kind)
 *   2. Symbol (predicate definitions, scoping)
 *   3. Safety (variable safety, memory bounds, type unification)
 *   4. Semantics (negative cycles, aggregates, recursion)
 *   5. Binary (SHA-256, encoding alignment)
 *
 * FAIL-CLOSED: If any phase fails, returns error immediately.
 * Returns BinaryResult_t with code=SUCCESS and result=ValidatedAST,
 * or code=ERR_* with result=NULL and metadata indicating phase.
 */
BinaryResult_t binary_builder_finalize(BinaryBuilder_t *builder);

/*
 * binary_builder_free(builder)
 * Release all resources associated with the builder.
 * Safe to call on NULL.
 */
void binary_builder_free(BinaryBuilder_t *builder);

/* ============================================================
 * RESULT HANDLING (Fail-Closed Pattern)
 * ============================================================ */

/*
 * binary_result_is_error(result)
 * Returns true if result indicates failure.
 */
static inline bool binary_result_is_error(const BinaryResult_t *result) {
    return result != NULL && result->code != SUCCESS;
}

/*
 * binary_result_phase(result)
 * Extract validation phase where error occurred (1-5, or 0 if no error).
 */
static inline uint8_t binary_result_phase(const BinaryResult_t *result) {
    return result != NULL ? metadata_phase(result->metadata) : 0;
}

/*
 * binary_result_is_recoverable(result)
 * Returns true if validation can continue despite this error.
 */
static inline bool binary_result_is_recoverable(const BinaryResult_t *result) {
    return result != NULL && metadata_recovery(result->metadata) != 0;
}

/*
 * binary_result_error_count(result)
 * Number of errors in validation result.
 */
static inline uint16_t binary_result_error_count(const BinaryResult_t *result) {
    return result != NULL ? metadata_error_count(result->metadata) : 0;
}

/* ============================================================
 * HANDLE MANAGEMENT (Interop)
 * ============================================================ */

/*
 * binary_free_handle(handle)
 * Release an opaque AST or result handle.
 * Safe to call on NULL.
 */
void binary_free_handle(void *handle);

/*
 * binary_handle_clone(handle)
 * Create a deep copy of an opaque handle (for crossing language boundaries).
 * Returns NULL on allocation failure.
 */
void *binary_handle_clone(const void *handle);

/*
 * binary_handle_serialize(handle, out_buffer, out_size)
 * Serialize an opaque handle to binary format (Turing header + marshaled AST + SHA-256).
 * Caller allocates out_buffer (suggest 4KB initially).
 * Returns error code; sets out_size to bytes written.
 */
int32_t binary_handle_serialize(
    const void  *handle,
    uint8_t     *out_buffer,
    size_t      *out_size
);

/*
 * binary_handle_deserialize(buffer, size)
 * Deserialize a binary buffer back to opaque handle.
 * Validates SHA-256 before returning.
 * Returns handle on success, NULL on failure.
 */
void *binary_handle_deserialize(const uint8_t *buffer, size_t size);

/* ============================================================
 * VALIDATION PREDICATES (Direct Interface)
 * ============================================================ */

/*
 * binary_validate_magic_header(magic_value)
 * Check magic header == 0x5455524E ("TURN").
 * Returns SUCCESS or ERR_INVALID_MAGIC.
 */
int32_t binary_validate_magic_header(uint32_t magic_value);

/*
 * binary_validate_version(version_value)
 * Check version == 0x0001.
 * Returns SUCCESS or ERR_INVALID_VERSION.
 */
int32_t binary_validate_version(uint16_t version_value);

/*
 * binary_validate_ast_kind(kind)
 * Check AST kind in legal range (AST_MODULE through AST_MACRO_INV).
 * Returns SUCCESS or ERR_VALIDATION_FAIL.
 */
int32_t binary_validate_ast_kind(uint32_t kind);

/*
 * binary_validate_safe_variables(rule_handle)
 * Check that all head variables appear in positive body literals.
 * Returns SUCCESS or ERR_UNSAFE_VARIABLE.
 */
int32_t binary_validate_safe_variables(void *rule_handle);

/*
 * binary_validate_no_undefined_predicates(builder_state)
 * Scan all predicates: check ∀ body pred ∈ (defined ∪ builtins).
 * Returns SUCCESS or ERR_UNDEFINED_PRED (first instance).
 */
int32_t binary_validate_no_undefined_predicates(void *builder_state);

/*
 * binary_validate_no_negative_cycles(builder_state)
 * Build dependency graph, detect cycles with negation edges.
 * Returns SUCCESS or ERR_NEGATIVE_CYCLE (first cycle).
 */
int32_t binary_validate_no_negative_cycles(void *builder_state);

/*
 * binary_validate_aggregate_syntax(aggregate_handle)
 * Check agg operation ∈ {count, sum, min, max}, bounds sensible.
 * Returns SUCCESS or ERR_AGGREGATE_INVALID.
 */
int32_t binary_validate_aggregate_syntax(void *aggregate_handle);

/*
 * binary_validate_type_unification(lhs_handle, rhs_handle)
 * Check if lhs and rhs types unify.
 * Returns SUCCESS or ERR_TYPE_MISMATCH.
 */
int32_t binary_validate_type_unification(void *lhs_handle, void *rhs_handle);

/*
 * binary_validate_memory_bounds(ptr_handle, offset, width)
 * Check (offset + width) ≤ bit_width_of(ptr).
 * Returns SUCCESS or ERR_BOUNDS_VIOLATED.
 */
int32_t binary_validate_memory_bounds(void *ptr_handle, int32_t offset, int32_t width);

/*
 * binary_validate_sha256(buffer, size, expected_hash)
 * Verify SHA-256(buffer) == expected_hash (32 bytes).
 * Returns SUCCESS or ERR_SERIALIZATION (hash mismatch).
 */
int32_t binary_validate_sha256(
    const uint8_t *buffer,
    size_t         size,
    const uint8_t  expected_hash[32]
);

/* ============================================================
 * INTROSPECTION
 * ============================================================ */

/*
 * binary_builder_error_count(builder)
 * Number of non-fatal validation errors accumulated so far.
 */
uint16_t binary_builder_error_count(const BinaryBuilder_t *builder);

/*
 * binary_builder_get_last_error(builder)
 * Retrieve the most recent validation error message.
 * Returns NULL if no errors.
 */
const char *binary_builder_get_last_error(const BinaryBuilder_t *builder);

/*
 * binary_builder_get_error_log(builder, out_messages, max_count)
 * Retrieve all accumulated validation error messages (up to max_count).
 * Populates out_messages array, returns actual count.
 */
int32_t binary_builder_get_error_log(
    const BinaryBuilder_t *builder,
    const char           **out_messages,
    int32_t               max_count
);

#ifdef __cplusplus
}
#endif

#endif /* POLYGLOT_BUILDER_H */
