/*
 * SPDX-License-Identifier: ISC
 * SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
 * SPDX-FileCopyrightText: Copyright © 2026 Paulo Dimas Junior <paulo.junior.1478361@sga.pucminas.br>
 * SPDX-FileCopyrightText: Copyright © 2026 Amanda Canizela Guimarães <amanda.canizela@gmail.com>
 * SPDX-FileCopyrightText: Copyright © 2026 Ariel Inácio Jordão <arielijordao@gmail.com>
 * SPDX-FileCopyrightText: Copyright © 2026 Pedro Vitor Andrade <pedrovitor0826@gmail.com>
 */

#include "display.h"
#include "parser.h"
#include "tomasulo.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>

static void usage(const char *prog)
{
	fprintf(stderr,
		"A Tomasulo Algorithm Simulator\n\n"
		"Usage: %s [OPTIONS] [<FILE>]\n\n"
		"Positional arguments:\n"
		"  <FILE>               Optional input file with simulation configuration.\n"
		"                       If omitted or set to ‘-’, input is read from stdin.\n\n"
		"Options:\n"
		"  -b, --batch          Batch mode: print all cycles immediately (no pausing).\n"
		"  -q, --quiet          Quiet mode: only print the final simulation state.\n"
		"  -o, --output=<file>  Write output to <file> (default: stdout).\n"
		"  -h, --help           Show this help message and exit.\n\n"
		"Examples:\n"
		"  %s program.tom\n"
		"  %s -b -o result.log program.tom\n"
		"  %s -q - < program.tom\n\n"
		"Example program:\n\n"
		"    cycles { ADD.D  = 2; SUB.D  = 2; MULT.D = 4; DIV.D  = 10; }\n"
		"    units { ADD.D  = 1; MULT.D = 1 }\n"
		"    registers { F4 = 2.0; F6 = 10.0 }\n\n"
		"    instructions {\n"
		"        ADDD  F8  F4  F6\n"
		"        MULTD F10 F8  F8\n"
		"        SUBD  F12 F10 F4\n"
		"    }\n\n"
		"Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>\n"
		"            2026 Paulo Dimas Junior <paulo.junior.1478361@sga.pucminas.br>\n"
		"            2026 Amanda Canizela Guimarães <amanda.canizela@gmail.com>\n"
		"            2026 Ariel Inácio Jordão <arielijordao@gmail.com>\n"
		"            2026 Pedro Vitor Andrade <pedrovitor0826@gmail.com>\n\n"
		"Permission to use, copy, modify, and/or distribute this software for any\n"
		"purpose with or without fee is hereby granted, provided that the above\n"
		"copyright notice and this permission notice appear in all copies.\n",
		prog, prog, prog, prog);
}

