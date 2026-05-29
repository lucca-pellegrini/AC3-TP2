// SPDX-License-Identifier: ISC
// SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
// NOTE: Test harness and some unit tests written with help from LLMs

//! Single-instruction correctness tests for each opcode.

const common = @import("common.zig");
const testing = common.testing;
const c = common.c;

const initDefaultSim = common.initDefaultSim;
const makeArithInst = common.makeArithInst;
const makeMemInst = common.makeMemInst;
const addInst = common.addInst;
const runToCompletion = common.runToCompletion;

test "operations: single ADD.D" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 4, 2.0);
    c.sim_set_reg(&sim, 6, 10.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 8, 4, 6));
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(12.0, sim.fp_regs[8], 0.001);
}

test "operations: single SUB.D" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 4, 10.0);
    c.sim_set_reg(&sim, 6, 3.0);
    addInst(&sim, makeArithInst(c.OP_SUBD, 8, 4, 6));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(7.0, sim.fp_regs[8], 0.001);
}

test "operations: single MUL.D" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 4, 3.0);
    c.sim_set_reg(&sim, 6, 7.0);
    addInst(&sim, makeArithInst(c.OP_MULTD, 8, 4, 6));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(21.0, sim.fp_regs[8], 0.001);
}

test "operations: single DIV.D" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 10.0);
    c.sim_set_reg(&sim, 3, 4.0);
    addInst(&sim, makeArithInst(c.OP_DIVD, 1, 2, 3));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(2.5, sim.fp_regs[1], 0.001);
}

test "operations: single L.D" {
    // L.D F6, 34(R2) where R2=100 => F6 = 34+100 = 134 (simulated)
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 100.0);
    addInst(&sim, makeMemInst(c.OP_LD, 6, 34, 2));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(134.0, sim.fp_regs[6], 0.001);
}

test "operations: single S.D completes without deadlock" {
    // S.D F6, 0(R2) -- stores don't write registers
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 6, 42.0);
    c.sim_set_reg(&sim, 2, 100.0);
    addInst(&sim, makeMemInst(c.OP_SD, 6, 0, 2));
    const cycles = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expect(cycles < 20);
    // F6 should remain unchanged (SD doesn't modify registers)
    try testing.expectApproxEqAbs(42.0, sim.fp_regs[6], 0.001);
}

test "operations: divide by zero returns 0" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 10.0);
    c.sim_set_reg(&sim, 3, 0.0);
    addInst(&sim, makeArithInst(c.OP_DIVD, 1, 2, 3));
    _ = runToCompletion(&sim);
    try testing.expect(c.sim_done(&sim));
    try testing.expectApproxEqAbs(0.0, sim.fp_regs[1], 0.001);
}

test "operations: negative operands" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, -5.0);
    c.sim_set_reg(&sim, 3, 3.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(-2.0, sim.fp_regs[1], 0.001);
}

test "operations: SUB.D with negative result" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 3.0);
    c.sim_set_reg(&sim, 3, 10.0);
    addInst(&sim, makeArithInst(c.OP_SUBD, 1, 2, 3));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(-7.0, sim.fp_regs[1], 0.001);
}

test "operations: MUL.D with zero" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 0.0);
    c.sim_set_reg(&sim, 3, 999.0);
    addInst(&sim, makeArithInst(c.OP_MULTD, 1, 2, 3));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(0.0, sim.fp_regs[1], 0.001);
}

test "operations: ADD.D with zero operands" {
    var sim = initDefaultSim();
    // Both regs are 0 by default
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(0.0, sim.fp_regs[1], 0.001);
}

test "operations: self-referencing F1 = F1 + F1" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 1, 5.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 1, 1));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(10.0, sim.fp_regs[1], 0.001);
}

test "operations: floating point precision with small values" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 0.1);
    c.sim_set_reg(&sim, 3, 0.2);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = runToCompletion(&sim);
    try testing.expectApproxEqAbs(0.3, sim.fp_regs[1], 0.0001);
}
