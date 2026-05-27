// SPDX-License-Identifier: MIT
// Tomasulo Algorithm Simulator -- Core implementation
//
// Pipeline stages per cycle (processed back-to-front):
//   1. Commit    -- retire instructions from ROB head
//   2. Write     -- CDB broadcast, free RS, mark ROB "written"
//   3. Execute   -- decrement counters, compute results
//   4. Issue     -- dispatch next instruction to RS + ROB
//
// Timing constraints:
//   - Issue and Execute cannot happen on the same cycle for the same instr
//   - Execute-complete and Write cannot happen on the same cycle
//   - Write and Commit cannot happen on the same cycle
//   - Single CDB: at most 1 write-result per cycle
//
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include "tomasulo.h"

#include <math.h>
#include <string.h>
#include <strings.h>

// ── Helpers ─────────────────────────────────────────────────────────────────

const char *opcode_name(Opcode op)
{
	static const char *names[] = {
		[OP_ADDD] = "ADD.D", [OP_SUBD] = "SUB.D", [OP_MULTD] = "MUL.D",
		[OP_DIVD] = "DIV.D", [OP_LD] = "L.D",	  [OP_SD] = "S.D",
	};
	if (op >= 0 && op < OP_COUNT)
		return names[op];
	return "???";
}

Opcode opcode_from_str(const char *s)
{
	struct {
		const char *name;
		Opcode op;
	} map[] = {
		{ "ADDD", OP_ADDD },  { "ADD.D", OP_ADDD },  { "SUBD", OP_SUBD },
		{ "SUB.D", OP_SUBD }, { "MULTD", OP_MULTD }, { "MUL.D", OP_MULTD },
		{ "DIVD", OP_DIVD },  { "DIV.D", OP_DIVD },  { "LD", OP_LD },
		{ "L.D", OP_LD },     { "SD", OP_SD },	     { "S.D", OP_SD },
	};
	for (size_t i = 0; i < sizeof(map) / sizeof(map[0]); i++) {
		if (strcasecmp(s, map[i].name) == 0)
			return map[i].op;
	}
	return OP_COUNT; // invalid
}

const char *rob_state_name(ROBState s)
{
	switch (s) {
	case ROB_ISSUE:
		return "Issue";
	case ROB_EXECUTING:
		return "Executing";
	case ROB_WRITE_RESULT:
		return "Write";
	case ROB_COMMIT:
		return "Commit";
	}
	return "?";
}

const char *rs_type_prefix(RSType t)
{
	switch (t) {
	case RS_ADD:
		return "Add";
	case RS_MULT:
		return "Mul";
	case RS_LOAD:
		return "Ld";
	case RS_STORE:
		return "St";
	default:
		return "??";
	}
}

void rs_clear(ReservationStation *rs)
{
	RSType saved_type = rs->type;
	int saved_id = rs->unit_id;
	memset(rs, 0, sizeof(*rs));
	rs->type = saved_type;
	rs->unit_id = saved_id;
}

// ── Configuration ───────────────────────────────────────────────────────────

TomasuloConfig config_default(void)
{
	return (TomasuloConfig){
		.latency = {
			[OP_ADDD]  = 2,
			[OP_SUBD]  = 2,
			[OP_MULTD] = 10,
			[OP_DIVD]  = 40,
			[OP_LD]    = 2,
			[OP_SD]    = 2,
		},
		.num_rs = {
			[RS_ADD]   = 3,
			[RS_MULT]  = 2,
			[RS_LOAD]  = 3,
			[RS_STORE] = 3,
		},
	};
}

// ── Simulator Init ──────────────────────────────────────────────────────────

void sim_init(Simulator *sim, const TomasuloConfig *cfg)
{
	memset(sim, 0, sizeof(*sim));
	sim->cfg = *cfg;

	// Allocate reservation stations
	int idx = 0;
	for (int t = 0; t < RS_TYPE_COUNT; t++) {
		for (int i = 0; i < cfg->num_rs[t] && idx < MAX_RS; i++) {
			sim->rs[idx].type = (RSType)t;
			sim->rs[idx].unit_id = i + 1;
			idx++;
		}
	}
	sim->num_rs = idx;
}

