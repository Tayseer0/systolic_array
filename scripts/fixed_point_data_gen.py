#!/usr/bin/env python3
# Generate fixed-point test vectors for systolic array
#
# Generates test vectors for systolic array verification including instruction stream,
# matrix operands, and expected results. Creates memory image files compatible with
# SystemVerilog testbench. Supports configurable fixed-point formats via fractional width.
#
# Parameters:
#   --frac: Number of fractional bits for fixed-point representation (default 15)
#           Determines Q format: Q(16-frac).frac (e.g., frac=15 -> Q1.15, frac=8 -> Q8.8)
#
# Behavior:
#   - Generates random matrices for sizes [4, 8, 16] with values constrained to prevent overflow
#   - Computes matrix products using fixed-point arithmetic with saturation
#   - Writes four memory files: instructions.mem, dataA.mem, dataB.mem, expected.mem
#   - Instruction stream contains matrix sizes followed by terminating 0
#   - Value range automatically computed based on fractional width to keep products in-range
#   - Uses fixed random seed (1) for reproducible test vectors

import argparse
import random
from pathlib import Path
from typing import List, Tuple


def saturate_s16(value: int) -> int:
    if value > 0x7FFF:
        return 0x7FFF
    if value < -0x8000:
        return -0x8000
    return value


def generate_matrix(rows: int, cols: int, value_range: int) -> List[List[int]]:
    return [
        [random.randint(-value_range, value_range) for _ in range(cols)]
        for _ in range(rows)
    ]


def compute_value_range(frac_width: int) -> int:
    base_real_limit = 5.6
    raw_limit = int(base_real_limit * (1 << frac_width))
    raw_limit = max(1, raw_limit)
    return min(raw_limit, 0x7FFF)


def multiply_matrices(
    a: List[List[int]], b: List[List[int]], frac_width: int
) -> List[List[int]]:
    rows = len(a)
    cols = len(b[0])
    depth = len(a[0])
    result = [[0 for _ in range(cols)] for _ in range(rows)]
    for r in range(rows):
        for c in range(cols):
            acc = 0
            for k in range(depth):
                acc += (a[r][k] * b[k][c]) >> frac_width
                acc = saturate_s16(acc)
            result[r][c] = saturate_s16(acc)
    return result


def flatten(matrix: List[List[int]]) -> List[int]:
    return [elem for row in matrix for elem in row]


def build_payload(
    sizes: List[int], frac_width: int, value_range: int
) -> Tuple[List[int], List[int], List[int], List[int]]:
    instructions: List[int] = []
    data_a: List[int] = []
    data_b: List[int] = []
    expected: List[int] = []

    for size in sizes:
        if size % 4 != 0:
            raise ValueError(f"Size {size} is not supported (must be a multiple of 4)")
        matrix_a = generate_matrix(size, 4, value_range)
        matrix_b = generate_matrix(4, size, value_range)
        matrix_c = multiply_matrices(matrix_a, matrix_b, frac_width)

        instructions.append(size)
        data_a.extend(flatten(matrix_a))
        data_b.extend(flatten(matrix_b))
        expected.extend(flatten(matrix_c))

    instructions.append(0)

    return instructions, data_a, data_b, expected


def write_mem_file(path: Path, values: List[int]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for value in values:
            handle.write(f"{int(value)}\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate fixed-point matrices.")
    parser.add_argument(
        "--frac",
        type=int,
        default=15,
        help="Number of fractional bits for the fixed-point representation.",
    )
    args = parser.parse_args()
    frac_width = args.frac

    random.seed(1)
    value_range = compute_value_range(frac_width)
    instruction_sizes = [4, 8, 16]
    instructions, data_a, data_b, expected = build_payload(
        instruction_sizes, frac_width, value_range
    )

    out_dir = Path("build")
    out_dir.mkdir(parents=True, exist_ok=True)

    write_mem_file(out_dir / "instructions.mem", instructions)
    write_mem_file(out_dir / "dataA.mem", data_a)
    write_mem_file(out_dir / "dataB.mem", data_b)
    write_mem_file(out_dir / "expected.mem", expected)

    print(
        f"Wrote {len(instruction_sizes)} instruction blocks to {out_dir} "
        f"(instructions+dataA+dataB+expected)."
    )


if __name__ == "__main__":
    main()
