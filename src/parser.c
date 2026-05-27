// SPDX-License-Identifier: MIT
// Tomasulo Simulator -- Input file parser
#define _GNU_SOURCE
#include "parser.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define MAX_LINE 512

// ── Utilities ───────────────────────────────────────────────────────────────

// Strip leading/trailing whitespace in-place, return pointer into buf.
static char *strip(char *buf)
{
	while (*buf && isspace((unsigned char)*buf))
		buf++;
	char *end = buf + strlen(buf) - 1;
	while (end > buf && isspace((unsigned char)*end))
		*end-- = '\0';
	return buf;
}

// Strip inline comments (everything from '#' onwards).
static void strip_comment(char *buf)
{
	char *p = strchr(buf, '#');
	if (p)
		*p = '\0';
}

// Replace commas with spaces for flexible token parsing.
static void replace_commas(char *buf)
{
	for (; *buf; buf++) {
		if (*buf == ',')
			*buf = ' ';
	}
}

int parse_register(const char *name)
{
	if (!name || !*name)
		return -1;
	char first = (char)toupper((unsigned char)name[0]);
	if (first != 'F' && first != 'R')
		return -1;
	if (name[1] == '\0') // bare "F" or "R" with no number
		return -1;
	char *end;
	long val = strtol(name + 1, &end, 10);
	if (end == name + 1 || *end != '\0' || val < 0 || val >= MAX_FP_REGISTERS)
		return -1;
	return (int)val;
}

// ── Config parsing ──────────────────────────────────────────────────────────

static int parse_config(FILE *f, TomasuloConfig *cfg)
{
	char line[MAX_LINE];

	// Seek to CONFIG_BEGIN
	bool found = false;
	while (fgets(line, sizeof(line), f)) {
		if (strstr(line, "CONFIG_BEGIN")) {
			found = true;
			break;
		}
	}
	if (!found) {
		fprintf(stderr, "error: CONFIG_BEGIN not found\n");
		return -1;
	}

	while (fgets(line, sizeof(line), f)) {
		strip_comment(line);
		char *trimmed = strip(line);

		if (strstr(trimmed, "CONFIG_END"))
			return 0;

		if (*trimmed == '\0')
			continue;

		char key[32], type_str[32];
		int value;
		if (sscanf(trimmed, "%31s %31s %d", key, type_str, &value) != 3)
			continue;

		Opcode op = opcode_from_str(type_str);

		if (strcasecmp(key, "CYCLES") == 0 && op < OP_COUNT) {
			cfg->latency[op] = value;
		} else if (strcasecmp(key, "UNITS") == 0 || strcasecmp(key, "MEM_UNITS") == 0) {
			// Map opcode to RS type
			RSType rst;
			if (op == OP_ADDD || op == OP_SUBD)
				rst = RS_ADD;
			else if (op == OP_MULTD || op == OP_DIVD)
				rst = RS_MULT;
			else if (op == OP_LD)
				rst = RS_LOAD;
			else if (op == OP_SD)
				rst = RS_STORE;
			else
				continue;
			cfg->num_rs[rst] = value;
		}
	}

	fprintf(stderr, "error: CONFIG_END not found\n");
	return -1;
}

// ── Register init parsing (optional section) ────────────────────────────────

static void parse_reg_init(FILE *f, Simulator *sim)
{
	char line[MAX_LINE];

	// Seek to REG_INIT_BEGIN (optional -- rewind first)
	rewind(f);
	bool found = false;
	while (fgets(line, sizeof(line), f)) {
		if (strstr(line, "REG_INIT_BEGIN")) {
			found = true;
			break;
		}
	}
	if (!found)
		return; // section is optional

	while (fgets(line, sizeof(line), f)) {
		strip_comment(line);
		char *trimmed = strip(line);

		if (strstr(trimmed, "REG_INIT_END"))
			return;
		if (*trimmed == '\0')
			continue;

		char reg_name[16];
		double val;
		if (sscanf(trimmed, "%15s %lf", reg_name, &val) == 2) {
			int idx = parse_register(reg_name);
			if (idx >= 0)
				sim_set_reg(sim, idx, val);
		}
	}
}

// ── Instruction parsing ─────────────────────────────────────────────────────

static int parse_instructions(FILE *f, Simulator *sim)
{
	char line[MAX_LINE];

	// Seek to INSTRUCTIONS_BEGIN
	rewind(f);
	bool found = false;
	while (fgets(line, sizeof(line), f)) {
		if (strstr(line, "INSTRUCTIONS_BEGIN")) {
			found = true;
			break;
		}
	}
	if (!found) {
		fprintf(stderr, "error: INSTRUCTIONS_BEGIN not found\n");
		return -1;
	}

	while (fgets(line, sizeof(line), f)) {
		strip_comment(line);
		replace_commas(line);
		char *trimmed = strip(line);

		if (strstr(trimmed, "INSTRUCTIONS_END"))
			return 0;
		if (*trimmed == '\0')
			continue;

		// Tokenize
		char *tokens[8];
		int ntok = 0;
		char *saveptr;
		char *tok = strtok_r(trimmed, " \t", &saveptr);
		while (tok && ntok < 8) {
			tokens[ntok++] = tok;
			tok = strtok_r(nullptr, " \t", &saveptr);
		}

		if (ntok < 3)
			continue;

		Opcode op = opcode_from_str(tokens[0]);
		if (op >= OP_COUNT) {
			fprintf(stderr, "warning: unknown opcode '%s', skipping\n", tokens[0]);
			continue;
		}

		Instruction inst = { .op = op, .dest = -1, .src1 = -1, .src2 = -1 };

		if (op == OP_LD) {
			// L.D Fdest offset Rbase  (or Fdest, offset(Rbase))
			inst.dest = parse_register(tokens[1]);
			// Try to parse offset
			char *endp;
			inst.imm = (int)strtol(tokens[2], &endp, 10);
			if (ntok >= 4)
				inst.src1 = parse_register(tokens[3]);
		} else if (op == OP_SD) {
			// S.D Fval offset Rbase
			inst.dest = parse_register(tokens[1]); // value source
			char *endp;
			inst.imm = (int)strtol(tokens[2], &endp, 10);
			if (ntok >= 4)
				inst.src1 = parse_register(tokens[3]);
		} else {
			// Arithmetic: OP Fdest Fsrc1 Fsrc2
			inst.dest = parse_register(tokens[1]);
			inst.src1 = parse_register(tokens[2]);
			if (ntok >= 4)
				inst.src2 = parse_register(tokens[3]);
		}

		if (!sim_add_instruction(sim, inst)) {
			fprintf(stderr, "error: too many instructions\n");
			return -1;
		}
	}

	fprintf(stderr, "error: INSTRUCTIONS_END not found\n");
	return -1;
}

// ── Public API ──────────────────────────────────────────────────────────────

int parse_input(const char *path, TomasuloConfig *cfg, Simulator *sim)
{
	FILE *f = fopen(path, "r");
	if (!f) {
		fprintf(stderr, "error: cannot open '%s'\n", path);
		return -1;
	}

	// Start with defaults, let the file override
	*cfg = config_default();

	if (parse_config(f, cfg) != 0) {
		fclose(f);
		return -1;
	}

	// Initialize simulator with parsed config
	sim_init(sim, cfg);

	// Parse optional register initialization
	parse_reg_init(f, sim);

	// Parse instructions
	if (parse_instructions(f, sim) != 0) {
		fclose(f);
		return -1;
	}

	fclose(f);
	return 0;
}
