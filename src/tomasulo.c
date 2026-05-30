/*
 * SPDX-License-Identifier: ISC
 * SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
 * SPDX-FileCopyrightText: Copyright © 2026 Paulo Dimas Junior <paulo.junior.1478361@sga.pucminas.br>
 * SPDX-FileCopyrightText: Copyright © 2026 Amanda Canizela Guimarães <amanda.canizela@gmail.com>
 * SPDX-FileCopyrightText: Copyright © 2026 Ariel Inácio Jordão <arielijordao@gmail.com>
 * SPDX-FileCopyrightText: Copyright © 2026 Pedro Vitor Andrade <pedrovitor0826@gmail.com>
 */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include "tomasulo.h"

#include <assert.h>
#include <ctype.h>
#include <string.h>
#include <strings.h>
#include <math.h>

/// Configuration /////////////////////////////////////////////////////////////

// Return default configuration struct
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

/// Initialization and Setup //////////////////////////////////////////////////

// Initialize the simulator with the given config
void sim_init(Simulator *sim, const TomasuloConfig *cfg)
{
	memset(sim, 0, sizeof(*sim));
	sim->cfg = *cfg;

	// Set-up all reservation stations
	for (int type = 0; type < RS_TYPE_COUNT; ++type) {
		for (int id = 0; id < cfg->num_rs[type] && sim->num_rs < MAX_RS;
		     ++id, ++sim->num_rs) {
			sim->rs[sim->num_rs].type = (RSType)type;
			sim->rs[sim->num_rs].unit_id = id + 1; // IDs are per-type
		}
	}
}

// Put the given value in the specified register
void sim_set_reg(Simulator *sim, int reg_idx, double value)
{
	if (reg_idx >= 0 && reg_idx < MAX_FP_REGISTERS)
		sim->fp_regs[reg_idx] = value;
}

// Add an instruction to the instruction queue
bool sim_add_instruction(Simulator *sim, Instruction inst)
{
	if (sim->num_instructions >= MAX_INSTRUCTIONS)
		return false;

	// Zero its counters
	inst.issue_cycle = 0;
	inst.exec_start = 0;
	inst.exec_end = 0;
	inst.write_cycle = 0;

	// Add to the array
	sim->instructions[sim->num_instructions++] = inst;

	return true;
}

/// Helper functions //////////////////////////////////////////////////////////

// Get opcode name
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

// Get opcode from name
Opcode opcode_from_str(const char *s)
{
	if (!s)
		return OP_COUNT;

	char buf[MAX_NAME_LEN + 1];
	size_t opcode_len = 0;

	// Set to uppercase, and strip '.' and '_'
	for (size_t i = 0; s[i] != '\0' && opcode_len < sizeof(buf) - 1; ++i) {
		unsigned char ch = (unsigned char)s[i];
		if (ch == '.' || ch == '_')
			continue;
		buf[opcode_len++] = (char)toupper(ch);
	}
	buf[opcode_len] = '\0';

	// Inverted list mapping name to opcode
	static const struct {
		const char *name;
		Opcode op;
	} map[] = {
		{ "ADDD", OP_ADDD },   { "SUBD", OP_SUBD }, { "MULD", OP_MULTD },
		{ "MULTD", OP_MULTD }, { "DIVD", OP_DIVD }, { "LD", OP_LD },
		{ "SD", OP_SD },
	};
	for (size_t i = 0; i < sizeof(map) / sizeof(map[0]); ++i)
		if (strcmp(buf, map[i].name) == 0)
			return map[i].op;
	return OP_COUNT; // Return illegal opcode if none matched
}

// Map state name to string
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

// Get the Reservation Station type for the given opcode
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

// Map Reservation Station type to its prefix
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

/// Reoder Buffer (ROB) and Reservation Stations (RS) helpers /////////////////

// Empty Reservation Station without losing the type and numeric id.
void rs_clear(ReservationStation *rs)
{
	RSType saved_type = rs->type;
	int saved_id = rs->unit_id;
	memset(rs, 0, sizeof(*rs));
	rs->type = saved_type;
	rs->unit_id = saved_id;
}

// Find a free RS of the given type. Returns null if there aren't any.
static ReservationStation *rs_find_free(Simulator *sim, RSType type)
{
	for (int i = 0; i < sim->num_rs; ++i)
		if (sim->rs[i].type == type && !sim->rs[i].busy)
			return &sim->rs[i];
	return nullptr;
}

