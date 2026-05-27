# Standalone Makefile -- build without Zig
# Usage: make          (build)
#        make run      (build and run with default input)
#        make test     (run basic tests)
#        make clean    (remove artifacts)

CC      ?= cc
CFLAGS  := -std=c23 -Wall -Wextra -Wpedantic -D_GNU_SOURCE -O2
LDFLAGS := -lm
SRC     := src/tomasulo.c src/parser.c src/display.c src/main.c
TARGET  := tomasulo

.PHONY: all run test clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -Isrc -o $@ $^ $(LDFLAGS)

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
	rm -rf zig-out .zig-cache