int main(int argc, char *argv[])
{
	const char *input_path = nullptr;
	const char *output_path = nullptr;
	DisplayMode mode = DISPLAY_INTERACTIVE;

	struct option long_options[] = { { "help", no_argument, NULL, 'h' },
					 { "batch", no_argument, NULL, 'b' },
					 { "quiet", no_argument, NULL, 'q' },
					 { "output", required_argument, NULL, 'o' },
					 { NULL, 0, NULL, 0 } };

	// Parse command-line arguments
	int opt;
	while ((opt = getopt_long(argc, argv, "hbqo:", long_options, NULL)) != -1) {
		switch (opt) {
		case 'h':
			usage(argv[0]);
			return EXIT_SUCCESS;
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
			return EXIT_FAILURE;
		}
	}

	// If there's a positional argument, it's the input file
	if (optind < argc)
		input_path = argv[optind];

	// If no input path passed, or if it's equal to “-”, read from stdin
	if (!input_path || !strcmp(input_path, "-"))
		input_path = "/dev/stdin";

	// Open output file, if specified
	FILE *out = stdout;
	if (output_path) {
		if (!(out = fopen(output_path, "w"))) {
			fprintf(stderr, "error: cannot open '%s' for writing\n", output_path);
			return EXIT_FAILURE;
		}
	}

	// Disallow interactive mode if we're not using stdin/stdout
	if (mode == DISPLAY_INTERACTIVE && (!strcmp(input_path, "/dev/stdin") || out != stdout))
		mode = DISPLAY_BATCH;

	// Parse input
	TomasuloConfig cfg;
	Simulator sim;
	if (parse_input(input_path, &cfg, &sim) != 0)
		return EXIT_FAILURE;
	int warning_count = parse_last_warning_count();

	// Store the input filename in the simulator
	sim.input_filename = input_path;

	if (sim.num_instructions == 0) {
		fprintf(stderr, "No valid instructions found.\n");
		return EXIT_FAILURE;
	}

	// Display configuration
	if (mode != DISPLAY_QUIET) {
		fprintf(out, "Loaded %d instructions.\n", sim.num_instructions);

		fprintf(out, "Configuration:\n");
		for (int i = 0; i < OP_COUNT; ++i)
			fprintf(out, "  %-6s latency: %d cycles\n", opcode_name((Opcode)i),
				cfg.latency[i]);

		fprintf(out, "Reservation stations:\n");
		const char *rs_names[] = { "Add/Sub", "Mul/Div", "Load", "Store" };
		for (int i = 0; i < RS_TYPE_COUNT; ++i)
			fprintf(out, "  %-8s: %d units\n", rs_names[i], cfg.num_rs[i]);

		fprintf(out, "\n");
	}

	// In interactive mode with stdout, give the user a chance to read and
	// optionally react to any parser warnings before we start clearing the
	// screen for cycle displays.
	if (mode == DISPLAY_INTERACTIVE && out == stdout && warning_count > 0) {
		fprintf(stderr, "Parser emitted %d warning%s. Ignore warning and continue [y/N]? ",
			warning_count, warning_count == 1 ? "" : "s");
		int ch = getchar();
		if (ch != 'y' && ch != 'Y') {
			// Consume rest of line to leave stdin in a clean state.
			while (ch != '\n' && ch != EOF)
				ch = getchar();
			if (out != stdout)
				fclose(out);
			return EXIT_FAILURE;
		}
		while (ch != '\n' && ch != EOF)
			ch = getchar();
	}

	// Maximum number of cycle permissible (arbitrary)
	constexpr int MAX_CYCLES = 1 << 13;

	// Fully buffer output
	setvbuf(out, NULL, _IOFBF, 1 << 16);

	// Display initial state in interactive mode
	if (mode == DISPLAY_INTERACTIVE && out == stdout) {
		fprintf(out, "\033[2J\033[H"); // Clear screen
		display_cycle(out, &sim);
		fflush(stdout);

		fprintf(stderr, "[cycle %d] Press Enter to continue (q to run all)...", sim.cycle);
		int ch = getchar();
		if (ch == 'q' || ch == 'Q') {
			mode = DISPLAY_BATCH;
			// consume rest of line
			while (ch != '\n' && ch != EOF)
				ch = getchar();
		}
	}

	// Run the simulation
	while (!sim_done(&sim) && sim.cycle < MAX_CYCLES) {
		sim_step(&sim);

		if (mode == DISPLAY_INTERACTIVE) {
			fprintf(out, "\n\033[2J\033[H"); // Clear screen
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
			fprintf(out, "\n"); // Separate cycles neatly
			display_cycle(out, &sim);
		}
	}
	setvbuf(out, NULL, _IOFBF, 0); // Return to default line-buffered output

	// Clear screen for final stats if in interactive mode
	if (mode == DISPLAY_INTERACTIVE && out == stdout)
		fprintf(out, "\033[2J\033[H");
	display_final(out, &sim); // Display stats

	// Display error if we exceeded maximum iterations
	if (sim.cycle >= MAX_CYCLES && !sim_done(&sim))
		fprintf(out,
			"\nSimulation exceeded %d cycles (possible deadlock). "
			"Aborting.\n",
			MAX_CYCLES);

	// Close output file
	if (out != stdout)
		fclose(out);

	return EXIT_SUCCESS;
}
