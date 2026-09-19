/*
 * interop_ffi.h
 *
 * Polyglot FFI Interoperability Layer
 * Enables transparent validation across C ↔ Rust ↔ Go language boundaries.
 *
 * Design:
 * - All cross-boundary data serialized to Turing binary format
 * - Validation status always explicit (never implicit success)
 * - SHA-256 integrity check on every crossing
 * - Opaque handles prevent accidental type confusion
 *
 * Error Handling (Fail-Closed):
 * - Every FFI boundary check returns explicit error code
 * - No undefined behavior on type mismatch
 * - Caller must check status before accessing result
 */

#ifndef INTEROP_FFI_H
#define INTEROP_FFI_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * CROSS-LANGUAGE HANDLE MANAGEMENT
 * ============================================================ */

/*
 * FFI Handle: Opaque pointer to language-specific AST.
 * Type information stored separately; never dereference directly.
 * Must be freed by the language that owns it.
 */
typedef void *FFIHandle;

/*
 * Handle ownership rules:
 * - C allocates & owns: Rust/Go receive read-only reference
 * - Rust allocates & owns: C holds *mut c_void, must call ffi_rust_free()
 * - Go allocates & owns: C holds unsafe.Pointer, must call ffi_go_free()
 *
 * Deep copies allowed at boundaries (via serialization).
 */

typedef enum {
    FFI_LANG_C = 0x4320202020,    /* "C   " */
    FFI_LANG_RUST = 0x52757374,   /* "Rust" */
    FFI_LANG_GO = 0x476F2020,     /* "Go  " */
} FFILanguage;

/*
 * ffi_handle_owner(handle)
 * Determine which language allocated this handle.
 * Returns FFI_LANG_* or 0 if unknown (error).
 */
FFILanguage ffi_handle_owner(FFIHandle handle);

/*
 * ffi_handle_retain(handle)
 * Increment reference count (for sharing). Not always supported.
 * Returns 0 on success, error code on failure.
 */
int32_t ffi_handle_retain(FFIHandle handle);

/*
 * ffi_handle_release(handle)
 * Decrement reference count; free when count reaches 0.
 * Safe to call on NULL.
 */
void ffi_handle_release(FFIHandle handle);

/* ============================================================
 * TURING BINARY SERIALIZATION (Cross-Boundary Format)
 * ============================================================ */

/*
 * Serialization Format:
 * [8 bytes ] Turing Header
 *   [4 bytes] Magic: 0x5455524E ("TURN")
 *   [2 bytes] Version: 0x0001
 *   [2 bytes] Reserved
 * [4 bytes ] AST Kind (enum value)
 * [4 bytes ] Payload Length N (including metadata)
 * [N bytes ] Marshaled AST (kind-specific)
 * [32 bytes] SHA-256 of (Magic || Version || AstKind || Payload)
 *
 * Big-endian throughout. No padding.
 */

#define TURING_MAGIC 0x5455524E      /* "TURN" */
#define TURING_VERSION 0x0001
#define TURING_HEADER_SIZE 8          /* magic(4) + version(2) + reserved(2) */
#define TURING_CHECKSUM_SIZE 32       /* SHA-256 */

typedef struct {
    uint8_t  magic[4];              /* 0x5455524E */
    uint8_t  version[2];            /* 0x0001 */
    uint8_t  reserved[2];           /* 0x0000 */
} TuringHeader;

typedef struct {
    uint32_t kind;                  /* AST kind enum */
    uint32_t payload_len;           /* Bytes following this field */
    uint8_t  payload[1];            /* Flexible array; actual size = payload_len */
} TuringBody;

typedef struct {
    TuringHeader header;
    TuringBody   body;              /* Pointer-based; actual size varies */
    uint8_t      checksum[TURING_CHECKSUM_SIZE];
} TuringBinary;

/*
 * ffi_serialize_handle(handle, out_buffer, out_size)
 * Marshal an opaque handle to Turing binary format.
 * Caller allocates out_buffer; suggest 4KB initially.
 * Returns error code; sets out_size to bytes written.
 *
 * Fail-closed: If serialization fails, out_buffer unchanged.
 */
