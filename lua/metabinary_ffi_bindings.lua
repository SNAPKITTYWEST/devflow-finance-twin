-- Lua FFI Bindings Module
-- FFI declarations for C/Rust/Go binary implementations
-- Supports transparent backend selection: C (speed), Rust (safety), Go (cross-platform)

local ffi = require("ffi")
local ffi_bindings = {}

-- ============================================================================
-- FFI C DECLARATIONS
-- ============================================================================

-- Declare C structures matching HE-BINARY-FUNCTOR format
ffi.cdef [[
    typedef uint16_t u16;
    typedef uint32_t u32;
    typedef uint64_t u64;
    typedef uint8_t u8;
    typedef int32_t i32;

    // Block header structure (32 bytes)
    struct block_header {
        u16 opcode;
        u8  version;
        u8  flags;
        u32 input_width;
        u32 output_width;
        u32 param_len;
        u16 child_count;
        u16 reserved;
        u64 integrity;
    };

    // Serialized block
    struct binary_block {
        struct block_header header;
        u8 *params;
        struct binary_block **children;
    };

    // Status codes
    typedef enum {
        STATUS_OK = 0,
        STATUS_INVALID_INPUT = 1,
        STATUS_INVALID_PARAM = 2,
        STATUS_OVERFLOW = 3,
        STATUS_NOISE_EXCEEDED = 4,
        STATUS_COMPOSITION_ERROR = 5,
    } status_t;

    // Validation result
    struct validation_result {
        status_t status;
        struct block_header header;
        char *error_msg;
    };

    // Builder interface
    struct builder_context {
        struct block_header header;
        u8 *params;
        u32 param_len;
        struct binary_block **children;
        u32 child_count;
        u32 capacity;
    };
]]

-- ============================================================================
-- C BACKEND DECLARATIONS
-- ============================================================================

ffi_bindings.c = {}

local function load_c_backend(lib_path)
    -- Try to load C library
    lib_path = lib_path or "libmetabinary.so" -- Unix
    if ffi.os == "Windows" then
        lib_path = lib_path or "metabinary.dll"
    end

    local ok, lib = pcall(ffi.load, lib_path)
    if not ok then
        return nil, string.format("Failed to load C backend: %s", lib)
    end

    return lib
end

-- C function declarations
ffi.cdef [[
    // C Backend: Serialization & Deserialization
    u8 *c_serialize_block(struct binary_block *block, u32 *out_size, char **error);
    struct binary_block *c_deserialize_block(const u8 *data, u32 size, char **error);

    // C Backend: Validation
    struct validation_result c_validate_block(const u8 *data, u32 size);
    status_t c_validate_header(struct block_header *header);
    status_t c_validate_opcode(u16 opcode);
    status_t c_validate_width(u32 input_width, u32 output_width);
    status_t c_validate_param_len(u16 opcode, u32 param_len);
    status_t c_validate_child_arity(u16 opcode, u16 child_count);

    // C Backend: Builder
    struct builder_context *c_builder_create(u16 opcode);
    void c_builder_set_dimensions(struct builder_context *ctx, u32 in_width, u32 out_width);
    void c_builder_set_params(struct builder_context *ctx, const u8 *params, u32 len);
    void c_builder_add_child(struct builder_context *ctx, struct binary_block *child);
    struct binary_block *c_builder_build(struct builder_context *ctx);
    void c_builder_free(struct builder_context *ctx);

    // C Backend: Utilities
    u64 c_blake3_hash(const u8 *data, u32 len);
    void c_free_block(struct binary_block *block);
    void c_free(void *ptr);
]]

function ffi_bindings.c.load(lib_path)
    local lib, err = load_c_backend(lib_path)
    if not lib then
        return nil, err
    end
    ffi_bindings.c.lib = lib
    ffi_bindings.c.available = true
    return lib
end

function ffi_bindings.c.is_available()
    return ffi_bindings.c.available or false
end

function ffi_bindings.c.serialize(block, size_ptr)
    if not ffi_bindings.c.available then
        return nil, "C backend not loaded"
    end
    local error_ptr = ffi.new("char*[1]")
    local size_out = ffi.new("u32[1]")

    local result = ffi_bindings.c.lib.c_serialize_block(block, size_out, error_ptr)
    if result == nil then
        local err = ffi.string(error_ptr[0]) or "Unknown error"
        ffi_bindings.c.lib.c_free(error_ptr[0])
        return nil, err
    end

    local serialized = ffi.string(result, size_out[0])
    ffi_bindings.c.lib.c_free(result)
    return serialized
end

function ffi_bindings.c.deserialize(data, size)
    if not ffi_bindings.c.available then
        return nil, "C backend not loaded"
    end
    local error_ptr = ffi.new("char*[1]")
    local block = ffi_bindings.c.lib.c_deserialize_block(data, size, error_ptr)
    if block == nil then
        local err = ffi.string(error_ptr[0]) or "Unknown error"
        ffi_bindings.c.lib.c_free(error_ptr[0])
        return nil, err
    end
    return block
