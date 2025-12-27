# Systolic Array Project

## Abstract
Fixed-point 4×4 systolic array for signed matrix multiplication. The RTL stack, generator, and testbench were refactored so the entire flow is driven by one parameter—`FRAC_WIDTH`—enabling different Q-series formats (e.g. Q1.15, Q8.8).

## Repository Structure
- `rtl/` – multiplier, adder, MAC PE, systolic fabric, controller, dual-port RAMs, and the top-level wrapper.
- `tb/` – `tb_systolic_top.sv`, a self-checking SystemVerilog environment.
- `scripts/` – `fixed_point_data_gen.py` emits deterministic instruction/data/expected memories.
- `include/` – `systolic_config.vh` centralizes all macro definitions.
- `Makefile` – orchestrates generation, compilation, simulation, and cleanup.

## Parameterization Strategy
- `SYSTOLIC_FRAC_WIDTH` defaults to 15 but is overridden via `make run FRAC_WIDTH=<N>`.
- The Makefile forwards the value to both the Python generator (`--frac`) and the RTL (`+define+`).
- Operand bounds in the generator are computed as `int(5.6 * 2^FRAC_WIDTH)` (clamped to signed 16-bit) so dot products stay within the accumulator’s saturation region.
- Other widths (`SYSTOLIC_INPUT_WIDTH`, `SYSTOLIC_RESULT_WIDTH`, `SYSTOLIC_ADDR_WIDTH`) remain constant at 16/16/10 to keep floorplan requirements stable.

## Architecture Overview
### Data Path
Sixteen identical MAC processing elements (PEs) form a 4×4 mesh. Each PE registers incoming activations (north) and weights (west), performs a signed 16×16 multiply, aligns the binary point by right-shifting `FRAC_WIDTH` bits, applies symmetric saturation, accumulates, and forwards operands to east/south neighbors on the next cycle. Steady state throughput is 16 MACs per clock regardless of Q-format.

### Control Path
`rtl/systolic_controller.v` implements a three-phase FSM per instruction:
1. **Load** – fetch matrix dimension from instruction memory and coordinate operand reads.
2. **Compute** – stream tiles through the array for `dimension/4` iterations while tracking fill/drain latency.
3. **Store** – capture array outputs and commit them to the result memory.
The controller exposes `ap_start` and `ap_done`, allowing workloads to queue sequentially.

### Memory Subsystem
Three dual-port RAMs store operand A, operand B, and results; a fourth RAM holds the instruction stream. Port A of every RAM is reserved for host programming, while Port B belongs to the controller, avoiding contention between initialization and execution phases.

## Processing Element Microarchitecture
- **`rtl/multiplier.v`** – Signed 16-bit multiply, binary-point shift via `FRAC_WIDTH`, symmetric saturation at ±2¹⁵.
- **`rtl/adder.v`** – Aligns partial sums, performs signed addition with saturation, and registers the output.
- **`rtl/mac_pe.v`** – Wraps multiplier, adder, and operand forwarding registers, enforcing deterministic one-cycle-per-hop timing across the mesh.

## Verification and Data Generation Flow
1. `scripts/fixed_point_data_gen.py --frac N` (invoked by the Makefile) produces `instructions.mem`, `dataA.mem`, `dataB.mem`, and `expected.mem` in `build/`. A fixed RNG seed guarantees reproducibility.
2. `tb/tb_systolic_top.sv` loads those memories through the host interface, programs the DUT, asserts `ap_start`, and waits for `ap_done` with timeout protection.
3. DUT outputs are dumped to `build/output.mem` and compared entry-by-entry against `expected.mem`, with detailed mismatch diagnostics if needed.
This flow keeps the software generator and hardware implementation synchronized whenever `FRAC_WIDTH` changes.

## Usage
```bash
make run            # default Q1.15 flow
make run FRAC_WIDTH=8  # example Q8.8 run
make clean          # remove build artifacts
```
Artifacts of interest: `build/{instructions,dataA,dataB,expected}.mem`, `build/output.mem`, and the simulator log (which reports the active Q format).

## Qualitative Evaluation
- **Performance** – Once the array is primed, throughput is 16 MAC/cycle. Latency per instruction is approximately `load_cycles + dimension + drain_cycles`; larger matrices better amortize fill/drain overhead. Critical path is the multiplier→adder chain, qualitatively implying a low-hundreds-of-megahertz ceiling in mainstream CMOS.
- **Power** – Dominated by multiplier/adder switching and dual-port RAM accesses. Energy scales roughly with matrix dimension because more rows toggle for longer durations. Tweaking `FRAC_WIDTH` shifts operand magnitudes slightly but does not alter the overall trend.
- **Area** – Set primarily by the sixteen MAC PEs and three dual-port memories. Since datapaths remain 16 bits, silicon area is effectively constant unless the array dimension or memory depth changes.

## Future Enhancements
- Integrate a synthesis + STA + power script (Yosys/OpenROAD or commercial) to provide quantitative PPA numbers.
- Add optional cycle counters so the testbench can emit latency statistics per instruction stream.
