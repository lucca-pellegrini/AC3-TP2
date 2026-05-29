// SPDX-License-Identifier: MIT
// Tomasulo Simulator -- Input file parser (driver)
//
// The actual grammar lives in parser.y (Bison) and the tokenizer in
// parser.l (Flex).  This file provides the public entry point declared
// in parser.h, plus the small helpers that those generated files call
// back into.
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include "parser.h"
#include "parser_internal.h"
#include "parser.tab.h"

#include <ctype.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

// ── Generated scanner control functions ────────────────────────────────────
//
// We can't include the flex header directly without dragging in a lot of
// macros, so we re-declare just the bits we need here.

typedef void *yyscan_t;
int tom_yylex_init(yyscan_t *scanner);
int tom_yylex_destroy(yyscan_t scanner);
void tom_yyset_in(FILE *in, yyscan_t scanner);
void tom_yyset_extra(void *user_defined, yyscan_t scanner);

// ── Error reporting ────────────────────────────────────────────────────────

void tom_parse_error_at(ParseContext *ctx, int line, const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	fprintf(stderr, "%s:%d: error: ", ctx->filename, line);
	vfprintf(stderr, fmt, ap);
	fputc('\n', stderr);
	va_end(ap);
	ctx->errors++;
}

// ── Public helpers ─────────────────────────────────────────────────────────

int parse_register(const char *name)
{
	if (!name || !*name)
		return -1;
	char first = (char)toupper((unsigned char)name[0]);
	if (first != 'F' && first != 'R')
		return -1;
	if (name[1] == '\0')
		return -1;
	char *end;
	long val = strtol(name + 1, &end, 10);
	if (end == name + 1 || *end != '\0' || val < 0 || val >= MAX_FP_REGISTERS)
		return -1;
	return (int)val;
}

// ── Public entry point ─────────────────────────────────────────────────────

int parse_input(const char *path, TomasuloConfig *cfg, Simulator *sim)
{
	FILE *f = fopen(path, "r");
	if (!f) {
		fprintf(stderr, "error: cannot open '%s'\n", path);
		return -1;
	}

	// Start from defaults; the grammar overrides whatever's specified.
	*cfg = config_default();

	ParseContext ctx = {
		.filename = path,
		.cfg = cfg,
		.sim = sim,
		.sim_ready = false,
		.errors = 0,
	};

	yyscan_t scanner;
	if (tom_yylex_init(&scanner) != 0) {
		fprintf(stderr, "error: cannot initialise scanner\n");
		fclose(f);
		return -1;
	}
	tom_yyset_in(f, scanner);
	tom_yyset_extra(&ctx, scanner);

	int rc = tom_yyparse(scanner, &ctx);

	tom_yylex_destroy(scanner);
	fclose(f);

	// Belt-and-braces: ensure sim_init() ran even if the input had no
	// instructions section (the grammar would normally reject that, but
	// in case YYERROR recovery left us hanging, we don't want the caller
	// observing an uninitialised simulator).
	if (!ctx.sim_ready)
		sim_init(sim, cfg);

	// Re-copy the final config into the simulator.  The grammar calls
	// ensure_sim_ready() when it sees the first register or instruction
	// block, but cycles{}/units{} blocks can appear later in the file.
	// Without this, the simulator would run with stale default values.
	sim->cfg = *cfg;

	if (rc != 0 || ctx.errors > 0)
		return -1;
	return 0;
}
