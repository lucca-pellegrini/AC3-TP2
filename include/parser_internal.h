/*
 * SPDX-License-Identifier: ISC
 * SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
 * NOTE: Tomasulo file parser logic written with help from LLMs
 */

#pragma once

#include "tomasulo.h"

#include <stdbool.h>

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
void tom_parse_error_at(ParseContext *ctx, const struct TOM_YYLTYPE *loc, const char *fmt, ...)
	__attribute__((format(printf, 3, 4)));

// Convenience macro: pass the whole bison location structure through.
#define tom_parse_error(ctx, loc, ...) tom_parse_error_at((ctx), &(loc), __VA_ARGS__)
