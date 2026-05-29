# Tomasulo Simulator - Modern Standalone Makefile
# Usage: make          (build)
#        make run      (build + run default test)
#        make test     (run all tests)
#        make release  (stripped + UPX compressed)
#        make clean

NAME     := tomasulo

# Directories
SRC_DIR  := src
INC_DIR  := include
OUT_DIR  := build
OBJ_DIR  := $(OUT_DIR)/obj
GEN_DIR  := $(OUT_DIR)/gen

# Tools
CC       ?= cc
LEX      ?= flex
YACC     ?= bison

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
    CFLAGS += -g -DDEBUG
endif

# Hand-written sources
SRCS     := $(wildcard $(SRC_DIR)/*.c)
OBJS     := $(patsubst $(SRC_DIR)/%.c,$(OBJ_DIR)/%.o,$(SRCS))

# Generated sources
GEN_C    := $(GEN_DIR)/parser.tab.c $(GEN_DIR)/lex.parser.c
GEN_H    := $(GEN_DIR)/parser.tab.h
GEN_O    := $(GEN_C:.c=.o)

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
else
    CC := ccache $(CC)
endif

# compiledb (clangd) support
ifeq ($(shell which compiledb 2>/dev/null),)
    CC_JSON :=
else
    CC_JSON := $(OUT_DIR)/compile_commands.json
endif

.PHONY: all run test release clean pgo

all: $(BIN)

# ====================== Generated Parser/Lexer ======================

$(GEN_DIR)/parser.tab.c $(GEN_DIR)/parser.tab.h: $(SRC_DIR)/parser.y | $(GEN_DIR)
	$(YACC) $(YFLAGS) -o $(GEN_DIR)/parser.tab.c $<

$(GEN_DIR)/lex.parser.c: $(SRC_DIR)/parser.l $(GEN_DIR)/parser.tab.h | $(GEN_DIR)
	$(LEX) -o $@ $<

# ====================== Compilation Rules ======================

# Hand-written sources
$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c $(GEN_H) | $(OBJ_DIR)
	$(CC) -I$(INC_DIR) -I$(GEN_DIR) $(CFLAGS) -c $< -o $@

# Generated sources (relaxed warnings)
$(GEN_O): $(GEN_DIR)/%.o: $(GEN_DIR)/%.c $(GEN_H) | $(GEN_DIR)
	$(CC) -I$(INC_DIR) -I$(GEN_DIR) $(GEN_CFLAGS) -c $< -o $@

# Create directories
$(OBJ_DIR) $(GEN_DIR):
	$(MKDIR) $@

# Linking
$(BIN): $(OBJS) $(GEN_O) | $(OUT_DIR)
	$(CC) $(LDFLAGS) $^ -o $@

# ====================== Release & PGO ======================

release: $(BIN)-release

$(BIN)-stripped: $(BIN)
	strip -o $@ $<

$(BIN)-release: $(BIN)-stripped
	upx -qqo $@ $<

# Profile-Guided Optimization (runs all tests)
pgo: clean
	@echo "=== Generating PGO profile ==="
	$(MAKE) all CFLAGS="$(CFLAGS) -fprofile-generate" LDFLAGS="$(LDFLAGS) -fprofile-generate"
	@echo "=== Running tests for profile data ==="
	@for test in tests/input_*.tom; do \
		echo "  Running $$test"; \
		$(BIN) $$test -q; \
	done
	@echo "=== Rebuilding with profile data ==="
	$(MAKE) all CFLAGS="$(CFLAGS) -fprofile-use" LDFLAGS="$(LDFLAGS) -fprofile-use"
	@echo "PGO completed."

# ====================== Utility Targets ======================

run: $(BIN)
	./$(BIN) tests/input_basic.tom -b

test: $(BIN)
	@echo "=== Running all tests ==="
	@for f in tests/input_*.tom; do \
		echo "=== $$f ==="; \
		./$(BIN) $$f -q || exit 1; \
	done
	@echo "All tests passed."

$(CC_JSON): Makefile | $(OUT_DIR)
	compiledb -nfo $@ make CC=clang --no-color

clean:
	$(RM) $(BIN) $(BIN)-stripped $(BIN)-release
	$(RMDIR) $(OUT_DIR)
	$(RM) *.gcda *.profraw *.profdata

# Directory creation
%/:
	$(MKDIR) $@

.PHONY: all run test release clean pgo
