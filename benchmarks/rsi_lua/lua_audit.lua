-- Run from repository root: lua benchmarks/rsi_lua/lua_audit.lua
-- JSON lines; any failed assertion or benchmark makes the process fail.
package.path = "./lua/?.lua;" .. package.path
local function quote(s)
    return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
end
local function emit(row)
    local parts = {}
    for k,v in pairs(row) do
        parts[#parts+1] = quote(k) .. ':' .. (type(v) == 'number' and tostring(v) or quote(v))
    end
    print('{' .. table.concat(parts, ',') .. '}')
end
emit({kind='runtime', version=_VERSION})
local failures = 0
local function check(name, fn)
    local ok, err = pcall(fn)
    if not ok then failures = failures + 1 end
    emit({kind='check', name=name, status=ok and 'pass' or 'fail', detail=ok and '' or tostring(err)})
end
local function bench(name, fn, iterations)
    if arg[1] == '--check-only' then return end
    local ok, err = pcall(function()
        for i=1,100 do fn() end
        for sample=1,7 do
            collectgarbage('collect')
            local start = os.clock()
            for i=1,iterations do fn() end
            emit({kind='benchmark', name=name, sample=sample, iterations=iterations,
                  seconds=os.clock()-start, clock='os.clock CPU seconds', status='measured'})
        end
    end)
    if not ok then
        failures = failures + 1
        emit({kind='benchmark', name=name, status='failed', detail=tostring(err)})
    end
end
for _, name in ipairs({'metabinary', 'metabinary_complete'}) do
    local binary = require(name)
    local leaf = binary.structures.block_new(binary.OPCODES.IDENTITY, 8, 8)
    local function test(suffix, fn) check(name .. '.' .. suffix, fn) end
    test('header_size', function()
        assert(#binary.structures.header_pack(binary.structures.header_new()) == 32)
    end)
    test('builder_methods', function()
        assert(type(binary.builder.new(1).set_dimensions) == 'function', 'builder returns plain table without methods')
    end)
    test('leaf_roundtrip', function()
        local bytes = assert(binary.serialize(leaf))
        local restored, err, consumed = binary.deserialize(bytes)
        assert(restored, err)
        assert(consumed == #bytes, 'consumed count is not byte length')
    end)
    test('missing_params', function()
        assert(binary.serialize({opcode=1, input_width=8, output_width=8}))
    end)
    test('impure_flag', function()
        local bytes = assert(binary.serialize(leaf))
        local header = binary.structures.header_unpack(bytes)
        assert(header.flags & 4 == 0, 'numeric zero is truthy: pure bit set')
    end)
    test('truncated_input', function()
        for length=0,31 do
            local restored = binary.deserialize(string.rep('\0', length))
            assert(restored == nil)
        end
    end)
    test('nand_all_words_roundtrip', function()
        for word=0,65535 do
            assert(binary.nand.encode_instruction(binary.nand.decode_instruction(word)) == word)
        end
        assert(binary.nand.load_program('x') == nil)
    end)
    test('consumed_bytes', function()
        local bytes = assert(binary.serialize(leaf))
        local restored, err, consumed = binary.deserialize(bytes .. '\0\0\0\0')
        assert(restored, err)
        assert(consumed == #bytes, 'consumed count must exclude trailing stream bytes')
    end)
    test('tampered_integrity_rejected', function()
        local bytes = assert(binary.serialize(leaf))
        bytes = bytes:sub(1,24) .. string.char(bytes:byte(25) ~ 1) .. bytes:sub(26)
        assert(not binary.validate(bytes), 'validate accepts changed integrity')
    end)
    test('two_children_roundtrip', function()
        local ast = binary.structures.block_new(binary.OPCODES.COMPOSE, 8, 8)
        ast.children = {leaf, leaf}
        local restored, err = binary.deserialize(assert(binary.serialize(ast)))
        assert(restored, err)
        assert(#restored.children == 2)
    end)
    test('nested_sibling_roundtrip', function()
        local inner = binary.builder.new(binary.OPCODES.COMPOSE):set_dimensions(8,8):add_children({leaf,leaf}):build()
        local outer = binary.builder.new(binary.OPCODES.COMPOSE):set_dimensions(8,8):add_children({inner,leaf,inner}):build()
        local bytes = assert(binary.serialize(outer))
        local restored, err, consumed = binary.deserialize(bytes)
        assert(restored, err)
        assert(consumed == #bytes and #restored.children == 3 and #restored.children[3].children == 2)
        assert(binary.validate(bytes))
        assert(binary.introspect.size(outer) == #bytes)
        assert(binary.serialize(restored) == bytes)
    end)
    test('trailing_data_rejected_by_validate', function()
        assert(not binary.validate(assert(binary.serialize(leaf)) .. '\0'))
    end)
    test('cycles_and_invalid_fields_rejected', function()
        local ast = binary.structures.block_new(binary.OPCODES.COMPOSE,8,8)
        ast.children = {ast}
        assert(binary.serialize(ast) == nil)
        assert(not pcall(binary.query.node_count, ast))
        assert(binary.serialize({opcode=1,input_width=-1,output_width=8}) == nil)
        assert(binary.serialize({opcode=1,input_width=0.5,output_width=8}) == nil)
        assert(binary.serialize({opcode=1,input_width=8,output_width=8,params='x'}) == nil)
    end)
    test('checksum_covers_header_params_and_children', function()
        local parameterized = binary.builder.new(binary.OPCODES.ADD_PLAIN):set_dimensions(8,8):set_params('abc'):build()
        local bytes = assert(binary.serialize(parameterized))
        for i=1,#bytes do
            local changed = bytes:sub(1,i-1) .. string.char(bytes:byte(i) ~ 1) .. bytes:sub(i+1)
            assert(not binary.validate(changed), 'undetected mutation at byte ' .. i)
        end
    end)
    bench(name .. '.header_pack_only', function()
        assert(#binary.structures.header_pack(binary.structures.header_new()) == 32)
    end, 10000)
    bench(name .. '.validated_leaf_roundtrip', function()
        local bytes = assert(binary.serialize(leaf))
        local restored, err, consumed = binary.deserialize(bytes)
        assert(restored, err)
        assert(consumed == #bytes and restored.opcode == leaf.opcode)
        assert(binary.validate(bytes))
    end, 10000)
    bench(name .. '.nand_decode_256_words', function()
        for i=0,255 do assert(binary.nand.decode_instruction(i)) end
    end, 1000)
    bench(name .. '.query_leaf', function() assert(binary.query.node_count(leaf) == 1) end, 100000)
end
check('facade.serialize_returns_bytes', function()
    local facade = require('metabinary_builder_facade')
    local result = facade.Builder.new(1):set_dimensions(8,8):serialize()
    assert(type(result) == 'string', 'serialize returns an AST table')
end)
check('facade.factories_and_pure_flag', function()
    local facade = require('metabinary_builder_facade')
    local binary = require('metabinary')
    local leaf = facade.Builder.new(1):set_dimensions(8,8):with_pure_flag(true):build()
    assert(leaf.flags & 4 ~= 0)
    local ast = facade.factory.conditional(leaf,leaf,leaf,8,8):build()
    assert(binary.validate(assert(binary.serialize(ast))))
    local encoded = facade.factory.encode(32,1,8):build()
    assert(#encoded.params == 11 and binary.validate(assert(binary.serialize(encoded))))
    assert(facade.factory.relinearization(0x1234,8,8):build().params == '\x34\x12')
    assert(facade.factory.iterate(leaf,0x12345678,8,8):build().params == '\x78\x56\x34\x12')
end)
check('ffi.header_layout', function()
    require('metabinary_ffi_bindings')
    local ffi = require('ffi')
    assert(ffi.sizeof('struct block_header') == 32)
    assert(ffi.offsetof('struct block_header', 'integrity') == 24)
end)
check('ffi.platform_defaults', function()
    local bindings, ffi = require('metabinary_ffi_bindings'), require('ffi')
    local original, attempted = ffi.load, {}
    ffi.load = function(path) attempted[#attempted+1] = path; error('test library unavailable') end
    local ok, err = pcall(function()
        for _,name in ipairs({'c','rust','go'}) do assert(bindings[name].load() == nil) end
    end)
    ffi.load = original
    assert(ok, err)
    local suffix = ffi.os == 'Windows' and '.dll' or (ffi.os == 'OSX' and '.dylib' or '.so')
    assert(#attempted == 3)
    for _,path in ipairs(attempted) do assert(path:sub(-#suffix) == suffix) end
end)
check('ffi.null_error_pointer', function()
    local c = require('metabinary_ffi_bindings').c
    local old_lib, old_available = c.lib, c.available
    c.lib, c.available = {c_serialize_block=function() return nil end,
        c_deserialize_block=function() return nil end,
        c_free=function() error('must not free null error pointer') end}, true
    local ok, err = pcall(function()
        local bytes, message = c.serialize(nil)
        assert(bytes == nil and message == 'Unknown error')
        local block, message2 = c.deserialize('', 0)
        assert(block == nil and message2 == 'Unknown error')
    end)
    c.lib, c.available = old_lib, old_available
    assert(ok, err)
end)
check('final_assembly.native_rejection_propagates', function()
    local assembly, bindings = require('metabinary_final_assembly'), require('metabinary_ffi_bindings')
    local original = bindings.rust.validate
    bindings.rust.validate = function() return {status=1} end
    local ok, err = pcall(function()
        local leaf = require('metabinary').structures.block_new(1,8,8)
        local bytes, message = assembly.serialization.serialize(leaf, 'rust')
        assert(bytes == nil and message:find('status 1', 1, true))
        assert(assembly.serialization.serialize(leaf, 'lua'))
    end)
    bindings.rust.validate = original
    assert(ok, err)
end)
check('final_assembly_load', function() require('metabinary_final_assembly') end)
check('examples_syntax', function()
    local chunk, err = loadfile('lua/example_usage_all_backends.lua')
    assert(chunk, err)
end)
os.exit(failures == 0 and 0 or 1)