end

function ffi_bindings.c.validate(data, size)
    if not ffi_bindings.c.available then
        return nil, "C backend not loaded"
    end
    local result = ffi_bindings.c.lib.c_validate_block(data, size)
    return result
end

-- ============================================================================
-- RUST BACKEND DECLARATIONS
-- ============================================================================

ffi_bindings.rust = {}

-- Rust function declarations (C ABI)
ffi.cdef [[
    // Rust Backend: Serialization & Deserialization
    const u8 *rust_serialize_block(struct binary_block *block, u32 *out_size, u32 *error_code);
    struct binary_block *rust_deserialize_block(const u8 *data, u32 size, u32 *error_code);

    // Rust Backend: Validation (with detailed diagnostics)
    struct validation_result rust_validate_block_safe(const u8 *data, u32 size);
    status_t rust_validate_header_safe(struct block_header *header, char **diagnostics);
    status_t rust_validate_all_constraints(struct binary_block *block);

    // Rust Backend: Builder with constraint checking
    struct builder_context *rust_builder_create_safe(u16 opcode, u32 *error_code);
    void rust_builder_set_dimensions_checked(struct builder_context *ctx, u32 in_width, u32 out_width, u32 *error_code);
    void rust_builder_set_params_checked(struct builder_context *ctx, const u8 *params, u32 len, u32 *error_code);
    void rust_builder_add_child_checked(struct builder_context *ctx, struct binary_block *child, u32 *error_code);
    struct binary_block *rust_builder_build_validated(struct builder_context *ctx, u32 *error_code);
    void rust_builder_free(struct builder_context *ctx);

    // Rust Backend: Safety utilities
    u64 rust_blake3_hash_safe(const u8 *data, u32 len);
    void rust_free_block(struct binary_block *block);
    void rust_free(void *ptr);
]]

local function load_rust_backend(lib_path)
    -- Try to load Rust library (compiled as C ABI)
    lib_path = lib_path or "libmetabinary_rust.so"
    if ffi.os == "Windows" then
        lib_path = lib_path or "metabinary_rust.dll"
    end

    local ok, lib = pcall(ffi.load, lib_path)
    if not ok then
        return nil, string.format("Failed to load Rust backend: %s", lib)
    end

    return lib
end

function ffi_bindings.rust.load(lib_path)
    local lib, err = load_rust_backend(lib_path)
    if not lib then
        return nil, err
    end
    ffi_bindings.rust.lib = lib
    ffi_bindings.rust.available = true
    return lib
end

function ffi_bindings.rust.is_available()
    return ffi_bindings.rust.available or false
end

function ffi_bindings.rust.serialize(block)
    if not ffi_bindings.rust.available then
        return nil, "Rust backend not loaded"
    end
    local size_out = ffi.new("u32[1]")
    local error_code = ffi.new("u32[1]")

    local result = ffi_bindings.rust.lib.rust_serialize_block(block, size_out, error_code)
    if result == nil then
        return nil, string.format("Serialization failed with code %d", error_code[0])
    end

    local serialized = ffi.string(result, size_out[0])
    ffi_bindings.rust.lib.rust_free(result)
    return serialized
end

function ffi_bindings.rust.deserialize(data, size)
    if not ffi_bindings.rust.available then
        return nil, "Rust backend not loaded"
    end
    local error_code = ffi.new("u32[1]")
    local block = ffi_bindings.rust.lib.rust_deserialize_block(data, size, error_code)
    if block == nil then
        return nil, string.format("Deserialization failed with code %d", error_code[0])
    end
    return block
end

function ffi_bindings.rust.validate(data, size)
    if not ffi_bindings.rust.available then
        return nil, "Rust backend not loaded"
    end
    local result = ffi_bindings.rust.lib.rust_validate_block_safe(data, size)
    return result
end

function ffi_bindings.rust.validate_all_constraints(block)
    if not ffi_bindings.rust.available then
        return nil, "Rust backend not loaded"
    end
    local status = ffi_bindings.rust.lib.rust_validate_all_constraints(block)
    return status
end

-- ============================================================================
-- GO BACKEND DECLARATIONS (VIA CGO)
-- ============================================================================

ffi_bindings.go = {}

-- Go function declarations (C ABI exported via CGO)
ffi.cdef [[
    // Go Backend: Serialization & Deserialization
    struct go_result {
        void *data;
        u32 len;
        u32 error_code;
    };

    struct go_result go_serialize_block(struct binary_block *block);
    struct binary_block *go_deserialize_block(const u8 *data, u32 size, u32 *error_code);

    // Go Backend: Validation
    struct validation_result go_validate_block_cross_platform(const u8 *data, u32 size);
    status_t go_validate_all(struct binary_block *block, char **diagnostics);

    // Go Backend: Builder
    struct builder_context *go_builder_create(u16 opcode, u32 *error_code);
    void go_builder_set_dimensions(struct builder_context *ctx, u32 in_width, u32 out_width, u32 *error_code);
    void go_builder_add_child(struct builder_context *ctx, struct binary_block *child, u32 *error_code);
    struct binary_block *go_builder_build(struct builder_context *ctx, u32 *error_code);
    void go_builder_free(struct builder_context *ctx);

    // Go Backend: Cross-platform utilities
    u64 go_blake3_hash(const u8 *data, u32 len);
    void go_free_block(struct binary_block *block);
    void go_free(void *ptr);
]]

