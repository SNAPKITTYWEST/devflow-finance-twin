-- Shared Lua 5.3+ codec. The checksum is deterministic error detection, NOT BLAKE3.
-- Header offsets follow HE-BINARY-FUNCTOR-SPEC-001: integrity at 24, body at 32.
local codec = {}
local FORMAT = '<I2I1I1I4I4I4I2I2xxxxi8'
local MAX_DEPTH, MAX_NODES, MAX_BYTES = 128, 10000, 64 * 1024 * 1024

local function checksum64(data)
    local value = 0x0123456789ABCDEF
    for i=1,#data do value = value * 31 + data:byte(i) end
    return value
end

local function integer(value, maximum, name)
    if type(value) ~= 'number' or math.tointeger(value) == nil or value < 0 or value > maximum then
        error('INVALID_' .. name, 0)
    end
end

function codec.install(binary)
    binary.integrity_algorithm = 'polynomial64-prototype-not-cryptographic'
    binary.limits = {max_depth=MAX_DEPTH, max_nodes=MAX_NODES, max_bytes=MAX_BYTES}

    function binary.structures.header_pack(h)
        integer(h.opcode, 0xFFFF, 'OPCODE')
        integer(h.version, 0xFF, 'VERSION')
        integer(h.flags, 0xFF, 'FLAGS')
        integer(h.input_width, 0xFFFFFFFF, 'INPUT_WIDTH')
        integer(h.output_width, 0xFFFFFFFF, 'OUTPUT_WIDTH')
        integer(h.param_len, 0xFFFFFFFF, 'PARAM_LEN')
        integer(h.child_count, 0xFFFF, 'CHILD_COUNT')
        integer(h.reserved, 0xFFFF, 'RESERVED')
        return string.pack(FORMAT, h.opcode, h.version, h.flags, h.input_width,
            h.output_width, h.param_len, h.child_count, h.reserved, h.integrity)
    end

    function binary.structures.header_unpack(data, offset)
        offset = offset or 1
        if type(data) ~= 'string' or #data-offset+1 < 32 then error('INSUFFICIENT_DATA', 0) end
        if data:sub(offset+20, offset+23) ~= '\0\0\0\0' then error('NONZERO_HEADER_PADDING', 0) end
        local h = {}
        h.opcode, h.version, h.flags, h.input_width, h.output_width, h.param_len,
            h.child_count, h.reserved, h.integrity, offset = string.unpack(FORMAT, data, offset)
        return h, offset
    end

    local function validate_header(h)
        if h.reserved ~= 0 then error('NONZERO_RESERVED', 0) end
        local valid, msg = binary.predicates.valid_header(h)
        if not valid then error(msg, 0) end
        if not binary.predicates.valid_opcode(h.opcode) then error('INVALID_OPCODE', 0) end
        valid, msg = binary.predicates.width_valid(h.input_width, h.output_width)
        if not valid then error(msg, 0) end
        valid, msg = binary.predicates.param_len_matches_opcode(h.opcode, h.param_len)
        if not valid then error(msg, 0) end
        valid, msg = binary.predicates.child_arity_matches_opcode(h.opcode, h.child_count)
        if not valid then error(msg, 0) end
        valid, msg = binary.predicates.flags_consistency(h.flags, h.child_count)
        if not valid then error(msg, 0) end
    end

    function binary.predicates.verify_integrity(header, params, children_bytes)
        local zeroed = {}
        for k,v in pairs(header) do zeroed[k] = v end
        zeroed.integrity = 0
        local computed = checksum64(binary.structures.header_pack(zeroed) .. params .. children_bytes)
        return header.integrity == computed, 'INTEGRITY_MISMATCH'
    end

    local function encode(ast, context, depth)
        if type(ast) ~= 'table' then error('INVALID_AST', 0) end
        if context.active[ast] then error('CYCLIC_AST', 0) end
        context.nodes = context.nodes + 1
        if depth > MAX_DEPTH or context.nodes > MAX_NODES then error('TREE_LIMIT', 0) end
        context.active[ast] = true
        local params, children = ast.params or '', ast.children or {}
        if type(params) ~= 'string' or type(children) ~= 'table' then error('INVALID_AST_FIELDS', 0) end
        for key in pairs(children) do
            if type(key) ~= 'number' or math.tointeger(key) == nil or key < 1 or key > #children then
                error('INVALID_CHILD_ARRAY', 0)
            end
        end
        context.bytes = context.bytes + 32 + #params
        if context.bytes > MAX_BYTES then error('BYTE_LIMIT', 0) end
        local h = binary.structures.header_new()
        h.opcode, h.version = ast.opcode, ast.version or 1
        h.input_width, h.output_width = ast.input_width or 0, ast.output_width or 0
        h.param_len, h.child_count = #params*8, #children
        integer(ast.flags or 0, 7, 'FLAGS')
        binary.structures.block_set_flags(h, #children > 0, #children == 0, ((ast.flags or 0) & 4) ~= 0)
        -- Packing checks integer ranges before predicate arithmetic.
        local header_bytes = binary.structures.header_pack(h)
        validate_header(h)
        local pieces = {}
        for i=1,#children do pieces[i] = encode(children[i], context, depth+1) end
        local child_bytes = table.concat(pieces)
        h.integrity = checksum64(header_bytes .. params .. child_bytes)
        context.active[ast] = nil
        return binary.structures.header_pack(h) .. params .. child_bytes
    end

    function binary.serialize(ast)
        local ok, result = pcall(encode, ast, {nodes=0, bytes=0, active={}}, 1)
        if not ok then return nil, result end
        return result
    end

    local function decode(data, offset, context, depth)
        context.nodes = context.nodes + 1
        if depth > MAX_DEPTH or context.nodes > MAX_NODES then error('TREE_LIMIT', 0) end
        local h, next_offset = binary.structures.header_unpack(data, offset)
        validate_header(h)
        local param_bytes = math.ceil(h.param_len/8)
        if next_offset+param_bytes-1 > #data then error('INSUFFICIENT_DATA_FOR_PARAMS', 0) end
        local params = data:sub(next_offset, next_offset+param_bytes-1)
        next_offset = next_offset+param_bytes
        local children_start, children = next_offset, {}
        for i=1,h.child_count do children[i], next_offset = decode(data, next_offset, context, depth+1) end
        local valid, msg = binary.predicates.verify_integrity(h, params, data:sub(children_start, next_offset-1))
        if not valid then error(msg, 0) end
        h.params, h.children = params, children
        return h, next_offset
    end

    function binary.deserialize(data)
        if type(data) ~= 'string' or #data < 32 then return nil, 'INSUFFICIENT_DATA' end
        if #data > MAX_BYTES then return nil, 'BYTE_LIMIT' end
        local ok, ast, next_offset = pcall(decode, data, 1, {nodes=0}, 1)
        if not ok then return nil, ast end
        -- Stream API: trailing bytes are allowed; this is a byte count, not an offset.
        return ast, nil, next_offset-1
    end

    function binary.validate(data)
        local ast, err, consumed = binary.deserialize(data)
        if not ast then return false, err, nil end
        if consumed ~= #data then return false, 'TRAILING_DATA', ast end
        return true, 'OK', ast
    end

    function binary.introspect.size(ast)
        local bytes, err = binary.serialize(ast)
        if not bytes then return nil, err end
        return #bytes
    end

    function binary.introspect.hash(ast)
        local bytes, err = binary.serialize(ast)
        if not bytes then return nil, err end
        return checksum64(bytes)
    end

    local function walk(ast, visit)
        local active, count = {}, 0
        local function traverse(node, depth)
            if type(node) ~= 'table' then error('INVALID_AST', 0) end
            if active[node] then error('CYCLIC_AST', 0) end
            count = count + 1
            if depth > MAX_DEPTH or count > MAX_NODES then error('TREE_LIMIT', 0) end
            active[node] = true
            visit(node, depth)
            for _,child in ipairs(node.children or {}) do traverse(child, depth+1) end
            active[node] = nil
        end
        traverse(ast, 1)
    end

    function binary.query.node_count(ast)
        local count = 0
        walk(ast, function() count = count+1 end)
        return count
    end
    function binary.query.leaf_count(ast)
        local count = 0
        walk(ast, function(node) if #(node.children or {}) == 0 then count = count+1 end end)
        return count
    end
    function binary.query.depth(ast)
        local maximum = 0
        walk(ast, function(_, depth) maximum = math.max(maximum, depth) end)
        return maximum
    end
    function binary.query.find_all_opcodes(ast, opcode)
        local found = {}
        walk(ast, function(node) if node.opcode == opcode then found[#found+1] = node end end)
        return found
    end
    function binary.query.collect_opcodes(ast)
        local seen, found = {}, {}
        walk(ast, function(node)
            if not seen[node.opcode] then
                seen[node.opcode] = true
                found[#found+1] = binary.introspect.opcode_info(node.opcode)
            end
        end)
        return found
    end
    function binary.introspect.tree(ast, initial_depth)
        local lines = {}
        walk(ast, function(node, depth)
            local info = binary.introspect.structure(node)
            lines[#lines+1] = string.format('%s[%s] in=%d out=%d children=%d',
                string.rep('  ', (initial_depth or 0)+depth-1), info.opcode_name or 'UNKNOWN',
                info.input_width, info.output_width, info.child_count)
        end)
        return lines
    end
end

return codec
