# SPDX-License-Identifier: ISC
# SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>

## Project configuration
NAME     ?= tomasulo

# Tools
CC       := musl-clang
LEX      := flex
YACC     := bison

# Directories
SRC_DIR  := src
INC_DIR  := include
OUT_DIR  := build
OBJ_DIR  := $(OUT_DIR)/obj
GEN_DIR  := $(OUT_DIR)/gen


## Tools configuration

# Compiler flags
CFLAGS   += -std=c23 -Wall -Wextra -Wpedantic -O3 -D_GNU_SOURCE
GEN_CFLAGS := $(CFLAGS) -Wno-unused-function -Wno-unused-but-set-variable

LDFLAGS  += -lm
YFLAGS   := -d --warnings=no-yacc

# Use static linking if compiler is musl
ifneq ($(findstring musl-,$(CC)),)
    LDFLAGS += -static
endif

# Ignore unused arguments when using a clang-like compiler
CC_VERSION := $(shell $(CC) --version 2>/dev/null)
ifneq ($(findstring clang,$(CC_VERSION)),)
    CFLAGS += -Wno-unused-command-line-argument
    GEN_CFLAGS += -Wno-unused-command-line-argument
endif

# FLTO support
ifdef FLTO
    CFLAGS  += -flto=auto
    LDFLAGS += -flto=auto
endif

# Debug mode
ifdef DEBUG
    CFLAGS += -g -DDEBUG --debug -O0
    GEN_CFLAGS += -g -DDEBUG --debug -O0
endif