local function load_go_backend(lib_path)
    -- Try to load Go library (exported via CGO)
    lib_path = lib_path or "libmetabinary_go.so"
    if ffi.os == "Windows" then
        lib_path = lib_path or "metabinary_go.dll"
    elseif ffi.os == "OSX" then
        lib_path = lib_path or "libmetabinary_go.dylib"
    end

    local ok, lib = pcall(ffi.load, lib_path)
    if not ok then
        return nil, string.format("Failed to load Go backend: %s", lib)
    end

    return lib
end

function ffi_bindings.go.load(lib_path)
    local lib, err = load_go_backend(lib_path)
    if not lib then
        return nil, err
    end
    ffi_bindings.go.lib = lib
    ffi_bindings.go.available = true
    return lib
end

function ffi_bindings.go.is_available()
    return ffi_bindings.go.available or false
end

function ffi_bindings.go.serialize(block)
    if not ffi_bindings.go.available then
        return nil, "Go backend not loaded"
    end
    local result = ffi_bindings.go.lib.go_serialize_block(block)
    if result.error_code ~= 0 then
        ffi_bindings.go.lib.go_free(result.data)
        return nil, string.format("Serialization failed with code %d", result.error_code)
    end

    local serialized = ffi.string(result.data, result.len)
    ffi_bindings.go.lib.go_free(result.data)
    return serialized
end

function ffi_bindings.go.deserialize(data, size)
    if not ffi_bindings.go.available then
        return nil, "Go backend not loaded"
    end
    local error_code = ffi.new("u32[1]")
    local block = ffi_bindings.go.lib.go_deserialize_block(data, size, error_code)
    if block == nil then
        return nil, string.format("Deserialization failed with code %d", error_code[0])
    end
    return block
end

function ffi_bindings.go.validate(data, size)
    if not ffi_bindings.go.available then
        return nil, "Go backend not loaded"
    end
    local result = ffi_bindings.go.lib.go_validate_block_cross_platform(data, size)
    return result
end

-- ============================================================================
-- BACKEND SELECTION & DETECTION
-- ============================================================================

ffi_bindings.detection = {}

function ffi_bindings.detection.available_backends()
    local available = {}
    if ffi_bindings.c.is_available() then table.insert(available, "c") end
    if ffi_bindings.rust.is_available() then table.insert(available, "rust") end
    if ffi_bindings.go.is_available() then table.insert(available, "go") end
    return available
end

function ffi_bindings.detection.prefer_backend(preference)
    -- preference: "speed" -> C, "safety" -> Rust, "cross_platform" -> Go
    if preference == "speed" and ffi_bindings.c.is_available() then
        return "c"
    elseif preference == "safety" and ffi_bindings.rust.is_available() then
        return "rust"
    elseif preference == "cross_platform" and ffi_bindings.go.is_available() then
        return "go"
    else
        -- Fallback to available backends
        local backends = ffi_bindings.detection.available_backends()
        if #backends > 0 then return backends[1] end
        return nil
    end
end

-- ============================================================================
-- UNIFIED INTERFACE
-- ============================================================================

ffi_bindings.unified = {}

function ffi_bindings.unified.serialize(block, backend)
    backend = backend or "c"

    if backend == "c" then
        return ffi_bindings.c.serialize(block)
    elseif backend == "rust" then
        return ffi_bindings.rust.serialize(block)
    elseif backend == "go" then
        return ffi_bindings.go.serialize(block)
    else
        return nil, "Unknown backend: " .. backend
    end
end

function ffi_bindings.unified.deserialize(data, size, backend)
    backend = backend or "c"
    size = size or #data

    if backend == "c" then
        return ffi_bindings.c.deserialize(data, size)
    elseif backend == "rust" then
        return ffi_bindings.rust.deserialize(data, size)
    elseif backend == "go" then
        return ffi_bindings.go.deserialize(data, size)
    else
        return nil, "Unknown backend: " .. backend
    end
end

function ffi_bindings.unified.validate(data, size, backend)
    backend = backend or "c"
    size = size or #data

    if backend == "c" then
        return ffi_bindings.c.validate(data, size)
    elseif backend == "rust" then
        return ffi_bindings.rust.validate(data, size)
    elseif backend == "go" then
        return ffi_bindings.go.validate(data, size)
    else
        return nil, "Unknown backend: " .. backend
    end
end

-- ============================================================================
-- EXPORT
-- ============================================================================

return ffi_bindings
