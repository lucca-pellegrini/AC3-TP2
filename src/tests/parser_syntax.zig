// SPDX-License-Identifier: ISC
// SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
// NOTE: Test harness and some unit tests written with help from LLMs

//! Parser syntax tests for the flex/bison front-end.
//! Covers block keywords, brace/comma/semicolon separators, '=' assignments,
//! comment styles, opcode/key spelling normalisation, memory operand forms,
//! and error cases.

const common = @import("common.zig");
const testing = common.testing;
const c = common.c;

const parseSource = common.parseSource;
const freeParse = common.freeParse;
const parseExpectFail = common.parseExpectFail;
const runToCompletion = common.runToCompletion;

// ═══════════════════════════════════════════════════════════════════════════
// Smoke: minimal program
// ═══════════════════════════════════════════════════════════════════════════

test "parser_syntax: minimal program (only instructions block)" {
    const src =
        \\instructions {
        \\    ADDD F1 F2 F3
        \\}
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 1), p.sim.num_instructions);
    try testing.expectEqual(@as(c_uint, c.OP_ADDD), p.sim.instructions[0].op);
    try testing.expectEqual(@as(c_int, 1), p.sim.instructions[0].dest);
    try testing.expectEqual(@as(c_int, 2), p.sim.instructions[0].src1);
    try testing.expectEqual(@as(c_int, 3), p.sim.instructions[0].src2);
}

test "parser_syntax: empty instructions block parses" {
    const src = "instructions {}";
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 0), p.sim.num_instructions);
}

test "parser_syntax: empty file is accepted (defaults apply)" {
    const src = "";
    const p = try parseSource(src);
    defer freeParse(p);
    // Defaults from config_default() should be in effect.
    try testing.expectEqual(@as(c_int, 2), p.cfg.latency[c.OP_ADDD]);
    try testing.expectEqual(@as(c_int, 0), p.sim.num_instructions);
}

// ═══════════════════════════════════════════════════════════════════════════
// Block keyword: case + punctuation flexibility
// ═══════════════════════════════════════════════════════════════════════════

test "parser_syntax: block keywords are case-insensitive" {
    const src =
        \\CYCLES { add.d = 3 }
        \\Units { mult.d = 2 }
        \\Registers { F1 = 1.5 }
        \\INSTRUCTIONS { ADDD F0 F0 F0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 3), p.cfg.latency[c.OP_ADDD]);
    try testing.expectEqual(@as(c_int, 2), p.cfg.num_rs[c.RS_MULT]);
    try testing.expectApproxEqAbs(1.5, p.sim.fp_regs[1], 0.001);
    try testing.expectEqual(@as(c_int, 1), p.sim.num_instructions);
}

test "parser_syntax: reg_init is an alias for registers" {
    const src =
        \\reg_init { F4 = 2.5 }
        \\instructions { ADDD F0 F0 F0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectApproxEqAbs(2.5, p.sim.fp_regs[4], 0.001);
}

test "parser_syntax: mem_units is an alias for units" {
    const src =
        \\mem_units { l.d = 4, s.d = 2 }
        \\instructions { ADDD F0 F0 F0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 4), p.cfg.num_rs[c.RS_LOAD]);
    try testing.expectEqual(@as(c_int, 2), p.cfg.num_rs[c.RS_STORE]);
}

// ═══════════════════════════════════════════════════════════════════════════
// Opcode/key spelling normalisation
// ═══════════════════════════════════════════════════════════════════════════

test "parser_syntax: opcode keys accept '.', '_', or no separator" {
    const src =
        \\cycles {
        \\    add.d  = 2
        \\    SUB_D  = 3
        \\    MultD  = 5
        \\    div.d  = 7
        \\    L_D    = 11
        \\    sd     = 13
        \\}
        \\instructions { ADDD F0 F0 F0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 2), p.cfg.latency[c.OP_ADDD]);
    try testing.expectEqual(@as(c_int, 3), p.cfg.latency[c.OP_SUBD]);
    try testing.expectEqual(@as(c_int, 5), p.cfg.latency[c.OP_MULTD]);
    try testing.expectEqual(@as(c_int, 7), p.cfg.latency[c.OP_DIVD]);
    try testing.expectEqual(@as(c_int, 11), p.cfg.latency[c.OP_LD]);
    try testing.expectEqual(@as(c_int, 13), p.cfg.latency[c.OP_SD]);
}

