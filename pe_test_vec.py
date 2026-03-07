"""
pe_test_vec.py  –  Generate PE test vectors + golden reference for tb_pe.sv
Output files (one per field – avoids $readmemh column-skip limitations):
  tv_data.hex    – 8-bit  signed data   values
  tv_weight.hex  – 8-bit  signed weight values
  tv_psum.hex    – 32-bit signed psum   values
  gold_mult.hex  – 16-bit signed expected multiply result
  gold_mac.hex   – 32-bit signed expected MAC result
"""

import random
import argparse
import os

def to_unsigned(val: int, width: int) -> int:
    return val & ((1 << width) - 1)

def fmt(val: int, width_bits: int) -> str:
    hex_digits = width_bits // 4
    return f"{to_unsigned(val, width_bits):0{hex_digits}X}"

def pe_model(data: int, weight: int, psum: int):
    mult = data * weight
    mac  = psum + mult
    return mult, mac

def corner_cases():
    return [
        (  5,    3,    0),    # basic positive multiply
        ( -2,    4,    0),    # negative data
        (  5,    3,   10),    # accumulate into psum
        ( -2,   10,  -20),    # negative psum
        (127,  127,    0),    # max positive 8b product (16129)
        (-128, -128,   0),    # max unsigned 8b product
        (  0,    0,    0),    # zero
        (  1,   -1,  100),    # mixed signs, non-zero psum
        (127, -128,    0),    # asymmetric extremes
        (-128,  127,   0),    # symmetric
        (  1,    1,  (2**31)//2 - 1),   # psum near positive max
        ( -1,    1, -(2**31)//2),        # psum near negative min
    ]

def random_cases(n: int, seed: int):
    """Generate n random (data, weight, psum) tuples."""
    rng = random.Random(seed)
    cases = []
    for _ in range(n):
        data   = rng.randint(-128,  127)
        weight = rng.randint(-128,  127)
        psum   = 0 if rng.random() < 0.3 else rng.randint(-(2**30), (2**30) - 1)
        cases.append((data, weight, psum))
    return cases

def write_fields(vectors, out_dir="."):
    """Write hex file per field so the TB can $readmemh read"""
    os.makedirs(out_dir, exist_ok=True)

    paths = {
        "tv_data":    os.path.join(out_dir, "tv_data.hex"),
        "tv_weight":  os.path.join(out_dir, "tv_weight.hex"),
        "tv_psum":    os.path.join(out_dir, "tv_psum.hex"),
        "gold_mult":  os.path.join(out_dir, "gold_mult.hex"),
        "gold_mac":   os.path.join(out_dir, "gold_mac.hex"),
    }

    files = {k: open(p, "w") for k, p in paths.items()}

    try:
        for data, weight, psum in vectors:
            mult, mac = pe_model(data, weight, psum)
            files["tv_data"]  .write(fmt(data,   8)  + "\n")
            files["tv_weight"].write(fmt(weight,  8)  + "\n")
            files["tv_psum"]  .write(fmt(psum,   32)  + "\n")
            files["gold_mult"].write(fmt(mult,   16)  + "\n")
            files["gold_mac"] .write(fmt(mac,    32)  + "\n")
    finally:
        for f in files.values():
            f.close()

    return paths


def main():
    parser = argparse.ArgumentParser(description="Generate PE test vectors and golden reference files")
    parser.add_argument("-n", "--num",    type=int, default=100, help="Number of random tests (corners always included)")
    parser.add_argument("-s", "--seed",   type=int, default=42, help="RNG seed for reproducibility")
    parser.add_argument("-o", "--outdir", default=".", help="Output directory for hex files")
    args = parser.parse_args()

    corners = corner_cases()
    randoms = random_cases(args.num, args.seed)
    all_vectors = corners + randoms

    paths = write_fields(all_vectors, args.outdir)

    total = len(all_vectors)
    print(f"[pe_test_vec]  {total} vectors  "
          f"({len(corners)} corners + {len(randoms)} random,  seed={args.seed})")
    for name, path in paths.items():
        print(f"  {name:12s} -> {path}")


if __name__ == "__main__":
    main()