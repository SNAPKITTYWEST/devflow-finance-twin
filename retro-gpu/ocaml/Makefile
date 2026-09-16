# RetroGPU Build System

OCAMLOPT=ocamlopt
OCAMLFIND=ocamlfind
OCAMLFLAGS=-w A-4 -g -thread -package unix

# Directories
SRC_DIR=src
TEST_DIR=tests
BUILD_DIR=_build

# Targets
TYPES=$(SRC_DIR)/types/RetroGPUTypes.ml
REGISTERS=$(SRC_DIR)/registers/Registers.ml
ALU=$(SRC_DIR)/alu/ALU.ml
WARP=$(SRC_DIR)/warp/Warp.ml
COMPILER=$(SRC_DIR)/compiler/RetroCompiler.ml
INTERPRETER=$(SRC_DIR)/interpreter/Interpreter.ml

all: build test

build: $(BUILD_DIR)/retro_gpu.native

$(BUILD_DIR)/%.cmx: $(SRC_DIR)/%.ml
	$(OCAMLFIND) $(OCAMLOPT) $(OCAMLFLAGS) -c $< -o $@

$(BUILD_DIR)/retro_gpu.native: $(TYPES) $(REGISTERS) $(ALU) $(WARP) $(COMPILER) $(INTERPRETER)
	mkdir -p $(BUILD_DIR)
	$(OCAMLFIND) $(OCAMLOPT) $(OCAMLFLAGS) -linkpkg \
		$(TYPES) $(REGISTERS) $(ALU) $(WARP) $(COMPILER) $(INTERPRETER) \
		-o $(BUILD_DIR)/retro_gpu.native

test: build
	$(OCAMLFIND) $(OCAMLOPT) $(OCAMLFLAGS) -linkpkg \
		$(TYPES) $(REGISTERS) \
		$(TEST_DIR)/test_registers.ml \
		-o $(BUILD_DIR)/test_registers.native
	./$(BUILD_DIR)/test_registers.native
	$(OCAMLFIND) $(OCAMLOPT) $(OCAMLFLAGS) -linkpkg \
		$(TYPES) $(REGISTERS) $(ALU) $(WARP) $(COMPILER) $(INTERPRETER) \
		$(TEST_DIR)/test_full_pipeline.ml \
		-o $(BUILD_DIR)/test_pipeline.native
	./$(BUILD_DIR)/test_pipeline.native

clean:
	rm -rf $(BUILD_DIR) *.cmx *.cmxa *.cmi *.o

.PHONY: all build test clean
