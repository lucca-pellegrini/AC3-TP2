// SPDX-License-Identifier: MIT
// Tomasulo Algorithm Simulator -- Core data structures and API
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

// ── Limits ──────────────────────────────────────────────────────────────────

#define MAX_INSTRUCTIONS 64
#define MAX_RS 16
#define MAX_FP_REGISTERS 32
#define MAX_NAME_LEN 16
#define ROB_SIZE 32

// ── Opcodes ─────────────────────────────────────────────────────────────────

typedef enum {
	OP_ADDD,
	OP_SUBD,
	OP_MULTD,
	OP_DIVD,
	OP_LD,
	OP_SD,
	OP_COUNT, // sentinel
} Opcode;

const char *opcode_name(Opcode op);
Opcode opcode_from_str(const char *s);

// ── Instruction ─────────────────────────────────────────────────────────────

typedef struct {
	Opcode op;
	int dest; // destination register index (Fx), or value source for SD
	int src1; // source register 1 / base register for LD/SD
	int src2; // source register 2
	int imm; // immediate/offset for LD/SD

	// Timing bookkeeping (filled during simulation)
	int issue_cycle;
	int exec_start;
	int exec_end;
	int write_cycle;
} Instruction;

// ── Reservation Station ─────────────────────────────────────────────────────

typedef enum {
	RS_ADD,
	RS_MULT,
	RS_LOAD,
	RS_STORE,
	RS_TYPE_COUNT,
} RSType;

typedef struct {
	bool busy;
	Opcode op;
	double Vj, Vk;
	int Qj, Qk; // 0 = value ready, >0 = ROB tag of producer
	int dest; // ROB tag
	double A; // address/offset for LD/SD
	int cycles_left;
	bool executing;
	double result;
	int instr_idx; // index into instruction array
	RSType type;
	int unit_id; // e.g., Add1 = 1, Add2 = 2 ...
} ReservationStation;

void rs_clear(ReservationStation *rs);

// ── Register Alias Table (RAT) ─────────────────────────────────────────────

typedef struct {
	int Qi[MAX_FP_REGISTERS]; // 0 = value committed / ready
} RegisterStatus;

// ── Reorder Buffer Entry ────────────────────────────────────────────────────

typedef enum {
	ROB_ISSUE,
	ROB_EXECUTING,
	ROB_WRITE_RESULT,
	ROB_COMMIT,
} ROBState;

typedef struct {
	bool busy;
	ROBState state;
	Opcode op;
	int dest_reg;
	double value;
	bool addr_ready;
	double addr;
	bool written; // true after CDB broadcast (or SD write), ready to commit
} ROBEntry;

// ── Configuration ───────────────────────────────────────────────────────────

typedef struct {
	int latency[OP_COUNT]; // execution cycles per opcode
	int num_rs[RS_TYPE_COUNT]; // number of reservation stations per type
} TomasuloConfig;

// Provide sensible defaults
TomasuloConfig config_default(void);

// ── Simulator State ─────────────────────────────────────────────────────────

typedef struct {
	TomasuloConfig cfg;

	Instruction instructions[MAX_INSTRUCTIONS];
	int num_instructions;
	int next_issue; // index of next instruction to issue

	ReservationStation rs[MAX_RS];
	int num_rs; // total RS entries allocated

	double fp_regs[MAX_FP_REGISTERS]; // architectural register file
	RegisterStatus rat;

	ROBEntry rob[ROB_SIZE];
	int rob_head;
	int rob_tail;

	int cycle;
	int committed;

	// CDB: single-bus, one result per cycle
	bool cdb_valid;
	int cdb_tag;
	double cdb_value;
} Simulator;

// ── Simulator API ───────────────────────────────────────────────────────────

// Initialize the simulator with a given config. Must be called before
// adding instructions.
void sim_init(Simulator *sim, const TomasuloConfig *cfg);

// Set initial register values.  reg_idx must be in [0, MAX_FP_REGISTERS).
void sim_set_reg(Simulator *sim, int reg_idx, double value);

// Add an instruction to the queue.  Returns false if full.
bool sim_add_instruction(Simulator *sim, Instruction inst);

// Execute one clock cycle (commit -> write -> execute -> issue).
// Returns true if the simulation is still running.
bool sim_step(Simulator *sim);

// Run the full simulation until completion (or max_cycles exceeded).
// Returns total cycles.
int sim_run(Simulator *sim, int max_cycles);

// ── Queries (for display / testing) ─────────────────────────────────────────

bool sim_done(const Simulator *sim);
const char *rob_state_name(ROBState s);
const char *rs_type_prefix(RSType t);
