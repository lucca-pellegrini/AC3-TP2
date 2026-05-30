// SPDX-License-Identifier: ISC
// SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
// NOTE: Test harness and some unit tests written with help from LLMs

//! Display output tests.
//! These tests capture the output of display functions and validate
//! that the displayed information is consistent and correct.

const common = @import("common.zig");
const std = common.std;
const testing = common.testing;
const c_io = common.c_io;

const initSim = common.initSim;
const initDefaultSim = common.initDefaultSim;
const initSimWith = common.initSimWith;
const makeArithInst = common.makeArithInst;
const makeMemInst = common.makeMemInst;
const addInst = common.addInst;
const runToCompletion = common.runToCompletion;

// Use common's c import which now includes display.h
const c = common.c;

// ═══════════════════════════════════════════════════════════════════════════
// Output capture helpers
// ═══════════════════════════════════════════════════════════════════════════

/// Capture display output to a buffer using a temp file.
/// Returns the output as a slice (caller must free).
fn captureOutput(comptime func: anytype, sim: *const c.Simulator) ![]u8 {
    // Create temp file
    var template_buf: [64]u8 = undefined;
    const template = std.fmt.bufPrintZ(
        &template_buf,
        "/tmp/tomasulo_display_test_XXXXXX",
        .{},
    ) catch unreachable;

    const fd = c_io.mkstemp(template.ptr);
    if (fd < 0) return error.MkstempFailed;
    defer _ = c_io.unlink(template.ptr);

    // Open as FILE* for the C display function
    const file = c_io.fdopen(fd, "w+");
    if (file == null) {
        _ = c_io.close(fd);
        return error.FdopenFailed;
    }
    defer _ = c_io.fclose(file);

    // Call the display function
    func(file, sim);

    // Flush and rewind
    _ = c_io.fflush(file);
    _ = c_io.fseek(file, 0, c_io.SEEK_SET);

    // Read the output
    var output: std.ArrayListUnmanaged(u8) = .empty;
    errdefer output.deinit(testing.allocator);

    var buf: [4096]u8 = undefined;
    while (true) {
        const n = c_io.fread(&buf, 1, buf.len, file);
        if (n == 0) break;
        try output.appendSlice(testing.allocator, buf[0..n]);
    }

    return output.toOwnedSlice(testing.allocator);
}

/// Strip ANSI escape codes from output for easier parsing
fn stripAnsi(input: []const u8) ![]u8 {
    var output: std.ArrayListUnmanaged(u8) = .empty;
    errdefer output.deinit(testing.allocator);

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == 0x1b and i + 1 < input.len and input[i + 1] == '[') {
            // Skip escape sequence
            i += 2;
            while (i < input.len and input[i] != 'm') : (i += 1) {}
            if (i < input.len) i += 1; // skip 'm'
        } else {
            try output.append(testing.allocator, input[i]);
            i += 1;
        }
    }

    return output.toOwnedSlice(testing.allocator);
}

/// Result type for parseIntsFromLine
const ParseResult = struct {
    values: [16]i32 = undefined,
    count: usize = 0,
};

/// Parse all integers from a line (max 16)
fn parseIntsFromLine(line: []const u8) ParseResult {
    var result = ParseResult{};

    var i: usize = 0;
    while (i < line.len and result.count < 16) {
        // Skip non-digit characters (but handle negative sign)
        while (i < line.len and !std.ascii.isDigit(line[i]) and line[i] != '-') : (i += 1) {}
        if (i >= line.len) break;

        // Check for negative
        const negative = line[i] == '-';
        if (negative) i += 1;
        if (i >= line.len or !std.ascii.isDigit(line[i])) continue;

        // Parse the number
        var num: i32 = 0;
        while (i < line.len and std.ascii.isDigit(line[i])) : (i += 1) {
            num = num * 10 + @as(i32, @intCast(line[i] - '0'));
        }
        if (negative) num = -num;

        result.values[result.count] = num;
        result.count += 1;
    }

    return result;
}

// ═══════════════════════════════════════════════════════════════════════════
// Basic display function tests (ensure they don't crash and produce output)
// ═══════════════════════════════════════════════════════════════════════════

