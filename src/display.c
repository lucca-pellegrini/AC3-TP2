// SPDX-License-Identifier: MIT
// Tomasulo Simulator -- Display / Output
//
// Uses Unicode box-drawing characters for clean table rendering.
// When the output stream is a terminal, ANSI escape codes are emitted to
// add colors and bold for readability. Otherwise (file/pipe) plain text.
#include "display.h"

#include <string.h>
#include <unistd.h>

// ── ANSI styling ────────────────────────────────────────────────────────────

#define ANSI_RESET "\x1b[0m"
#define ANSI_BOLD "\x1b[1m"
#define ANSI_DIM "\x1b[2m"
#define ANSI_ITALIC "\x1b[3m"
#define ANSI_UNDER "\x1b[4m"

#define ANSI_BLACK "\x1b[30m"
#define ANSI_RED "\x1b[31m"
#define ANSI_GREEN "\x1b[32m"
#define ANSI_YELLOW "\x1b[33m"
#define ANSI_BLUE "\x1b[34m"
#define ANSI_MAGENTA "\x1b[35m"
#define ANSI_CYAN "\x1b[36m"
#define ANSI_WHITE "\x1b[37m"

#define ANSI_BR_RED "\x1b[91m"
#define ANSI_BR_GREEN "\x1b[92m"
#define ANSI_BR_YELLOW "\x1b[93m"
#define ANSI_BR_BLUE "\x1b[94m"
#define ANSI_BR_MAGENTA "\x1b[95m"
#define ANSI_BR_CYAN "\x1b[96m"

// Cache TTY detection per stream so we don't keep calling isatty().
static bool use_color(FILE *out)
{
	int fd = fileno(out);
	if (fd < 0)
		return false;
	return isatty(fd) != 0;
}

// Helper: returns the escape string if colors are enabled, "" otherwise.
static inline const char *C(FILE *out, const char *code)
{
	return use_color(out) ? code : "";
}

// ── Box-drawing helpers ─────────────────────────────────────────────────────

void display_separator(FILE *out, int width, const char *title)
{
	const char *bold = C(out, ANSI_BOLD);
	const char *cyan = C(out, ANSI_BR_CYAN);
	const char *dim = C(out, ANSI_DIM);
	const char *reset = C(out, ANSI_RESET);

	if (title && *title) {
		int tlen = (int)strlen(title);
		int pad = (width - tlen - 4) / 2;
		if (pad < 0)
			pad = 0;
		fprintf(out, "\n%s", dim);
		for (int i = 0; i < pad; i++)
			fprintf(out, "\u2500");
		fprintf(out, "%s\u2524 %s%s%s%s %s\u251C%s", reset, bold, cyan, title, reset, dim,
			reset);
		fprintf(out, "%s", dim);
		for (int i = 0; i < width - pad - tlen - 4; i++)
			fprintf(out, "\u2500");
		fprintf(out, "%s\n", reset);
	} else {
		fprintf(out, "\n%s", dim);
		for (int i = 0; i < width; i++)
			fprintf(out, "\u2500");
		fprintf(out, "%s\n", reset);
	}
}

// ── Instruction Status Table ────────────────────────────────────────────────

void display_instructions(FILE *out, const Simulator *sim)
{
	const char *bold = C(out, ANSI_BOLD);
	const char *dim = C(out, ANSI_DIM);
	const char *reset = C(out, ANSI_RESET);
	const char *op_color = C(out, ANSI_BR_MAGENTA);
	const char *reg_color = C(out, ANSI_BR_BLUE);
	const char *issue_color = C(out, ANSI_YELLOW);
	const char *exec_color = C(out, ANSI_CYAN);
	const char *write_color = C(out, ANSI_BR_GREEN);

	display_separator(out, 61, "Instruction Status");

	// Header row (bold + underlined)
	fprintf(out, "%s%s", bold, C(out, ANSI_UNDER));
	fprintf(out, " %-4s  %-6s  %-4s %-4s %-4s  %6s  %6s  %6s  %6s", "#", "Op", "Dest", "Src1",
		"Src2", "Issue", "ExBeg", "ExEnd", "Write");
	fprintf(out, "%s\n", reset);

	for (int i = 0; i < sim->num_instructions; i++) {
		const Instruction *inst = &sim->instructions[i];

		char dest_buf[16] = "-";
		char src1_buf[16] = "-";
		char src2_buf[16] = "-";
		if (inst->dest >= 0)
			snprintf(dest_buf, sizeof(dest_buf), "F%d", inst->dest);
		if (inst->src1 >= 0)
			snprintf(src1_buf, sizeof(src1_buf), "F%d", inst->src1);
		if (inst->src2 >= 0)
			snprintf(src2_buf, sizeof(src2_buf), "F%d", inst->src2);

		// For LD/SD, show immediate in src1 column
		if (inst->op == OP_LD || inst->op == OP_SD) {
			snprintf(src1_buf, sizeof(src1_buf), "%d", inst->imm);
			if (inst->src1 >= 0)
				snprintf(src2_buf, sizeof(src2_buf), "R%d", inst->src1);
			else
				snprintf(src2_buf, sizeof(src2_buf), "-");
		}

		char issue_s[16] = "", exec_s_s[16] = "", exec_e_s[16] = "", write_s[16] = "";
		if (inst->issue_cycle > 0)
			snprintf(issue_s, sizeof(issue_s), "%d", inst->issue_cycle);
		if (inst->exec_start > 0)
			snprintf(exec_s_s, sizeof(exec_s_s), "%d", inst->exec_start);
		if (inst->exec_end > 0)
			snprintf(exec_e_s, sizeof(exec_e_s), "%d", inst->exec_end);
		if (inst->write_cycle > 0)
			snprintf(write_s, sizeof(write_s), "%d", inst->write_cycle);

		// Row index in dim, opcode in magenta, registers in blue, timings colored.
		fprintf(out,
			" %s%-4d%s  %s%-6s%s  %s%-4s %-4s %-4s%s  "
			"%s%6s%s  %s%6s%s  %s%6s%s  %s%6s%s\n",
			dim, i + 1, reset, op_color, opcode_name(inst->op), reset, reg_color,
			dest_buf, src1_buf, src2_buf, reset, issue_color, issue_s, reset,
			exec_color, exec_s_s, reset, exec_color, exec_e_s, reset, write_color,
			write_s, reset);
	}
}

