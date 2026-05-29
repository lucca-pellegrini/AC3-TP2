# Tomasulo Simulator - Modern Standalone Makefile
# Usage: make          (build)
#        make run      (build + run default test)
#        make test     (run all tests)
#        make release  (stripped + UPX compressed)
#        make clean

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
    CC_JSON :=
else
    CC_JSON := $(OUT_DIR)/compile_commands.json
endif

.PHONY: all run test release clean pgo

all: $(BIN)

# ====================== Generated Parser/Lexer ======================

Y_SRCS := $(wildcard $(SRC_DIR)/*.y)
L_SRCS := $(wildcard $(SRC_DIR)/*.l)

Y_GEN_C := $(patsubst $(SRC_DIR)/%.y,$(GEN_DIR)/%.tab.c,$(Y_SRCS))
Y_GEN_H := $(patsubst $(SRC_DIR)/%.y,$(GEN_DIR)/%.tab.h,$(Y_SRCS))
L_GEN_C := $(patsubst $(SRC_DIR)/%.l,$(GEN_DIR)/lex.%.c,$(L_SRCS))

GEN_C := $(Y_GEN_C) $(L_GEN_C)
GEN_H := $(Y_GEN_H)

# Bison
$(GEN_DIR)/%.tab.c $(GEN_DIR)/%.tab.h: $(SRC_DIR)/%.y | $(GEN_DIR)
	$(YACC) $(YFLAGS) -o $(GEN_DIR)/$*.tab.c $<

# Flex
$(GEN_DIR)/lex.%.c: $(SRC_DIR)/%.l $(GEN_DIR)/%.tab.h | $(GEN_DIR)
	$(LEX) -o $@ $<

# ====================== Compilation Rules ======================

# Hand-written sources
$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c $(GEN_H) | $(OBJ_DIR)
	$(CC_WRAPPER) $(CC) -I$(INC_DIR) -I$(GEN_DIR) $(CFLAGS) -c $< -o $@

# Generated sources (relaxed warnings)
$(GEN_O): $(OBJ_DIR)/%.o: $(GEN_DIR)/%.c $(GEN_H) | $(GEN_DIR)
	$(CC_WRAPPER) $(CC) -I$(INC_DIR) -I$(GEN_DIR) $(GEN_CFLAGS) -c $< -o $@

# Create directories
$(OUT_DIR) $(OBJ_DIR) $(GEN_DIR):
	$(MKDIR) $@

# Linking
$(BIN): $(OBJS) $(GEN_O) | $(OUT_DIR)
	$(CC_WRAPPER) $(CC) $(LDFLAGS) $^ -o $@

# ====================== Release & PGO ======================

release: $(BIN)-release

$(BIN)-stripped: $(BIN)
	strip -o $@ $<

$(BIN)-release: $(BIN)-stripped
	upx -qqo $@ -9 $<

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