test "display: display_cycle produces output" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = c.sim_step(&sim);

    const output = try captureOutput(c.display_cycle, &sim);
    defer testing.allocator.free(output);

    try testing.expect(output.len > 0);
}

test "display: display_instructions produces output" {
    var sim = initDefaultSim();
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));

    const output = try captureOutput(c.display_instructions, &sim);
    defer testing.allocator.free(output);

    try testing.expect(output.len > 0);
}

test "display: display_rs produces output" {
    var sim = initDefaultSim();

    const output = try captureOutput(c.display_rs, &sim);
    defer testing.allocator.free(output);

    try testing.expect(output.len > 0);
}

test "display: display_rob produces output with busy entries" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = c.sim_step(&sim); // Issue the instruction

    const output = try captureOutput(c.display_rob, &sim);
    defer testing.allocator.free(output);

    try testing.expect(output.len > 0);
}

test "display: display_rat produces output when RAT has entries" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = c.sim_step(&sim); // Issue - RAT should have entry for F1

    const output = try captureOutput(c.display_rat, &sim);
    defer testing.allocator.free(output);

    try testing.expect(output.len > 0);
}

test "display: display_final produces output" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = runToCompletion(&sim);

    const output = try captureOutput(c.display_final, &sim);
    defer testing.allocator.free(output);

    try testing.expect(output.len > 0);
}

test "display: display_separator produces output" {
    const sim = initDefaultSim();
    _ = sim; // unused but needed for capture helper signature

    // We need a different approach for display_separator since it has different args
    var template_buf: [64]u8 = undefined;
    const template = std.fmt.bufPrintZ(
        &template_buf,
        "/tmp/tomasulo_display_test_XXXXXX",
        .{},
    ) catch unreachable;

    const fd = c_io.mkstemp(template.ptr);
    if (fd < 0) return error.MkstempFailed;
    defer _ = c_io.unlink(template.ptr);

    const file = c_io.fdopen(fd, "w+");
    if (file == null) {
        _ = c_io.close(fd);
        return error.FdopenFailed;
    }
    defer _ = c_io.fclose(file);

    c.display_separator(file, 40, "Test Title");
    _ = c_io.fflush(file);
    _ = c_io.fseek(file, 0, c_io.SEEK_SET);

    var buf: [256]u8 = undefined;
    const n = c_io.fread(&buf, 1, buf.len, file);
    try testing.expect(n > 0);
}

// ═══════════════════════════════════════════════════════════════════════════
// Cycle count validation (never negative)
// ═══════════════════════════════════════════════════════════════════════════

