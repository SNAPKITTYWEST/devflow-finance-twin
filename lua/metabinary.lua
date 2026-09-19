-- Lua 5.4 Metabinary Module
-- Binary serialization/deserialization for HE-BINARY-FUNCTOR and NAND binary formats
-- Supports AST manipulation, constraint validation, and introspection

local binary = {}

-- ============================================================================
-- CONSTANTS & OPCODE DEFINITIONS
-- ============================================================================

binary.OPCODES = {
    -- Core Arithmetic
    IDENTITY = 0x0001,
    ADD = 0x0010,
    ADD_PLAIN = 0x0011,
    SUB = 0x0012,
    MUL = 0x0020,
    MUL_PLAIN = 0x0021,
    NEG = 0x0030,
    -- Relinearization & Key Switching
    RELINEARIZE = 0x0100,
    KEY_SWITCH = 0x0101,
    ROTATE = 0x0102,
    -- Modulus Management
    MOD_SWITCH = 0x0200,
    RESCALE = 0x0201,
    MOD_UP = 0x0202,
    -- Encoding/Decoding
    ENCODE = 0x0300,
    DECODE = 0x0301,
    ENCRYPT = 0x0302,
    DECRYPT = 0x0303,
    -- Noise & Error Management
    NOISE_ESTIMATE = 0x0400,
    NOISE_ASSERT = 0x0401,
    BOOTSTRAP = 0x0402,
    -- Composition & Control
    COMPOSE = 0xF000,
    PARALLEL = 0xF001,
    CONDITIONAL = 0xF002,
    ITERATE = 0xF003,
}

binary.OPCODE_NAMES = {
    [0x0001] = "IDENTITY",
    [0x0010] = "ADD",
    [0x0011] = "ADD_PLAIN",
    [0x0012] = "SUB",
    [0x0020] = "MUL",
    [0x0021] = "MUL_PLAIN",
    [0x0030] = "NEG",
    [0x0100] = "RELINEARIZE",
    [0x0101] = "KEY_SWITCH",
    [0x0102] = "ROTATE",
    [0x0200] = "MOD_SWITCH",
    [0x0201] = "RESCALE",
    [0x0202] = "MOD_UP",
    [0x0300] = "ENCODE",
    [0x0301] = "DECODE",
    [0x0302] = "ENCRYPT",
    [0x0303] = "DECRYPT",
    [0x0400] = "NOISE_ESTIMATE",
    [0x0401] = "NOISE_ASSERT",
    [0x0402] = "BOOTSTRAP",
    [0xF000] = "COMPOSE",
    [0xF001] = "PARALLEL",
    [0xF002] = "CONDITIONAL",
    [0xF003] = "ITERATE",
}

binary.STATUS = {
    OK = 0,
    INVALID_INPUT = 1,
    INVALID_PARAM = 2,
    OVERFLOW = 3,
    NOISE_EXCEEDED = 4,
    COMPOSITION_ERROR = 5,
}

binary.STATUS_NAMES = {
    [0] = "OK",
    [1] = "INVALID_INPUT",
    [2] = "INVALID_PARAM",
    [3] = "OVERFLOW",
    [4] = "NOISE_EXCEEDED",
    [5] = "COMPOSITION_ERROR",
}

-- NAND instruction opcodes
binary.NAND_OPS = {
    NAND = 0x0,
    HALT = 0x1,
    LOAD = 0x2,
    STORE = 0x3,
    LDI = 0x4,
    JMP = 0x5,
    JZ = 0x6,
}

binary.NAND_OP_NAMES = {
    [0x0] = "NAND",
    [0x1] = "HALT",
    [0x2] = "LOAD",
    [0x3] = "STORE",
    [0x4] = "LDI",
    [0x5] = "JMP",
    [0x6] = "JZ",
}

-- ============================================================================
-- BINARY I/O UTILITIES
-- ============================================================================

local function pack_u16_le(value)
    -- Pack u16 as little-endian bytes
    return string.char(value & 0xFF, (value >> 8) & 0xFF)
end

local function pack_u32_le(value)
    -- Pack u32 as little-endian bytes
    return string.char(
        value & 0xFF,
        (value >> 8) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 24) & 0xFF
    )
end

local function pack_u64_le(value)
    -- Pack u64 as little-endian bytes (Lua uses doubles, so this is approximate)
    local low = value & 0xFFFFFFFF
    local high = (value >> 32) & 0xFFFFFFFF
    return pack_u32_le(low) .. pack_u32_le(high)
