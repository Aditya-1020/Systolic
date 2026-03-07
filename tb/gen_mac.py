import sys
import os
import random

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))
from vec_utils import VecWriter, base_parser, rand_signed

DATA_W = 8
WEIGHT_W = 8
ACCUM_W = 32

def mac_model(data: int, weight: int, accum_in: int):
    return accum_in + data * weight


def corner_cases():
    return [
        (   5,    3,    0),   # basic
        (  -2,    4,    0),   # negative data
        ( 127,  127,    0),   # max positive product
        (-128, -128,    0),   # max unsigned product
        (   0,    0,  999),   # zero multiply, non-zero accum
        (   1,   -1,  100),   # mixed signs
    ]

def random_cases(n: int, seed: int):
    rng = random.Random(seed)
    return [
        (rand_signed(rng, DATA_W), rand_signed(rng, WEIGHT_W), rand_signed(rng, ACCUM_W))
        for _ in range(n)
    ]

def main():
    args = base_parser("Generate mac_unit.sv test vectors").parse_args()
    vectors = corner_cases() + random_cases(args.num, args.seed)


    fields = {
        "tv_data":    DATA_W,
        "tv_weight":  WEIGHT_W,
        "tv_accum":   ACCUM_W,
        "gold_accum": ACCUM_W,
    }

    with VecWriter(args.outdir, fields) as writer:
        for data, weight, accum_in in vectors:
            writer.write(
                tv_data    = data,
                tv_weight  = weight,
                tv_accum   = accum_in,
                gold_accum = mac_model(data, weight, accum_in),
            )
        writer.report()


if __name__ == "__main__":
    main()