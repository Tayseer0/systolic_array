#!/usr/bin/env python3
"""
Utility script to generate fixed-point matrices for the 4x4 systolic array.

It produces four memory image files plus a JSON metadata file that describe
the input operands, instruction stream, and expected outputs. The SystemVerilog
testbench consumes the `.mem` files directly.
"""

import argparse
import json
import random
from pathlib import Path
from typing import List, Dict, Any, Tuple


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
    base_real_limit = 5.6  # keep products/accumulations in-range
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
) -> Tuple[List[int], List[int], List[int], List[int], Dict[str, Any]]:
    instructions: List[int] = []
    data_a: List[int] = []
    data_b: List[int] = []
    expected: List[int] = []
    meta: Dict[str, Any] = {
        "frac_width": frac_width,
        "value_range": value_range,
        "instructions": [],
    }

    a_base = 0
    b_base = 0
    o_base = 0
    expected_base = 0

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

        meta["instructions"].append(
            {
                "size": size,
                "a_base": a_base,
                "b_base": b_base,
                "o_base": o_base,
                "expected_base": expected_base,
            }
        )

        a_base += size * 4
        b_base += size * 4
        o_base += size * size
        expected_base += size * size

    instructions.append(0)  # termination instruction
    meta["instruction_count"] = len(sizes)
    meta["total_a_words"] = a_base
    meta["total_b_words"] = b_base
    meta["total_expected_words"] = expected_base

    return instructions, data_a, data_b, expected, meta


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

    random.seed(1)
    value_range = compute_value_range(args.frac_width)
    instruction_sizes = [4, 8, 16]
    instructions, data_a, data_b, expected, meta = build_payload(
        instruction_sizes, args.frac_width, value_range
    )

    out_dir = Path("build")
    out_dir.mkdir(parents=True, exist_ok=True)

    write_mem_file(out_dir / "instructions.mem", instructions)
    write_mem_file(out_dir / "dataA.mem", data_a)
    write_mem_file(out_dir / "dataB.mem", data_b)
    write_mem_file(out_dir / "expected.mem", expected)

    with (out_dir / "vectors_meta.json").open("w", encoding="utf-8") as handle:
        json.dump(meta, handle, indent=2)

    print(
        f"Wrote {meta['instruction_count']} instruction blocks to {out_dir} "
        f"(instructions+dataA+dataB+expected)."
    )


if __name__ == "__main__":
    main()