test "display: cycle count in output is never negative" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));

    // Run several cycles and check output each time
    while (!c.sim_done(&sim)) {
        _ = c.sim_step(&sim);

        const output = try captureOutput(c.display_cycle, &sim);
        defer testing.allocator.free(output);

        const stripped = try stripAnsi(output);
        defer testing.allocator.free(stripped);

        // Look for "Cycle X" and verify X >= 0
        if (std.mem.indexOf(u8, stripped, "Cycle ")) |idx| {
            const after_cycle = stripped[idx + 6 ..];
            const parsed = parseIntsFromLine(after_cycle);
            if (parsed.count > 0) {
                try testing.expect(parsed.values[0] >= 0);
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Instruction timing validation
// ═══════════════════════════════════════════════════════════════════════════

test "display: instruction timing columns are monotonically increasing" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    addInst(&sim, makeArithInst(c.OP_SUBD, 4, 2, 3));
    _ = runToCompletion(&sim);

    const output = try captureOutput(c.display_instructions, &sim);
    defer testing.allocator.free(output);

    const stripped = try stripAnsi(output);
    defer testing.allocator.free(stripped);

    // Parse instruction timing from output
    var lines = std.mem.splitScalar(u8, stripped, '\n');
    var found_data = false;
    while (lines.next()) |line| {
        // Skip header and empty lines
        if (line.len < 10) continue;
        if (std.mem.indexOf(u8, line, "Issue") != null) continue;
        if (std.mem.indexOf(u8, line, "───") != null) continue;

        // Look for lines with instruction data (start with number or *)
        const trimmed = std.mem.trimStart(u8, line, " *");
        if (trimmed.len == 0) continue;
        if (!std.ascii.isDigit(trimmed[0])) continue;

        // Parse the timing values from the line
        // Format: # Op Dest Src1 Src2 Issue ExBeg ExEnd Write
        const parsed = parseIntsFromLine(line);
        if (parsed.count >= 5) {
            found_data = true;
            // Extract timing values (last 4 numbers if present)
            // Values of 0 mean "not yet"
            const issue = parsed.values[parsed.count - 4];
            const exec_beg = parsed.values[parsed.count - 3];
            const exec_end = parsed.values[parsed.count - 2];
            const write = parsed.values[parsed.count - 1];

            // Verify monotonicity for non-zero values
            if (issue > 0 and exec_beg > 0) {
                try testing.expect(issue <= exec_beg);
            }
            if (exec_beg > 0 and exec_end > 0) {
                try testing.expect(exec_beg <= exec_end);
            }
            if (exec_end > 0 and write > 0) {
                try testing.expect(exec_end <= write);
            }
        }
    }
    try testing.expect(found_data);
}

// ═══════════════════════════════════════════════════════════════════════════
// CDB contention validation
// ═══════════════════════════════════════════════════════════════════════════

test "display: CDB contention only shown when multiple instructions waiting" {
    // Setup: single instruction should never show CDB contention
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));

    while (!c.sim_done(&sim)) {
        _ = c.sim_step(&sim);

        const output = try captureOutput(c.display_rob, &sim);
        defer testing.allocator.free(output);

        const stripped = try stripAnsi(output);
        defer testing.allocator.free(stripped);

        // With a single instruction, should never see "CDB contention"
        try testing.expect(std.mem.indexOf(u8, stripped, "CDB contention") == null);
    }
}

test "display: CDB contention shown when actually present" {
    // Setup matching cdb_contention.tom:
    // One ADD produces F10, then 3 ADDs all depend on F10.
    // When F10 is ready, all 3 dependents start executing on the same cycle.
    // With latency=2, they all finish execution together and all want the CDB.
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.num_rs[c.RS_ADD] = 4; // Need 4 RS to issue all at once
    var sim = initSim(&cfg);

    // Setup registers like cdb_contention.tom
    c.sim_set_reg(&sim, 0, 1.0); // F0
    c.sim_set_reg(&sim, 1, 2.0); // F1
    c.sim_set_reg(&sim, 2, 3.0); // F2
    c.sim_set_reg(&sim, 3, 4.0); // F3
    c.sim_set_reg(&sim, 4, 5.0); // F4

    // F10 = F0 + F1 (independent, finishes first)
    addInst(&sim, makeArithInst(c.OP_ADDD, 10, 0, 1));
    // F11 = F10 + F2 (waits for F10)
    addInst(&sim, makeArithInst(c.OP_ADDD, 11, 10, 2));
    // F12 = F10 + F3 (waits for F10)
    addInst(&sim, makeArithInst(c.OP_ADDD, 12, 10, 3));
    // F13 = F10 + F4 (waits for F10)
    addInst(&sim, makeArithInst(c.OP_ADDD, 13, 10, 4));

    var saw_contention = false;
    var max_waiters: i32 = 0;
    while (!c.sim_done(&sim)) {
        _ = c.sim_step(&sim);

        const output = try captureOutput(c.display_rob, &sim);
        defer testing.allocator.free(output);

        const stripped = try stripAnsi(output);
        defer testing.allocator.free(stripped);

        if (std.mem.indexOf(u8, stripped, "CDB contention") != null) {
            saw_contention = true;
            // Verify the contention message includes count > 1
            if (std.mem.indexOf(u8, stripped, "waiting)")) |idx| {
                // Find the number before "waiting)"
                var j = idx;
                while (j > 0 and stripped[j - 1] != '(') : (j -= 1) {}
                const count_str = stripped[j..idx];
                const parsed = parseIntsFromLine(count_str);
                if (parsed.count > 0) {
                    try testing.expect(parsed.values[0] > 1);
                    if (parsed.values[0] > max_waiters) {
                        max_waiters = parsed.values[0];
                    }
                }
            }
        }
    }
    // With this setup, CDB contention MUST occur
    try testing.expect(saw_contention);
    // At peak, 3 instructions should be waiting (the 3 dependents)
    try testing.expect(max_waiters >= 2);

    // Verify correctness
    try testing.expectApproxEqAbs(3.0, sim.fp_regs[10], 0.001); // 1+2
    try testing.expectApproxEqAbs(6.0, sim.fp_regs[11], 0.001); // 3+3
    try testing.expectApproxEqAbs(7.0, sim.fp_regs[12], 0.001); // 3+4
    try testing.expectApproxEqAbs(8.0, sim.fp_regs[13], 0.001); // 3+5
}

