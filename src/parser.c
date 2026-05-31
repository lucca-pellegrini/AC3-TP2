/*
 * SPDX-License-Identifier: ISC
 * SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
 * NOTE: Tomasulo file parser logic written with help from LLMs
 */

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
#include <string.h>

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

// Simple ANSI helpers.  We keep this local so the rest of the codebase
// doesn't grow a hard dependency on coloured output.
#define ANSI_RED "\x1b[31m"
#define ANSI_BOLD "\x1b[1m"
#define ANSI_RESET "\x1b[0m"
#define ANSI_DIM "\x1b[2m"
#define ANSI_BOLDWHITE "\x1b[1m\x1b[37m"

// Maximum line length we will try to show in an error snippet.  Input files
// for this tool are expected to be small, so a fixed buffer is fine.
#define TOM_MAX_LINE_SNIPPET 512

static void print_error_snippet(ParseContext *ctx, const struct TOM_YYLTYPE *loc,
				const char *primary_msg)
{
	if (!ctx || !ctx->filename || !loc)
		return;

	// We highlight the primary line, but also try to print a small amount
	// of surrounding context to give the user some orientation.
	int line = loc->first_line > 0 ? loc->first_line : 1;
	FILE *f = fopen(ctx->filename, "r");
	if (!f)
		return;

	char buf[TOM_MAX_LINE_SNIPPET];
	int current = 1;
	int first_ctx = line - 2;
	if (first_ctx < 1)
		first_ctx = 1;

	// Walk to the first context line.
	while (current < first_ctx && fgets(buf, sizeof(buf), f))
		current++;

	int last_ctx = line + 2;
	for (; current <= last_ctx && fgets(buf, sizeof(buf), f); current++) {
		int this_line = current;
		// Strip trailing newlines so our caret line lines up.
		size_t len = strlen(buf);
		while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r'))
			buf[--len] = '\0';

		// Line number + separator in a dim style.
		fprintf(stderr, "%s%4d |%s ", ANSI_DIM, this_line, ANSI_RESET);
		if (this_line == line) {
			// Highlight the offending source line in bold.
			fprintf(stderr, "%s%s%s\n", ANSI_BOLD, buf, ANSI_RESET);
			int start_col = loc->first_column > 0 ? loc->first_column : 1;
			fprintf(stderr, "%s     |%s ", ANSI_DIM, ANSI_RESET);
			for (int i = 1; i < start_col; i++)
				fputc(' ', stderr);
			fprintf(stderr, "%s^%s ", ANSI_RED, ANSI_RESET);
			if (primary_msg)
				fprintf(stderr, "%s%serror:%s %s", ANSI_BOLD, ANSI_RED, ANSI_RESET,
					primary_msg);
			fputc('\n', stderr);
		} else {
			// Non-primary context lines: normal text after dim line number.
			fprintf(stderr, "%s\n", buf);
		}
	}
	fclose(f);
}

void tom_parse_error_at(ParseContext *ctx, const struct TOM_YYLTYPE *loc, const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	int line = loc ? loc->first_line : 0;
	if (line <= 0)
		line = 1;

	// Render message once into a buffer so we can reuse it
	// both in the filename:line header and inline with the caret.
	char msg_buf[256];
	vsnprintf(msg_buf, sizeof(msg_buf), fmt, ap);
	va_end(ap);

	// Primary error line, coloured similar to GCC-style diagnostics.
	fprintf(stderr, "%s:%d: %serror:%s %s%s%s\n", ctx->filename, line, ANSI_BOLD ANSI_RED,
		ANSI_RESET, ANSI_BOLDWHITE, msg_buf, ANSI_RESET);

	print_error_snippet(ctx, loc, msg_buf);

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
