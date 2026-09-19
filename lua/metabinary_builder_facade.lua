-- Lua Builder Facade Module
-- Unified builder interface with transparent backend selection
-- Handles constraint validation dispatch and builder pattern composition

local builder_facade = {}

-- ============================================================================
-- CONSTRAINT VALIDATORS
-- ============================================================================

builder_facade.validators = {}

function builder_facade.validators.validate_opcode(opcode)
    local valid_opcodes = {
        0x0001, 0x0010, 0x0011, 0x0012, 0x0020, 0x0021, 0x0030, -- Arithmetic
        0x0100, 0x0101, 0x0102,                                  -- Relinearization
        0x0200, 0x0201, 0x0202,                                  -- Modulus Management
        0x0300, 0x0301, 0x0302, 0x0303,                          -- Encoding
        0x0400, 0x0401, 0x0402,                                  -- Noise & Error
        0xF000, 0xF001, 0xF002, 0xF003,                          -- Composition
    }

    for _, valid_op in ipairs(valid_opcodes) do
        if valid_op == opcode then return true end
    end
    return false, "Invalid opcode: 0x" .. string.format("%04X", opcode)
end

function builder_facade.validators.validate_width(input_width, output_width)
    if input_width < 0 or output_width < 0 then
        return false, "Width values must be non-negative"
    end
    if input_width == 0 and output_width == 0 then
        return false, "At least one width dimension must be determined"
    end
    return true
end