void sim_set_reg(Simulator *sim, int reg_idx, double value)
{
	if (reg_idx >= 0 && reg_idx < MAX_FP_REGISTERS)
		sim->fp_regs[reg_idx] = value;
}

bool sim_add_instruction(Simulator *sim, Instruction inst)
{
	if (sim->num_instructions >= MAX_INSTRUCTIONS)
		return false;
	inst.issue_cycle = 0;
	inst.exec_start = 0;
	inst.exec_end = 0;
	inst.write_cycle = 0;
	sim->instructions[sim->num_instructions++] = inst;
	return true;
}

// ── ROB helpers ─────────────────────────────────────────────────────────────

static bool rob_full(const Simulator *sim)
{
	return sim->rob[sim->rob_tail].busy;
}

// Allocate a ROB entry, returns 1-based tag (0 = failure)
static int rob_alloc(Simulator *sim, const Instruction *inst)
{
	if (rob_full(sim))
		return 0;

	ROBEntry *e = &sim->rob[sim->rob_tail];
	memset(e, 0, sizeof(*e));
	e->busy = true;
	e->state = ROB_ISSUE;
	e->op = inst->op;
	e->dest_reg = inst->dest;

	int tag = sim->rob_tail + 1; // 1-based
	sim->rob_tail = (sim->rob_tail + 1) % ROB_SIZE;
	return tag;
}

static ROBEntry *rob_get(Simulator *sim, int tag)
{
	return &sim->rob[tag - 1];
}

// ── RS type for a given opcode ──────────────────────────────────────────────

static RSType rs_type_for_op(Opcode op)
{
	switch (op) {
	case OP_ADDD:
	case OP_SUBD:
		return RS_ADD;
	case OP_MULTD:
	case OP_DIVD:
		return RS_MULT;
	case OP_LD:
		return RS_LOAD;
	case OP_SD:
		return RS_STORE;
	default:
		return RS_ADD;
	}
}

// Find a free RS of the given type.  Returns NULL if none available.
static ReservationStation *rs_find_free(Simulator *sim, RSType type)
{
	for (int i = 0; i < sim->num_rs; i++) {
		if (sim->rs[i].type == type && !sim->rs[i].busy)
			return &sim->rs[i];
	}
	return nullptr;
}

// ── Operand read helper ─────────────────────────────────────────────────────
// Reads a source register, checking the RAT for pending producers.
// Sets Vx and Qx on the reservation station.

static void read_operand(Simulator *sim, int reg_idx, double *Vx, int *Qx)
{
	if (reg_idx < 0 || reg_idx >= MAX_FP_REGISTERS) {
		*Vx = 0.0;
		*Qx = 0;
		return;
	}

	int q = sim->rat.Qi[reg_idx];
	if (q != 0 && rob_get(sim, q)->busy) {
		ROBEntry *producer = rob_get(sim, q);
		if (producer->state == ROB_WRITE_RESULT || producer->state == ROB_COMMIT) {
			// Value already available in ROB
			*Vx = producer->value;
			*Qx = 0;
		} else {
			// Still waiting
			*Qx = q;
		}
	} else {
		// Value is in the register file
		*Vx = sim->fp_regs[reg_idx];
		*Qx = 0;
	}
}

// ── Stage: Issue ────────────────────────────────────────────────────────────