end

local function pack_u8(value)
    return string.char(value & 0xFF)
end

local function unpack_u16_le(data, offset)
    offset = offset or 1
    local b1 = string.byte(data, offset)
    local b2 = string.byte(data, offset + 1)
    return (b2 << 8) | b1, offset + 2
end

local function unpack_u32_le(data, offset)
    offset = offset or 1
    local b1 = string.byte(data, offset)
    local b2 = string.byte(data, offset + 1)
    local b3 = string.byte(data, offset + 2)
    local b4 = string.byte(data, offset + 3)
    return (b4 << 24) | (b3 << 16) | (b2 << 8) | b1, offset + 4
end

local function unpack_u64_le(data, offset)
    offset = offset or 1
    local low, new_offset = unpack_u32_le(data, offset)
    local high = unpack_u32_le(data, new_offset)
    return (high << 32) | low, new_offset + 4
end

local function unpack_u8(data, offset)
    offset = offset or 1
    return string.byte(data, offset), offset + 1
end

-- Blake3 mock for testing (real implementation would use external library)

-- ============================================================================
-- BLOCK HEADER STRUCTURE
-- ============================================================================

binary.structures = {}

function binary.structures.header_new()
    return {
        opcode = 0x0001,
        version = 0x01,
        flags = 0x00,
        input_width = 0,
        output_width = 0,
        param_len = 0,
        child_count = 0,
        reserved = 0,
        integrity = 0,
    }
end

function binary.structures.header_size()
    return 32 -- Fixed 32-byte header
end



-- ============================================================================
-- BLOCK FUNCTOR STRUCTURE
-- ============================================================================

function binary.structures.block_new(opcode, input_width, output_width)
    return {
        opcode = opcode or 0x0001,
        version = 0x01,
        flags = 0x00,
        input_width = input_width or 0,
        output_width = output_width or 0,
        param_len = 0,
        params = "",
        child_count = 0,
        children = {},
        integrity = 0,
    }
end

function binary.structures.block_set_flags(block, has_children, is_leaf, pure)
    block.flags = 0
    if has_children then block.flags = block.flags | 0x01 end
    if is_leaf then block.flags = block.flags | 0x02 end
    if pure then block.flags = block.flags | 0x04 end
end

-- ============================================================================
-- VALIDATION PREDICATES
-- ============================================================================

binary.predicates = {}

-- Predicate: header structural validity
function binary.predicates.valid_header(header)
    if not header.opcode or header.opcode == 0 then
        return false, "INVALID_OPCODE"
    end
    if header.version ~= 0x01 then
        return false, "INVALID_VERSION"
    end
    if (header.flags & 0xF8) ~= 0 then
        return false, "INVALID_FLAGS_RESERVED"
    end
    return true
end

-- Predicate: opcode is known and valid
function binary.predicates.valid_opcode(opcode)
    return binary.OPCODE_NAMES[opcode] ~= nil
end

-- Predicate: width consistency
function binary.predicates.width_valid(input_width, output_width)
    if input_width < 0 or output_width < 0 then
        return false, "NEGATIVE_WIDTH"
    end
    -- At least one dimension must be determined
    if input_width == 0 and output_width == 0 then
        return false, "UNDETERMINED_DIMENSIONS"
    end
    return true
end

-- Predicate: parameter length matches opcode
function binary.predicates.param_len_matches_opcode(opcode, param_len)
    -- Define expected parameter sizes by opcode (in bits)
    local expected_sizes = {
        [0x0001] = 0,    -- IDENTITY: no params
        [0x0010] = 0,    -- ADD: no params
        [0x0011] = nil,  -- ADD_PLAIN: variable
        [0x0012] = 0,    -- SUB: no params
        [0x0020] = 0,    -- MUL: no params
        [0x0021] = nil,  -- MUL_PLAIN: variable
        [0x0030] = 0,    -- NEG: no params
        [0x0100] = 16,   -- RELINEARIZE: u16
        [0x0101] = 16,   -- KEY_SWITCH: u16
        [0x0102] = 32,   -- ROTATE: i16 + u16
        [0x0200] = 8,    -- MOD_SWITCH: u8
        [0x0201] = 64,   -- RESCALE: u64
        [0x0202] = 0,    -- MOD_UP: no params
        [0x0300] = 88,   -- ENCODE: u64 + u16 + u8
        [0x0302] = 32,   -- ENCRYPT: u32
        [0x0303] = 32,   -- DECRYPT: u32
        [0x0401] = 64,   -- NOISE_ASSERT: u64
        [0xF003] = 32,   -- ITERATE: u32
    }

    local expected = expected_sizes[opcode]
    if expected == nil then
        -- Variable or unknown opcode, allow any param_len
        return true
    end
    return param_len == expected, string.format("PARAM_MISMATCH: expected %d bits, got %d", expected, param_len)