test "parser_syntax: instruction opcodes accept mixed spellings" {
    const src =
        \\instructions {
        \\    add.d  F1 F2 F3
        \\    SUB_D  F4 F2 F3
        \\    MultD  F5 F2 F3
        \\    div_d  F6 F2 F3
        \\}
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 4), p.sim.num_instructions);
    try testing.expectEqual(@as(c_uint, c.OP_ADDD), p.sim.instructions[0].op);
    try testing.expectEqual(@as(c_uint, c.OP_SUBD), p.sim.instructions[1].op);
    try testing.expectEqual(@as(c_uint, c.OP_MULTD), p.sim.instructions[2].op);
    try testing.expectEqual(@as(c_uint, c.OP_DIVD), p.sim.instructions[3].op);
}

// ═══════════════════════════════════════════════════════════════════════════
// Block ordering
// ═══════════════════════════════════════════════════════════════════════════

test "parser_syntax: block order is flexible (instructions first)" {
    const src =
        \\instructions { ADDD F1 F2 F3 }
        \\cycles { add.d = 5 }
        \\registers { F2 = 7.0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 1), p.sim.num_instructions);
    try testing.expectEqual(@as(c_int, 5), p.cfg.latency[c.OP_ADDD]);
    // Note: registers block after instructions still sets the register.
    try testing.expectApproxEqAbs(7.0, p.sim.fp_regs[2], 0.001);
}

test "parser_syntax: same block can appear twice (later wins)" {
    const src =
        \\cycles { add.d = 2 }
        \\cycles { add.d = 9 }
        \\instructions { ADDD F0 F0 F0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 9), p.cfg.latency[c.OP_ADDD]);
}

// ═══════════════════════════════════════════════════════════════════════════
// Separators (commas, semicolons, newlines)
// ═══════════════════════════════════════════════════════════════════════════

test "parser_syntax: items can be comma-separated on one line" {
    const src =
        \\cycles { add.d = 2, mult.d = 4, div.d = 8 }
        \\units  { add.d = 1, mult.d = 1 }
        \\instructions { ADDD F0 F0 F0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 2), p.cfg.latency[c.OP_ADDD]);
    try testing.expectEqual(@as(c_int, 4), p.cfg.latency[c.OP_MULTD]);
    try testing.expectEqual(@as(c_int, 8), p.cfg.latency[c.OP_DIVD]);
}

test "parser_syntax: semicolons work as item separators" {
    const src =
        \\cycles { add.d = 2; mult.d = 4; }
        \\instructions { ADDD F0 F0 F0; }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 2), p.cfg.latency[c.OP_ADDD]);
    try testing.expectEqual(@as(c_int, 4), p.cfg.latency[c.OP_MULTD]);
    try testing.expectEqual(@as(c_int, 1), p.sim.num_instructions);
}

test "parser_syntax: extra commas and whitespace are tolerated" {
    const src =
        \\cycles {,,, add.d = 2,,, mult.d = 4 ,,,}
        \\instructions {  ADDD  F0  F0  F0  }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 2), p.cfg.latency[c.OP_ADDD]);
}

// ═══════════════════════════════════════════════════════════════════════════
// Comments
// ═══════════════════════════════════════════════════════════════════════════

test "parser_syntax: '#' comments are stripped" {
    const src =
        \\# top-level comment
        \\cycles {
        \\    add.d = 2  # trailing comment
        \\    # comment in the middle
        \\    mult.d = 4
        \\}
        \\instructions { ADDD F0 F0 F0 }  # comment after block
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 2), p.cfg.latency[c.OP_ADDD]);
    try testing.expectEqual(@as(c_int, 4), p.cfg.latency[c.OP_MULTD]);
}

test "parser_syntax: '//' comments are stripped" {
    const src =
        \\// like C
        \\cycles { add.d = 2 } // trailing
        \\instructions { ADDD F0 F0 F0 // comment inside block
        \\}
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 2), p.cfg.latency[c.OP_ADDD]);
    try testing.expectEqual(@as(c_int, 1), p.sim.num_instructions);
}

// ═══════════════════════════════════════════════════════════════════════════
// Memory operand forms
// ═══════════════════════════════════════════════════════════════════════════

