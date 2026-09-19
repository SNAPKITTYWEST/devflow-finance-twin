-- Lua Final Assembly Module
-- Complete integrated Lua + binary implementation
-- Combines metabinary.lua + FFI bindings + builder facade
-- Prototype unified interface; native validation requires matching libraries

local metabinary = require("metabinary")
local ffi_bindings = require("metabinary_ffi_bindings")
local builder_facade = require("metabinary_builder_facade")

local final_assembly = {}

-- ============================================================================
-- INTEGRATION CONFIGURATION
-- ============================================================================

final_assembly.config = {
    backend = "lua",        -- Lua codec; native names request additional validation
    auto_select = false,    -- Auto-select best backend
    validation_mode = "strict",
    enable_profiling = false,
    enable_diagnostics = false,
}

function final_assembly.configure(options)
    for key, value in pairs(options) do
        if final_assembly.config[key] ~= nil then
            final_assembly.config[key] = value
        end
    end
end

-- ============================================================================
-- BACKEND INITIALIZATION
-- ============================================================================

final_assembly.backends = {}

function final_assembly.backends.init_c(lib_path)
    local lib, err = ffi_bindings.c.load(lib_path)
    if lib then
        final_assembly.config.available_backends = final_assembly.config.available_backends or {}
        table.insert(final_assembly.config.available_backends, "c")
        return true
    end
    return false, err
end

function final_assembly.backends.init_rust(lib_path)
    local lib, err = ffi_bindings.rust.load(lib_path)
    if lib then
        final_assembly.config.available_backends = final_assembly.config.available_backends or {}
        table.insert(final_assembly.config.available_backends, "rust")
        return true
    end
    return false, err
end

function final_assembly.backends.init_go(lib_path)
    local lib, err = ffi_bindings.go.load(lib_path)
    if lib then
        final_assembly.config.available_backends = final_assembly.config.available_backends or {}
        table.insert(final_assembly.config.available_backends, "go")
        return true
    end
    return false, err
end

function final_assembly.backends.init_all(c_path, rust_path, go_path)
    final_assembly.config.available_backends = {}
    final_assembly.backends.init_c(c_path)
    final_assembly.backends.init_rust(rust_path)
    final_assembly.backends.init_go(go_path)
    return #final_assembly.config.available_backends > 0
end

function final_assembly.backends.select_best(preference)
    if final_assembly.config.auto_select then
        local best = ffi_bindings.detection.prefer_backend(preference or "speed")
        if best then
            final_assembly.config.backend = best
            return best
        end
    end
    return final_assembly.config.backend
end

-- ============================================================================
-- UNIFIED BUILDER INTERFACE
-- ============================================================================

final_assembly.builder = {}

function final_assembly.builder.new(opcode, options)
    options = options or {}
    options.backend = options.backend or final_assembly.config.backend
    options.validation_mode = options.validation_mode or final_assembly.config.validation_mode
    return builder_facade.Builder.new(opcode, options)
end

-- Delegate factory functions
function final_assembly.builder.arithmetic(op_type, input_width, output_width)
    return builder_facade.factory.arithmetic(op_type, input_width, output_width)
        :set_backend(final_assembly.config.backend)
end

function final_assembly.builder.relinearization(relin_id, input_width, output_width)
    return builder_facade.factory.relinearization(relin_id, input_width, output_width)
        :set_backend(final_assembly.config.backend)
end

function final_assembly.builder.compose(children, input_width, output_width)
    return builder_facade.factory.compose(children, input_width, output_width)
        :set_backend(final_assembly.config.backend)
end

function final_assembly.builder.parallel(children, input_width, output_width)
    return builder_facade.factory.parallel(children, input_width, output_width)
        :set_backend(final_assembly.config.backend)
end

function final_assembly.builder.conditional(condition, true_branch, false_branch, input_width, output_width)
    return builder_facade.factory.conditional(condition, true_branch, false_branch, input_width, output_width)
        :set_backend(final_assembly.config.backend)
end

function final_assembly.builder.iterate(body, iterations, input_width, output_width)
    return builder_facade.factory.iterate(body, iterations, input_width, output_width)
        :set_backend(final_assembly.config.backend)
end

-- ============================================================================
-- CONSTRAINT VALIDATION DISPATCH
-- ============================================================================

final_assembly.validation = {}

