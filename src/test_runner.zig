// SPDX-License-Identifier: ISC
// SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
// NOTE: Test runner written by an LLM

const std = @import("std");
const builtin = @import("builtin");

const ansi = struct {
    const reset = "\x1b[0m";
    const bold = "\x1b[1m";
    const dim = "\x1b[2m";
    const red = "\x1b[31m";
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const cyan = "\x1b[36m";
};

pub const std_options: std.Options = .{
    .logFn = log,
};

var log_err_count: usize = 0;

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime fmt: []const u8,
    args: anytype,
) void {
    @disableInstrumentation();
    if (@intFromEnum(level) <= @intFromEnum(std.log.Level.err))
        log_err_count +|= 1;
    if (@intFromEnum(level) <= @intFromEnum(std.testing.log_level)) {
        std.debug.print(
            "[" ++ @tagName(scope) ++ "] (" ++ @tagName(level) ++ "): " ++ fmt ++ "\n",
            args,
        );
    }
}

pub fn main() void {
    @disableInstrumentation();

    const total: usize = builtin.test_functions.len;
    var passed: usize = 0;
    var failed: usize = 0;
    var skipped: usize = 0;
    var leaks: usize = 0;

    // Always use ANSI colors. Pipe through `sed 's/\x1b\[[0-9;]*m//g'` to strip.
    const c = ansi;

    std.debug.print(
        "{s}{s}Running {d} test{s}...{s}\n",
        .{ c.bold, c.cyan, total, if (total == 1) "" else "s", c.reset },
    );

    var max_name_len: usize = 0;
    for (builtin.test_functions) |t| {
        if (t.name.len > max_name_len) max_name_len = t.name.len;
    }
    if (max_name_len > 120) max_name_len = 120;

    for (builtin.test_functions, 0..) |test_fn, i| {
        std.testing.allocator_instance = .{};
        defer {
            if (std.testing.allocator_instance.deinit() == .leak) {
                leaks += 1;
                std.debug.print(
                    "  {s}LEAK{s} memory leak detected in {s}\n",
                    .{ c.yellow, c.reset, test_fn.name },
                );
            }
        }
        log_err_count = 0;

        // Print test name with manual padding
        std.debug.print(
            "  {s}[{d:>3}/{d}]{s} {s}",
            .{ c.dim, i + 1, total, c.reset, test_fn.name },
        );
        if (test_fn.name.len < max_name_len) {
            for (0..max_name_len - test_fn.name.len) |_|
                std.debug.print(" ", .{});
        }
        std.debug.print("  ", .{});

        const result = test_fn.func();

        if (result) |_| {
            if (log_err_count != 0) {
                failed += 1;
                std.debug.print(
                    "{s}FAIL{s} (error logs)\n",
                    .{ c.red, c.reset },
                );
            } else {
                passed += 1;
                std.debug.print("{s}ok{s}\n", .{ c.green, c.reset });
            }
        } else |err| switch (err) {
            error.SkipZigTest => {
                skipped += 1;
                std.debug.print(
                    "{s}skip{s}\n",
                    .{ c.yellow, c.reset },
                );
            },
            else => {
                failed += 1;
                std.debug.print(
                    "{s}FAIL{s}: {s}{any}{s}\n",
                    .{ c.red, c.reset, c.bold, err, c.reset },
                );
            },
        }
    }

    std.debug.print("\n", .{});
    const status_color = if (failed > 0 or leaks > 0) c.red else c.green;
    const status_word = if (failed > 0 or leaks > 0) "FAILED" else "PASSED";
    std.debug.print(
        "{s}{s}{s}: {s}{d} passed{s}",
        .{ c.bold, status_color, status_word, c.green, passed, c.reset },
    );
    if (failed > 0)
        std.debug.print(", {s}{d} failed{s}", .{ c.red, failed, c.reset });
    if (skipped > 0)
        std.debug.print(", {s}{d} skipped{s}", .{ c.yellow, skipped, c.reset });
    if (leaks > 0)
        std.debug.print(", {s}{d} leaked{s}", .{ c.yellow, leaks, c.reset });
    std.debug.print("\n", .{});

    if (failed > 0 or leaks > 0)
        std.process.exit(1);
}
