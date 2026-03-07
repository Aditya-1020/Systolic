import sys
import os
import random
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))
from vec_utils import VecWriter, base_parser, rand_signed, rand_signed_small

DATA_W = 8
ACCUM_W = 32


def pe_model(data: int, weight: int, psum: int):
    mult = data * weight
    mac = psum + mult
    return mult, mac

def corner_cases():
    return [
        #  data   weight   psum          # what it tests
        (   5,     3,      0  ),         # basic positive multiply
        (  -2,     4,      0  ),         # negative data
        (   5,     3,     10  ),         # accumulate
        (  -2,    10,    -20  ),         # negative psum
        ( 127,   127,      0  ),         # max positive 8-bit product (16129)
        (-128,  -128,      0  ),         # largest unsigned product (16384)
        (   0,     0,      0  ),         # zero
        (   1,    -1,    100  ),         # mixed signs
        ( 127,  -128,      0  ),         # asymmetric extremes
        (-128,   127,      0  ),         # symmetric
        (   1,     1,  (2**31)//2 - 1), # psum near +max
        (  -1,     1, -(2**31)//2    ), # psum near -min
    ]

def random_cases(n: int, seed: int):
    rng = random.Random(seed)
    cases = []
    for _ in range(n):
        data   = rand_signed(rng, DATA_W)
        weight = rand_signed(rng, DATA_W)
        psum   = rand_signed_small(rng, ACCUM_W, frac=0.3)
        cases.append((data, weight, psum))
    return cases

def main():
    args = base_parser("Generate pe.sv test vectors").parse_args()
    vectors = corner_cases() + random_cases(args.num, args.seed)
    fields = {
        "tv_data":    DATA_W,
        "tv_weight":  DATA_W,
        "tv_psum":    ACCUM_W,
        "gold_mult":  2 * DATA_W,   # 16b: fits 8b×8b product exactly
        "gold_mac":   ACCUM_W,
    }
    
    with VecWriter(args.outdir, fields) as writer:
        for data, weight, psum in vectors:
            mult, mac = pe_model(data, weight, psum)
            writer.write(
                tv_data = data,
                tv_weight = weight,
                tv_psum = psum,
                gold_mult = mult,
                gold_mac = mac,
            )
        writer.report()

if __name__ == "__main__":
    main()