function final_assembly.validation.validate_block(data, backend)
    backend = backend or final_assembly.config.backend
    local valid, msg, header = metabinary.validate(data)
    if not valid then return false, msg, header end
    if backend == "lua" then return true, "OK", header end
    local binding = ffi_bindings[backend]
    if not binding or type(binding.validate) ~= "function" then return false, "Unknown backend: " .. tostring(backend) end
    local result, err = binding.validate(data, #data)
    if not result then return false, err or "Native validation unavailable" end
    if tonumber(result.status) ~= 0 then
        return false, "Native validation failed with status " .. tostring(result.status)
    end
    return true, "OK", result.header
end

function final_assembly.validation.validate_and_dispatch(data, backend)
    return final_assembly.validation.validate_block(data, backend)
end

-- ============================================================================
-- SERIALIZATION & DESERIALIZATION
-- ============================================================================

final_assembly.serialization = {}

function final_assembly.serialization.serialize(ast, backend)
    backend = backend or final_assembly.config.backend

    if final_assembly.config.enable_diagnostics then
        io.stderr:write(string.format("[SERIALIZE] backend=%s, opcode=0x%04X\n", backend, ast.opcode))
    end

    -- Always use Lua serialization as primary (more portable)
    -- Then optionally validate/optimize with native backends
    local serialized, err = metabinary.serialize(ast)
    if not serialized then
        return nil, err
    end

    local valid, msg = final_assembly.validation.validate_block(serialized, backend)
    if not valid then return nil, msg end

    return serialized
end

function final_assembly.serialization.deserialize(data, backend)
    backend = backend or final_assembly.config.backend

    if final_assembly.config.enable_diagnostics then
        io.stderr:write(string.format("[DESERIALIZE] backend=%s, data_size=%d\n", backend, #data))
    end

    -- Always use Lua deserialization as primary
    local ast, err, consumed = metabinary.deserialize(data)
    if not ast then
        return nil, err
    end

    if backend ~= "lua" then
        local valid, msg = final_assembly.validation.validate_block(data:sub(1, consumed), backend)
        if not valid then return nil, msg end
    end

    if final_assembly.config.enable_diagnostics then
        io.stderr:write(string.format("[DESERIALIZE] Success: opcode=0x%04X, children=%d\n", ast.opcode, ast.child_count or 0))
    end

    return ast, nil, consumed
end

-- ============================================================================
-- UNIFIED INTROSPECTION
-- ============================================================================

final_assembly.introspection = {}

function final_assembly.introspection.describe_ast(ast)
    return {
        opcode = ast.opcode,
        opcode_name = metabinary.OPCODE_NAMES[ast.opcode],
        version = ast.version,
        flags = ast.flags,
        dimensions = {
            input = ast.input_width,
            output = ast.output_width,
        },
        parameters = {
            length_bits = ast.param_len,
            length_bytes = math.ceil((ast.param_len or 0) / 8),
        },
        children = {
            count = ast.child_count or #(ast.children or {}),
            nodes = ast.children,
        },
        integrity = ast.integrity,
        complexity = final_assembly.introspection.measure_complexity(ast),
    }
end

function final_assembly.introspection.measure_complexity(ast)
    local complexity = builder_facade.constraints.compute_complexity(ast)
    return {
        total_nodes = complexity.nodes,
        tree_depth = complexity.depth,
        leaf_count = complexity.leaves,
    }
end

function final_assembly.introspection.tree_view(ast, indent)
    indent = indent or 0
    local prefix = string.rep("  ", indent)
    local opcode_name = metabinary.OPCODE_NAMES[ast.opcode] or "UNKNOWN"

    local line = string.format(
        "%s[0x%04X] %s (in=%d, out=%d, children=%d)",
        prefix,
        ast.opcode,
        opcode_name,
        ast.input_width or 0,
        ast.output_width or 0,
        ast.child_count or #(ast.children or {})
    )

    local lines = { line }
    for _, child in ipairs(ast.children or {}) do
        for _, child_line in ipairs(final_assembly.introspection.tree_view(child, indent + 1)) do
            table.insert(lines, child_line)
        end
    end

    return lines
end

function final_assembly.introspection.to_string(ast)
    local lines = final_assembly.introspection.tree_view(ast)
    return table.concat(lines, "\n")
end

-- ============================================================================
-- QUERY & ANALYSIS
-- ============================================================================

final_assembly.query = {}

function final_assembly.query.find_all(ast, opcode)
    return metabinary.query.find_all_opcodes(ast, opcode)
end

function final_assembly.query.count_nodes(ast)
    return metabinary.query.node_count(ast)
end

function final_assembly.query.count_leaves(ast)
    return metabinary.query.leaf_count(ast)
end

function final_assembly.query.tree_depth(ast)
    return metabinary.query.depth(ast)
end

function final_assembly.query.analyze(ast)
    return {
        nodes = final_assembly.query.count_nodes(ast),
        leaves = final_assembly.query.count_leaves(ast),
        depth = final_assembly.query.tree_depth(ast),
        opcodes_used = final_assembly.query.collect_opcodes(ast),
    }
end

function final_assembly.query.collect_opcodes(ast)
    local opcodes = {}
    local seen = {}

    local function traverse(node)
        if not seen[node.opcode] then
            seen[node.opcode] = true
            table.insert(opcodes, {
                code = node.opcode,
                name = metabinary.OPCODE_NAMES[node.opcode],
            })
        end
        for _, child in ipairs(node.children or {}) do
            traverse(child)
        end
    end

    traverse(ast)
    return opcodes
end

-- ============================================================================
-- PERFORMANCE PROFILING
-- ============================================================================

final_assembly.profiling = {}

function final_assembly.profiling.profile_serialize(ast, backend)
    backend = backend or final_assembly.config.backend
    local start_time = os.clock()

    local serialized = final_assembly.serialization.serialize(ast, backend)

    local end_time = os.clock()
    local elapsed = (end_time - start_time) * 1000 -- Convert to ms

    return {
        serialized = serialized,
        time_ms = elapsed,
        backend = backend,
        size_bytes = serialized and #serialized or 0,
        throughput_mb_s = serialized and (#serialized / elapsed / 1024 / 1024) or 0,
    }
end

function final_assembly.profiling.profile_deserialize(data, backend)
    backend = backend or final_assembly.config.backend
    local start_time = os.clock()

    local ast = final_assembly.serialization.deserialize(data, backend)

    local end_time = os.clock()
    local elapsed = (end_time - start_time) * 1000

    return {
        ast = ast,
        time_ms = elapsed,
        backend = backend,
        input_size_bytes = #data,
    }
end

function final_assembly.profiling.compare_backends(ast)
    local results = {}

    for _, backend in ipairs(final_assembly.config.available_backends or {"c"}) do
        local profile = final_assembly.profiling.profile_serialize(ast, backend)
        table.insert(results, {
            backend = backend,
            time_ms = profile.time_ms,
            size_bytes = profile.size_bytes,
        })
    end

    table.sort(results, function(a, b) return a.time_ms < b.time_ms end)
    return results
end

-- ============================================================================
-- STATUS & DIAGNOSTICS
-- ============================================================================

final_assembly.diagnostics = {}

function final_assembly.diagnostics.status()
    return {
        active_backend = final_assembly.config.backend,
        available_backends = final_assembly.config.available_backends or {},
        validation_mode = final_assembly.config.validation_mode,
        profiling_enabled = final_assembly.config.enable_profiling,
        diagnostics_enabled = final_assembly.config.enable_diagnostics,
        ffi_c_available = ffi_bindings.c.is_available(),
        ffi_rust_available = ffi_bindings.rust.is_available(),
        ffi_go_available = ffi_bindings.go.is_available(),
    }
end

function final_assembly.diagnostics.verify_installation()
    local status = final_assembly.diagnostics.status()
    local issues = {}

    if #status.available_backends == 0 then
        table.insert(issues, "No native backends available (falling back to pure Lua)")
    end

    if not ffi_bindings.c.is_available() then
        table.insert(issues, "C backend not loaded (C library may be missing)")
    end

    if not ffi_bindings.rust.is_available() then
        table.insert(issues, "Rust backend not loaded (Rust library may be missing)")
    end

    if not ffi_bindings.go.is_available() then
        table.insert(issues, "Go backend not loaded (Go library may be missing)")
    end

    return {
        status = status,
        issues = issues,
        all_available = #issues == 0,
    }
end

-- ============================================================================
-- PRESETS & TEMPLATES
-- ============================================================================

final_assembly.presets = {}

function final_assembly.presets.simple_arithmetic()
    local add_op = final_assembly.builder.arithmetic("add", 128, 128)
    return add_op:build()
end

function final_assembly.presets.encrypted_computation()
    local encode = final_assembly.builder.new(0x0300)
        :set_dimensions(0, 2048)

    local add = final_assembly.builder.new(0x0010)
        :set_dimensions(2048, 2048)

    local relinearize = final_assembly.builder.new(0x0100)
        :set_dimensions(2048, 2048)

    local decrypt = final_assembly.builder.new(0x0303)
        :set_dimensions(2048, 128)

    local pipeline = final_assembly.builder.compose(
        {encode:build(), add:build(), relinearize:build(), decrypt:build()},
        0,
        128
    )

    return pipeline:build()
end

function final_assembly.presets.bootstrapping_circuit()
    local noise_check = final_assembly.builder.new(0x0401)
        :set_dimensions(2048, 2048)

    local bootstrap = final_assembly.builder.new(0x0402)
        :set_dimensions(2048, 2048)

    local pipeline = final_assembly.builder.compose(
        {noise_check:build(), bootstrap:build()},
        2048,
        2048
    )

    return pipeline:build()
end

-- ============================================================================
-- EXPORT
-- ============================================================================

return final_assembly