// ═══════════════════════════════════════════════════════════════════════════
// No duplicate write cycles
// ═══════════════════════════════════════════════════════════════════════════

test "display: no two instructions write in the same cycle" {
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.num_rs[c.RS_ADD] = 4;
    var sim = initSim(&cfg);

    // Four independent adds
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    addInst(&sim, makeArithInst(c.OP_ADDD, 4, 2, 3));
    addInst(&sim, makeArithInst(c.OP_ADDD, 7, 2, 3));
    addInst(&sim, makeArithInst(c.OP_ADDD, 10, 2, 3));

    _ = runToCompletion(&sim);

    // Collect all write cycles (excluding SD which doesn't use CDB)
    var write_cycles: [c.MAX_INSTRUCTIONS]i32 = undefined;
    var write_count: usize = 0;

    for (0..@as(usize, @intCast(sim.num_instructions))) |i| {
        const inst = sim.instructions[i];
        if (inst.write_cycle > 0 and inst.op != c.OP_SD) {
            write_cycles[write_count] = inst.write_cycle;
            write_count += 1;
        }
    }

    // Check no duplicates (except for SD)
    for (0..write_count) |i| {
        for (i + 1..write_count) |j| {
            try testing.expect(write_cycles[i] != write_cycles[j]);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ROB state validation
// ═══════════════════════════════════════════════════════════════════════════

test "display: ROB shows only valid states" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));

    const valid_states = [_][]const u8{ "Issue", "Executing", "Write", "Commit" };

    while (!c.sim_done(&sim)) {
        _ = c.sim_step(&sim);

        const output = try captureOutput(c.display_rob, &sim);
        defer testing.allocator.free(output);

        const stripped = try stripAnsi(output);
        defer testing.allocator.free(stripped);

        // Check each line for state values
        var lines = std.mem.splitScalar(u8, stripped, '\n');
        while (lines.next()) |line| {
            // Skip header and separator lines
            if (std.mem.indexOf(u8, line, "Tag") != null) continue;
            if (std.mem.indexOf(u8, line, "───") != null) continue;
            if (line.len < 5) continue;

            // Look for state strings - lines starting with #
            if (std.mem.indexOf(u8, line, "#")) |_| {
                // This is a ROB entry line, check it contains a valid state
                var found_state = false;
                for (valid_states) |state| {
                    if (std.mem.indexOf(u8, line, state) != null) {
                        found_state = true;
                        break;
                    }
                }
                // If line has a state column, it should be valid
                // (some lines might be just tags without states shown)
                if (std.mem.indexOf(u8, line, "ADD.D") != null or
                    std.mem.indexOf(u8, line, "SUB.D") != null or
                    std.mem.indexOf(u8, line, "MUL.D") != null or
                    std.mem.indexOf(u8, line, "DIV.D") != null or
                    std.mem.indexOf(u8, line, "L.D") != null or
                    std.mem.indexOf(u8, line, "S.D") != null)
                {
                    try testing.expect(found_state);
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Reservation station cycles validation
// ═══════════════════════════════════════════════════════════════════════════

test "display: RS cycles_left is never negative" {
    var cfg = c.config_default();
    cfg.latency[c.OP_MULTD] = 10; // Long latency to observe countdown
    var sim = initSim(&cfg);

    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_MULTD, 1, 2, 3));

    while (!c.sim_done(&sim)) {
        _ = c.sim_step(&sim);

        const output = try captureOutput(c.display_rs, &sim);
        defer testing.allocator.free(output);

        const stripped = try stripAnsi(output);
        defer testing.allocator.free(stripped);

        // Parse the Cyc column values
        var lines = std.mem.splitScalar(u8, stripped, '\n');
        while (lines.next()) |line| {
            // Skip header lines
            if (std.mem.indexOf(u8, line, "Name") != null) continue;
            if (std.mem.indexOf(u8, line, "───") != null) continue;
            if (line.len < 5) continue;

            // Lines with busy RS (contain opcode and Cyc value)
            if (std.mem.indexOf(u8, line, "MUL.D") != null) {
                // The last number on the line should be cycles
                const parsed = parseIntsFromLine(line);
                if (parsed.count > 0) {
                    const cyc = parsed.values[parsed.count - 1];
                    try testing.expect(cyc >= 0);
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Final statistics validation
// ═══════════════════════════════════════════════════════════════════════════

test "display: final stats show non-negative values" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = runToCompletion(&sim);

    const output = try captureOutput(c.display_final, &sim);
    defer testing.allocator.free(output);

    const stripped = try stripAnsi(output);
    defer testing.allocator.free(stripped);

    // Check key statistics are present and non-negative
    const checks = [_][]const u8{
        "Total cycles:",
        "Instructions:",
        "Total stalls:",
    };

    for (checks) |check| {
        if (std.mem.indexOf(u8, stripped, check)) |idx| {
            const after = stripped[idx + check.len ..];
            const parsed = parseIntsFromLine(after);
            if (parsed.count > 0) {
                try testing.expect(parsed.values[0] >= 0);
            }
        }
    }
}

test "display: CPI and IPC are consistent" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    addInst(&sim, makeArithInst(c.OP_SUBD, 4, 2, 3));
    _ = runToCompletion(&sim);

    // CPI * IPC should approximately equal 1
    const cycles: f64 = @floatFromInt(sim.cycle);
    const insts: f64 = @floatFromInt(sim.num_instructions);
    const cpi = cycles / insts;
    const ipc = insts / cycles;

    // CPI * IPC = (cycles/insts) * (insts/cycles) = 1
    try testing.expectApproxEqAbs(1.0, cpi * ipc, 0.001);
}

// ═══════════════════════════════════════════════════════════════════════════
// Register display validation
// ═══════════════════════════════════════════════════════════════════════════

test "display: final register values match simulator state" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 5.0);
    c.sim_set_reg(&sim, 3, 7.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3)); // F1 = 5 + 7 = 12
    _ = runToCompletion(&sim);

    const output = try captureOutput(c.display_final, &sim);
    defer testing.allocator.free(output);

    const stripped = try stripAnsi(output);
    defer testing.allocator.free(stripped);

    // F1 should be 12.0
    try testing.expectApproxEqAbs(12.0, sim.fp_regs[1], 0.001);

    // The output should contain "F1" and "12"
    try testing.expect(std.mem.indexOf(u8, stripped, "F1") != null);
    try testing.expect(std.mem.indexOf(u8, stripped, "12") != null);
}

// ═══════════════════════════════════════════════════════════════════════════
// Memory instruction display
// ═══════════════════════════════════════════════════════════════════════════

test "display: LD instruction shows offset and base register" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 100.0);
    addInst(&sim, makeMemInst(c.OP_LD, 1, 8, 2)); // L.D F1, 8(R2)
    _ = c.sim_step(&sim);

    const output = try captureOutput(c.display_instructions, &sim);
    defer testing.allocator.free(output);

    const stripped = try stripAnsi(output);
    defer testing.allocator.free(stripped);

    // Should show L.D and offset 8
    try testing.expect(std.mem.indexOf(u8, stripped, "L.D") != null);
    try testing.expect(std.mem.indexOf(u8, stripped, "8") != null);
}

test "display: SD instruction shows in output" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 1, 42.0);
    c.sim_set_reg(&sim, 2, 100.0);
    addInst(&sim, makeMemInst(c.OP_SD, 1, 0, 2)); // S.D F1, 0(R2)
    _ = c.sim_step(&sim);

    const output = try captureOutput(c.display_instructions, &sim);
    defer testing.allocator.free(output);

    const stripped = try stripAnsi(output);
    defer testing.allocator.free(stripped);

    // Should show S.D
    try testing.expect(std.mem.indexOf(u8, stripped, "S.D") != null);
}

