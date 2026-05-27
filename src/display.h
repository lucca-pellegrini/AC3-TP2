// SPDX-License-Identifier: MIT
// Tomasulo Simulator -- Display / Output
#pragma once

#include "tomasulo.h"

#include <stdio.h>

// Output mode for the simulator
typedef enum {
	DISPLAY_INTERACTIVE, // step-by-step, wait for Enter
	DISPLAY_BATCH, // run all, print each cycle
	DISPLAY_QUIET, // only final state
} DisplayMode;

// Print the full simulator state for the current cycle.
void display_cycle(FILE *out, const Simulator *sim);

// Print the instruction status table.
void display_instructions(FILE *out, const Simulator *sim);

// Print reservation stations.
void display_rs(FILE *out, const Simulator *sim);

// Print ROB contents.
void display_rob(FILE *out, const Simulator *sim);

// Print register status (RAT).
void display_rat(FILE *out, const Simulator *sim);

// Print final register values.
void display_final(FILE *out, const Simulator *sim);

// Print a horizontal separator line.
void display_separator(FILE *out, int width, const char *title);