function builder_facade.validators.validate_params(opcode, params)
    -- Expected parameter sizes by opcode (in bytes)
    local expected_sizes = {
        [0x0001] = 0,    -- IDENTITY
        [0x0010] = 0,    -- ADD
        [0x0011] = nil,  -- ADD_PLAIN (variable)
        [0x0012] = 0,    -- SUB
        [0x0020] = 0,    -- MUL
        [0x0021] = nil,  -- MUL_PLAIN (variable)
        [0x0030] = 0,    -- NEG
        [0x0100] = 2,    -- RELINEARIZE (u16)
        [0x0101] = 2,    -- KEY_SWITCH (u16)
        [0x0102] = 4,    -- ROTATE (i16 + u16)
        [0x0200] = 1,    -- MOD_SWITCH (u8)
        [0x0201] = 8,    -- RESCALE (u64)
        [0x0202] = 0,    -- MOD_UP
        [0x0300] = 9,    -- ENCODE (u64 + u16 + u8)
        [0x0302] = 4,    -- ENCRYPT (u32)
        [0x0303] = 4,    -- DECRYPT (u32)
        [0x0401] = 8,    -- NOISE_ASSERT (u64)
        [0xF003] = 4,    -- ITERATE (u32)
    }

    local expected = expected_sizes[opcode]
    if expected == nil then
        -- Variable or unknown opcode - allow any param length
        return true
    end
    if #params ~= expected then
        return false, string.format("Parameter size mismatch for opcode 0x%04X: expected %d bytes, got %d", opcode, expected, #params)
    end
    return true
end

function builder_facade.validators.validate_child_arity(opcode, child_count)
    local valid_arities = {
        [0x0001] = 0,       -- IDENTITY
        [0x0010] = 0,       -- ADD
        [0x0011] = 0,       -- ADD_PLAIN
        [0x0012] = 0,       -- SUB
        [0x0020] = 0,       -- MUL
        [0x0021] = 0,       -- MUL_PLAIN
        [0x0030] = 0,       -- NEG
        [0x0100] = 0,       -- RELINEARIZE
        [0x0101] = 0,       -- KEY_SWITCH
        [0x0102] = 0,       -- ROTATE
        [0x0200] = 0,       -- MOD_SWITCH
        [0x0201] = 0,       -- RESCALE
        [0x0202] = 0,       -- MOD_UP
        [0x0300] = 0,       -- ENCODE
        [0x0301] = 0,       -- DECODE
        [0x0302] = 0,       -- ENCRYPT
        [0x0303] = 0,       -- DECRYPT
        [0x0400] = 0,       -- NOISE_ESTIMATE
        [0x0401] = 0,       -- NOISE_ASSERT
        [0x0402] = 0,       -- BOOTSTRAP
        [0xF000] = nil,     -- COMPOSE (1+ children)
        [0xF001] = nil,     -- PARALLEL (1+ children)
        [0xF002] = 3,       -- CONDITIONAL (exactly 3)
        [0xF003] = 1,       -- ITERATE (exactly 1)
    }

    local valid = valid_arities[opcode]
    if valid == nil then
        -- Variable arity, require at least 1
        if child_count > 0 then return true end
        return false, string.format("Opcode 0x%04X requires 1+ children, got %d", opcode, child_count)
    end
    if child_count ~= valid then
        return false, string.format("Opcode 0x%04X requires exactly %d children, got %d", opcode, valid, child_count)
    end
    return true
end

function builder_facade.validators.validate_flags(flags, child_count)
    local has_children = (flags & 0x01) ~= 0
    local is_leaf = (flags & 0x02) ~= 0
    local reserved = (flags & 0xF8) ~= 0

    if reserved then
        return false, "Reserved flag bits are set"
    end
    if is_leaf and has_children then
        return false, "Cannot be both leaf and have children"
    end
    if (child_count > 0) ~= has_children then
        return false, "has_children flag does not match child_count"
    end
    if (child_count == 0) ~= is_leaf then
        return false, "is_leaf flag does not match child_count"
    end
    return true
end

-- ============================================================================
-- BUILDER CLASS
-- ============================================================================

local Builder = {}
Builder.__index = Builder

function Builder.new(opcode, options)
    options = options or {}

    -- Validate opcode
    local valid, msg = builder_facade.validators.validate_opcode(opcode)
    if not valid then
        error(msg)
    end

    local self = setmetatable({}, Builder)
    self.opcode = opcode
    self.version = 0x01
    self.flags = 0x00
    self.input_width = options.input_width or 0
    self.output_width = options.output_width or 0
    self.params = options.params or ""
    self.children = options.children or {}
    self.backend = options.backend or "c"
    self.validation_mode = options.validation_mode or "strict" -- "strict" or "lenient"
    self._is_built = false

    return self
end

function Builder:set_dimensions(input_width, output_width)
    if self._is_built then
        error("Cannot modify builder after build()")
    end

    local valid, msg = builder_facade.validators.validate_width(input_width, output_width)
    if not valid then
        if self.validation_mode == "strict" then
            error(msg)
        else
            -- Log warning but continue
            io.stderr:write(string.format("WARNING: %s\n", msg))
        end
    end

    self.input_width = input_width
    self.output_width = output_width
    return self
end

function Builder:set_params(params)
    if self._is_built then
        error("Cannot modify builder after build()")
    end

    local valid, msg = builder_facade.validators.validate_params(self.opcode, params)
    if not valid then
        if self.validation_mode == "strict" then
            error(msg)
        else
            io.stderr:write(string.format("WARNING: %s\n", msg))
        end
    end

    self.params = params or ""
    return self
end

function Builder:add_child(child)
    if self._is_built then
        error("Cannot modify builder after build()")
    end

    table.insert(self.children, child)

    -- Revalidate arity after adding child
    local valid, msg = builder_facade.validators.validate_child_arity(self.opcode, #self.children)
    if not valid then
        table.remove(self.children)
        if self.validation_mode == "strict" then
            error(msg)
        else
            io.stderr:write(string.format("WARNING: %s\n", msg))
        end
    end

    return self
end

function Builder:add_children(children)
    for _, child in ipairs(children) do
        self:add_child(child)
    end
    return self
end

function Builder:with_pure_flag(is_pure)
    if is_pure then
        self.flags = self.flags | 0x04
    else
        self.flags = self.flags & ~0x04
    end
    return self
end

function Builder:set_backend(backend)
    if backend ~= "c" and backend ~= "rust" and backend ~= "go" then
        error("Invalid backend: " .. backend)
    end
    self.backend = backend
    return self
end

function Builder:validate()
    -- Manual validation step before build
    local valid, msg = builder_facade.validators.validate_opcode(self.opcode)
    if not valid then return false, msg end

    valid, msg = builder_facade.validators.validate_width(self.input_width, self.output_width)
    if not valid then return false, msg end

    valid, msg = builder_facade.validators.validate_params(self.opcode, self.params)
    if not valid then return false, msg end

    valid, msg = builder_facade.validators.validate_child_arity(self.opcode, #self.children)
    if not valid then return false, msg end

    -- Update flags based on children
    self.flags = 0
    if #self.children > 0 then self.flags = self.flags | 0x01 end
    if #self.children == 0 then self.flags = self.flags | 0x02 end

    valid, msg = builder_facade.validators.validate_flags(self.flags, #self.children)
    if not valid then return false, msg end

    return true
end

function Builder:build()
    if self._is_built then
        error("Builder has already been built")
    end

    -- Perform final validation
    local valid, msg = self:validate()
    if not valid then
        if self.validation_mode == "strict" then
            error(msg)
        else
            io.stderr:write(string.format("WARNING: %s\n", msg))
        end
    end

    self._is_built = true

    local ast = {
        opcode = self.opcode,
        version = self.version,
        flags = self.flags,
        input_width = self.input_width,
        output_width = self.output_width,
        param_len = #self.params * 8,
        params = self.params,
        child_count = #self.children,
        children = self.children,
        backend = self.backend,
    }

    return ast
end

function Builder:serialize()
    local ast = self:build()
    -- Serialization would call binary.serialize() from main module
    return ast
end

function Builder:describe()
    return string.format(
        "Builder { opcode=0x%04X, in=%d, out=%d, children=%d, backend=%s, params=%d bytes }",
        self.opcode,
        self.input_width,
        self.output_width,
        #self.children,
        self.backend,
        #self.params
    )
end

-- ============================================================================
-- BUILDER FACTORY FUNCTIONS
-- ============================================================================

builder_facade.factory = {}

function builder_facade.factory.arithmetic(op_type, input_width, output_width)
    -- Factory for arithmetic operations
    local opcode_map = {
        add = 0x0010,
        add_plain = 0x0011,
        sub = 0x0012,
        mul = 0x0020,
        mul_plain = 0x0021,
        neg = 0x0030,
        identity = 0x0001,
    }

    local opcode = opcode_map[op_type]
    if not opcode then
        error("Unknown arithmetic operation: " .. op_type)
    end

    return Builder.new(opcode, {
        input_width = input_width,
        output_width = output_width,
    })
end

function builder_facade.factory.relinearization(relin_id, input_width, output_width)
    return Builder.new(0x0100, {
        input_width = input_width,
        output_width = output_width,
        params = string.char((relin_id >> 8) & 0xFF, relin_id & 0xFF), -- Pack as u16
    })
end

function builder_facade.factory.key_switching(ks_id, input_width, output_width)
    return Builder.new(0x0101, {
        input_width = input_width,
        output_width = output_width,
        params = string.char((ks_id >> 8) & 0xFF, ks_id & 0xFF),
    })
end

function builder_facade.factory.rotate(shift, mask, input_width, output_width)
    -- shift (i16) and mask (u16)
    local params = ""
    params = params .. string.char((shift >> 8) & 0xFF, shift & 0xFF)
    params = params .. string.char((mask >> 8) & 0xFF, mask & 0xFF)

    return Builder.new(0x0102, {
        input_width = input_width,
        output_width = output_width,
        params = params,
    })
end

function builder_facade.factory.encode(plaintext_size, scale, precision)
    -- plaintext_size (u64), scale (u16), precision (u8)
    local params = ""
    for i = 0, 7 do
        params = params .. string.char((plaintext_size >> (i * 8)) & 0xFF)
    end
    params = params .. string.char((scale >> 8) & 0xFF, scale & 0xFF)
    params = params .. string.char(precision & 0xFF)

    return Builder.new(0x0300, {
        output_width = plaintext_size,
        params = params,
    })
end

function builder_facade.factory.decrypt(key_id, input_width, output_width)
    return Builder.new(0x0303, {
        input_width = input_width,
        output_width = output_width,
        params = string.char(
            (key_id >> 24) & 0xFF,
            (key_id >> 16) & 0xFF,
            (key_id >> 8) & 0xFF,
            key_id & 0xFF
        ),
    })
end

function builder_facade.factory.compose(children, input_width, output_width)
    local builder = Builder.new(0xF000, {
        input_width = input_width,
        output_width = output_width,
    })
    for _, child in ipairs(children) do
        builder:add_child(child)
    end
    return builder
end

function builder_facade.factory.parallel(children, input_width, output_width)
    local builder = Builder.new(0xF001, {
        input_width = input_width,
        output_width = output_width,
    })
    for _, child in ipairs(children) do
        builder:add_child(child)
    end
    return builder
end

function builder_facade.factory.conditional(condition, true_branch, false_branch, input_width, output_width)
    local builder = Builder.new(0xF002, {
        input_width = input_width,
        output_width = output_width,
    })
    builder:add_child(condition)
    builder:add_child(true_branch)
    builder:add_child(false_branch)
    return builder
end

function builder_facade.factory.iterate(body, iterations, input_width, output_width)
    -- iterations packed as u32
    local params = string.char(
        (iterations >> 24) & 0xFF,
        (iterations >> 16) & 0xFF,
        (iterations >> 8) & 0xFF,
        iterations & 0xFF
    )

    local builder = Builder.new(0xF003, {
        input_width = input_width,
        output_width = output_width,
        params = params,
    })
    builder:add_child(body)
    return builder
end

-- ============================================================================
-- CONSTRAINT CHECKING EXTENSIONS
-- ============================================================================

builder_facade.constraints = {}

function builder_facade.constraints.check_integrity(ast, blake3_hash_fn)
    -- Verify structural integrity of AST
    if not ast or not ast.opcode then
        return false, "Invalid AST structure"
    end

    local valid, msg = builder_facade.validators.validate_opcode(ast.opcode)
    if not valid then return false, msg end

    valid, msg = builder_facade.validators.validate_width(ast.input_width or 0, ast.output_width or 0)
    if not valid then return false, msg end

    valid, msg = builder_facade.validators.validate_child_arity(ast.opcode, ast.child_count or #(ast.children or {}))
    if not valid then return false, msg end

    return true
end

function builder_facade.constraints.compute_complexity(ast)
    -- Compute AST complexity metrics
    local node_count = 1
    local depth = 1
    local leaf_count = 0

    if not ast.children or #ast.children == 0 then
        leaf_count = 1
    else
        for _, child in ipairs(ast.children) do
            local child_complexity = builder_facade.constraints.compute_complexity(child)
            node_count = node_count + child_complexity.nodes
            depth = math.max(depth, 1 + child_complexity.depth)
            leaf_count = leaf_count + child_complexity.leaves
        end
    end

    return {
        nodes = node_count,
        depth = depth,
        leaves = leaf_count,
    }
end

-- ============================================================================
-- EXPORT
-- ============================================================================

builder_facade.Builder = Builder

return builder_facade