test "parser_syntax: L.D with bare 'offset base' form" {
    const src =
        \\registers { R1 = 100 }
        \\instructions { L.D F2 8 R1 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    const inst = p.sim.instructions[0];
    try testing.expectEqual(@as(c_uint, c.OP_LD), inst.op);
    try testing.expectEqual(@as(c_int, 2), inst.dest);
    try testing.expectEqual(@as(c_int, 1), inst.src1); // R1
    try testing.expectEqual(@as(c_int, 8), inst.imm);
}

test "parser_syntax: L.D with C-like 'offset(base)' form" {
    const src =
        \\registers { R1 = 100 }
        \\instructions { L.D F2 8(R1) }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    const inst = p.sim.instructions[0];
    try testing.expectEqual(@as(c_uint, c.OP_LD), inst.op);
    try testing.expectEqual(@as(c_int, 2), inst.dest);
    try testing.expectEqual(@as(c_int, 1), inst.src1);
    try testing.expectEqual(@as(c_int, 8), inst.imm);
}

test "parser_syntax: both LD forms produce identical instruction" {
    const src1 =
        \\instructions { L.D F2 16 R1 }
    ;
    const src2 =
        \\instructions { L.D F2 16(R1) }
    ;
    const p1 = try parseSource(src1);
    defer freeParse(p1);
    const p2 = try parseSource(src2);
    defer freeParse(p2);
    try testing.expectEqual(p1.sim.instructions[0].op, p2.sim.instructions[0].op);
    try testing.expectEqual(p1.sim.instructions[0].dest, p2.sim.instructions[0].dest);
    try testing.expectEqual(p1.sim.instructions[0].src1, p2.sim.instructions[0].src1);
    try testing.expectEqual(p1.sim.instructions[0].imm, p2.sim.instructions[0].imm);
}

test "parser_syntax: S.D with offset(base) form" {
    const src =
        \\instructions { S.D F8 0(R3) }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    const inst = p.sim.instructions[0];
    try testing.expectEqual(@as(c_uint, c.OP_SD), inst.op);
    try testing.expectEqual(@as(c_int, 8), inst.dest);
    try testing.expectEqual(@as(c_int, 3), inst.src1);
    try testing.expectEqual(@as(c_int, 0), inst.imm);
}

test "parser_syntax: negative offset on memory instruction" {
    const src =
        \\instructions { L.D F2 -16(R1) }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, -16), p.sim.instructions[0].imm);
}

// ═══════════════════════════════════════════════════════════════════════════
// Register init: numeric forms
// ═══════════════════════════════════════════════════════════════════════════