// Returns if all slots are full
static bool rob_full(const Simulator *sim)
{
	return sim->rob[sim->rob_tail].busy;
}

// Allocate a ROB entry and return tag (0 means failure)
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

	int tag = sim->rob_tail + 1; // +1 because 0 means failure
	sim->rob_tail = (sim->rob_tail + 1) % ROB_SIZE;
	return tag;
}

// Get the ROB entry at the given tag
static ROBEntry *rob_get(Simulator *sim, int tag)
{
	return &sim->rob[tag - 1];
}

/// Actually stage and execute instructions ///////////////////////////////////

// Helper to read a source operand for instruction issue. Uses rename logic.
static void read_operand(Simulator *sim, int reg_idx, double *Vx, int *Qx)
{
	// If the register is invalid, we bail.
	assert(0 <= reg_idx && reg_idx < MAX_FP_REGISTERS);

	// Check the Register Alias Table (RAT) for a pending producer.
	int producer_tag = sim->rat.Qi[reg_idx];
	if (producer_tag != 0 && rob_get(sim, producer_tag)->busy) {
		ROBEntry *producer = rob_get(sim, producer_tag);

		// If the producer has already written, we just forward the value
		if (producer->state == ROB_WRITE_RESULT || producer->state == ROB_COMMIT) {
			*Vx = producer->value;
			*Qx = 0; // No need to wait!
		} else {
			*Vx = 0.0; // Reset unavailable value
			*Qx = producer_tag; // Wait for this ROB tag on CDB
		}
	} else {
		// If there's no pending producer, the register already has the value
		*Vx = sim->fp_regs[reg_idx]; // Get from register.
		*Qx = 0; // No need to wait!
	}
}

// Helper to stage instructions for issue.
static void stage_issue(Simulator *sim)
{
	// If we're finished or the ROB is full, don't do anything
	if (sim->next_issue >= sim->num_instructions || rob_full(sim))
		return;

	Instruction *inst = &sim->instructions[sim->next_issue];
	RSType needed = rs_type_for_op(inst->op);
	ReservationStation *rs = rs_find_free(sim, needed);
	if (!rs) // Structural hazard: no free Reservation Stations
		return;

	// Allocate a new tag on the ROB
	int tag = rob_alloc(sim, inst);
	if (tag == 0)
		return;

	assert(0 <= tag && tag < MAX_FP_REGISTERS);

	// Put instruction in the reservation station
	rs_clear(rs);
	rs->busy = true;
	rs->op = inst->op;
	rs->dest = tag;
	rs->instr_idx = sim->next_issue;

	switch (inst->op) {
	case OP_ADDD:
	case OP_SUBD:
	case OP_MULTD:
	case OP_DIVD:
		read_operand(sim, inst->src1, &rs->Vj, &rs->Qj);
		read_operand(sim, inst->src2, &rs->Vk, &rs->Qk);
		break;
	case OP_LD:
		assert(inst->src1 >= 0);
		rs->A = inst->imm;
		read_operand(sim, inst->src1, &rs->Vj, &rs->Qj);
		rs->Qk = 0; // LD has no second source
		break;
	case OP_SD:
		assert(inst->src1 >= 0);
		rs->A = inst->imm;
		read_operand(sim, inst->dest, &rs->Vj, &rs->Qj); // Value to store
		read_operand(sim, inst->src1, &rs->Vk, &rs->Qk); // Base address register
		break;
	default:
		assert(false);
	}

	// Update RAT (SD doesn't write)
	if (inst->op != OP_SD)
		sim->rat.Qi[inst->dest] = tag;

	inst->issue_cycle = sim->cycle;
	++sim->next_issue;
}

// Compute the result of the operation at the given Reservation Station.
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
		// Let's just ignore division by 0 becaus we don't really care
		return (rs->Vk != 0.0) ? (rs->Vj / rs->Vk) : 0.0;
	case OP_LD:
		// No time to implement actual memory, just return address
		return rs->A + rs->Vj;
	case OP_SD:
		return NAN;
	default:
		assert(false);
	}
}

