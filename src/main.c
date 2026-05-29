// SPDX-License-Identifier: MIT
// Tomasulo Algorithm Simulator -- Entry Point
//
// Usage:
//   tomasulo <input.tom>                  (interactive mode)
//   tomasulo <input.tom> -b               (batch mode, print all cycles)
//   tomasulo <input.tom> -q               (quiet, only final state)
//   tomasulo <input.tom> -o <output.txt>  (write output to file)
//
#include "display.h"
#include "parser.h"
#include "tomasulo.h"

#include <stdio.h>
#include <string.h>
#include <getopt.h>

static void usage(const char *prog)
{
	fprintf(stderr,
		"Tomasulo Algorithm Simulator\n\n"
		"Usage: %s <input.tom> [options]\n\n"
		"Options:\n"
		"  -b          Batch mode (print all cycles, no pause)\n"
		"  -q          Quiet mode (only print final state)\n"
		"  -o <file>   Write output to file (default: stdout)\n"
		"  -h          Show this help\n",
		prog);
}

int main(int argc, char *argv[])
{
	const char *input_path = nullptr;
	const char *output_path = nullptr;
	DisplayMode mode = DISPLAY_INTERACTIVE;
	int opt;

	// Parse arguments
	struct option long_options[] = { { "help", no_argument, NULL, 'h' },
					 { "batch", no_argument, NULL, 'b' },
					 { "quiet", no_argument, NULL, 'q' },
					 { "output", required_argument, NULL, 'o' },
					 { NULL, 0, NULL, 0 } };

	while ((opt = getopt_long(argc, argv, "hbqo:", long_options, NULL)) != -1) {
		switch (opt) {
		case 'h':
			usage(argv[0]);
			return 0;
		case 'b':
			mode = DISPLAY_BATCH;
			break;
		case 'q':
			mode = DISPLAY_QUIET;
			break;
		case 'o':
			output_path = optarg;
			break;
		default:
			usage(argv[0]);
			return 1;
		}
	}

	// Handle positional arguments (input file)
	if (optind < argc) {
		input_path = argv[optind];
	}

	// Handle stdin input: if no input or "-" is specified
	if (!input_path || strcmp(input_path, "-") == 0)
		input_path = "/dev/stdin";


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