// ── Reservation Stations ────────────────────────────────────────────────────

void display_rs(FILE *out, const Simulator *sim)
{
	const char *bold = C(out, ANSI_BOLD);
	const char *dim = C(out, ANSI_DIM);
	const char *reset = C(out, ANSI_RESET);
	const char *name_color = C(out, ANSI_BR_BLUE);
	const char *op_color = C(out, ANSI_BR_MAGENTA);
	const char *busy_yes = C(out, ANSI_BR_GREEN);
	const char *busy_no = C(out, ANSI_DIM);
	const char *val_color = C(out, ANSI_CYAN);
	const char *tag_color = C(out, ANSI_YELLOW);

	display_separator(out, 64, "Reservation Stations");

	fprintf(out, "%s%s", bold, C(out, ANSI_UNDER));
	fprintf(out, " %-6s  %-3s  %-6s  %8s  %8s  %4s  %4s  %4s  %4s", "Name", "Occ", "Op", "Vj",
		"Vk", "Qj", "Qk", "Dest", "Cyc");
	fprintf(out, "%s\n", reset);

	for (int i = 0; i < sim->num_rs; i++) {
		const ReservationStation *rs = &sim->rs[i];
		char name[16];
		snprintf(name, sizeof(name), "%s%d", rs_type_prefix(rs->type), rs->unit_id);

		if (!rs->busy) {
			fprintf(out, " %s%-6s%s  %s%-3s%s\n", name_color, name, reset, busy_no,
				"No", reset);
			continue;
		}

		char qj_buf[8], qk_buf[8];
		if (rs->Qj)
			snprintf(qj_buf, sizeof(qj_buf), "#%d", rs->Qj);
		else
			snprintf(qj_buf, sizeof(qj_buf), "-");
		if (rs->Qk)
			snprintf(qk_buf, sizeof(qk_buf), "#%d", rs->Qk);
		else
			snprintf(qk_buf, sizeof(qk_buf), "-");

		fprintf(out,
			" %s%-6s%s  %s%-3s%s  %s%-6s%s  %s%8.2f%s  %s%8.2f%s  "
			"%s%4s%s  %s%4s%s  %s%4d%s  %s%4d%s\n",
			name_color, name, reset, busy_yes, "Yes", reset, op_color,
			opcode_name(rs->op), reset, val_color, rs->Vj, reset, val_color, rs->Vk,
			reset, tag_color, qj_buf, reset, tag_color, qk_buf, reset, dim, rs->dest,
			reset, dim, rs->cycles_left, reset);
	}
}

// ── Reorder Buffer ──────────────────────────────────────────────────────────

// Pick a color for the ROB state.
static const char *rob_state_color(FILE *out, ROBState state)
{
	if (!use_color(out))
		return "";
	switch (state) {
	case ROB_ISSUE:
		return ANSI_YELLOW;
	case ROB_EXECUTING:
		return ANSI_CYAN;
	case ROB_WRITE_RESULT:
		return ANSI_BR_GREEN;
	case ROB_COMMIT:
		return ANSI_BR_MAGENTA;
	default:
		return ANSI_DIM;
	}
}

