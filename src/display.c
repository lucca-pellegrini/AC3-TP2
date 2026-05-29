/*
 * SPDX-License-Identifier: ISC
 * SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
 * NOTE: Display logic written with help from LLMs
 */

#include "display.h"

#include <stdbool.h>
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
		fprintf(out, "\u2524%s %s%s%s%s %s\u251C%s", reset, bold, cyan, title, reset, dim,
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
	const char *issue_color = C(out, ANSI_GREEN);
	const char *exec_color = C(out, ANSI_CYAN);
	const char *write_color = C(out, ANSI_BR_GREEN);
	const char *new_issue_marker = C(out, ANSI_BR_YELLOW);

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

		// Determine instruction state for styling
		bool is_finished = (inst->write_cycle > 0);
		bool just_issued = (inst->issue_cycle > 0 && inst->issue_cycle == sim->cycle);
		bool in_flight = (inst->issue_cycle > 0 && !is_finished && !just_issued);

		// Style the instruction info columns based on state:
		// - Finished: dim/gray
		// - Just issued (this cycle): bold + magenta, with asterisk
		// - In-flight (issued previously, not finished): yellow
		// - Not yet issued: normal magenta
		const char *idx_color = (just_issued) ? bold : dim;
		const char *curr_op_style = just_issued ? bold : "";
		const char *curr_op_color = is_finished ? dim :
							  (in_flight ? issue_color : op_color);
		const char *curr_reg_color = is_finished ? dim : reg_color;

		// Marker for just-issued instruction
		const char *marker = just_issued ? "*" : " ";
		const char *marker_color = just_issued ? new_issue_marker : "";
		const char *marker_style = just_issued ? bold : "";

		fprintf(out,
			"%s%s%s%s%s%-4d%s  %s%s%-6s%s  %s%-4s %-4s %-4s%s  "
			"%s%6s%s  %s%6s%s  %s%6s%s  %s%6s%s\n",
			marker_style, marker_color, marker, reset, idx_color, i + 1, reset,
			curr_op_style, curr_op_color, opcode_name(inst->op), reset, curr_reg_color,
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
	const char *op_exec_color = C(out, ANSI_BR_MAGENTA);
	const char *busy_yes = C(out, ANSI_BR_GREEN);
	const char *busy_no = C(out, ANSI_DIM);
	const char *val_color = C(out, ANSI_CYAN);
	const char *tag_color = C(out, ANSI_YELLOW);
	const char *cycle_color = C(out, ANSI_BR_CYAN);

	display_separator(out, 64, "Reservation Stations");

	fprintf(out, "%s%s", bold, C(out, ANSI_UNDER));
	fprintf(out, " %-6s  %-4s  %-6s  %8s  %8s  %4s  %4s  %4s", "Name", "Tag", "Op", "Vj", "Vk",
		"Qj", "Qk", "Cyc");
	fprintf(out, "%s\n", reset);

	for (int i = 0; i < sim->num_rs; i++) {
		const ReservationStation *rs = &sim->rs[i];
		char name[16];
		snprintf(name, sizeof(name), "%s%d", rs_type_prefix(rs->type), rs->unit_id);

		if (!rs->busy) {
			fprintf(out, " %s%-6s%s  %s%-4s%s\n", dim, name, reset, busy_no, "#0",
				reset);
			continue;
		}

		// Show ROB tag in Occ column (green, like ROB display)
		char occ_buf[8];
		snprintf(occ_buf, sizeof(occ_buf), "#%d", rs->dest);

		char qj_buf[8], qk_buf[8];
		if (rs->Qj)
			snprintf(qj_buf, sizeof(qj_buf), "#%d", rs->Qj);
		else
			snprintf(qj_buf, sizeof(qj_buf), "-");
		if (rs->Qk)
			snprintf(qk_buf, sizeof(qk_buf), "#%d", rs->Qk);
		else
			snprintf(qk_buf, sizeof(qk_buf), "-");

		// Use bold+yellow for executing instructions, regular magenta for waiting
		const char *curr_op_style = rs->executing ? bold : "";
		const char *curr_op_color = rs->executing ? op_exec_color : op_color;

		// Cycle display: bold cyan = latency (not yet executing), regular cyan = countdown
		int cyc_display;
		const char *cyc_style;
		const char *cyc_color;
		if (rs->executing) {
			// Executing: show countdown in regular cyan
			cyc_display = rs->cycles_left;
			cyc_style = "";
			cyc_color = cycle_color;
		} else {
			// Not yet executing: show latency in bold cyan
			cyc_display = sim->cfg.latency[rs->op];
			cyc_style = bold;
			cyc_color = cycle_color;
		}

		fprintf(out,
			" %s%s%-6s%s  %s%s%-4s%s  %s%s%-6s%s  %s%8.2f%s  "
			"%s%8.2f%s  %s%4s%s  %s%4s%s  %s%s%4d%s\n",
			bold, name_color, name, reset, bold, busy_yes, occ_buf, reset,
			curr_op_style, curr_op_color, opcode_name(rs->op), reset, val_color, rs->Vj,
			reset, val_color, rs->Vk, reset, tag_color, qj_buf, reset, tag_color,
			qk_buf, reset, cyc_style, cyc_color, cyc_display, reset);
	}
}

// ── Reorder Buffer ──────────────────────────────────────────────────────────

// Check if an ROB entry is waiting for CDB (in Write state but not yet written)
// For SD instructions, they don't use CDB so we exclude them
static bool is_waiting_for_cdb(const Simulator *sim, int rob_tag)
{
	const ROBEntry *e = &sim->rob[rob_tag - 1];
	if (!e->busy || e->state != ROB_WRITE_RESULT || e->written)
		return false;
	// SD doesn't use CDB
	if (e->op == OP_SD)
		return false;
	return true;
}

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
	const char *dim = C(out, ANSI_DIM);
	const char *tag_color = C(out, ANSI_BR_BLUE);
	const char *op_color = C(out, ANSI_BR_MAGENTA);
	const char *reg_color = C(out, ANSI_BR_BLUE);
	const char *val_color = C(out, ANSI_CYAN);
	const char *busy_yes = C(out, ANSI_BR_GREEN);
	const char *cdb_wait_color = C(out, ANSI_BR_RED);

	display_separator(out, 50, "Reorder Buffer");

	fprintf(out, "%s%s", bold, C(out, ANSI_UNDER));
	fprintf(out, " %-4s  %-3s  %-10s  %-6s  %-6s  %10s", "Tag", "Occ", "State", "Op", "Dest",
		"Value");
	fprintf(out, "%s\n", reset);

	// First pass: count how many are waiting for CDB
	int cdb_waiters = 0;
	int cdb_waiter_tags[MAX_RS];
	for (int i = 0; i < ROB_SIZE; i++) {
		if (is_waiting_for_cdb(sim, i + 1)) {
			cdb_waiter_tags[cdb_waiters++] = i + 1;
		}
	}

	for (int i = 0; i < ROB_SIZE; i++) {
		const ROBEntry *e = &sim->rob[i];
		if (!e->busy)
			continue;

		char dest_buf[16] = "Mem";
		if (e->op != OP_SD && e->dest_reg >= 0)
			snprintf(dest_buf, sizeof(dest_buf), "F%d", e->dest_reg);

		const char *state_col = rob_state_color(out, e->state);

		// Check if this entry is waiting for CDB (contention)
		bool waiting_cdb = is_waiting_for_cdb(sim, i + 1);

		// Show state with CDB wait indicator
		char state_buf[24];
		if (waiting_cdb && cdb_waiters > 1) {
			// Multiple waiting = contention, show "Write[CDB]" in red
			snprintf(state_buf, sizeof(state_buf), "Write");
			fprintf(out,
				" %s#%-3d%s  %s%-3s%s  %s%s%-5s%s%s[CDB]%s  %s%-6s%s  "
				"%s%-6s%s  %s%10.2f%s\n",
				tag_color, i + 1, reset, busy_yes, "Yes", reset, bold,
				cdb_wait_color, state_buf, reset, cdb_wait_color, reset, op_color,
				opcode_name(e->op), reset, reg_color, dest_buf, reset, val_color,
				e->value, reset);
		} else {
			fprintf(out,
				" %s#%-3d%s  %s%-3s%s  %s%-10s%s  %s%-6s%s  %s%-6s%s  %s%10.2f%s\n",
				tag_color, i + 1, reset, busy_yes, "Yes", reset, state_col,
				rob_state_name(e->state), reset, op_color, opcode_name(e->op),
				reset, reg_color, dest_buf, reset, val_color, e->value, reset);
		}
	}

	// Show CDB contention summary if there are multiple waiters
	if (cdb_waiters > 1) {
		fprintf(out, " %s%sCDB contention:%s", bold, cdb_wait_color, reset);
		for (int i = 0; i < cdb_waiters; i++) {
			fprintf(out, " %s#%d%s", cdb_wait_color, cdb_waiter_tags[i], reset);
		}
		fprintf(out, " %s(%d waiting)%s\n", dim, cdb_waiters, reset);
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
	const char *cyan = C(out, ANSI_BR_CYAN);
	const char *magenta = C(out, ANSI_BR_MAGENTA);
	const char *blue = C(out, ANSI_BR_BLUE);
	const char *reg_color = C(out, ANSI_BR_BLUE);
	const char *val_color = C(out, ANSI_CYAN);
	const char *dim = C(out, ANSI_DIM);
	const char *reset = C(out, ANSI_RESET);

	const SimulatorStats *s = &sim->stats;
	int cycles = sim->cycle > 0 ? sim->cycle : 1; // avoid div by zero

	fprintf(out, "\n");
	display_separator(out, 61, "SIMULATION COMPLETE");
	// ── Instruction Status Table ──
	display_instructions(out, sim);


	// Calculate performance metrics
	double cpi = (sim->num_instructions > 0) ? (double)sim->cycle / sim->num_instructions : 0.0;
	double ipc = (sim->cycle > 0) ? (double)sim->num_instructions / sim->cycle : 0.0;

	// Calculate stall statistics from instruction timing
	int total_issue_stalls = 0; // Stalls waiting to issue (structural hazards)
	int total_exec_stalls = 0; // Stalls waiting for operands (data hazards)
	int total_write_stalls = 0; // Stalls waiting to write result (CDB contention)

	for (int i = 0; i < sim->num_instructions; i++) {
		const Instruction *inst = &sim->instructions[i];
		if (inst->issue_cycle <= 0)
			continue;

		// Issue stalls: cycles between previous issue and this issue - 1
		// (ideal is 1 cycle between issues)
		if (i > 0 && sim->instructions[i - 1].issue_cycle > 0) {
			int issue_gap = inst->issue_cycle - sim->instructions[i - 1].issue_cycle;
			if (issue_gap > 1)
				total_issue_stalls += (issue_gap - 1);
		}

		// Execution stalls: cycles between issue and exec start - 1
		// (waiting for operands due to RAW hazards)
		if (inst->exec_start > 0) {
			int exec_wait = inst->exec_start - inst->issue_cycle;
			if (exec_wait > 1)
				total_exec_stalls += (exec_wait - 1);
		}

		// Write stalls: cycles between exec end and write - 1
		// (CDB contention)
		if (inst->exec_end > 0 && inst->write_cycle > 0) {
			int write_wait = inst->write_cycle - inst->exec_end;
			if (write_wait > 1)
				total_write_stalls += (write_wait - 1);
		}
	}

	int total_stalls = total_issue_stalls + total_exec_stalls + total_write_stalls;

	// ── Performance Metrics ──
	display_separator(out, 61, "Performance Metrics");
	fprintf(out, " %sTotal cycles:%s %s%s%d%s\n", bold, reset, bold, green, sim->cycle, reset);
	fprintf(out, " %sInstructions:%s %s%s%d%s\n", bold, reset, bold, yellow,
		sim->num_instructions, reset);
	fprintf(out, " %sCPI (Cycles/Instruction):%s %s%s%.3f%s\n", bold, reset, bold, cyan, cpi,
		reset);
	fprintf(out, " %sIPC (Instructions/Cycle):%s %s%s%.3f%s\n", bold, reset, bold, cyan, ipc,
		reset);
	fprintf(out, "\n");
	fprintf(out, " %sTotal stalls:%s %s%s%d%s\n", bold, reset, bold, magenta, total_stalls,
		reset);
	fprintf(out, "   %s├─ Issue stalls (structural):%s %s%d%s\n", dim, reset, magenta,
		total_issue_stalls, reset);
	fprintf(out, "   %s├─ Exec stalls (RAW hazards):%s %s%d%s\n", dim, reset, magenta,
		total_exec_stalls, reset);
	fprintf(out, "   %s└─ Write stalls (CDB contention):%s %s%d%s\n", dim, reset, magenta,
		total_write_stalls, reset);

	// ── Functional Unit Utilization ──
	display_separator(out, 61, "Functional Unit Utilization");
	static const char *fu_names[] = { "Adder", "Multiplier", "Load Unit", "Store Unit" };
	for (int t = 0; t < RS_TYPE_COUNT; t++) {
		if (sim->cfg.num_rs[t] == 0)
			continue;
		double busy_pct = 100.0 * s->fu_busy_cycles[t] / cycles;
		double avg_occ = (double)s->fu_total_occupancy[t] / cycles;
		fprintf(out,
			" %s%-12s%s %sbusy:%s %s%5.1f%%%s  %savg:%s %s%.2f%s  %speak:%s %s%d%s\n",
			bold, fu_names[t], reset, dim, reset, cyan, busy_pct, reset, dim, reset,
			cyan, avg_occ, reset, dim, reset, cyan, s->fu_peak_occupancy[t], reset);
	}

	// ── Reservation Station Utilization ──
	display_separator(out, 61, "Reservation Station Utilization");
	static const char *rs_names[] = { "Add RS", "Mult RS", "Load RS", "Store RS" };
	for (int t = 0; t < RS_TYPE_COUNT; t++) {
		if (sim->cfg.num_rs[t] == 0)
			continue;
		double avg_occ = (double)s->rs_total_occupancy[t] / cycles;
		double full_pct = 100.0 * s->rs_full_cycles[t] / cycles;
		fprintf(out,
			" %s%-12s%s %savg:%s %s%.2f%s/%d  %speak:%s %s%d%s  %sfull:%s %s%5.1f%%%s\n",
			bold, rs_names[t], reset, dim, reset, blue, avg_occ, reset,
			sim->cfg.num_rs[t], dim, reset, blue, s->rs_peak_occupancy[t], reset, dim,
			reset, blue, full_pct, reset);
	}

	// ── CDB Utilization ──
	display_separator(out, 61, "CDB (Common Data Bus) Utilization");
	double cdb_busy_pct = 100.0 * s->cdb_busy_cycles / cycles;
	double avg_broadcasts = (double)s->cdb_total_requests / cycles;
	fprintf(out, " %sBusy cycles:%s %s%d%s / %d %s(%.1f%%)%s\n", bold, reset, green,
		s->cdb_busy_cycles, reset, cycles, dim, cdb_busy_pct, reset);
	fprintf(out, " %sTotal broadcasts:%s %s%d%s\n", bold, reset, green, s->cdb_total_requests,
		reset);
	fprintf(out, " %sAvg broadcasts/cycle:%s %s%.3f%s\n", bold, reset, green, avg_broadcasts,
		reset);
	fprintf(out, " %sContention cycles:%s %s%d%s %s(multiple RS wanted CDB)%s\n", bold, reset,
		yellow, s->cdb_contention_cycles, reset, dim, reset);

	// ── ROB Utilization ──
	display_separator(out, 61, "Reorder Buffer (ROB) Utilization");
	double rob_avg = (double)s->rob_total_occupancy / cycles;
	double rob_full_pct = 100.0 * s->rob_full_cycles / cycles;
	fprintf(out, " %sAverage occupancy:%s %s%.2f%s / %d entries\n", bold, reset, cyan, rob_avg,
		reset, ROB_SIZE);
	fprintf(out, " %sPeak occupancy:%s %s%d%s\n", bold, reset, cyan, s->rob_peak_occupancy,
		reset);
	fprintf(out, " %sFull cycles:%s %s%d%s %s(%.1f%%)%s\n", bold, reset, cyan,
		s->rob_full_cycles, reset, dim, rob_full_pct, reset);

	// ── Final Register Values ──
	display_separator(out, 61, "Final Register Values");
	bool any_reg = false;

	// Collect non-zero registers first
	int nz_regs[MAX_FP_REGISTERS];
	int nz_count = 0;
	for (int i = 0; i < MAX_FP_REGISTERS; i++) {
		if (sim->fp_regs[i] != 0.0)
			nz_regs[nz_count++] = i;
	}

	if (nz_count == 0) {
		fprintf(out, "  %s(all zero)%s\n", dim, reset);
	} else {
		any_reg = true;
		// Column layout: "F## = " (6 chars) + value (14 chars) = 20 chars per entry
		// With 64 char max width and 2 char indent, fit 3 columns
		const int num_cols = 3;
		int col = 0;

		for (int j = 0; j < nz_count; j++) {
			int i = nz_regs[j];
			// Build the value string first to measure/pad it
			char val_str[32];
			snprintf(val_str, sizeof(val_str), "%.4f", sim->fp_regs[i]);

			if (col == 0)
				fprintf(out, " ");
			// Fixed width: F## (3) + " = " (3) + value (14) = 20 chars per column
			fprintf(out, " %sF%-2d%s = %s%-14s%s", reg_color, i, reset, val_color,
				val_str, reset);
			col++;
			if (col >= num_cols || j == nz_count - 1) {
				fprintf(out, "\n");
				col = 0;
			}
		}
	}
	(void)any_reg; // suppress unused warning
	fprintf(out, "\n");
}