# Hand-written sources
SRCS     := $(wildcard $(SRC_DIR)/*.c)
OBJS     := $(patsubst $(SRC_DIR)/%.c,$(OBJ_DIR)/%.o,$(SRCS))

# Generated sources
GEN_C    := $(GEN_DIR)/parser.tab.c $(GEN_DIR)/lex.parser.c
GEN_H    := $(GEN_DIR)/parser.tab.h
GEN_O    := $(patsubst $(GEN_DIR)/%.o,$(OBJ_DIR)/%.o,$(GEN_C:.c=.o))

# Final binary
BIN      := $(OUT_DIR)/$(NAME)

# Platform-specific
ifneq ($(OS),Windows_NT)
    MKDIR := mkdir -p
    RMDIR := rm -rf
else
    MKDIR := mkdir
    RMDIR := rmdir /s /q
endif

# ccache support
ifeq ($(shell which ccache 2>/dev/null),)
    CC_WRAPPER :=
else
    CC_WRAPPER := ccache
endif

# compiledb (clangd) support
ifeq ($(shell which compiledb 2>/dev/null),)
    COMPILE_COMMANDS_JSON :=
else
    COMPILE_COMMANDS_JSON := $(OUT_DIR)/compile_commands.json
endif

# Default target
all: $(COMPILE_COMMANDS_JSON) $(BIN)


## Generated parser and lexer

# Where the sources are
Y_SRCS := $(wildcard $(SRC_DIR)/*.y)
L_SRCS := $(wildcard $(SRC_DIR)/*.l)

# Where the generated files go
Y_GEN_C := $(patsubst $(SRC_DIR)/%.y,$(GEN_DIR)/%.tab.c,$(Y_SRCS))
Y_GEN_H := $(patsubst $(SRC_DIR)/%.y,$(GEN_DIR)/%.tab.h,$(Y_SRCS))
L_GEN_C := $(patsubst $(SRC_DIR)/%.l,$(GEN_DIR)/lex.%.c,$(L_SRCS))

# Combined generated sources
GEN_C := $(Y_GEN_C) $(L_GEN_C)
GEN_H := $(Y_GEN_H)

# How to compile Bison/Yacc targets
$(GEN_DIR)/%.tab.c $(GEN_DIR)/%.tab.h: $(SRC_DIR)/%.y | $(GEN_DIR)
	$(YACC) $(YFLAGS) -o $(GEN_DIR)/$*.tab.c $<

# How to compile Flex/Lex targets
$(GEN_DIR)/lex.%.c: $(SRC_DIR)/%.l $(GEN_DIR)/%.tab.h | $(GEN_DIR)
	$(LEX) -o $@ $<

# Disable the implicit rule for .y files, which breaks parser.c
%.c: %.y


## Normal compilation rules

# Hand-written sources
$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c $(GEN_H) | $(OBJ_DIR)
	$(CC_WRAPPER) $(CC) -I$(INC_DIR) -I$(GEN_DIR) $(CFLAGS) -c $< -o $@

# Generated sources
$(GEN_O): $(OBJ_DIR)/%.o: $(GEN_DIR)/%.c $(GEN_H) | $(GEN_DIR)
	$(CC_WRAPPER) $(CC) -I$(INC_DIR) -I$(GEN_DIR) $(GEN_CFLAGS) -c $< -o $@

# How to create directories directories
$(OUT_DIR) $(OBJ_DIR) $(GEN_DIR):
	$(MKDIR) $@

# How to link the final executable
$(BIN): $(OBJS) $(GEN_O) | $(OUT_DIR)
	$(CC_WRAPPER) $(CC) $(LDFLAGS) $^ -o $@


## Release and PGO rules

# Main release target
release: $(BIN)-release

# Stripped binary
$(BIN)-stripped: $(BIN)
	strip -o $@ $<

# Compressed release binary
$(BIN)-release: $(BIN)-stripped
	upx -qqo $@ -9 $<

# Profile-Guided Optimization (runs all tests)
pgo: clean
	@echo "=== Generating PGO profile ==="
	$(MAKE) all CFLAGS="$(CFLAGS) -fprofile-generate" LDFLAGS="$(LDFLAGS) -fprofile-generate"
	@echo "=== Running tests for profile data ==="
	@for test in tests/*.tom; do \
		echo "  Running $$test"; \
		$(BIN) $$test -q; \
	done
	@echo "=== Rebuilding with profile data ==="
	$(MAKE) all CFLAGS="$(CFLAGS) -fprofile-use" LDFLAGS="$(LDFLAGS) -fprofile-use"
	@echo "PGO completed."


## Utility targets

# Run each executable
run: $(BIN)
	$<
run-stripped: $(BIN)-stripped
	$<
run-release: $(BIN)-release
	$<

# Test each executable
test-stripped: $(BIN)-stripped
	@echo "=== Running all tests ==="
	@for f in tests/*.tom; do \
		cols=$$(tput cols 2>/dev/null || echo 120); \
		[ $$cols -gt 120 ] && cols=120; \
		printf '\033[1;35m%*s\033[0m\n' $$cols '' | tr ' ' '='; \
		printf '\033[1;35m=== %s ===\033[0m\n' "$$f"; \
		printf '\033[1;35m%*s\033[0m\n' $$cols '' | tr ' ' '='; \
		$< "$$f" -q || exit 1; \
	done
	@echo "All tests passed."
test-release: $(BIN)-release
	@echo "=== Running all tests ==="
	@for f in tests/*.tom; do \
		cols=$$(tput cols 2>/dev/null || echo 120); \
		[ $$cols -gt 120 ] && cols=120; \
		printf '\033[1;35m%*s\033[0m\n' $$cols '' | tr ' ' '='; \
		printf '\033[1;35m=== %s ===\033[0m\n' "$$f"; \
		printf '\033[1;35m%*s\033[0m\n' $$cols '' | tr ' ' '='; \
		$< "$$f" -q || exit 1; \
	done
	@echo "All tests passed."
test: $(BIN)
	@echo "=== Running all tests ==="
	@for f in tests/*.tom; do \
		cols=$$(tput cols 2>/dev/null || echo 120); \
		[ $$cols -gt 120 ] && cols=120; \
		printf '\033[1;35m%*s\033[0m\n' $$cols '' | tr ' ' '='; \
		printf '\033[1;35m=== %s ===\033[0m\n' "$$f"; \
		printf '\033[1;35m%*s\033[0m\n' $$cols '' | tr ' ' '='; \
		$< "$$f" -q || exit 1; \
	done
	@echo "All tests passed."

# Create compile_commands.json for clangd
$(COMPILE_COMMANDS_JSON): Makefile | $(OUT_DIR)
	compiledb -nfo $@ make CC=clang

# Remove all artifacts
clean:
	$(RM) $(BIN) $(BIN)-stripped $(BIN)-release
	$(RMDIR) $(OUT_DIR)
	$(RM) *.gcda *.profraw *.profdata

.PHONY: all clean pgo release \
	run test run-stripped test-stripped run-release test-release
