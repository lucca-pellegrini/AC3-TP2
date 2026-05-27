// SPDX-License-Identifier: MIT
// Tomasulo Simulator -- Display / Output
//
// Uses Unicode box-drawing characters for clean table rendering.
#include "display.h"

#include <string.h>

// ── Box-drawing helpers ─────────────────────────────────────────────────────

void display_separator(FILE *out, int width, const char *title)
{
	if (title && *title) {
		int tlen = (int)strlen(title);
		int pad = (width - tlen - 4) / 2;
		if (pad < 0)
			pad = 0;
		fprintf(out, "\n");
		for (int i = 0; i < pad; i++)
			fprintf(out, "\u2500");
		fprintf(out, "\u2524 %s \u251C", title);
		for (int i = 0; i < width - pad - tlen - 4; i++)
			fprintf(out, "\u2500");
		fprintf(out, "\n");
	} else {
		fprintf(out, "\n");
		for (int i = 0; i < width; i++)
			fprintf(out, "\u2500");
		fprintf(out, "\n");
	}
}

// ── Instruction Status Table ────────────────────────────────────────────────

void display_instructions(FILE *out, const Simulator *sim)
{
	display_separator(out, 78, "Instruction Status");
	fprintf(out, " %-4s  %-6s  %-4s %-4s %-4s  %6s  %6s  %6s  %6s\n", "#", "Op", "Dest", "Src1",
		"Src2", "Issue", "ExBeg", "ExEnd", "Write");
	fprintf(out, " %-4s  %-6s  %-4s %-4s %-4s  %6s  %6s  %6s  %6s\n", "----", "------", "----",
		"----", "----", "------", "------", "------", "------");

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

		fprintf(out, " %-4d  %-6s  %-4s %-4s %-4s  %6s  %6s  %6s  %6s\n", i + 1,
			opcode_name(inst->op), dest_buf, src1_buf, src2_buf, issue_s, exec_s_s,
			exec_e_s, write_s);
	}
}

// ── Reservation Stations ────────────────────────────────────────────────────

void display_rs(FILE *out, const Simulator *sim)
{
	display_separator(out, 78, "Reservation Stations");
	fprintf(out, " %-6s  %-3s  %-6s  %8s  %8s  %4s  %4s  %4s  %4s\n", "Name", "Occ", "Op", "Vj",
		"Vk", "Qj", "Qk", "Dest", "Cyc");
	fprintf(out, " %-6s  %-3s  %-6s  %8s  %8s  %4s  %4s  %4s  %4s\n", "------", "---", "------",
		"--------", "--------", "----", "----", "----", "----");

	for (int i = 0; i < sim->num_rs; i++) {
		const ReservationStation *rs = &sim->rs[i];
		char name[16];
		snprintf(name, sizeof(name), "%s%d", rs_type_prefix(rs->type), rs->unit_id);

		if (!rs->busy) {
			fprintf(out, " %-6s  %-3s\n", name, "No");
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

		fprintf(out, " %-6s  %-3s  %-6s  %8.2f  %8.2f  %4s  %4s  %4d  %4d\n", name, "Yes",
			opcode_name(rs->op), rs->Vj, rs->Vk, qj_buf, qk_buf, rs->dest,
			rs->cycles_left);
	}
}

// ── Reorder Buffer ──────────────────────────────────────────────────────────

void display_rob(FILE *out, const Simulator *sim)
{
	display_separator(out, 78, "Reorder Buffer");
	fprintf(out, " %-4s  %-3s  %-10s  %-6s  %-6s  %10s\n", "Tag", "Occ", "State", "Op", "Dest",
		"Value");
	fprintf(out, " %-4s  %-3s  %-10s  %-6s  %-6s  %10s\n", "----", "---", "----------",
		"------", "------", "----------");

	// Walk the ROB from head to tail
	for (int i = 0; i < ROB_SIZE; i++) {
		const ROBEntry *e = &sim->rob[i];
		if (!e->busy)
			continue;

		char dest_buf[16] = "Mem";
		if (e->op != OP_SD && e->dest_reg >= 0)
			snprintf(dest_buf, sizeof(dest_buf), "F%d", e->dest_reg);

		fprintf(out, " %-4d  %-3s  %-10s  %-6s  %-6s  %10.2f\n", i + 1, "Yes",
			rob_state_name(e->state), opcode_name(e->op), dest_buf, e->value);
	}
}

// ── Register Alias Table ────────────────────────────────────────────────────

void display_rat(FILE *out, const Simulator *sim)
{
	display_separator(out, 78, "Register Status (RAT)");

	// First line: register names
	fprintf(out, " ");
	for (int i = 0; i < MAX_FP_REGISTERS; i++) {
		if (sim->rat.Qi[i] != 0) {
			fprintf(out, " F%-3d", i);
		}
	}
	fprintf(out, "\n ");
	for (int i = 0; i < MAX_FP_REGISTERS; i++) {
		if (sim->rat.Qi[i] != 0) {
			fprintf(out, " #%-3d", sim->rat.Qi[i]);
		}
	}
	fprintf(out, "\n");
}

// ── Full Cycle Display ──────────────────────────────────────────────────────

void display_cycle(FILE *out, const Simulator *sim)
{
	fprintf(out, "\n\u2550\u2550\u2550 Cycle %d \u2550\u2550\u2550\n", sim->cycle);
	display_instructions(out, sim);
	display_rs(out, sim);
	display_rob(out, sim);
	display_rat(out, sim);
}

// ── Final State ─────────────────────────────────────────────────────────────

void display_final(FILE *out, const Simulator *sim)
{
	display_separator(out, 78, "SIMULATION COMPLETE");
	fprintf(out, " Total cycles: %d\n", sim->cycle);
	fprintf(out, " Instructions: %d\n\n", sim->num_instructions);

	display_instructions(out, sim);

	display_separator(out, 78, "Final Register Values");
	bool any = false;
	for (int i = 0; i < MAX_FP_REGISTERS; i++) {
		if (sim->fp_regs[i] != 0.0) {
			fprintf(out, "  F%-2d = %.4f\n", i, sim->fp_regs[i]);
			any = true;
		}
	}
	if (!any)
		fprintf(out, "  (all zero)\n");
	fprintf(out, "\n");
}