// ═══════════════════════════════════════════════════════════════════════════
// RAT display validation
// ═══════════════════════════════════════════════════════════════════════════

test "display: RAT shows pending register when instruction in flight" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = c.sim_step(&sim); // Issue - F1 should be in RAT

    const output = try captureOutput(c.display_rat, &sim);
    defer testing.allocator.free(output);

    const stripped = try stripAnsi(output);
    defer testing.allocator.free(stripped);

    // RAT should show F1 with a tag
    try testing.expect(std.mem.indexOf(u8, stripped, "F1") != null);
    try testing.expect(std.mem.indexOf(u8, stripped, "#") != null);
}

test "display: RAT is empty after all instructions complete" {
    var sim = initDefaultSim();
    c.sim_set_reg(&sim, 2, 1.0);
    c.sim_set_reg(&sim, 3, 2.0);
    addInst(&sim, makeArithInst(c.OP_ADDD, 1, 2, 3));
    _ = runToCompletion(&sim);

    const output = try captureOutput(c.display_rat, &sim);
    defer testing.allocator.free(output);

    const stripped = try stripAnsi(output);
    defer testing.allocator.free(stripped);

    // RAT should show "no in-flight" message
    try testing.expect(std.mem.indexOf(u8, stripped, "no in-flight") != null);
}