int32_t ffi_serialize_handle(
    FFIHandle   handle,
    uint8_t    *out_buffer,
    size_t     *out_size
);

/*
 * ffi_deserialize_to_c(buffer, size)
 * Unmarshal Turing binary to C AST handle.
 * Validates SHA-256 before returning.
 * Returns handle on success, NULL on error.
 */
FFIHandle ffi_deserialize_to_c(const uint8_t *buffer, size_t size);

/*
 * ffi_deserialize_to_rust(buffer, size)
 * Unmarshal Turing binary to Rust AST handle (opaque).
 * Validates SHA-256 before returning.
 * Returns handle on success, NULL on error.
 * Caller must call ffi_rust_free() to release.
 */
FFIHandle ffi_deserialize_to_rust(const uint8_t *buffer, size_t size);

/*
 * ffi_deserialize_to_go(buffer, size)
 * Unmarshal Turing binary to Go AST handle (opaque).
 * Validates SHA-256 before returning.
 * Returns handle on success, NULL on error.
 * Caller must call ffi_go_free() to release.
 */
FFIHandle ffi_deserialize_to_go(const uint8_t *buffer, size_t size);

/* ============================================================
 * VALIDATION AT FFI BOUNDARIES
 * ============================================================ */

/*
 * ffi_validate_buffer_format(buffer, size)
 * Quick validation: check Turing header magic/version and buffer length.
 * Does NOT deserialize or check SHA-256.
 * Returns error code; 0 = valid format.
 */
int32_t ffi_validate_buffer_format(const uint8_t *buffer, size_t size);

/*
 * ffi_validate_buffer_integrity(buffer, size)
 * Verify SHA-256 checksum in buffer.
 * Returns 0 if checksum valid, ERR_SERIALIZATION if mismatch.
 */
int32_t ffi_validate_buffer_integrity(const uint8_t *buffer, size_t size);

/*
 * ffi_validate_handle_language(handle, expected_lang)
 * Verify handle came from expected language.
 * Returns 0 if match, ERR_INTEROP_MISMATCH if mismatch.
 */
int32_t ffi_validate_handle_language(FFIHandle handle, FFILanguage expected_lang);

/* ============================================================
 * LANGUAGE-SPECIFIC FFI (Stubs for Rust & Go)
 * ============================================================ */

/* --- RUST INTEROP --- */

/*
 * ffi_rust_builder_new()
 * Create a new Rust BinaryBuilder via FFI.
 * Returns opaque handle; must call ffi_rust_builder_free() to release.
 */
FFIHandle ffi_rust_builder_new(void);

/*
 * ffi_rust_builder_add_predicate(builder, name, arity)
 * Add predicate to Rust builder (fluent interface).
 * Returns error code; 0 = success.
 */
int32_t ffi_rust_builder_add_predicate(
    FFIHandle   builder,
    const char *name,
    int32_t     arity
);

/*
 * ffi_rust_builder_finalize(builder, out_result)
 * Execute Rust validation pipeline; return serialized AST.
 * Allocates out_result buffer via malloc (caller must free).
 * Returns error code; 0 = success.
 */
int32_t ffi_rust_builder_finalize(
    FFIHandle   builder,
    uint8_t   **out_result,
    size_t     *out_result_size
);

/*
 * ffi_rust_free(handle)
 * Release Rust-owned handle (builder or AST).
 * Safe to call on NULL.
 */
void ffi_rust_free(FFIHandle handle);

/*
 * ffi_rust_validate_safe_variables(rule_handle)
 * Call Rust validation predicate from C.
 * Returns error code; 0 = safe.
 */
int32_t ffi_rust_validate_safe_variables(FFIHandle rule_handle);

/*
 * ffi_rust_validate_negative_cycles(ast_handle)
 * Check for negative cycles in Rust AST.
 * Returns error code; 0 = no cycles.
 */
int32_t ffi_rust_validate_negative_cycles(FFIHandle ast_handle);

/* --- GO INTEROP --- */