static void stage_issue(Simulator *sim)
{
	if (sim->next_issue >= sim->num_instructions)
		return;
	if (rob_full(sim))
		return;

	Instruction *inst = &sim->instructions[sim->next_issue];
	RSType needed = rs_type_for_op(inst->op);
	ReservationStation *rs = rs_find_free(sim, needed);
	if (!rs)
		return; // structural stall

	int tag = rob_alloc(sim, inst);
	if (tag == 0)
		return;

	rs_clear(rs);
	rs->busy = true;
	rs->op = inst->op;
	rs->dest = tag;
	rs->instr_idx = sim->next_issue;

	bool is_arith = (inst->op == OP_ADDD || inst->op == OP_SUBD || inst->op == OP_MULTD ||
			 inst->op == OP_DIVD);

	if (is_arith) {
		read_operand(sim, inst->src1, &rs->Vj, &rs->Qj);
		read_operand(sim, inst->src2, &rs->Vk, &rs->Qk);
	} else if (inst->op == OP_LD) {
		rs->A = inst->imm;
		if (inst->src1 >= 0)
			read_operand(sim, inst->src1, &rs->Vj, &rs->Qj);
		rs->Qk = 0; // LD has no second source
	} else if (inst->op == OP_SD) {
		rs->A = inst->imm;
		// Vj/Qj = value to store (from inst->dest which is the value register)
		read_operand(sim, inst->dest, &rs->Vj, &rs->Qj);
		// Vk/Qk = base address register
		if (inst->src1 >= 0)
			read_operand(sim, inst->src1, &rs->Vk, &rs->Qk);
	}

	// Update RAT (SD doesn't write a register)
	if (inst->op != OP_SD && inst->dest >= 0 && inst->dest < MAX_FP_REGISTERS)
		sim->rat.Qi[inst->dest] = tag;

	inst->issue_cycle = sim->cycle;
	sim->next_issue++;
}

// ── Stage: Execute ──────────────────────────────────────────────────────────

static double compute_result(const ReservationStation *rs)
{
	switch (rs->op) {
	case OP_ADDD:
		return rs->Vj + rs->Vk;
	case OP_SUBD:
		return rs->Vj - rs->Vk;
	case OP_MULTD:
		return rs->Vj * rs->Vk;
	case OP_DIVD:
		return (rs->Vk != 0.0) ? (rs->Vj / rs->Vk) : 0.0;
	case OP_LD:
		return rs->A + rs->Vj; // simulated: address = offset + base
	case OP_SD:
		return rs->A + rs->Vk; // effective address
	default:
		return 0.0;
	}
}

static void stage_execute(Simulator *sim)
{
	for (int i = 0; i < sim->num_rs; i++) {
		ReservationStation *rs = &sim->rs[i];
		if (!rs->busy)
			continue;

		ROBEntry *rob = rob_get(sim, rs->dest);
		Instruction *inst = &sim->instructions[rs->instr_idx];

		// Can't start executing on the same cycle as issue
		if (inst->issue_cycle == sim->cycle)
			continue;

		// Already done executing -- waiting for write
		if (rob->state == ROB_WRITE_RESULT)
			continue;

		bool is_arith = (rs->op == OP_ADDD || rs->op == OP_SUBD || rs->op == OP_MULTD ||
				 rs->op == OP_DIVD);

		if (is_arith || rs->op == OP_LD) {
			if (rs->Qj != 0 || rs->Qk != 0)
				continue;

			if (!rs->executing) {
				rs->executing = true;
				rs->cycles_left = sim->cfg.latency[rs->op];
				rob->state = ROB_EXECUTING;
				inst->exec_start = sim->cycle;
			}

			rs->cycles_left--;

			if (rs->cycles_left == 0) {
				rs->result = compute_result(rs);
				rob->value = rs->result;
				rob->state = ROB_WRITE_RESULT;
				inst->exec_end = sim->cycle;
			}
		} else if (rs->op == OP_SD) {
			// Store: two phases
			// Phase 1: compute address (needs Qk = base)
			if (rs->Qk == 0 && !rob->addr_ready) {
				rob->addr = rs->A + rs->Vk;
				rob->addr_ready = true;
			}

			if (!rs->executing && rob->addr_ready) {
				rs->executing = true;
				rs->cycles_left = sim->cfg.latency[rs->op];
				rob->state = ROB_EXECUTING;
				inst->exec_start = sim->cycle;
			}

			if (rs->executing) {
				rs->cycles_left--;
				// Phase 2: when addr ready AND value ready AND cycles done
				if (rs->cycles_left <= 0 && rs->Qj == 0 && rob->addr_ready) {
					rob->value = rs->Vj;
					rob->state = ROB_WRITE_RESULT;
					inst->exec_end = sim->cycle;
				}
			}
		}
	}
}

