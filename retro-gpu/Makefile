OCCAMC = occamc
OCCAMFLAGS = -v

SOURCES = \
  RetroGPUTypes.occ \
  Registers.occ \
  ALU.occ \
  Warp.occ \
  SharedMemory.occ \
  GlobalMemory.occ \
  Synchronization.occ \
  Tensor.occ \
  RetroGPUCompiler.occ

EXAMPLES = \
  examples/GemmKernel.occ

TESTS = \
  tests/CompilerTests.occ

.PHONY: all clean test build

all: build

build:
	$(OCCAMC) $(OCCAMFLAGS) -o retro-gpu $(SOURCES) RetroGPUCompiler.occ

test: build
	$(OCCAMC) $(OCCAMFLAGS) -o test-retro-gpu $(SOURCES) $(TESTS)
	./test-retro-gpu

clean:
	rm -f retro-gpu test-retro-gpu *.o *.tce

.PHONY: all clean test build