end

-- Predicate: child arity matches opcode
function binary.predicates.child_arity_matches_opcode(opcode, child_count)
    local valid_arities = {
        [0x0001] = 0,       -- IDENTITY: no children
        [0x0010] = 0,       -- ADD: no children (operands are inputs)
        [0x0011] = 0,       -- ADD_PLAIN: no children
        [0x0012] = 0,       -- SUB: no children
        [0x0020] = 0,       -- MUL: no children
        [0x0021] = 0,       -- MUL_PLAIN: no children
        [0x0030] = 0,       -- NEG: no children
        [0x0100] = 0,       -- RELINEARIZE: no children
        [0x0101] = 0,       -- KEY_SWITCH: no children
        [0x0102] = 0,       -- ROTATE: no children
        [0x0200] = 0,       -- MOD_SWITCH: no children
        [0x0201] = 0,       -- RESCALE: no children
        [0x0202] = 0,       -- MOD_UP: no children
        [0x0300] = 0,       -- ENCODE: no children
        [0x0301] = 0,       -- DECODE: no children
        [0x0302] = 0,       -- ENCRYPT: no children
        [0x0303] = 0,       -- DECRYPT: no children
        [0x0400] = 0,       -- NOISE_ESTIMATE: no children
        [0x0401] = 0,       -- NOISE_ASSERT: no children
        [0x0402] = 0,       -- BOOTSTRAP: no children
        [0xF000] = nil,     -- COMPOSE: 1+ children
        [0xF001] = nil,     -- PARALLEL: 1+ children
        [0xF002] = 3,       -- CONDITIONAL: exactly 3 children
        [0xF003] = 1,       -- ITERATE: exactly 1 child
    }

    local valid = valid_arities[opcode]
    if valid == nil then
        -- Variable arity, allow any count >= 1
        return child_count > 0, "INVALID_CHILD_COUNT"
    end
    return child_count == valid, string.format("CHILD_ARITY_MISMATCH: expected %d, got %d", valid, child_count)
end

-- Predicate: flags consistency with children
function binary.predicates.flags_consistency(flags, child_count)
    local has_children = (flags & 0x01) ~= 0
    local is_leaf = (flags & 0x02) ~= 0

    -- Cannot be both leaf and have children
    if is_leaf and has_children then
        return false, "CONTRADICTORY_FLAGS"
    end

    -- has_children flag must match child_count
    if (child_count > 0) ~= has_children then
        return false, "FLAGS_CHILD_MISMATCH"
    end

    -- is_leaf must match child_count
    if (child_count == 0) ~= is_leaf then
        return false, "FLAGS_LEAF_MISMATCH"
    end

    return true
end

-- Predicate: integrity check

-- ============================================================================
-- VALIDATION ENGINE
-- ============================================================================


-- ============================================================================
-- SERIALIZATION
-- ============================================================================


-- ============================================================================
-- DESERIALIZATION
-- ============================================================================


-- ============================================================================
-- BUILDER PATTERN
-- ============================================================================

binary.builder = {}

function binary.builder.new(opcode)
    return setmetatable({
        opcode = opcode or 0x0001,
        version = 0x01,
        flags = 0x00,
        input_width = 0,
        output_width = 0,
        params = "",
        children = {},
    }, {__index = binary.builder})
end

function binary.builder:set_dimensions(input_width, output_width)
    self.input_width = input_width or 0
    self.output_width = output_width or 0
    return self
end

function binary.builder:set_params(params)
    self.params = params or ""
    return self
end

function binary.builder:add_child(child)
    table.insert(self.children, child)
    return self
end

function binary.builder:add_children(children)
    for _, child in ipairs(children) do
        table.insert(self.children, child)
    end
    return self
end

function binary.builder:build()
    local ast = {
        opcode = self.opcode,
        version = self.version,
        flags = self.flags,
        input_width = self.input_width,
        output_width = self.output_width,
        params = self.params,
        param_len = #self.params * 8,
        children = self.children,
        child_count = #self.children,
    }
    return ast
