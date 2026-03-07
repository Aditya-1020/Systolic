"""
scripts/vec_utils.py  –  Shared utilities for all gen_<module>.py scripts

IMPORT IN YOUR GENERATOR:
    import sys, os
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))
    from vec_utils import VecWriter, fmt, pe_model  # etc.

DESIGN PHILOSOPHY
─────────────────
Each module generator (tb/gen_<module>.py) only needs to:
  1. Define what vectors look like (corner cases + random cases)
  2. Define a software model that computes expected outputs
  3. Call VecWriter to write the hex files

Everything else – two's-complement encoding, file management, CLI arg
parsing, the "one file per field" pattern – lives here and is reused.
"""

import os
import random
import argparse

def to_unsigned(val: int, width: int) -> int:
    """Signed integer → unsigned two's-complement representation."""
    return val & ((1 << width) - 1)

def fmt(val: int, width_bits: int) -> str:
    """
    Zero-padded uppercase hex string for val at the given bit width.

    Examples:
        fmt(-1, 8)   → 'FF'
        fmt(-1, 16)  → 'FFFF'
        fmt(255, 8)  → 'FF'
    """
    hex_digits = width_bits // 4
    return f"{to_unsigned(val, width_bits):0{hex_digits}X}"

class VecWriter:
    """ Writes one hex file per named field into an output directory.

    USAGE
    ─────
        writer = VecWriter(
            out_dir  = args.outdir,
            fields   = {
                # name        : bit width
                "tv_data"     : 8,
                "tv_weight"   : 8,
                "tv_psum"     : 32,
                "gold_mult"   : 16,
                "gold_mac"    : 32,
            }
        )

        for data, weight, psum in vectors:
            mult, mac = my_model(data, weight, psum)
            writer.write(
                tv_data   = data,
                tv_weight = weight,
                tv_psum   = psum,
                gold_mult = mult,
                gold_mac  = mac,
            )

        writer.close()
        writer.report()   # prints file paths + vector count
    """
    
    def __init__(self, out_dir: str, fields: dict):
        """
        out_dir : directory where hex files are written
        fields  : ordered dict of {field_name: bit_width}
        """
        os.makedirs(out_dir, exist_ok=True)
        self._fields   = fields          # {name: width}
        self._out_dir  = out_dir
        self._count    = 0
        self._handles  = {
            name: open(os.path.join(out_dir, f"{name}.hex"), "w")
            for name in fields
        }

    def write(self, **values):
        """ Write one row. Keyword args must match the field names exactly. """
        for name, width in self._fields.items():
            self._handles[name].write(fmt(values[name], width) + "\n")
        self._count += 1

    def close(self):
        for f in self._handles.values():
            f.close()

    def report(self):
        print(f"[vec_utils] {self._count} vectors written to {self._out_dir}/")
        for name in self._fields:
            print(f"  {name+'.hex':<24} ({self._fields[name]}b per entry)")

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


def base_parser(description: str) -> argparse.ArgumentParser:
    """
    Standard CLI arguments shared by every gen_<module>.py.
    Add module-specific args after calling this:

        parser = base_parser("Generate conv_layer vectors")
        parser.add_argument("--channels", type=int, default=1)
        args = parser.parse_args()
    """
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument("-n", "--num",    type=int, default=100, help="Number of random test cases (corners always added)")
    parser.add_argument("-s", "--seed",   type=int, default=42, help="RNG seed for reproducibility")
    parser.add_argument("-o", "--outdir", default=".", help="Output directory for hex files")
    return parser


#Helpers
def rand_signed(rng: random.Random, bits: int) -> int:
    """Uniform random signed integer for the given bit width."""
    lo = -(1 << (bits - 1))
    hi =  (1 << (bits - 1)) - 1
    return rng.randint(lo, hi)


def rand_signed_small(rng: random.Random, bits: int, frac: float = 0.3) -> int:
    """
    Random signed integer biased toward zero.
    frac = probability of returning 0 (useful for psum in multiply-only tests).
    """
    return 0 if rng.random() < frac else rand_signed(rng, bits)