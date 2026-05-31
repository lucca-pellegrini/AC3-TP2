# SPDX-License-Identifier: ISC
# SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>

## Project configuration
NAME    ?= tomasulo

# Tools
CC      := musl-clang
LEX     := flex
YACC    := bison

# Directories
SRC_DIR := src
INC_DIR := include
OUT_DIR := build
OBJ_DIR := $(OUT_DIR)/obj
DEP_DIR := $(OUT_DIR)/dep
GEN_DIR := $(OUT_DIR)/gen
COV_DIR := $(OUT_DIR)/coverage


## Tools configuration

# Compiler flags
CFLAGS     += -std=c23 -Wall -Wextra -Wpedantic -O3 -D_GNU_SOURCE
GEN_CFLAGS := $(CFLAGS) -Wno-unused-function -Wno-unused-but-set-variable
DEPFLAGS   := -MMD -MP
LDFLAGS    += -flto=full -lm
YFLAGS     := -d --warnings=no-yacc

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

# Debug mode
ifndef NODEBUG
    CFLAGS += -g -DDEBUG --debug
    GEN_CFLAGS += -g -DDEBUG --debug
endif
ifndef NOOPTIMIZE
    CFLAGS += -O0
    GEN_CFLAGS += -O0
endif

# Hand-written sources
SRCS     := $(wildcard $(SRC_DIR)/*.c)
OBJS     := $(patsubst $(SRC_DIR)/%.c,$(OBJ_DIR)/%.o,$(SRCS))

# Generated sources
GEN_C    := $(GEN_DIR)/parser.tab.c $(GEN_DIR)/lex.parser.c
GEN_H    := $(GEN_DIR)/parser.tab.h
GEN_O    := $(patsubst $(GEN_DIR)/%.o,$(OBJ_DIR)/%.o,$(GEN_C:.c=.o))

# Dependency lists
DEPS := \
	$(patsubst $(OBJ_DIR)/%.o,$(DEP_DIR)/%.d,$(OBJS)) \
	$(patsubst $(OBJ_DIR)/%.o,$(DEP_DIR)/%.d,$(GEN_O))

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

# List targets
help:
	@echo "A Tomasulo Algorithm Simulator — Makefile"
	@echo
	@echo "Usage: make [<OPTION>=<VALUE>...] [<TARGET>]"
	@echo
	@echo "Possible targets:"
	@echo "  help          Display this help page."
	@echo "  all           Build the Tomasulo Simulator at ‘./<OUT_DIR>/tomasulo’."
	@echo "                  Requires a C23-capable compiler, Flex, and GNU Bison."
	@echo "                  This is the default target if none is specified."
	@echo "  clean         Clean up all build artifacts and delete the <OUT_DIR> dir."
	@echo "  release       Compile the release build at ‘<OUT_DIR>/tomasulo-release’."
	@echo "                  Requires the ‘upx’ command to be available."
	@echo "  test          Run the simulator against all simulations in the ‘simulations/’"
	@echo "                  directory."
	@echo "  cov           Run code coverage tests using all simulations in the ‘simulations/’"
	@echo "                  directory. Requires the ‘kcov’ command to be available."
	@echo "  pgo           Build the simulator using profile-guided optimization by"
	@echo "                  running the simulator against all simulations in ‘simulations/’."
	@echo "                  Cannot be used with static libc (which is the default)"
	@echo "  run           Run the simulator (input is read from stdin)."
	@echo
	@echo "Options:"
	@echo "  CC            What C compiler to use. Defaults to ‘musl-clang’."
	@echo "                  If this matches the regex ‘^musl-.*’, the resulting"
	@echo "                  binary will be statically linked."
	@echo "  LEX           What lexical analyzer generator to use. Defaults to ‘flex’."
	@echo "  YACC          What parser generator to use. Defaults to ‘bison’."
	@echo "  NODEBUG       If set, causes debug symbols to be omitted."
	@echo "  NOOPTIMIZE    If set, builds with ‘-O0’ (default is ‘-O3’)."
	@echo "  OUT_DIR       Directory where all build artifacts are to be stored."
	@echo "                  Defaults to ‘build/’                          "
	@echo "  SRC_DIR       Directory containing .c, .y, and .l source files."
	@echo "                  Defaults to ‘src/’                            "
	@echo "  INC_DIR       Directory containing header files. Defaults to ‘include/’."


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

# Disable the implicit rule for .y/.l files, which breaks parser.c
%.c: %.y
%.c: %.l


## Normal compilation rules

# Hand-written sources
$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c $(GEN_H) | $(OBJ_DIR) $(DEP_DIR)
	$(CC_WRAPPER) $(CC) -I$(INC_DIR) -I$(GEN_DIR) $(CFLAGS) \
		$(DEPFLAGS) -MF $(DEP_DIR)/$*.d -MT $@ -c $< -o $@

# Generated sources
$(GEN_O): $(OBJ_DIR)/%.o: $(GEN_DIR)/%.c $(GEN_H) | $(GEN_DIR) $(DEP_DIR)
	$(CC_WRAPPER) $(CC) -I$(INC_DIR) -I$(GEN_DIR) $(GEN_CFLAGS) \
		$(DEPFLAGS) -MF $(DEP_DIR)/$*.d -MT $@ -c $< -o $@

# How to create directories directories
$(OUT_DIR) $(OBJ_DIR) $(DEP_DIR) $(GEN_DIR) $(COV_DIR):
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

# Profile-Guided Optimization (runs all simulations)
pgo: clean
	@echo "=== Generating PGO profile ==="
	$(MAKE) all CFLAGS="$(CFLAGS) -fprofile-generate" LDFLAGS="$(LDFLAGS) -fprofile-generate"
	@echo "=== Running simulations for profile data ==="
	@for simulation in simulations/*.tom; do \
		echo "  Running $$simulation"; \
		$(BIN) $$simulation -q; \
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
	@echo "=== Running all simulations ==="
	@for f in simulations/*.tom; do \
		cols=$$(tput cols 2>/dev/null || echo 120); \
		[ $$cols -gt 120 ] && cols=120; \
		printf '\033[1;35m%*s\033[0m\n' $$cols '' | tr ' ' '='; \
		printf '\033[1;35m=== %s ===\033[0m\n' "$$f"; \
		printf '\033[1;35m%*s\033[0m\n' $$cols '' | tr ' ' '='; \
		$< "$$f" -q || exit 1; \
	done
	@echo "All simulations passed."
test-release: $(BIN)-release
	@echo "=== Running all simulations ==="
	@for f in simulations/*.tom; do \
		cols=$$(tput cols 2>/dev/null || echo 120); \
		[ $$cols -gt 120 ] && cols=120; \
		printf '\033[1;35m%*s\033[0m\n' $$cols '' | tr ' ' '='; \
		printf '\033[1;35m=== %s ===\033[0m\n' "$$f"; \
		printf '\033[1;35m%*s\033[0m\n' $$cols '' | tr ' ' '='; \
		$< "$$f" -q || exit 1; \
	done
	@echo "All simulations passed."
test: $(BIN)
	@echo "=== Running all simulations ==="
	@for f in simulations/*.tom; do \
		cols=$$(tput cols 2>/dev/null || echo 120); \
		[ $$cols -gt 120 ] && cols=120; \
		printf '\033[1;35m%*s\033[0m\n' $$cols '' | tr ' ' '='; \
		printf '\033[1;35m=== %s ===\033[0m\n' "$$f"; \
		printf '\033[1;35m%*s\033[0m\n' $$cols '' | tr ' ' '='; \
		$< "$$f" -q || exit 1; \
	done
	@echo "All simulations passed."

# Create compile_commands.json for clangd
$(COMPILE_COMMANDS_JSON): Makefile | $(OUT_DIR)
	compiledb -nfo $@ make CC=clang

# Run code coverage tests
cov: $(BIN) | $(COV_DIR)
	@echo Running kcov...
	@i=0; \
	for f in simulations/*.tom; do \
		i=$$((i+1)); \
		kcov --include-path=$(CURDIR) \
			$(COV_DIR)/run$$i \
			$(BIN) "$$f" -qo/dev/null || exit 1; \
	done

	kcov --merge $(COV_DIR) $(COV_DIR)/run*

# Remove all artifacts
clean:
	$(RM) $(BIN) $(BIN)-stripped $(BIN)-release
	$(RMDIR) $(OUT_DIR)
	$(RM) *.gcda *.profraw *.profdata

.PHONY: all help clean cov pgo release \
	run test run-stripped test-stripped run-release test-release

-include $(DEPS)
