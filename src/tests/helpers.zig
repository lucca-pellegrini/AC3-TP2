// SPDX-License-Identifier: ISC
// SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
// NOTE: Test harness and some unit tests written with help from LLMs

//! Tests for helper functions: opcode_name, opcode_from_str, rob_state_name,
//! rs_type_prefix, rs_clear, config_default.

const common = @import("common.zig");
const std = common.std;
const testing = common.testing;
const c = common.c;

test "helpers: opcode_name returns correct strings" {
    try testing.expectEqualStrings("ADD.D", std.mem.span(c.opcode_name(c.OP_ADDD)));
    try testing.expectEqualStrings("SUB.D", std.mem.span(c.opcode_name(c.OP_SUBD)));
    try testing.expectEqualStrings("MUL.D", std.mem.span(c.opcode_name(c.OP_MULTD)));
    try testing.expectEqualStrings("DIV.D", std.mem.span(c.opcode_name(c.OP_DIVD)));
    try testing.expectEqualStrings("L.D", std.mem.span(c.opcode_name(c.OP_LD)));
    try testing.expectEqualStrings("S.D", std.mem.span(c.opcode_name(c.OP_SD)));
}

test "helpers: opcode_name returns ??? for invalid" {
    try testing.expectEqualStrings("???", std.mem.span(c.opcode_name(c.OP_COUNT)));
    try testing.expectEqualStrings("???", std.mem.span(c.opcode_name(99)));
}

test "helpers: opcode_from_str round-trip all variants" {
    const cases = [_]struct { name: [*:0]const u8, expected: c.Opcode }{
        .{ .name = "ADDD", .expected = c.OP_ADDD },
        .{ .name = "ADD.D", .expected = c.OP_ADDD },
        .{ .name = "addd", .expected = c.OP_ADDD }, // case-insensitive
        .{ .name = "add.d", .expected = c.OP_ADDD },
        .{ .name = "SUBD", .expected = c.OP_SUBD },
        .{ .name = "SUB.D", .expected = c.OP_SUBD },
        .{ .name = "MULTD", .expected = c.OP_MULTD },
        .{ .name = "MUL.D", .expected = c.OP_MULTD },
        .{ .name = "Multd", .expected = c.OP_MULTD }, // mixed case
        .{ .name = "DIVD", .expected = c.OP_DIVD },
        .{ .name = "DIV.D", .expected = c.OP_DIVD },
        .{ .name = "LD", .expected = c.OP_LD },
        .{ .name = "L.D", .expected = c.OP_LD },
        .{ .name = "SD", .expected = c.OP_SD },
        .{ .name = "S.D", .expected = c.OP_SD },
    };
    for (cases) |tc| {
        try testing.expectEqual(tc.expected, c.opcode_from_str(tc.name));
    }
}

test "helpers: opcode_from_str invalid returns OP_COUNT" {
    try testing.expectEqual(@as(c_uint, c.OP_COUNT), c.opcode_from_str("NOPE"));
    try testing.expectEqual(@as(c_uint, c.OP_COUNT), c.opcode_from_str(""));
    try testing.expectEqual(@as(c_uint, c.OP_COUNT), c.opcode_from_str("ADD"));
    try testing.expectEqual(@as(c_uint, c.OP_COUNT), c.opcode_from_str("MULTIPLY"));
    try testing.expectEqual(@as(c_uint, c.OP_COUNT), c.opcode_from_str("123"));
}

test "helpers: rob_state_name returns correct strings" {
    try testing.expectEqualStrings("Issue", std.mem.span(c.rob_state_name(c.ROB_ISSUE)));
    try testing.expectEqualStrings("Executing", std.mem.span(c.rob_state_name(c.ROB_EXECUTING)));
    try testing.expectEqualStrings("Write", std.mem.span(c.rob_state_name(c.ROB_WRITE_RESULT)));
    try testing.expectEqualStrings("Commit", std.mem.span(c.rob_state_name(c.ROB_COMMIT)));
}

test "helpers: rs_type_prefix returns correct strings" {
    try testing.expectEqualStrings("Add", std.mem.span(c.rs_type_prefix(c.RS_ADD)));
    try testing.expectEqualStrings("Mul", std.mem.span(c.rs_type_prefix(c.RS_MULT)));
    try testing.expectEqualStrings("Ld", std.mem.span(c.rs_type_prefix(c.RS_LOAD)));
    try testing.expectEqualStrings("St", std.mem.span(c.rs_type_prefix(c.RS_STORE)));
}

test "helpers: rs_clear preserves type and unit_id" {
    var rs: c.ReservationStation = undefined;
    rs.type = c.RS_MULT;
    rs.unit_id = 3;
    rs.busy = true;
    rs.Vj = 42.0;
    rs.Qj = 5;
    c.rs_clear(&rs);
    try testing.expectEqual(false, rs.busy);
    try testing.expectApproxEqAbs(0.0, rs.Vj, 0.001);
    try testing.expectEqual(@as(c_int, 0), rs.Qj);
    try testing.expectEqual(@as(c_uint, c.RS_MULT), rs.type);
    try testing.expectEqual(@as(c_int, 3), rs.unit_id);
}

test "helpers: config_default has reasonable values" {
    const cfg = c.config_default();
    try testing.expectEqual(@as(c_int, 2), cfg.latency[c.OP_ADDD]);
    try testing.expectEqual(@as(c_int, 2), cfg.latency[c.OP_SUBD]);
    try testing.expectEqual(@as(c_int, 10), cfg.latency[c.OP_MULTD]);
    try testing.expectEqual(@as(c_int, 40), cfg.latency[c.OP_DIVD]);
    try testing.expectEqual(@as(c_int, 2), cfg.latency[c.OP_LD]);
    try testing.expectEqual(@as(c_int, 2), cfg.latency[c.OP_SD]);
    try testing.expectEqual(@as(c_int, 3), cfg.num_rs[c.RS_ADD]);
    try testing.expectEqual(@as(c_int, 2), cfg.num_rs[c.RS_MULT]);
    try testing.expectEqual(@as(c_int, 3), cfg.num_rs[c.RS_LOAD]);
    try testing.expectEqual(@as(c_int, 3), cfg.num_rs[c.RS_STORE]);
}
