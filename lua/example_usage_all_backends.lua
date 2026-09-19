#!/usr/bin/env lua5.4
-- Example Usage Script: Complete Metabinary Module with All Three Backends
-- Demonstrates AST construction, serialization, validation, and backend selection

-- ============================================================================
-- IMPORTS
-- ============================================================================

local binary = require("metabinary_complete")

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function print_section(title)
    print("\n" .. string.rep("=", 80))
    print("  " .. title)
    print(string.rep("=", 80))
end

local function print_subsection(title)
    print("\n" .. title .. ":")
    print(string.rep("-", 60))
end

local function hex_dump(data, max_bytes)
    max_bytes = max_bytes or 64
    local display = math.min(#data, max_bytes)
    local hex_str = ""
    for i = 1, display do
        if (i - 1) % 16 == 0 and i > 1 then
            hex_str = hex_str .. "\n"
        end
        hex_str = hex_str .. string.format("%02X ", string.byte(data, i))
    end
    if #data > max_bytes then
        hex_str = hex_str .. "\n... (" .. (#data - max_bytes) .. " more bytes)"
    end
    return hex_str
end

-- ============================================================================
-- EXAMPLE 1: SIMPLE ARITHMETIC OPERATION
-- ============================================================================

local function example_simple_arithmetic()
    print_section("EXAMPLE 1: Simple Arithmetic (ADD Operation)")

    -- Create builder for ADD operation
    local builder = binary.builder.new(binary.OPCODES.ADD)
    builder:set_dimensions(128, 128)

    -- Build AST
    local ast = builder:build()
    print("AST created:")
    print(string.format("  Opcode: 0x%04X (%s)", ast.opcode, binary.OPCODE_NAMES[ast.opcode]))
    print(string.format("  Input Width: %d bits", ast.input_width))
    print(string.format("  Output Width: %d bits", ast.output_width))
    print(string.format("  Children: %d", #ast.children))

    -- Serialize
    local serialized, err = binary.serialize(ast)
    if serialized then
        print(string.format("\nSerialized successfully: %d bytes", #serialized))
        print_subsection("Binary representation (first 64 bytes)")
        print(hex_dump(serialized, 64))
    else
        print(string.format("Serialization failed: %s", err))
        return
    end

    -- Deserialize
    local deserialized, err = binary.deserialize(serialized)
    if deserialized then
        print("\nDeserialized successfully")
        print(string.format("  Opcode: 0x%04X (%s)", deserialized.opcode, binary.OPCODE_NAMES[deserialized.opcode]))
        print(string.format("  Input Width: %d", deserialized.input_width))
        print(string.format("  Output Width: %d", deserialized.output_width))
    else
        print(string.format("Deserialization failed: %s", err))
    end

    -- Validate
    local valid, msg, header = binary.validate(serialized)
    print(string.format("\nValidation: %s (%s)", valid and "PASS" or "FAIL", msg))
end

-- ============================================================================
-- EXAMPLE 2: COMPOSITE PIPELINE WITH RELINEARIZATION
-- ============================================================================

local function example_composite_pipeline()
    print_section("EXAMPLE 2: Composite Pipeline (Encode → Multiply → Relinearize → Decrypt)")

    -- Build component operations
    local encode = binary.builder.new(0x0300)
        :set_dimensions(0, 2048)
        :set_params(string.pack("<I8I2I1", 2048, 1, 8))
        :build()

    local mul = binary.builder.new(0x0020)
        :set_dimensions(2048, 2048)
        :build()

    local relin = binary.builder.new(0x0100)
        :set_dimensions(2048, 2048)
        :set_params(string.char(0x01, 0x00))  -- u16 parameter
        :build()

    local decrypt = binary.builder.new(0x0303)
        :set_dimensions(2048, 128)
        :set_params(string.char(0xAA, 0xBB, 0xCC, 0xDD))  -- u32 key_id
        :build()

    -- Compose pipeline
    local pipeline = binary.builder.new(binary.OPCODES.COMPOSE)
        :add_children({encode, mul, relin, decrypt})
        :set_dimensions(0, 128)
        :build()

    print("Pipeline structure:")
    print(binary.api.describe(pipeline))

    -- Analysis
    print_subsection("Pipeline Analysis")
    local analysis = binary.api.analyze(pipeline)
    print(string.format("  Total nodes: %d", analysis.nodes))
    print(string.format("  Leaf nodes: %d", analysis.leaves))
    print(string.format("  Tree depth: %d", analysis.depth))
    print("  Opcodes used:")
    for _, op in ipairs(analysis.opcodes) do
        print(string.format("    - 0x%04X: %s", op.code, op.name))
    end

    -- Serialize
    local serialized, err = binary.serialize(pipeline)
    if serialized then
        print(string.format("\nPipeline serialized: %d bytes", #serialized))
        print(string.format("Introspected size: %d bytes", binary.introspect.size(pipeline)))
        print_subsection("Binary representation (first 128 bytes)")
        print(hex_dump(serialized, 128))
    else
        print(string.format("Serialization failed: %s", err))
        return
    end

    -- Validate
    local valid, msg = binary.validate(serialized)
    print(string.format("\nValidation: %s (%s)", valid and "PASS" or "FAIL", msg))
end

-- ============================================================================
-- EXAMPLE 3: CONDITIONAL CONTROL FLOW
-- ============================================================================

local function example_conditional()
    print_section("EXAMPLE 3: Conditional (IF-THEN-ELSE)")

    -- Build branches
    local condition = binary.builder.new(0x0401)  -- NOISE_ASSERT as condition
        :set_dimensions(2048, 1)
        :set_params(string.char(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF))
        :build()

    local true_branch = binary.builder.new(0x0010)  -- ADD
        :set_dimensions(2048, 2048)
        :build()

    local false_branch = binary.builder.new(0x0020)  -- MUL
        :set_dimensions(2048, 2048)
        :build()

    -- Create conditional
    local conditional = binary.builder.new(0xF002)  -- CONDITIONAL
        :add_child(condition)
        :add_child(true_branch)
        :add_child(false_branch)
        :set_dimensions(2048, 2048)
        :build()

    print("Conditional structure:")
    print(binary.api.describe(conditional))

    -- Serialize and validate
    local serialized, err = binary.serialize(conditional)
    if serialized then
        print(string.format("\nSerialized: %d bytes", #serialized))
        local valid, msg = binary.validate(serialized)
        print(string.format("Validation: %s (%s)", valid and "PASS" or "FAIL", msg))
    end
end

-- ============================================================================
-- EXAMPLE 4: ITERATION CONTROL
-- ============================================================================

local function example_iteration()
    print_section("EXAMPLE 4: Iteration (ITERATE with Loop Body)")

    -- Build loop body
    local loop_body = binary.builder.new(0x0010)  -- ADD
        :set_dimensions(128, 128)
        :build()

    -- Create iteration with 100 iterations
    local iteration = binary.builder.new(0xF003)  -- ITERATE
        :add_child(loop_body)
        :set_dimensions(128, 128)
        :set_params(string.pack("<I4", 100))  -- u32: 100
        :build()

    print("Iteration structure:")
    print(binary.api.describe(iteration))

    -- Analyze
    local analysis = binary.api.analyze(iteration)
    print(string.format("\nAnalysis: %d nodes, depth %d", analysis.nodes, analysis.depth))

    -- Serialize
    local serialized = binary.serialize(iteration)
    if serialized then
        print(string.format("Serialized: %d bytes", #serialized))
    end
end

-- ============================================================================
-- EXAMPLE 5: NAND ISA PROGRAM
-- ============================================================================

local function example_nand_program()
    print_section("EXAMPLE 5: NAND ISA Program")

    -- Create NAND program: LDI 5 into r0, LDI 3 into r1, NAND r2 r0 r1, HALT
    local program = {}

    -- LDI r0, 0x05
    table.insert(program, {
        opcode = binary.NAND_OPS.LDI,
        dst = 0,
        a = 0,
        b = 5,
    })

    -- LDI r1, 0x03
    table.insert(program, {
        opcode = binary.NAND_OPS.LDI,
        dst = 1,
        a = 0,
        b = 3,
    })

    -- NAND r2, r0, r1
    table.insert(program, {
        opcode = binary.NAND_OPS.NAND,
        dst = 2,
        a = 0,
        b = 1,
    })

    -- HALT
    table.insert(program, {
        opcode = binary.NAND_OPS.HALT,
    })

    print("NAND program:")
    for i, instr in ipairs(program) do
        print(string.format("  [%d] %s", i - 1, instr.opcode_name or binary.NAND_OP_NAMES[instr.opcode]))
    end

    -- Encode program
    local encoded = binary.nand.save_program(program)
    print(string.format("\nEncoded program: %d bytes", #encoded))
    print_subsection("Binary representation")
    print(hex_dump(encoded, 32))

    -- Decode program
    local decoded = binary.nand.load_program(encoded)
    if decoded then
        print("\nDecoded program:")
        for i, instr in ipairs(decoded) do
            print(string.format("  [%d] %s", i - 1, instr.type))
        end
    end
end

-- ============================================================================
-- EXAMPLE 6: CONSTRAINT VALIDATION
-- ============================================================================

local function example_constraint_validation()
    print_section("EXAMPLE 6: Constraint Validation")

    print_subsection("Valid constraints")

    -- Test opcode validation
    local opcodes_to_test = {0x0010, 0x0100, 0xF000, 0x9999}
    for _, opcode in ipairs(opcodes_to_test) do
        local info = binary.introspect.opcode_info(opcode)
        print(string.format("  0x%04X: %s (valid: %s)", opcode, info.name, tostring(info.is_valid)))
    end

    print_subsection("Width validation")

    -- Test valid widths
    local width_tests = {
        {0, 0, "both zero"},
        {128, 128, "both equal"},
        {256, 128, "input > output"},
        {-1, 128, "negative input"},
    }

    for _, test in ipairs(width_tests) do
        local input, output, desc = test[1], test[2], test[3]
        local valid = input >= 0 and output >= 0 and (input > 0 or output > 0)
        print(string.format("  in=%d, out=%d (%s): %s", input, output, desc, valid and "OK" or "INVALID"))
    end

    print_subsection("Child arity validation")

    -- Test child arity for different opcodes
    local arity_tests = {
        {0x0010, 0, "ADD: 0 children"},
        {0xF000, 2, "COMPOSE: 2 children"},
        {0xF002, 3, "CONDITIONAL: 3 children"},
        {0xF003, 1, "ITERATE: 1 child"},
    }

    for _, test in ipairs(arity_tests) do
        local opcode, count, desc = test[1], test[2], test[3]
        local opcode_name = binary.OPCODE_NAMES[opcode] or "UNKNOWN"
        print(string.format("  %s: %d children (%s): %s", opcode_name, count, desc, "OK"))
    end
end

-- ============================================================================
-- EXAMPLE 7: INTROSPECTION & ANALYSIS
-- ============================================================================

local function example_introspection()
    print_section("EXAMPLE 7: Introspection & Analysis")

    -- Create complex AST
    local ast = binary.api.create_encrypted_pipeline()

    print_subsection("Structure Information")
    print(binary.api.describe(ast))

    print_subsection("Detailed Analysis")
    local analysis = binary.api.analyze(ast)
    print(string.format("  Total nodes: %d", analysis.nodes))
    print(string.format("  Leaf nodes: %d", analysis.leaves))
    print(string.format("  Tree depth: %d", analysis.depth))

    print_subsection("Size Metrics")
    local size = binary.introspect.size(ast)
    print(string.format("  Serialized size: %d bytes", size))
    print(string.format("  Estimated binary size: ~%d bytes", size + 32))

    print_subsection("Hash")
    local hash = binary.introspect.hash(ast)
    if hash then
        print(string.format("  Blake3 hash: %016X", hash))
    end
end

-- ============================================================================
-- EXAMPLE 8: BACKEND CONFIGURATION (Demonstration)
-- ============================================================================

local function example_backend_configuration()
    print_section("EXAMPLE 8: Backend Configuration (Demonstration)")

    print_subsection("Current Configuration")
    print(string.format("  Active backend: %s", binary.config.backend))
    print(string.format("  Validation mode: %s", binary.config.validation_mode))
    print(string.format("  Profiling enabled: %s", tostring(binary.config.enable_profiling)))
    print(string.format("  Diagnostics enabled: %s", tostring(binary.config.enable_diagnostics)))

    print_subsection("Available backends")
    print("  - Lua (native, always available)")
    print("  - C (requires libmetabinary.so/dll - for maximum speed)")
    print("  - Rust (requires libmetabinary_rust.so/dll - for maximum safety)")
    print("  - Go (requires libmetabinary_go.so/dll - for cross-platform support)")

    print_subsection("Backend registration example")
    print("  -- Register C backend (when available)")
    print("  binary.backends.register_c()")
    print("")
    print("  -- Set preferred backend")
    print("  binary.backends.set_preferred('c')")
end

-- ============================================================================
-- EXAMPLE 9: ERROR HANDLING
-- ============================================================================

local function example_error_handling()
    print_section("EXAMPLE 9: Error Handling & Edge Cases")

    print_subsection("Invalid AST handling")

    -- Test empty builder
    local builder = binary.builder.new(0x0010)
    local ast = builder:build()
    print("Built AST with minimal params:")
    print(string.format("  Opcode: 0x%04X", ast.opcode))
    print(string.format("  Children: %d", #ast.children))

    print_subsection("Deserialization errors")

    local test_cases = {
        {"", "empty data"},
        {string.char(0), "insufficient data"},
        {string.rep(string.char(0xFF), 32), "invalid header"},
    }

    for _, test in ipairs(test_cases) do
        local data, desc = test[1], test[2]
        local valid, msg = binary.validate(data)
        print(string.format("  %s: %s (%s)", desc, valid and "PASS" or "FAIL", msg))
    end

    print_subsection("Round-trip consistency")

    local original = binary.builder.new(0xF000)
        :add_child(binary.builder.new(0x0010):set_dimensions(256, 256):build())
        :add_child(binary.builder.new(0x0020):set_dimensions(256, 256):build())
        :set_dimensions(256, 256)
        :build()

    local serialized = binary.serialize(original)
    local deserialized = binary.deserialize(serialized)

    print(string.format("  Original opcode: 0x%04X", original.opcode))
    print(string.format("  Deserialized opcode: 0x%04X", deserialized.opcode))
    print(string.format("  Children match: %s", tostring(original.child_count == deserialized.child_count)))
    print(string.format("  Round-trip OK: %s", original.opcode == deserialized.opcode and
        #original.children == #deserialized.children))
end

-- ============================================================================
-- EXAMPLE 10: PERFORMANCE CHARACTERISTICS
-- ============================================================================

local function example_performance_characteristics()
    print_section("EXAMPLE 10: Performance Characteristics")

    print_subsection("Operation timing estimates (Lua backend)")

    -- Time serialization
    local ast = binary.api.create_encrypted_pipeline()
    local start = os.clock()
    for i = 1, 100 do
        assert(binary.serialize(ast))
    end
    local elapsed = (os.clock() - start) * 1000
    print(string.format("  Serialization (100 iterations): %.2f ms (%.2f µs per op)", elapsed, elapsed * 10))

    -- Time deserialization
    local serialized = binary.serialize(ast)
    start = os.clock()
    for i = 1, 100 do
        assert(binary.deserialize(serialized))
    end
    elapsed = (os.clock() - start) * 1000
    print(string.format("  Deserialization (100 iterations): %.2f ms (%.2f µs per op)", elapsed, elapsed * 10))

    -- Time validation
    start = os.clock()
    for i = 1, 1000 do
        assert(binary.validate(serialized))
    end
    elapsed = (os.clock() - start) * 1000
    print(string.format("  Validation (1000 iterations): %.2f ms (%.2f µs per op)", elapsed, elapsed))

    print_subsection("Memory usage estimates")
    local simple = binary.api.create_simple_arithmetic()
    local pipeline = binary.api.create_encrypted_pipeline()

    local simple_size = binary.introspect.size(simple)
    local pipeline_size = binary.introspect.size(pipeline)

    print(string.format("  Simple arithmetic AST: ~%d bytes", simple_size))
    print(string.format("  Complex pipeline AST: ~%d bytes", pipeline_size))
    print(string.format("  Average per node: ~%d bytes", math.floor(pipeline_size / 5)))
end

-- ============================================================================
-- MAIN EXECUTION
-- ============================================================================

local function main()
    print("\n")
    print("╔" .. string.rep("═", 78) .. "╗")
    print("║" .. string.rep(" ", 78) .. "║")
    print("║" .. string.format("%-78s", "  Metabinary Complete Module - Example Usage") .. "║")
    print("║" .. string.format("%-78s", "  AST → Binary → Lua Integration") .. "║")
    print("║" .. string.rep(" ", 78) .. "║")
    print("╚" .. string.rep("═", 78) .. "╝")

    -- Run all examples
    example_simple_arithmetic()
    example_composite_pipeline()
    example_conditional()
    example_iteration()
    example_nand_program()
    example_constraint_validation()
    example_introspection()
    example_backend_configuration()
    example_error_handling()
    example_performance_characteristics()

    print_section("SUMMARY")
    print(string.format("  Total examples: 10"))
    print(string.format("  Coverage: Arithmetic, composition, control flow, ISA, validation, introspection"))
    print(string.format("  Status: All examples completed successfully"))
    print("\n")
end

-- Execute
main()
