/*
 * SPDX-License-Identifier: ISC
 * SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
 * SPDX-FileCopyrightText: Copyright © 2026 Paulo Dimas Junior <paulo.junior.1478361@sga.pucminas.br>
 * SPDX-FileCopyrightText: Copyright © 2026 Amanda Canizela Guimarães <amanda.canizela@gmail.com>
 * SPDX-FileCopyrightText: Copyright © 2026 Ariel Inácio Jordão <arielijordao@gmail.com>
 * SPDX-FileCopyrightText: Copyright © 2026 Pedro Vitor Andrade <pedrovitor0826@gmail.com>
 */

#pragma once

#include <stdbool.h>
#include <stdint.h>

/// Configuration /////////////////////////////////////////////////////////////

#define MAX_INSTRUCTIONS 64
#define MAX_RS 16
#define MAX_FP_REGISTERS 32
#define MAX_NAME_LEN 16
#define ROB_SIZE 32 // FIXME: ROB size ought to be configurable, but I'm lazy!

/// Data types and their related functions ////////////////////////////////////

// Supported opcodes
typedef enum opcode {
	OP_ADDD, // Double-precision floating-point addition
	OP_SUBD, // Double-precision floating-point subtraction
	OP_MULTD, // Double-precision floating-point multiplication
	OP_DIVD, // Double-precision floating-point division
	OP_LD, // Load a double-precision floating-point word
	OP_SD, // Store a double-precision floating-point word
	OP_COUNT, // Sentinel value (invalid opcode)
} Opcode;

// Get opcode name
const char *opcode_name(Opcode op);
// Get opcode from name
Opcode opcode_from_str(const char *s);

// Internal representation of an instruction
typedef struct instruction {
	Opcode op;
	int dest; // Destination register index, or value source for SD
	int src1; // Source register 1, or base register for load/store
	int src2; // Source register 2
	int imm; // Immediate, or offset for load/store

	// Timing bookkeeping, filled during simulation
	int issue_cycle; // Cycle when the instruction was issued
	int exec_start; // Cycle when the instruction started executing
	int exec_end; // Cycle when the instruction finished executing
	int write_cycle; // Cycle when the instruction broadcast to CDB
} Instruction;

// Reservation station types
typedef enum rs_type {
	RS_ADD,
	RS_MULT,
	RS_LOAD,
	RS_STORE,
	RS_TYPE_COUNT,
} RSType;

// Internal representation of a reservation station (RS)
typedef struct reservation_station {
	bool busy; // Whether there's an instruction in
	Opcode op; // Opcode of the instruction that's in
	double Vj, Vk; // Values of the operands
	int Qj, Qk; // Tag of values producers (0 when ready)
	int dest; // Reoder buffer tag of the destination
	int A; // Address offset for load/store
	int cycles_left; // How many cycles are left for the execution
	bool executing; // Whether we're already executing
	double result; // What the result of the operation is
	int instr_idx; // Index into the instruction array (input queue)
	RSType type; // What type of station we are (this doesn't change)
	int unit_id; // Which station of that type we are (e.g.: Add1, St2, etc.)
} ReservationStation;

// Empty Reservation Station without losing the type and numeric id
void rs_clear(ReservationStation *rs);

// Internal representation of the Register Alias Table (RAT)
typedef struct register_status {
	// Array of ROB tags that write to tag of that index (0 means committed)
	int Qi[MAX_FP_REGISTERS];
} RegisterStatus;

// Possible states of a Reoder Buffer (ROB) entry
typedef enum rob_state {
	ROB_ISSUE,
	ROB_EXECUTING,
	ROB_WRITE_RESULT,
	ROB_COMMIT,
} ROBState;

// Internal representation of a Reoder Buffer (ROB) entry
typedef struct rob_entry {
	bool busy; // Whether there's an instruction in
	ROBState state; // State of the instruction
	Opcode op; // Opcode of the instruction
	int dest_reg; // Where we're going to write when done
	double value; // Value to be written (result of operation)
	bool addr_ready; // Whether the effective address for LD/SD is computed
	double addr; // What the effective address for LD/SD is
	bool written; // Whether we've broadcast to CDB (or SD write)
} ROBEntry;

