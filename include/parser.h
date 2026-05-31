/*
 * SPDX-License-Identifier: ISC
 * SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
 * NOTE: Tomasulo file parser logic written with help from LLMs
 */

#pragma once

#include "tomasulo.h"

// Parse a Tomasulo input file.  Populates `cfg` with configuration and
// fills `sim` with instructions.  Initial register values are also loaded
// if present in the file (REG_INIT section).
//
// Returns 0 on success, -1 on error (with message printed to stderr).
int parse_input(const char *path, TomasuloConfig *cfg, Simulator *sim);

// After a successful parse_input() (return 0), callers can optionally query
// how many warnings were emitted while parsing the last file.
int parse_last_warning_count(void);

// Enable or disable printed diagnostics (warnings/errors). When disabled,
// parse_input() still fails on errors, but nothing is printed to stderr.
void parse_set_quiet(bool quiet);

// Parse a register name like "F6" or "R2" into its numeric index.
// Returns -1 on failure.
int parse_register(const char *name);