// ── Stage: Write Result (CDB Broadcast) ────────────────────────────────────

static void stage_write_result(Simulator *sim)
{
	sim->cdb_valid = false;

	for (int i = 0; i < sim->num_rs; i++) {
		ReservationStation *rs = &sim->rs[i];
		if (!rs->busy)
			continue;

		ROBEntry *rob = rob_get(sim, rs->dest);
		Instruction *inst = &sim->instructions[rs->instr_idx];

		if (rob->state != ROB_WRITE_RESULT)
			continue;

		// Can't write on the same cycle execution finishes
		if (inst->exec_end == sim->cycle)
			continue;

		// SD doesn't broadcast on CDB, but still needs to free RS
		if (rs->op == OP_SD) {
			inst->write_cycle = sim->cycle;
			rob->written = true;
			rs_clear(rs);
			continue; // SD doesn't use CDB slot
		}

		// Single CDB: only 1 broadcast per cycle
		if (sim->cdb_valid)
			continue;

		sim->cdb_valid = true;
		sim->cdb_tag = rs->dest;
		sim->cdb_value = rob->value;
		inst->write_cycle = sim->cycle;

		// Broadcast to all waiting RSs
		for (int j = 0; j < sim->num_rs; j++) {
			ReservationStation *other = &sim->rs[j];
			if (!other->busy || j == i)
				continue;
			if (other->Qj == rs->dest) {
				other->Vj = rob->value;
				other->Qj = 0;
			}
			if (other->Qk == rs->dest) {
				other->Vk = rob->value;
				other->Qk = 0;
			}
		}

		// Mark as written -- commit can now retire this entry
		rob->written = true;

		// Free the RS
		rs_clear(rs);
		break; // single CDB
	}
}

// ── Stage: Commit ───────────────────────────────────────────────────────────

static void stage_commit(Simulator *sim)
{
	ROBEntry *head = &sim->rob[sim->rob_head];
	if (!head->busy)
		return;

	// Only commit after the CDB broadcast has happened (written == true).
	// This ensures we don't commit before write_result runs.
	if (!head->written)
		return;

	int tag = sim->rob_head + 1;

	if (head->op != OP_SD) {
		if (head->dest_reg >= 0 && head->dest_reg < MAX_FP_REGISTERS) {
			sim->fp_regs[head->dest_reg] = head->value;
			if (sim->rat.Qi[head->dest_reg] == tag)
				sim->rat.Qi[head->dest_reg] = 0;
		}
	}

	head->busy = false;
	head->state = ROB_COMMIT;
	sim->rob_head = (sim->rob_head + 1) % ROB_SIZE;
	sim->committed++;
}

// ── Public API ──────────────────────────────────────────────────────────────

bool sim_step(Simulator *sim)
{
	if (sim_done(sim))
		return false;

	sim->cycle++;

	// Process back-to-front to prevent same-cycle advancement
	stage_commit(sim);
	stage_write_result(sim);
	stage_execute(sim);
	stage_issue(sim);

	return !sim_done(sim);
}

int sim_run(Simulator *sim, int max_cycles)
{
	while (!sim_done(sim) && sim->cycle < max_cycles)
		sim_step(sim);
	return sim->cycle;
}

bool sim_done(const Simulator *sim)
{
	return sim->committed >= sim->num_instructions && sim->next_issue >= sim->num_instructions;
}