/*
 * ffi_go_builder_new()
 * Create a new Go BinaryBuilder via FFI.
 * Returns opaque handle; must call ffi_go_builder_free() to release.
 */
FFIHandle ffi_go_builder_new(void);

/*
 * ffi_go_builder_add_predicate(builder, name, arity)
 * Add predicate to Go builder.
 * Returns error code; 0 = success.
 */
int32_t ffi_go_builder_add_predicate(
    FFIHandle   builder,
    const char *name,
    int32_t     arity
);

/*
 * ffi_go_builder_finalize(builder, out_result)
 * Execute Go validation pipeline; return serialized AST.
 * Allocates out_result buffer (caller must free).
 * Returns error code; 0 = success.
 */
int32_t ffi_go_builder_finalize(
    FFIHandle   builder,
    uint8_t   **out_result,
    size_t     *out_result_size
);

/*
 * ffi_go_free(handle)
 * Release Go-owned handle.
 * Safe to call on NULL.
 */
void ffi_go_free(FFIHandle handle);

/*
 * ffi_go_validate_safe_variables(rule_handle)
 * Call Go validation predicate from C.
 * Returns error code; 0 = safe.
 */
int32_t ffi_go_validate_safe_variables(FFIHandle rule_handle);

/*
 * ffi_go_validate_negative_cycles(ast_handle)
 * Check for negative cycles in Go AST.
 * Returns error code; 0 = no cycles.
 */
int32_t ffi_go_validate_negative_cycles(FFIHandle ast_handle);

/* ============================================================
 * ERROR HANDLING AT FFI BOUNDARIES
 * ============================================================ */

/*
 * ffi_get_last_error(language, out_message, max_len)
 * Retrieve error message from specified language backend.
 * Writes up to max_len bytes to out_message.
 * Returns error code that caused the message, or 0 if no error.
 */
int32_t ffi_get_last_error(
    FFILanguage language,
    char       *out_message,
    size_t      max_len
);

/*
 * ffi_clear_error(language)
 * Clear error state in specified language backend.
 * Allows next operation to proceed without inheriting prior errors.
 */
void ffi_clear_error(FFILanguage language);

/* ============================================================
 * CROSS-LANGUAGE VALIDATION WORKFLOW
 * ============================================================ */

/*
 * Example: Build in Rust, validate in C, finalize in Go
 *
 * // 1. Create Rust builder
 * FFIHandle rust_builder = ffi_rust_builder_new();
 * if (rust_builder == NULL) {
 *     // Handle error
 * }
 *
 * // 2. Add predicates (Rust side)
 * if (ffi_rust_builder_add_predicate(rust_builder, "parent", 2) != 0) {
 *     // Handle error
 *     ffi_rust_free(rust_builder);
 * }
 *
 * // 3. Finalize in Rust (serialize to Turing binary)
 * uint8_t *rust_result = NULL;
 * size_t rust_result_size = 0;
 * if (ffi_rust_builder_finalize(rust_builder, &rust_result, &rust_result_size) != 0) {
 *     // Handle error
 * }
 * ffi_rust_free(rust_builder);
 *
 * // 4. Validate buffer format in C
 * if (ffi_validate_buffer_format(rust_result, rust_result_size) != 0) {
 *     free(rust_result);
 *     // Handle error
 * }
 *
 * // 5. Deserialize to Go AST
 * FFIHandle go_ast = ffi_deserialize_to_go(rust_result, rust_result_size);
 * free(rust_result);
 * if (go_ast == NULL) {
 *     // Handle error
 * }
 *
 * // 6. Validate Go AST
 * if (ffi_go_validate_negative_cycles(go_ast) != 0) {
 *     ffi_go_free(go_ast);
 *     // Handle error
 * }
 *
 * // 7. Use validated AST or serialize again
 * ffi_go_free(go_ast);
 */

/* ============================================================
 * CLEANUP
 * ============================================================ */

/*
 * ffi_free_all()
 * Emergency cleanup: release all pending handles across all languages.
 * Call only when aborting due to error; not for normal cleanup.
 */
void ffi_free_all(void);

#ifdef __cplusplus
}
#endif

#endif /* INTEROP_FFI_H */
