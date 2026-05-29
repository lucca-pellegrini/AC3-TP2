// SPDX-License-Identifier: MIT
// Internal glue shared between the flex scanner, the bison parser and
// the parser driver (parser.c).  Not part of the public API.
#pragma once

#include "tomasulo.h"

#include <stdbool.h>
#include <stdio.h>

// State threaded through the parser via %parse-param.
typedef struct ParseContext {
	const char *filename; // for error messages
	TomasuloConfig *cfg;
	Simulator *sim;
	bool sim_ready; // true once sim_init() has been called
	int errors; // count of parse errors encountered
} ParseContext;

// Helper used by both the scanner and the grammar to report errors with
// source location.  Defined in parser.c.
struct TOM_YYLTYPE; // forward decl, real type comes from bison
void tom_parse_error_at(ParseContext *ctx, int line, const char *fmt, ...)
	__attribute__((format(printf, 3, 4)));

// Convenience macro: extract the line number from a bison location and
// dispatch to the variadic reporter.
#define tom_parse_error(ctx, loc, ...) tom_parse_error_at((ctx), (loc).first_line, __VA_ARGS__)