void display_rob(FILE *out, const Simulator *sim)
{
	const char *bold = C(out, ANSI_BOLD);
	const char *reset = C(out, ANSI_RESET);
	const char *tag_color = C(out, ANSI_BR_BLUE);
	const char *op_color = C(out, ANSI_BR_MAGENTA);
	const char *reg_color = C(out, ANSI_BR_BLUE);
	const char *val_color = C(out, ANSI_CYAN);
	const char *busy_yes = C(out, ANSI_BR_GREEN);

	display_separator(out, 50, "Reorder Buffer");

	fprintf(out, "%s%s", bold, C(out, ANSI_UNDER));
	fprintf(out, " %-4s  %-3s  %-10s  %-6s  %-6s  %10s", "Tag", "Occ", "State", "Op", "Dest",
		"Value");
	fprintf(out, "%s\n", reset);

	for (int i = 0; i < ROB_SIZE; i++) {
		const ROBEntry *e = &sim->rob[i];
		if (!e->busy)
			continue;

		char dest_buf[16] = "Mem";
		if (e->op != OP_SD && e->dest_reg >= 0)
			snprintf(dest_buf, sizeof(dest_buf), "F%d", e->dest_reg);

		const char *state_col = rob_state_color(out, e->state);

		fprintf(out, " %s#%-3d%s  %s%-3s%s  %s%-10s%s  %s%-6s%s  %s%-6s%s  %s%10.2f%s\n",
			tag_color, i + 1, reset, busy_yes, "Yes", reset, state_col,
			rob_state_name(e->state), reset, op_color, opcode_name(e->op), reset,
			reg_color, dest_buf, reset, val_color, e->value, reset);
	}
}

// ── Register Alias Table ────────────────────────────────────────────────────

void display_rat(FILE *out, const Simulator *sim)
{
	const char *bold = C(out, ANSI_BOLD);
	const char *reset = C(out, ANSI_RESET);
	const char *reg_color = C(out, ANSI_BR_BLUE);
	const char *tag_color = C(out, ANSI_YELLOW);
	const char *dim = C(out, ANSI_DIM);

	bool any = false;
	for (int i = 0; i < MAX_FP_REGISTERS; i++) {
		if (sim->rat.Qi[i] != 0) {
			any = true;
			break;
		}
	}
	if (!any) {
		fprintf(out, "\n\n %s(no in-flight register renames)%s\n", dim, reset);
		return;
	}

	display_separator(out, 32, "Register Status (RAT)");

	// First line: register names
	fprintf(out, " %s", bold);
	for (int i = 0; i < MAX_FP_REGISTERS; i++) {
		if (sim->rat.Qi[i] != 0) {
			fprintf(out, " %sF%-3d%s%s", reg_color, i, reset, bold);
		}
	}
	fprintf(out, "%s\n ", reset);
	for (int i = 0; i < MAX_FP_REGISTERS; i++) {
		if (sim->rat.Qi[i] != 0) {
			fprintf(out, " %s#%-3d%s", tag_color, sim->rat.Qi[i], reset);
		}
	}
	fprintf(out, "\n");
}

// ── Full Cycle Display ──────────────────────────────────────────────────────

void display_cycle(FILE *out, const Simulator *sim)
{
	const char *bold = C(out, ANSI_BOLD);
	const char *cyan = C(out, ANSI_BR_CYAN);
	const char *yellow = C(out, ANSI_BR_YELLOW);
	const char *reset = C(out, ANSI_RESET);

	fprintf(out, "%s%s\u2550\u2550\u2550 %sCycle %d%s%s%s \u2550\u2550\u2550%s\n", bold, cyan,
		yellow, sim->cycle, reset, bold, cyan, reset);
	display_instructions(out, sim);
	display_rs(out, sim);
	display_rob(out, sim);
	display_rat(out, sim);
}

// ── Final State ─────────────────────────────────────────────────────────────

void display_final(FILE *out, const Simulator *sim)
{
	const char *bold = C(out, ANSI_BOLD);
	const char *green = C(out, ANSI_BR_GREEN);
	const char *yellow = C(out, ANSI_BR_YELLOW);
	const char *reg_color = C(out, ANSI_BR_BLUE);
	const char *val_color = C(out, ANSI_CYAN);
	const char *dim = C(out, ANSI_DIM);
	const char *reset = C(out, ANSI_RESET);

	fprintf(out, "\n");
	display_separator(out, 78, "SIMULATION COMPLETE");
	fprintf(out, " %sTotal cycles:%s %s%s%d%s\n", bold, reset, bold, green, sim->cycle, reset);
	fprintf(out, " %sInstructions:%s %s%s%d%s\n\n", bold, reset, bold, yellow,
		sim->num_instructions, reset);

	display_instructions(out, sim);

	display_separator(out, 78, "Final Register Values");
	bool any = false;
	for (int i = 0; i < MAX_FP_REGISTERS; i++) {
		if (sim->fp_regs[i] != 0.0) {
			fprintf(out, "  %sF%-2d%s = %s%.4f%s\n", reg_color, i, reset, val_color,
				sim->fp_regs[i], reset);
			any = true;
		}
	}
	if (!any)
		fprintf(out, "  %s(all zero)%s\n", dim, reset);
	fprintf(out, "\n");
}
