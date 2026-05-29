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

const ParsedName = struct { section: ?[]const u8, rest: []const u8 };

/// Parse the section name from a test name.
/// Test names from Zig follow the pattern "module.path.test.section: description"
/// where "test." marks the actual test name. We extract just the section name.
fn parseSection(name: []const u8) ParsedName {
    // Find the colon separator first
    if (std.mem.indexOf(u8, name, ": ")) |colon_idx| {
        // Look for "test." prefix which marks where the actual test name starts
        // Test names look like: "tests.helpers.test.helpers: description"
        // We want to extract "helpers" as the section
        const before_colon = name[0..colon_idx];
        if (std.mem.lastIndexOf(u8, before_colon, "test.")) |test_idx| {
            const section = before_colon[test_idx + 5 ..]; // Skip "test."
            return .{
                .section = section,
                .rest = name[colon_idx + 2 ..],
            };
        }
        // Fallback: use everything before colon as section
        return .{
            .section = before_colon,
            .rest = name[colon_idx + 2 ..],
        };
    }
    return .{ .section = null, .rest = name };
}

const Duration = struct { value: u64, unit: []const u8 };

fn formatDuration(ns: u64) Duration {
    if (ns >= 5_000_000_000) {
        return .{ .value = ns / 1_000_000_000, .unit = "s" };
    } else if (ns >= 5_000_000) {
        return .{ .value = ns / 1_000_000, .unit = "ms" };
    } else if (ns >= 5_000) {
        return .{ .value = ns / 1_000, .unit = "μs" };
    } else {
        return .{ .value = ns, .unit = "ns" };
    }
}

fn countDigits(n: usize) usize {
    if (n == 0) return 1;
    var count: usize = 0;
    var val = n;
    while (val > 0) : (val /= 10) count += 1;
    return count;
}

fn processResult(
    result: anyerror!void,
    passed: *usize,
    failed: *usize,
    skipped: *usize,
    c: type,
    parsed: ParsedName,
    index: usize,
    total: usize,
    elapsed_ns: u64,
    has_leak: bool,
) void {
    const duration = formatDuration(elapsed_ns);
    var test_failed = false;
    var error_msg: ?anyerror = null;
    var fail_reason: []const u8 = "";

    if (result) |_| {
        if (log_err_count != 0) {
            failed.* += 1;
            test_failed = true;
            fail_reason = "error logs";
        } else {
            passed.* += 1;
        }
    } else |err| switch (err) {
        error.SkipZigTest => {
            skipped.* += 1;
            printTestLine(c, c.yellow, " SKIP ", parsed, index, total, duration);
            return;
        },
        else => {
            failed.* += 1;
            test_failed = true;
            error_msg = err;
        },
    }

    // Print the test line
    if (test_failed) {
        printTestLine(c, c.red, "FAILED", parsed, index, total, duration);
    } else {
        printTestLine(c, c.green, "  OK  ", parsed, index, total, duration);
    }

    // Print error details below the line if failed
    if (test_failed) {
        if (error_msg) |err| {
            std.debug.print("         {s}└─ {any}{s}\n", .{ c.red, err, c.reset });
        } else if (fail_reason.len > 0) {
            std.debug.print("         {s}└─ {s}{s}\n", .{ c.red, fail_reason, c.reset });
        }
        if (has_leak) {
            std.debug.print("         {s}└─ memory leak detected{s}\n", .{ c.yellow, c.reset });
        }
    }
}

fn printTestLine(
    c: type,
    status_color: []const u8,
    status_text: []const u8,
    parsed: ParsedName,
    index: usize,
    total: usize,
    duration: Duration,
) void {
    // Print status badge: brackets are default, only inner text is colored+bold
    std.debug.print("[{s}{s}{s}{s}] ", .{ c.bold, status_color, status_text, c.reset });

    // Calculate the name display length
    var name_len: usize = 0;
    if (parsed.section) |section| {
        // Print section in bold, rest in normal
        std.debug.print("{s}{s}{s}: {s}", .{ c.bold, section, c.reset, parsed.rest });
        name_len = section.len + 2 + parsed.rest.len; // "section: rest"
    } else {
        std.debug.print("{s}", .{parsed.rest});
        name_len = parsed.rest.len;
    }

    // Calculate suffix length: " (XXXμs YYY/ZZZ)"
    // Format: space + '(' + digits + unit(2 display chars) + space + digits + '/' + digits + ')'
    // Note: both "ms" and "μs" are 2 display characters (μ is multi-byte but 1 char wide)
    const unit_display_len: usize = switch (duration.unit.len) {
        1 => 1,
        else => 2,
    };

    const counter_width = countDigits(total);
    const suffix_len =
        1 + // leading space
        1 + // '('
        countDigits(duration.value) +
        unit_display_len +
        1 + // space
        counter_width +
        1 + // '/'
        counter_width +
        1; // ')'

    // Total used: "[STATUS] " (9) + name_len + suffix_len
    const prefix_len: usize = 9; // "[XXXXXX] "
    const used = prefix_len + name_len + suffix_len;
    const target_width: usize = 120;

    // Add padding to right-align at column 120
    if (used < target_width) {
        const padding = target_width - used;
        for (0..padding) |_| std.debug.print(" ", .{});
    }

    // Print duration and counter in dim/gray
    std.debug.print(
        " {s}{d}{s} ({d:[6]}/{d:[6]}){s}\n",
        .{
            c.dim,
            duration.value,
            duration.unit,
            index + 1,
            total,
            c.reset,
            counter_width,
        },
    );
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

    for (builtin.test_functions, 0..) |test_fn, i| {
        std.testing.allocator_instance = .{};
        var has_leak = false;
        defer {
            if (std.testing.allocator_instance.deinit() == .leak) {
                leaks += 1;
                has_leak = true;
            }
        }
        log_err_count = 0;

        // Parse section from test name
        const parsed = parseSection(test_fn.name);

        // Run the test and measure duration using clock_gettime
        var start_ts: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(.MONOTONIC, &start_ts);
        const result = test_fn.func();
        var end_ts: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(.MONOTONIC, &end_ts);
        const start_ns: i128 = @as(i128, start_ts.sec) * 1_000_000_000 + start_ts.nsec;
        const end_ns: i128 = @as(i128, end_ts.sec) * 1_000_000_000 + end_ts.nsec;
        const elapsed_ns: u64 = @intCast(@max(0, end_ns - start_ns));

        processResult(result, &passed, &failed, &skipped, c, parsed, i, total, elapsed_ns, has_leak);
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