test "parser_syntax: register init accepts int, float and exponent" {
    const src =
        \\registers {
        \\    F1 = 42
        \\    F2 = 3.14
        \\    F3 = -2.5
        \\    F4 = 1.5e2
        \\    F5 = -1e-3
        \\}
        \\instructions { ADDD F0 F0 F0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectApproxEqAbs(42.0, p.sim.fp_regs[1], 0.001);
    try testing.expectApproxEqAbs(3.14, p.sim.fp_regs[2], 0.001);
    try testing.expectApproxEqAbs(-2.5, p.sim.fp_regs[3], 0.001);
    try testing.expectApproxEqAbs(150.0, p.sim.fp_regs[4], 0.001);
    try testing.expectApproxEqAbs(-0.001, p.sim.fp_regs[5], 1e-6);
}

test "parser_syntax: F and R registers share the same index space" {
    // R1 and F1 should refer to the same physical register.
    const src =
        \\registers { R1 = 7.0 }
        \\instructions { ADDD F0 F0 F0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectApproxEqAbs(7.0, p.sim.fp_regs[1], 0.001);
}

// ═══════════════════════════════════════════════════════════════════════════
// End-to-end: parse + run
// ═══════════════════════════════════════════════════════════════════════════

test "parser_syntax: full program parses and simulates correctly" {
    const src =
        \\cycles { add.d = 2, mult.d = 4 }
        \\units  { add.d = 1, mult.d = 1 }
        \\registers { F4 = 2.0, F6 = 10.0 }
        \\instructions {
        \\    ADDD  F8  F4 F6     # F8  = 12
        \\    MULTD F10 F8 F8     # F10 = 144
        \\}
    ;
    var p = try parseSource(src);
    defer freeParse(p);
    _ = runToCompletion(&p.sim);
    try testing.expect(c.sim_done(&p.sim));
    try testing.expectApproxEqAbs(12.0, p.sim.fp_regs[8], 0.001);
    try testing.expectApproxEqAbs(144.0, p.sim.fp_regs[10], 0.001);
}

// ═══════════════════════════════════════════════════════════════════════════
// Error cases
// ═══════════════════════════════════════════════════════════════════════════

test "parser_syntax: unknown opcode rejected" {
    try parseExpectFail(
        \\instructions { FROB F1 F2 F3 }
    );
}

test "parser_syntax: unknown block keyword rejected" {
    try parseExpectFail(
        \\widgets { foo = 1 }
        \\instructions { ADDD F0 F0 F0 }
    );
}

test "parser_syntax: missing closing brace rejected" {
    try parseExpectFail(
        \\cycles { add.d = 2
        \\instructions { ADDD F0 F0 F0 }
    );
}

test "parser_syntax: register out of range rejected" {
    try parseExpectFail(
        \\instructions { ADDD F99 F0 F0 }
    );
}

test "parser_syntax: arithmetic opcode with offset form rejected" {
    try parseExpectFail(
        \\instructions { ADDD F1 0(R2) }
    );
}

test "parser_syntax: memory opcode with three register form rejected" {
    try parseExpectFail(
        \\instructions { L.D F1 F2 F3 }
    );
}

test "parser_syntax: missing '=' in config item rejected" {
    try parseExpectFail(
        \\cycles { add.d 2 }
        \\instructions { ADDD F0 F0 F0 }
    );
}

test "parser_syntax: zero cycles value rejected" {
    try parseExpectFail(
        \\cycles { add.d = 0 }
        \\instructions { ADDD F0 F0 F0 }
    );
}

test "parser_syntax: negative cycles value rejected" {
    try parseExpectFail(
        \\cycles { mult.d = -5 }
        \\instructions { ADDD F0 F0 F0 }
    );
}

test "parser_syntax: zero units value rejected" {
    try parseExpectFail(
        \\units { add.d = 0 }
        \\instructions { ADDD F0 F0 F0 }
    );
}

test "parser_syntax: negative units value rejected" {
    try parseExpectFail(
        \\units { l.d = -2 }
        \\instructions { ADDD F0 F0 F0 }
    );
}

test "parser_syntax: positive cycles and units accepted" {
    const src =
        \\cycles { add.d = 1, mult.d = 10 }
        \\units { add.d = 1, mult.d = 2 }
        \\instructions { ADDD F0 F0 F0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 1), p.cfg.latency[c.OP_ADDD]);
    try testing.expectEqual(@as(c_int, 10), p.cfg.latency[c.OP_MULTD]);
    try testing.expectEqual(@as(c_int, 1), p.cfg.num_rs[c.RS_ADD]);
    try testing.expectEqual(@as(c_int, 2), p.cfg.num_rs[c.RS_MULT]);
}

// ═══════════════════════════════════════════════════════════════════════════
// Instruction limit tests (too many instructions)
// ═══════════════════════════════════════════════════════════════════════════

test "parser_syntax: too many instructions rejected (REG REG REG form)" {
    // Generate MAX_INSTRUCTIONS + 1 arithmetic instructions
    comptime var src: []const u8 = "instructions {\n";
    inline for (0..c.MAX_INSTRUCTIONS + 1) |_| {
        src = src ++ "    ADDD F0 F0 F0\n";
    }
    src = src ++ "}";
    try parseExpectFail(src);
}

test "parser_syntax: too many instructions rejected (REG INT REG form)" {
    // Generate MAX_INSTRUCTIONS + 1 load instructions with bare offset
    comptime var src: []const u8 = "instructions {\n";
    inline for (0..c.MAX_INSTRUCTIONS + 1) |_| {
        src = src ++ "    L.D F0 0 R0\n";
    }
    src = src ++ "}";
    try parseExpectFail(src);
}

test "parser_syntax: too many instructions rejected (REG INT(REG) form)" {
    // Generate MAX_INSTRUCTIONS + 1 load instructions with offset(base)
    comptime var src: []const u8 = "instructions {\n";
    inline for (0..c.MAX_INSTRUCTIONS + 1) |_| {
        src = src ++ "    L.D F0 0(R0)\n";
    }
    src = src ++ "}";
    try parseExpectFail(src);
}

// ═══════════════════════════════════════════════════════════════════════════
// Arithmetic opcodes with immediate offset rejected
// ═══════════════════════════════════════════════════════════════════════════

test "parser_syntax: SUBD with INT REG form rejected" {
    try parseExpectFail(
        \\instructions { SUBD F1 0 R2 }
    );
}

test "parser_syntax: MULTD with INT REG form rejected" {
    try parseExpectFail(
        \\instructions { MULTD F1 0 R2 }
    );
}

test "parser_syntax: DIVD with INT REG form rejected" {
    try parseExpectFail(
        \\instructions { DIVD F1 0 R2 }
    );
}

// ═══════════════════════════════════════════════════════════════════════════
// Lexer error cases
// ═══════════════════════════════════════════════════════════════════════════

test "parser_syntax: unexpected character rejected" {
    try parseExpectFail(
        \\instructions { @ }
    );
}

test "parser_syntax: unexpected dollar sign rejected" {
    try parseExpectFail(
        \\instructions { ADDD $F0 F0 F0 }
    );
}

test "parser_syntax: long identifier is truncated and still works" {
    // An identifier longer than MAX_NAME_LEN (16) should be truncated but
    // still match if the first 16 characters (minus punctuation) match a
    // known keyword. "INSTRUCTIONS" is 12 chars, so add extra padding.
    const src =
        \\INSTRUCTIONS________________extra { ADDD F0 F0 F0 }
    ;
    const p = try parseSource(src);
    defer freeParse(p);
    try testing.expectEqual(@as(c_int, 1), p.sim.num_instructions);
}
