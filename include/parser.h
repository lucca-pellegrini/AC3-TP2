// SPDX-License-Identifier: MIT
// Tomasulo Simulator -- Input file parser
#pragma once

#include "tomasulo.h"

#include <stdio.h>

// Parse a Tomasulo input file.  Populates `cfg` with configuration and
// fills `sim` with instructions.  Initial register values are also loaded
// if present in the file (REG_INIT section).
//
// Returns 0 on success, -1 on error (with message printed to stderr).
int parse_input(const char *path, TomasuloConfig *cfg, Simulator *sim);

// Parse a register name like "F6" or "R2" into its numeric index.
// Returns -1 on failure.
int parse_register(const char *name);
