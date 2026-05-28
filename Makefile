# Standalone Makefile -- build without Zig
# Usage: make          (build)
#        make run      (build and run with default input)
#        make test     (run basic tests)
#        make clean    (remove artifacts)

CC      ?= cc
LEX     ?= flex
YACC    ?= bison
CFLAGS  := -std=c23 -Wall -Wextra -Wpedantic -D_GNU_SOURCE -O2
# Generated flex/bison sources tend to emit code that trips strict
# warnings; relax just for them.
GEN_CFLAGS := -std=c23 -D_GNU_SOURCE -O2 -Wno-unused-function -Wno-unused-but-set-variable
LDFLAGS := -lm

# Hand-written sources.
SRC     := src/tomasulo.c src/parser.c src/display.c src/main.c
OBJ     := $(SRC:.c=.o)

# Generated sources (created by flex/bison from parser.l / parser.y).
# GNU make has implicit rules for .l -> .yy.c via $(LEX) and .y -> .tab.c
# via $(YACC), but they don't produce reentrant scanners and they put
# files in awkward places.  Use explicit rules to keep things tidy.
GEN_C   := src/parser.tab.c src/lex.parser.c
GEN_O   := $(GEN_C:.c=.o)
GEN_H   := src/parser.tab.h

TARGET  := tomasulo

# Kill GNU make's built-in .y -> .c and .l -> .c rules so they don't
# clobber src/parser.c (the hand-written driver next to parser.y).
%.c: %.y
%.c: %.l

.PHONY: all run test clean

all: $(TARGET)

# Flex generates a reentrant scanner because parser.l declares it via
# %option reentrant.  We name the output explicitly so it slots cleanly
# next to the bison output.
src/lex.parser.c: src/parser.l src/parser.tab.h
	$(LEX) -o $@ $<

# Bison produces both the .tab.c parser and the .tab.h with token codes.
src/parser.tab.c src/parser.tab.h: src/parser.y
	$(YACC) -d -o src/parser.tab.c $<

# Hand-written .c -> .o with strict warnings.
src/%.o: src/%.c $(GEN_H)
	$(CC) $(CFLAGS) -Isrc -c -o $@ $<

# Generated .c -> .o with relaxed warnings.
src/parser.tab.o src/lex.parser.o: src/%.o: src/%.c $(GEN_H)
	$(CC) $(GEN_CFLAGS) -Isrc -c -o $@ $<

$(TARGET): $(OBJ) $(GEN_O)
	$(CC) -o $@ $^ $(LDFLAGS)

run: $(TARGET)
	./$(TARGET) tests/input_basic.txt -b

test: $(TARGET)
	@echo "=== Basic test ==="
	./$(TARGET) tests/input_basic.txt -q
	@echo ""
	@echo "=== CDB contention test ==="
	./$(TARGET) tests/input_cdb_contention.txt -q
	@echo ""
	@echo "=== Chain test ==="
	./$(TARGET) tests/input_chain.txt -q
	@echo ""
	@echo "=== Daxpy test ==="
	./$(TARGET) tests/input_daxpy.txt -q
	@echo ""
	@echo "=== Hennessy test ==="
	./$(TARGET) tests/input_hennessy.txt -q
	@echo ""
	@echo "=== Horner test ==="
	./$(TARGET) tests/input_horner.txt -q
	@echo ""
	@echo "=== Load use test ==="
	./$(TARGET) tests/input_load_use.txt -q
	@echo ""
	@echo "=== Mixed stress test ==="
	./$(TARGET) tests/input_mixed_stress.txt -q
	@echo ""
	@echo "=== Parallel test ==="
	./$(TARGET) tests/input_parallel.txt -q
	@echo ""
	@echo "=== Structural hazard test ==="
	./$(TARGET) tests/input_structural.txt -q
	@echo ""
	@echo "=== WAW test ==="
	./$(TARGET) tests/input_waw.txt -q
	@echo ""
	@echo "All tests completed."

clean:
	rm -f $(TARGET)
	rm -f $(OBJ) $(GEN_O) $(GEN_C) $(GEN_H)
	rm -rf zig-out .zig-cache
