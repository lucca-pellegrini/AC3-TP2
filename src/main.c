// SPDX-License-Identifier: MIT
// Tomasulo Algorithm Simulator -- Entry Point
//
// Usage:
//   tomasulo <input.txt>                  (interactive mode)
//   tomasulo <input.txt> -b               (batch mode, print all cycles)
//   tomasulo <input.txt> -q               (quiet, only final state)
//   tomasulo <input.txt> -o <output.txt>  (write output to file)
//
#include "display.h"
#include "parser.h"
#include "tomasulo.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void usage(const char *prog)
{
	fprintf(stderr,
		"Tomasulo Algorithm Simulator\n\n"
		"Usage: %s <input.txt> [options]\n\n"
		"Options:\n"
		"  -b          Batch mode (print all cycles, no pause)\n"
		"  -q          Quiet mode (only print final state)\n"
		"  -o <file>   Write output to file (default: stdout)\n"
		"  -h          Show this help\n",
		prog);
}

int main(int argc, char *argv[])
{
	if (argc < 2) {
		usage(argv[0]);
		return 1;
	}

	const char *input_path = nullptr;
	const char *output_path = nullptr;
	DisplayMode mode = DISPLAY_INTERACTIVE;

	// Parse arguments
	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
			usage(argv[0]);
			return 0;
		} else if (strcmp(argv[i], "-b") == 0) {
			mode = DISPLAY_BATCH;
		} else if (strcmp(argv[i], "-q") == 0) {
			mode = DISPLAY_QUIET;
		} else if (strcmp(argv[i], "-o") == 0) {
			if (i + 1 >= argc) {
				fprintf(stderr, "error: -o requires a filename\n");
				return 1;
			}
			output_path = argv[++i];
		} else if (argv[i][0] != '-') {
			input_path = argv[i];
		} else {
			fprintf(stderr, "error: unknown option '%s'\n", argv[i]);
			usage(argv[0]);
			return 1;
		}
	}

	if (!input_path) {
		fprintf(stderr, "error: no input file specified\n");
		usage(argv[0]);
		return 1;
	}

	// Open output
	FILE *out = stdout;
	if (output_path) {
		out = fopen(output_path, "w");
		if (!out) {
			fprintf(stderr, "error: cannot open '%s' for writing\n", output_path);
			return 1;
		}
	}

	// Parse input
	TomasuloConfig cfg;
	Simulator sim;
	if (parse_input(input_path, &cfg, &sim) != 0)
		return 1;

	if (sim.num_instructions == 0) {
		fprintf(stderr, "No valid instructions found.\n");
		return 1;
	}

	// Show initial state
	if (mode != DISPLAY_QUIET) {
		fprintf(out, "Loaded %d instructions.\n", sim.num_instructions);
		fprintf(out, "Configuration:\n");
		for (int i = 0; i < OP_COUNT; i++) {
			fprintf(out, "  %-6s latency: %d cycles\n", opcode_name((Opcode)i),
				cfg.latency[i]);
		}
		fprintf(out, "Reservation stations:\n");
		const char *rs_names[] = { "Add/Sub", "Mul/Div", "Load", "Store" };
		for (int i = 0; i < RS_TYPE_COUNT; i++) {
			fprintf(out, "  %-8s: %d units\n", rs_names[i], cfg.num_rs[i]);
		}
		fprintf(out, "\n");
	}

	// Run simulation
	const int MAX_CYCLES = 500;

	setvbuf(out, NULL, _IOFBF, 1 << 16); // fully buffered
	while (!sim_done(&sim) && sim.cycle < MAX_CYCLES) {
		sim_step(&sim);

		if (mode == DISPLAY_INTERACTIVE) {
			fprintf(out, "\033[2J\033[H");
			display_cycle(out, &sim);
			fflush(stdout);
			if (out == stdout) {
				fprintf(stderr,
					"[cycle %d] Press Enter to continue (q to run all)...",
					sim.cycle);
				int ch = getchar();
				if (ch == 'q' || ch == 'Q') {
					mode = DISPLAY_BATCH;
					// consume rest of line
					while (ch != '\n' && ch != EOF)
						ch = getchar();
				}
			}
		} else if (mode == DISPLAY_BATCH) {
			display_cycle(out, &sim);
		}
	}
	setvbuf(out, NULL, _IOFBF, 0); // Return to line-buffered out

	if (sim.cycle >= MAX_CYCLES && !sim_done(&sim)) {
		fprintf(out,
			"\nSimulation exceeded %d cycles (possible deadlock). "
			"Aborting.\n",
			MAX_CYCLES);
	}

	display_final(out, &sim);

	if (out != stdout)
		fclose(out);

	return 0;
}