end

function binary.builder:serialize()
    return binary.serialize(self:build())
end

-- ============================================================================
-- NAND ISA SUPPORT
-- ============================================================================

binary.nand = {}

function binary.nand.decode_instruction(word)
    -- word is u16, decode per NAND format spec
    local op = (word >> 12) & 0xF
    local dst = (word >> 8) & 0xF
    local a = (word >> 4) & 0xF
    local b = word & 0xF

    local instr = {
        opcode = op,
        opcode_name = binary.NAND_OP_NAMES[op],
        dst = dst,
        a = a,
        b = b,
    }

    -- Decode based on opcode
    if op == binary.NAND_OPS.NAND then
        instr.type = "NAND"
        instr.dst = dst
        instr.a = a
        instr.b = b
    elseif op == binary.NAND_OPS.HALT then
        instr.type = "HALT"
    elseif op == binary.NAND_OPS.LOAD then
        instr.type = "LOAD"
        instr.dst = dst
        instr.a = a
        instr.imm = b
    elseif op == binary.NAND_OPS.STORE then
        instr.type = "STORE"
        instr.dst = dst
        instr.a = a
        instr.imm = b
    elseif op == binary.NAND_OPS.LDI then
        instr.type = "LDI"
        instr.dst = dst
        instr.imm = (a << 4) | b
    elseif op == binary.NAND_OPS.JMP then
        instr.type = "JMP"
        instr.a = a
    elseif op == binary.NAND_OPS.JZ then
        instr.type = "JZ"
        instr.dst = dst
        instr.a = a
    else
        instr.type = "INVALID"
    end

    return instr
end

function binary.nand.encode_instruction(instr)
    -- Encode instruction back to u16
    local op = instr.opcode or 0
    local dst = instr.dst or 0
    local a = instr.a or 0
    local b = instr.b or 0

    return ((op & 0xF) << 12) | ((dst & 0xF) << 8) | ((a & 0xF) << 4) | (b & 0xF)
end

function binary.nand.load_program(data)
    -- Load NAND binary program (sequence of u16 little-endian words)
    if type(data) ~= "string" or (#data % 2) ~= 0 then
        return nil, "INVALID_PROGRAM_FORMAT"
    end

    local program = {}
    for offset = 1, #data, 2 do
        local word, _ = unpack_u16_le(data, offset)
        local instr = binary.nand.decode_instruction(word)
        table.insert(program, instr)
    end

    return program
end

function binary.nand.save_program(program)
    -- Serialize NAND program to binary
    local data = ""
    for _, instr in ipairs(program) do
        local word = binary.nand.encode_instruction(instr)
        data = data .. pack_u16_le(word)
    end
    return data
end

-- ============================================================================
-- INTROSPECTION
-- ============================================================================

binary.introspect = {}

function binary.introspect.structure(ast)
    if not ast then return nil end

    return {
        opcode = ast.opcode,
        opcode_name = binary.OPCODE_NAMES[ast.opcode],
        version = ast.version,
        flags = ast.flags,
        input_width = ast.input_width,
        output_width = ast.output_width,
        param_len = ast.param_len or #(ast.params or "") * 8,
        param_bytes = #(ast.params or ""),
        child_count = ast.child_count or #(ast.children or {}),
        integrity = ast.integrity,
    }
end

function binary.introspect.type(ast)
    local structure = binary.introspect.structure(ast)
    if not structure then return "unknown" end

    if ast.child_count == 0 or #(ast.children or {}) == 0 then
        return "leaf"
    else
        return "composite"
    end
end

function binary.introspect.offset(ast, field_name)
    -- Calculate byte offset of field in serialized block
    local offsets = {
        opcode = 0,
        version = 2,
        flags = 3,
        input_width = 4,
        output_width = 8,
        param_len = 12,
        child_count = 16,
        reserved = 18,
        integrity = 24,
        params = 32,
    }
    return offsets[field_name]
end



function binary.introspect.opcode_info(opcode)
    return {
        code = opcode,
        name = binary.OPCODE_NAMES[opcode] or "UNKNOWN",
        is_valid = binary.OPCODE_NAMES[opcode] ~= nil,
    }
end


-- ============================================================================
-- QUERY & ANALYSIS
-- ============================================================================

binary.query = {}





-- ============================================================================
-- EXPORT
-- ============================================================================

require("metabinary_codec").install(binary)

return binary
