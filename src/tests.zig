// SPDX-License-Identifier: ISC
// SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
// NOTE: Test harness and some unit tests written with help from LLMs

//! Main test entry point that imports all test modules.
//! Each module contains tests for a specific category.

// Test modules - import references trigger test discovery
comptime {
    _ = @import("tests/helpers.zig");
    _ = @import("tests/parser.zig");
    _ = @import("tests/simulator.zig");
    _ = @import("tests/operations.zig");
    _ = @import("tests/timing.zig");
    _ = @import("tests/hazards.zig");
    _ = @import("tests/cdb.zig");
    _ = @import("tests/memory.zig");
    _ = @import("tests/complex.zig");
    _ = @import("tests/parser_syntax.zig");
    _ = @import("tests/stats.zig");
    _ = @import("tests/fuzz.zig");
    _ = @import("tests/display.zig");
}