// Simulator configuration.
typedef struct tomasulo_config {
	int latency[OP_COUNT]; // How many execution cycles are taken per opcode
	int num_rs[RS_TYPE_COUNT]; // Number of reservation stations of each type
} TomasuloConfig;

// Return default configuration struct
TomasuloConfig config_default(void);

// Structure to keep track of simulation statistics
typedef struct simulator_stats {
	// Functional Unit Utilization (indexed by RSType: ADD, MULT, LOAD, STORE)
	int fu_busy_cycles[RS_TYPE_COUNT]; // cycles each FU type was busy
	int fu_peak_occupancy[RS_TYPE_COUNT]; // max concurrent busy units per type
	int fu_total_occupancy[RS_TYPE_COUNT]; // sum of busy units each cycle (for avg)

	// Reservation Station Utilization (indexed by RSType)
	int rs_peak_occupancy[RS_TYPE_COUNT]; // max busy RS entries per type
	int rs_total_occupancy[RS_TYPE_COUNT]; // sum of busy RS entries (for avg)
	int rs_full_cycles[RS_TYPE_COUNT]; // cycles where RS type was completely full

	// CDB Utilization
	int cdb_busy_cycles; // cycles where CDB was used
	int cdb_total_requests; // total CDB broadcast requests (successful)
	int cdb_contention_cycles; // cycles where multiple RS wanted CDB

	// ROB Utilization
	int rob_peak_occupancy; // max busy ROB entries
	int rob_total_occupancy; // sum of busy ROB entries (for avg)
	int rob_full_cycles; // cycles where ROB was full
} SimulatorStats;

// Structure to represent simulator state
typedef struct simulator {
	TomasuloConfig cfg;

	Instruction instructions[MAX_INSTRUCTIONS]; // Instruction queue
	int num_instructions; // Number of instructions in queue
	int next_issue; // Index of the next instruction to issue

	ReservationStation rs[MAX_RS]; // Reservation stations list
	int num_rs; // Number of RS entries allocated

	double fp_regs[MAX_FP_REGISTERS]; // Architectural register file
	RegisterStatus rat; // Register Alias Table (RAT)

	ROBEntry rob[ROB_SIZE]; // Reoder Buffer (ROB)
	int rob_head; // Index of first ROB entry
	int rob_tail; // Index of last ROB entry

	int cycle; // Clock cycles counter
	int committed; // Counter of committed instructions

	// CDB: single-bus, one result per cycle
	bool cdb_valid; // Whether there's something being broadcast on the CDB
	int cdb_tag; // What tag's result is being broadcast
	double cdb_value; // What the value being broadcast is

	// Simulator statistics (collected during simulation)
	SimulatorStats stats;

	// Simulation name (merely for display purposes)
	const char *input_filename;
} Simulator;

/// Public simulator API //////////////////////////////////////////////////////

// Initialize the simulator with a given config. Must be called before
// adding instructions.
void sim_init(Simulator *sim, const TomasuloConfig *cfg);

// Set initial register values.  reg_idx must be in [0, MAX_FP_REGISTERS).
void sim_set_reg(Simulator *sim, int reg_idx, double value);

// Add an instruction to the queue. Returns false if full.
bool sim_add_instruction(Simulator *sim, Instruction inst);

// Run a single step of the simulator. Returns `false` if finished.
// Returns `true` if the simulation is still running.
bool sim_step(Simulator *sim);

// Run the entire simulation, up to the configured cycle limit.
// Returns total cycles.
int sim_run(Simulator *sim, int max_cycles);

/// Queries (for display / testing) ///////////////////////////////////////////

// Returns whether the simulation has finished.
bool sim_done(const Simulator *sim);
// Map Reorder State name to string
const char *rob_state_name(ROBState s);
// Map Reservation Station type to its prefix
const char *rs_type_prefix(RSType t);
