<!--
    SPDX-License-Identifier: ISC
    SPDX-FileCopyrightText: Copyright © 2026 Lucca M. A. Pellegrini <lucca@verticordia.com>
    NOTE: Explanation file written with help from LLMs.
-->

# Simulations Documentation

This directory contains Tomasulo simulation files (`.tom` files) that validate
various aspects of the Tomasulo's Algorithm simulator implementation. Each
simulation is designed to stress specific features, hazards, or performance
characteristics of the simulator.

## Simulation Structure

Each `.tom` simulation file follows the configuration format described in the
main [README](../README.md#configuration-format--tom-files-). A typical file
looks like this:

<!-- Obviously the files here aren't TOML, but I just think plain colorless text sucks here -->
```toml
cycles {
    add.d  = 2
    mult.d = 4
}

units {
    add.d  = 1
    mult.d = 1
}

registers {
    F0 = 1.0
    F1 = 2.0
}

instructions {
    ADD.D F2 F0 F1
}
```

Conceptually:

| Section        | Meaning                                              |
| -------------- | ---------------------------------------------------- |
| `cycles`       | Execution latency for each operation type           |
| `units`        | Number of reservation stations/functional units     |
| `registers`    | Initial values for architectural and integer regs   |
| `instructions` | Program instructions in order of execution          |

Simulations are organized to progressively demonstrate more complex behaviors
of the Tomasulo algorithm, from basic functionality to intricate hazard
handling and resource contention scenarios.

## Conventions

Many simulations use a simple memory model where loads return `base + offset`.
For example, with `R1 = 100`, a load `L.D F0 8(R1)` yields
\(F_0 = 8 + 100 = 108\). When relevant, the simulation descriptions below refer
to this model.

The simulator uses a unified register file: integer and floating-point
registers share indices, so `R2` and `F2` refer to the same architected
location. Simulations that rely on this (for example, when using distant base
registers like `R30`/`R31`) are noted explicitly.

## Running Simulations

Individual simulation can be run using:

```bash
zig build run -- simulations/<simulation_name>.tom
```

To run in batch mode (no interactive stepping):

```bash
zig build run -- -b simulations/<simulation_name>.tom
```

Other useful flags are documented in the simulator help:

```bash
zig build run -- --help
```

---

### [basic.tom](basic.tom)

Demonstrates a short dependency chain with three arithmetic instructions and
true data dependencies (RAW hazards).

Program:

```asm
ADDD  F8  F4 F6
MULTD F10 F8 F8
SUBD  F12 F10 F4
```

With the provided configuration, the final state satisfies
\(F_8 = F_4 + F_6\), \(F_{10} = F_8 \times F_8\), and
\(F_{12} = F_{10} - F_4\).

### [chain.tom](chain.tom)

Creates a longer dependency chain to evaluate how the Tomasulo algorithm
handles multiple consecutive dependent instructions.

Program:

```asm
ADDD  F1 F2 F3
MULTD F4 F1 F5
ADDD  F6 F4 F7
MULTD F8 F6 F9
```

With the initial register values in `chain.tom`, the chain computes
\(F_1, F_4, F_6, F_8\) as successive dependents; only one instruction can
proceed at a time because each result feeds the next.

### [deep_chain.tom](deep_chain.tom)

Creates a very deep dependency chain with alternating operations to
stress-test the Tomasulo algorithm's ability to handle long dependency
sequences and exercise all floating-point units. It executes 12
instructions in a chain where each depends on the previous one,
alternating between ADD, MUL, SUB, and DIV operations.

Program:

```asm
ADD.D F1  F0  F20
MUL.D F2  F1  F21
SUB.D F3  F2  F20
DIV.D F4  F3  F20
ADD.D F5  F4  F21
MUL.D F6  F5  F22
SUB.D F7  F6  F24
DIV.D F8  F7  F21
ADD.D F9  F8  F23
MUL.D F10 F9  F21
SUB.D F11 F10 F25
DIV.D F12 F11 F23
```

Starting from \(F_0 = 2\) and the constants defined in `deep_chain.tom`,
the final result is \(F_{12} = 4\). The simulation highlights how operation
latencies and limited functional units impact throughput in a strictly
serial chain.

### [div_stress.tom](div_stress.tom)

Focuses on stress-testing the division unit and examining CDB behavior
when multiple long-latency operations complete in close succession, while
shorter-latency adds run in parallel.

Program:

```asm
DIV.D F10 F0 F1
DIV.D F11 F2 F3
DIV.D F12 F4 F5
DIV.D F13 F6 F7
ADD.D F14 F0 F1
ADD.D F15 F4 F5
ADD.D F16 F10 F11
ADD.D F17 F12 F13
```

The independent adds \(F_{14}\) and \(F_{15}\) can complete while the
divisions are still in flight; the final adds \(F_{16}\) and
\(F_{17}\) must wait for the corresponding division results on the CDB.

### [dot_product.tom](dot_product.tom)

Computes the dot product of two 4-element vectors to demonstrate parallel
execution capabilities and tree-style reduction.

Mathematically, the simulation evaluates
\(\mathbf{A} \cdot \mathbf{B} = \sum_{i=0}^{3} A[i] \times B[i]\) with
\(\mathbf{A} = [2,3,4,5]\) in \(F_0..F_3\) and
\(\mathbf{B} = [1,2,3,4]\) in \(F_4..F_7\).

Program:

```asm
MUL.D F8  F0 F4
MUL.D F9  F1 F5
MUL.D F10 F2 F6
MUL.D F11 F3 F7
ADD.D F12 F8  F9
ADD.D F13 F10 F11
ADD.D F14 F12 F13
```

The four multiplies can execute in parallel on the multiplier units; the
reduction steps form a small tree. The final result is \(F_{14} = 40\).

### [fibonacci.tom](fibonacci.tom)

Computes Fibonacci numbers using a strict sequential dependency chain to
demonstrate how the Tomasulo algorithm handles true data dependencies
in a dependency-limited workload.

Recurrence:

\[\mathit{fib}(n) = \mathit{fib}(n-1) + \mathit{fib}(n-2)\]

Program:

```asm
ADD.D F2 F0 F1
ADD.D F3 F1 F2
ADD.D F4 F2 F3
ADD.D F5 F3 F4
ADD.D F6 F4 F5
ADD.D F7 F5 F6
```

Starting from \(F_0 = F_1 = 1\), the simulation yields
\(F_2..F_7 = 2,3,5,8,13,21\) in program order.

### [hennessy.tom](hennessy.tom)

Implements the classic Tomasulo algorithm example from Hennessy & Patterson's
"Computer Architecture: A Quantitative Approach". It combines memory
operations, arithmetic operations, and multiple dependencies.

Program:

```asm
L.D   F6  34(R2)
L.D   F2  45(R3)
MUL.D F0  F2 F4
SUB.D F8  F6 F2
DIV.D F10 F0 F6
ADD.D F6  F8 F2
```

The simulation exercises load buffers, long-latency division, and an overwrite
of \(F_6\) by the final add while preserving correct commit order.

### [horner.tom](horner.tom)

Implements Horner's method for polynomial evaluation to demonstrate how the
Tomasulo algorithm handles long, strictly-serial dependency chains that
alternate between two operation types.

The polynomial is

\[p(x) = a_3 x^3 + a_2 x^2 + a_1 x + a_0\]

evaluated via Horner's rule

\[p(x) = ((a_3 x + a_2) x + a_1) x + a_0.\]

Program:

```asm
MULTD F10 F1  F0
ADDD  F11 F10 F2
MULTD F12 F11 F0
ADDD  F13 F12 F3
MULTD F14 F13 F0
ADDD  F15 F14 F4
```

With \(x = 2\) and coefficients \(a_3 = 1, a_2 = 2, a_1 = 3, a_0 = 4\),
the final result is \(p(2) = 26\) in \(F_{15}\).

### [all_ops.tom](all_ops.tom)

Exercises every supported instruction type exactly once to verify basic
functionality of all unit types, using six independent instructions with
no RAW hazards.

Program:

```asm
L.D   F10 8(R1)
ADD.D F11 F0 F1
SUB.D F12 F0 F2
MUL.D F13 F3 F1
DIV.D F14 F4 F3
S.D   F11 16(R1)
```

With the initial state in `all_ops.tom`, this confirms that each unit type
produces the expected result and that independent operations can overlap.

### [cdb_contention.tom](cdb_contention.tom)

Demonstrates Common Data Bus (CDB) contention in the Tomasulo algorithm.
Four ADD instructions are issued; three depend on the result of the first.

Program:

```asm
ADDD F10 F0 F1
ADDD F11 F10 F2
ADDD F12 F10 F3
ADDD F13 F10 F4
```

With ADD latency of 2 cycles and four add reservation stations, the three
dependent instructions finish execution on the same cycle and then queue
on the CDB. Numerically, the final values are \(F_{10} = 3\),
\(F_{11} = 6\), \(F_{12} = 7\), \(F_{13} = 8\).

### [daxpy.tom](daxpy.tom)

Implements a DAXPY-style kernel \(Y_i = a \times X_i + Y_i\), a canonical
scientific-computing inner loop and a textbook Tomasulo example.

Program (one unrolled iteration):

```asm
L.D   F0 0(R1)
L.D   F2 0(R2)
MUL.D F4 F0 F2
L.D   F6 0(R3)
ADD.D F8 F4 F6
S.D   F8 0(R3)
```

The three loads can overlap on the load buffers, the add waits for the
multiplier result, and the final store waits for the add via the CDB.

### [matrix_elem.tom](matrix_elem.tom)

Computes a single matrix element
\(C[i,j] = \sum_{k=0}^{2} A[i,k] \times B[k,j]\), corresponding to the
inner loop of a 3×3 matrix multiplication. It loads row \(i\) of \(A\)
and column \(j\) of \(B\), multiplies corresponding elements, and sums
them.

Program:

```asm
L.D F0 0(R1)
L.D F1 8(R1)
L.D F2 16(R1)
L.D F3 0(R2)
L.D F4 8(R2)
L.D F5 16(R2)
MUL.D F6 F0 F3
MUL.D F7 F1 F4
MUL.D F8 F2 F5
ADD.D F9  F6 F7
ADD.D F10 F9 F8
```

Using the standard load model, this corresponds to \(C[i,j] = 1\times4 +
2\times5 + 3\times6 = 32\) scaled by the chosen base values. The simulation
focuses on load–multiply–add patterns and reuse of loaded values.

### [mixed_stress.tom](mixed_stress.tom)

Performs a mixed-workload stress test exercising every functional unit type. It
loads four values, performs independent multiplies and adds, a divide, a
subtract, and finally stores results back to memory. The simulation mixes
independent loads (parallel on the load buffers), RAW dependencies across unit
types (LD → MUL → ADD), a long-latency DIV running in parallel with shorter
operations, a WAW on \(F_{20}\), and stores that must wait on their producers.

Program:

```asm
L.D   F20 0(R30)
L.D   F21 8(R30)
L.D   F22 16(R31)
L.D   F23 24(R31)
MUL.D F8  F20 F21
MUL.D F10 F22 F23
ADD.D F12 F8  F10
SUB.D F14 F10 F8
DIV.D F16 F12 F14
ADD.D F20 F16 F21
S.D   F12 32(R30)
S.D   F20 40(R30)
```

Because integer and FP register indices are shared, base registers
\(R_{30}\) and \(R_{31}\) are chosen far from the FP destinations to
avoid accidental aliasing.

### [parallel.tom](parallel.tom)

Demonstrates instruction-level parallelism in the Tomasulo algorithm by
executing independent instructions that can run concurrently.

Program:

```asm
ADDD  F1 F2 F3
ADDD  F4 F5 F6
MULTD F7 F1 F4
MULTD F8 F2 F5
```

With two add units and two multiply units available, the two ADDD
instructions can execute in parallel, followed by overlapping multiplies
once dependencies are resolved.

### [producer_consumer.tom](producer_consumer.tom)

Demonstrates the producer–consumer pattern with multiple consumers to
validate the CDB broadcast mechanism. One multiply produces a value that
four adds consume.

Program:

```asm
MUL.D F10 F0 F1
ADD.D F11 F10 F2
ADD.D F12 F10 F3
ADD.D F13 F10 F4
ADD.D F14 F10 F5
```

With four add units, all consumers can start executing on the cycle when
\(F_{10}\) broadcasts, and then they contend for the CDB to write their
results.

### [quadratic.tom](quadratic.tom)

Computes one root of the quadratic formula

\[x = \frac{-b + \sqrt{b^2 - 4ac}}{2a}\]

using a precomputed square root to focus on the dependency structure.

For \(a = 1, b = 5, c = 6\) (roots at \(x = -2, x = -3\)), the simulation
computes the root \(x = -2\).

Program:

```asm
MUL.D F10 F1 F1
MUL.D F11 F3 F0
MUL.D F12 F11 F2
SUB.D F13 F10 F12
SUB.D F15 F5 F1
ADD.D F16 F15 F14
MUL.D F17 F4 F0
DIV.D F18 F16 F17
```

The sequence combines multiplies, subtracts, an add, and a final divide to
form the numerator and denominator of the quadratic expression.

### [reduction.tom](reduction.tom)
Implements a parallel reduction (sum of 8 elements using tree reduction) to
demonstrate how the Tomasulo algorithm handles tree-shaped dependency patterns
that maximize parallelism.
Given 8 values \([1,2,3,4,5,6,7,8]\) in \(F_0..F_7\), the program reduces them to
a single sum in \(F_{16}\).
Program:
```asm
ADD.D F10 F0 F1
ADD.D F11 F2 F3
ADD.D F12 F4 F5
ADD.D F13 F6 F7
ADD.D F14 F10 F11
ADD.D F15 F12 F13
ADD.D F16 F14 F15
```

With four add units, level 0 executes in parallel, then level 1, then level 2.
Total depth is three additions (\(\log2 8 = 3\)), yielding \(F{16} = 36\).

### [store_forward.tom](store_forward.tom)

Exercises store and load patterns to verify memory ordering and
store-to-load forwarding in the Tomasulo algorithm, using a mix of
independent and dependent memory operations.

Program:

```asm
L.D   F0 0(R1)
L.D   F1 8(R1)
ADD.D F2 F0 F1
MUL.D F3 F0 F10
S.D   F2 32(R1)
S.D   F3 40(R1)
L.D   F4 0(R2)
L.D   F5 8(R2)
ADD.D F6 F4 F5
```

Loads to different addresses can run in parallel; stores must wait on
their producers, and later loads observe the correct values given the
simulator's memory model.

### [structural.tom](structural.tom)

Demonstrates structural hazards in the Tomasulo algorithm by executing
more ADD instructions than available Add reservation stations. With only
one Add RS, the 2nd and 3rd ADD instructions must stall until the first
frees up.

Program:

```asm
ADDD F10 F1 F2
ADDD F11 F3 F5
ADDD F12 F7 F9
```

All three ADD instructions are independent; only structural limits force
them to serialize at the reservation station level.

### [minimal.tom](minimal.tom)

Minimal sanity check that the Tomasulo simulator can execute a single
arithmetic instruction with both operands ready and no hazards or
contention.

Program:

```asm
ADD.D F2 F0 F1
```

With initial register values \(F_0 = 1\) and \(F_1 = 2\), the expected
result is \(F_2 = 3\). This validates the basic issue/execute/writeback
pipeline, reservation station allocation, ROB handling, and CDB
broadcast for the simplest non-trivial program.

### [single_add.tom](single_add.tom)

Even more stripped-down variant of `minimal.tom`, designed to exercise
the edge case of a program with exactly one instruction and a 1-cycle
adder latency.

Program:

```asm
ADD.D F0 F1 F1
```

With the initial register value \(F_1 = 1\), the expected result is
\(F_0 = 2\). This validates that the simulator correctly handles a
single-ADD program from start to finish (issue, execute in one cycle,
writeback, and commit) without hazards or structural stalls.

### [load_use.tom](load_use.tom)

Demonstrates a classic load–use hazard, where an arithmetic instruction
immediately follows a load that produces one of its source operands. Two
independent loads execute in parallel, then a chain of dependent
arithmetic operations consumes their results.

Program:

```asm
L.D   F2 8(R1)
L.D   F4 16(R1)
ADD.D F6 F2 F4
MUL.D F8 F6 F2
```

With base register \(R_1 = 100\), the simulator models memory such that a
load from offset \(k\) returns \(k + 100\). Independent loads to
different addresses can execute in parallel on multiple load buffers,
the `ADD.D` waits for both loads to broadcast their results on the CDB,
and the dependent `MUL.D` waits on the result of the add.

### [war.tom](war.tom)

Demonstrates a Write-After-Read (WAR) hazard scenario and shows how
Tomasulo’s register renaming prevents it. Several instructions read from
\(F_2\) while a later instruction overwrites \(F_2\), and a final
instruction must see the new value.

Program:

```asm
ADD.D F4 F2 F3
MUL.D F6 F2 F3
SUB.D F2 F0 F1
ADD.D F8 F2 F1
```

In a naive pipeline, the write to \(F_2\) in the `SUB.D` could clobber
the value that the earlier instructions still need to read, creating a
WAR hazard. Tomasulo’s algorithm avoids this via register renaming and
ROB ordering so the adds and multiply read the original \(F_2\), while
the later `ADD.D F8` reads the renamed, updated \(F_2\).

### [waw.tom](waw.tom)

Focuses on a Write-After-Write (WAW) hazard, where two instructions in
program order both write the same architectural register \(F_1\), but
with different latencies. A third instruction then consumes the final
value.

Program:

```asm
MUL.D F1 F4 F5
ADD.D F1 F2 F3
ADD.D F6 F1 F7
```

Because `MUL.D` is much slower than `ADD.D`, it will finish after the
add. In a naive design, the late `MUL.D` could overwrite \(F_1\) with
its value, clobbering the correct, last-writer value. Tomasulo’s
algorithm uses the ROB and RAT so only the ADD’s result becomes the
architected \(F_1\), and the consumer \(F_6\) is bound to that final
value.

### [wide_issue.tom](wide_issue.tom)

Performs a wide-issue, high-parallelism stress simulation with many independent
operations. It saturates the available reservation stations and functional
units to exercise the issue logic, scheduling, and CDB contention behavior.

Program:

```asm
L.D   F0 0(R1)
L.D   F1 8(R1)
L.D   F2 16(R1)
L.D   F3 0(R2)
L.D   F4 8(R2)
L.D   F5 16(R2)
MUL.D F10 F21 F22
MUL.D F11 F23 F24
MUL.D F12 F25 F26
MUL.D F13 F27 F28
ADD.D F14 F20 F21
ADD.D F15 F22 F23
ADD.D F16 F24 F25
ADD.D F17 F26 F27
With base registers \(R1 = 100\), \(R2 = 200\) and the constants defined in
wide_issue.tom, loads, multiplies, and adds can all overlap across multiple
units, and the CDB must arbitrate among many long-latency completions.