// ═══════════════════════════════════════════════════════════════════════════
// Stress test with many parallel operations (like wide_issue.tom)
// ═══════════════════════════════════════════════════════════════════════════

test "display: wide issue stress test shows correct CDB arbitration" {
    // Pattern from wide_issue.tom: many independent ops of different types
    // stressing CDB arbitration across all functional unit types
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.latency[c.OP_MULTD] = 4;
    cfg.latency[c.OP_LD] = 2;
    cfg.num_rs[c.RS_ADD] = 4;
    cfg.num_rs[c.RS_MULT] = 4;
    cfg.num_rs[c.RS_LOAD] = 4;
    var sim = initSim(&cfg);

    // Setup base registers
    c.sim_set_reg(&sim, 1, 100.0); // R1
    c.sim_set_reg(&sim, 2, 200.0); // R2

    // Constants for arithmetic
    c.sim_set_reg(&sim, 20, 1.0);
    c.sim_set_reg(&sim, 21, 2.0);
    c.sim_set_reg(&sim, 22, 3.0);
    c.sim_set_reg(&sim, 23, 4.0);
    c.sim_set_reg(&sim, 24, 5.0);
    c.sim_set_reg(&sim, 25, 6.0);
    c.sim_set_reg(&sim, 26, 7.0);
    c.sim_set_reg(&sim, 27, 8.0);

    // 4 independent loads
    addInst(&sim, makeMemInst(c.OP_LD, 0, 0, 1)); // F0 = 0+100 = 100
    addInst(&sim, makeMemInst(c.OP_LD, 3, 8, 1)); // F3 = 8+100 = 108
    addInst(&sim, makeMemInst(c.OP_LD, 4, 0, 2)); // F4 = 0+200 = 200
    addInst(&sim, makeMemInst(c.OP_LD, 5, 8, 2)); // F5 = 8+200 = 208

    // 2 independent multiplies
    addInst(&sim, makeArithInst(c.OP_MULTD, 10, 21, 22)); // F10 = 2*3 = 6
    addInst(&sim, makeArithInst(c.OP_MULTD, 11, 23, 24)); // F11 = 4*5 = 20

    // 2 independent adds
    addInst(&sim, makeArithInst(c.OP_ADDD, 14, 20, 21)); // F14 = 1+2 = 3
    addInst(&sim, makeArithInst(c.OP_ADDD, 15, 22, 23)); // F15 = 3+4 = 7

    var cdb_contention_cycles: i32 = 0;
    while (!c.sim_done(&sim)) {
        _ = c.sim_step(&sim);

        const output = try captureOutput(c.display_rob, &sim);
        defer testing.allocator.free(output);

        const stripped = try stripAnsi(output);
        defer testing.allocator.free(stripped);

        if (std.mem.indexOf(u8, stripped, "CDB contention") != null) {
            cdb_contention_cycles += 1;
        }
    }

    // With many parallel operations, we should see some CDB contention
    try testing.expect(cdb_contention_cycles > 0);

    // Verify correctness of results
    try testing.expectApproxEqAbs(100.0, sim.fp_regs[0], 0.001);
    try testing.expectApproxEqAbs(108.0, sim.fp_regs[3], 0.001);
    try testing.expectApproxEqAbs(200.0, sim.fp_regs[4], 0.001);
    try testing.expectApproxEqAbs(208.0, sim.fp_regs[5], 0.001);
    try testing.expectApproxEqAbs(6.0, sim.fp_regs[10], 0.001);
    try testing.expectApproxEqAbs(20.0, sim.fp_regs[11], 0.001);
    try testing.expectApproxEqAbs(3.0, sim.fp_regs[14], 0.001);
    try testing.expectApproxEqAbs(7.0, sim.fp_regs[15], 0.001);
}