// Helper to stage instructions for execution.
static void stage_execute(Simulator *sim)
{
	// Iterate over all reservation stations.
	for (int i = 0; i < sim->num_rs; ++i) {
		ReservationStation *rs = &sim->rs[i];
		if (!rs->busy)
			continue; // Skip empty ones

		ROBEntry *rob = rob_get(sim, rs->dest);
		Instruction *inst = &sim->instructions[rs->instr_idx];

		// Can't start issue and execute on the same cycle.
		// Also don't execute if we've already executed (🧠)!
		if (inst->issue_cycle == sim->cycle || rob->state == ROB_WRITE_RESULT)
			continue;

		switch (rs->op) {
		case OP_ADDD:
		case OP_SUBD:
		case OP_MULTD:
		case OP_DIVD:
		case OP_LD:
			// If we're waiting for someone, don't do anything yet.
			if (rs->Qj != 0 || rs->Qk != 0)
				continue;

			// If not executing, go to executing stage.
			if (!rs->executing) {
				rs->executing = true;
				rs->cycles_left = sim->cfg.latency[rs->op];
				rob->state = ROB_EXECUTING;
				inst->exec_start = sim->cycle;
			}

			// Count down cycles.
			--rs->cycles_left;

			// If finished, go to writing stage.
			if (rs->cycles_left == 0) {
				rs->result = compute_result(rs);
				rob->value = rs->result;
				rob->state = ROB_WRITE_RESULT;
				inst->exec_end = sim->cycle;
			}

			break;
		case OP_SD:
			// If we're waiting for base register, don't do anything yet.
			if (rs->Qk != 0)
				continue;

			// Compute effective address (only once!)
			if (!rob->addr_ready) {
				rob->addr = rs->A + rs->Vk;
				rob->addr_ready = true;
			}

			// Also wait for the value we're going to store.
			if (rs->Qj != 0)
				continue;

			// If not executing, go to executing stage.
			if (!rs->executing) {
				rs->executing = true;
				rs->cycles_left = sim->cfg.latency[rs->op];
				rob->state = ROB_EXECUTING;
				inst->exec_start = sim->cycle;
			}

			// Count down cycles.
			--rs->cycles_left;

			// If finished, go to writing stage.
			if (rs->cycles_left == 0) {
				// [❓] Is Vj the value that will be written to memory?
				// I'm confused about this...
				rob->value = rs->Vj;
				rob->state = ROB_WRITE_RESULT;
				inst->exec_end = sim->cycle;
			}

			break;
		default:
			assert(false);
		}
	}
}

// Helper to broadcast instructions results to the CDB.
static void stage_write_result(Simulator *sim)
{
	// Flag to allow through a single broadcast.
	sim->cdb_valid = false;

	// Iterate over non-empty reservation stations, as long as CDB empty.
	for (int i = 0; i < sim->num_rs && !sim->cdb_valid; ++i) {
		ReservationStation *rs = &sim->rs[i];
		if (!rs->busy)
			continue;

		ROBEntry *rob = rob_get(sim, rs->dest);
		Instruction *inst = &sim->instructions[rs->instr_idx];

		// Can't finish execution and write on the same cycle.
		// Also don't write if we're not in the writing stage.
		if (inst->exec_end == sim->cycle || rob->state != ROB_WRITE_RESULT)
			continue;

		// HACK: SD doesn't broadcast on CDB, but we don't want to deal
		// with the complexity of having a heterogenous pipeline.
		// We just skip so as to not use up the CDB “slot”.
		// This is me coping (it's so over 😭):
		if (rs->op == OP_SD) {
			inst->write_cycle = sim->cycle;
			rob->written = true;
			rs_clear(rs);
			continue;
		}

		sim->cdb_valid = true; // Our broadcast “slot” is occupied.
		sim->cdb_tag = rs->dest;
		sim->cdb_value = rob->value;
		inst->write_cycle = sim->cycle;

		// Broadcast to all waiting reservation stations.
		// I'm sure there's a better way of doing this (inverted lists? 🤔),
		// but it's way past my bedtime and I just want to get this over with!
		for (int j = 0; j < sim->num_rs; ++j) {
			ReservationStation *other = &sim->rs[j];

			// Don't broadcast to empty RSs (nor to ourselves).
			if (!other->busy || j == i)
				continue;

			if (other->Qj == rs->dest) {
				other->Vj = rob->value;
				other->Qj = 0; // No longer waiting.
			}
			if (other->Qk == rs->dest) {
				other->Vk = rob->value;
				other->Qk = 0; // No longer waiting.
			}
		}

		rob->written = true; // Set so that the commit stage deletes us.
		rs_clear(rs); // Free the RS.
	}
}

// Helper to commit the oldest instruction in the ROB
static void stage_commit(Simulator *sim)
{
	// If the ROB is empty, there's nothing to commit!
	ROBEntry *head = &sim->rob[sim->rob_head];
	if (!head->busy)
		return;

	// Only commit if the instruction has already broadcast its result.
	if (!head->written)
		return;

	int tag = sim->rob_head + 1; // Tag is 1-based (0 means invalid tag).
	assert(head->dest_reg >= 0 && head->dest_reg < MAX_FP_REGISTERS); // Just in case lol

	// Update the actual physical registers (unless we're a store).
	if (head->op != OP_SD) {
		sim->fp_regs[head->dest_reg] = head->value;

		// Clear RAT entry if we're the most recent writer.
		if (sim->rat.Qi[head->dest_reg] == tag)
			sim->rat.Qi[head->dest_reg] = 0;
	}

	// Free the ROB entry
	head->busy = false;
	head->state = ROB_COMMIT;
	sim->rob_head = (sim->rob_head + 1) % ROB_SIZE; // Circular-buffer type thing
	++sim->committed;
}

// Helper to collect statistics for the current cycle
static void collect_stats(Simulator *sim)
{
	SimulatorStats *s = &sim->stats;

	// We're going to count busy RS and executing FUs per type.
	int rs_busy[RS_TYPE_COUNT] = { 0 };
	int fu_busy[RS_TYPE_COUNT] = { 0 };

	for (int i = 0; i < sim->num_rs; ++i) {
		ReservationStation *rs = &sim->rs[i];
		if (rs->busy) {
			++rs_busy[rs->type];
			if (rs->executing)
				++fu_busy[rs->type];
		}
	}

	// Update reservation stations statistics
	for (int type = 0; type < RS_TYPE_COUNT; ++type) {
		s->rs_total_occupancy[type] += rs_busy[type];
		if (rs_busy[type] > s->rs_peak_occupancy[type])
			s->rs_peak_occupancy[type] = rs_busy[type];
		if (rs_busy[type] == sim->cfg.num_rs[type] && sim->cfg.num_rs[type] > 0)
			++s->rs_full_cycles[type];

		// Functional units statistics
		s->fu_total_occupancy[type] += fu_busy[type];
		if (fu_busy[type] > 0)
			++s->fu_busy_cycles[type];
		if (fu_busy[type] > s->fu_peak_occupancy[type])
			s->fu_peak_occupancy[type] = fu_busy[type];
	}

	// Count how many RS want to broadcast in this cycle (CDB contention)
	int cdb_requests = 0;
	for (int i = 0; i < sim->num_rs; ++i) {
		ReservationStation *rs = &sim->rs[i];
		if (!rs->busy)
			continue;
		ROBEntry *rob = rob_get(sim, rs->dest);
		Instruction *inst = &sim->instructions[rs->instr_idx];
		// Check if RS wants CDB
		if (rob->state == ROB_WRITE_RESULT && rs->op != OP_SD &&
		    inst->exec_end != sim->cycle)
			++cdb_requests;
	}
	if (cdb_requests > 1)
		++s->cdb_contention_cycles;
	if (sim->cdb_valid) {
		++s->cdb_busy_cycles;
		++s->cdb_total_requests;
	}

	// Reorder buffer stats
	int rob_busy = 0;
	for (int i = 0; i < ROB_SIZE; ++i)
		if (sim->rob[i].busy)
			++rob_busy;
	s->rob_total_occupancy += rob_busy;
	if (rob_busy > s->rob_peak_occupancy)
		s->rob_peak_occupancy = rob_busy;
	if (rob_busy == ROB_SIZE)
		++s->rob_full_cycles;
}

/// Public API ////////////////////////////////////////////////////////////////

// Run a single step of the simulator. Returns `false` if finished.
bool sim_step(Simulator *sim)
{
	if (sim_done(sim))
		return false;

	++sim->cycle;

	// Process back-to-front to prevent same-cycle advancement!
	stage_commit(sim);
	stage_write_result(sim);
	stage_execute(sim);
	stage_issue(sim);

	// Collect statistics.
	collect_stats(sim);

	return !sim_done(sim);
}

// Run the entire simulation, up to the configured cycle limit.
int sim_run(Simulator *sim, int max_cycles)
{
	while (!sim_done(sim) && sim->cycle < max_cycles)
		sim_step(sim);
	return sim->cycle;
}

// Returns whether the simulation has finished.
bool sim_done(const Simulator *sim)
{
	return sim->committed >= sim->num_instructions && sim->next_issue >= sim->num_instructions;
}