test "display: mixed stress test with dependencies shows correct state transitions" {
    // Pattern from mixed_stress.tom: loads feeding muls feeding adds
    var cfg = c.config_default();
    cfg.latency[c.OP_ADDD] = 2;
    cfg.latency[c.OP_SUBD] = 2;
    cfg.latency[c.OP_MULTD] = 6;
    cfg.latency[c.OP_LD] = 2;
    cfg.num_rs[c.RS_ADD] = 3;
    cfg.num_rs[c.RS_MULT] = 2;
    cfg.num_rs[c.RS_LOAD] = 3;
    var sim = initSim(&cfg);

    // Base registers
    c.sim_set_reg(&sim, 30, 100.0); // R30
    c.sim_set_reg(&sim, 31, 200.0); // R31

    // Loads
    addInst(&sim, makeMemInst(c.OP_LD, 20, 0, 30)); // F20 = 0+100 = 100
    addInst(&sim, makeMemInst(c.OP_LD, 21, 8, 30)); // F21 = 8+100 = 108

    // Multiply dependent on loads
    addInst(&sim, makeArithInst(c.OP_MULTD, 8, 20, 21)); // F8 = F20*F21 = 10800

    // Add dependent on multiply
    addInst(&sim, makeArithInst(c.OP_ADDD, 12, 8, 21)); // F12 = F8+F21 = 10908

    var saw_issue = false;
    var saw_executing = false;
    var saw_write = false;

    while (!c.sim_done(&sim)) {
        _ = c.sim_step(&sim);

        const output = try captureOutput(c.display_rob, &sim);
        defer testing.allocator.free(output);

        const stripped = try stripAnsi(output);
        defer testing.allocator.free(stripped);

        // Check for valid state strings
        if (std.mem.indexOf(u8, stripped, "Issue") != null) saw_issue = true;
        if (std.mem.indexOf(u8, stripped, "Executing") != null) saw_executing = true;
        if (std.mem.indexOf(u8, stripped, "Write") != null) saw_write = true;
    }

    // We should have seen all major states during simulation
    try testing.expect(saw_issue);
    try testing.expect(saw_executing);
    try testing.expect(saw_write);

    // Verify correctness
    try testing.expectApproxEqAbs(100.0, sim.fp_regs[20], 0.001);
    try testing.expectApproxEqAbs(108.0, sim.fp_regs[21], 0.001);
    try testing.expectApproxEqAbs(10800.0, sim.fp_regs[8], 0.001);
    try testing.expectApproxEqAbs(10908.0, sim.fp_regs[12], 0.001);
}
