import random, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../scripts'))
from vec_utils import fmt, base_parser

def matmul(A, B, N):
    C = [[0]*N for _ in range(N)]
    for i in range(N):
        for j in range(N):
            for k in range(N):
                C[i][j] += A[i][k] * B[k][j]
    return C

def stagger_rows(M, N):
    """
    Stagger matrix M for systolic array row-feed (A matrix).
    BRAM address t holds the diagonal slice for time step t.
    At time t, lane r receives A[r][t-r] if 0 <= t-r < N, else 0.
    Total addresses needed: 2*N - 1
    """
    total = 2 * N - 1
    result = [[0] * N for _ in range(total)]
    for r in range(N):
        for k in range(N):
            result[r + k][r] = M[r][k]
    return result  # result[t][r] = value to feed lane r at time t

def stagger_cols(M, N):
    """
    Stagger matrix M for systolic array col-feed (B matrix).
    At time t, lane c receives B[t-c][c] if 0 <= t-c < N, else 0.
    Total addresses needed: 2*N - 1
    """
    total = 2 * N - 1
    result = [[0] * N for _ in range(total)]
    for c in range(N):
        for k in range(N):
            result[c + k][c] = M[k][c]
    return result  # result[t][c] = value to feed lane c at time t

def main():
    parser = base_parser("Generate top test vectors")
    parser.add_argument("--N", type=int, default=4)
    parser.add_argument("--data-width", type=int, default=8)
    parser.add_argument("--accum-width", type=int, default=48)
    args = parser.parse_args()

    N, DW, AW = args.N, args.data_width, args.accum_width
    rng = random.Random(args.seed)
    os.makedirs(args.outdir, exist_ok=True)

    total_feed_cycles = 2 * N - 1  # BRAM rows per matrix

    lo, hi = -(1 << (DW-1)), (1 << (DW-1)) - 1

    test_cases = []

    # Corner 1: identity x random  (C should equal B)
    A = [[1 if i==j else 0 for j in range(N)] for i in range(N)]
    B = [[rng.randint(lo, hi) for _ in range(N)] for _ in range(N)]
    test_cases.append((A, B, matmul(A, B, N)))

    # Corner 2: all max positive
    A = [[127]*N for _ in range(N)]
    B = [[127]*N for _ in range(N)]
    test_cases.append((A, B, matmul(A, B, N)))

    # Corner 3: all max negative
    A = [[-128]*N for _ in range(N)]
    B = [[-128]*N for _ in range(N)]
    test_cases.append((A, B, matmul(A, B, N)))

    # Random cases
    for _ in range(args.num):
        A = [[rng.randint(lo, hi) for _ in range(N)] for _ in range(N)]
        B = [[rng.randint(lo, hi) for _ in range(N)] for _ in range(N)]
        test_cases.append((A, B, matmul(A, B, N)))

    num_cases = len(test_cases)

    with open(os.path.join(args.outdir, 'tv_a_rows.hex'), 'w') as fa, \
         open(os.path.join(args.outdir, 'tv_b_rows.hex'), 'w') as fb, \
         open(os.path.join(args.outdir, 'gold_c.hex'),    'w') as fc:

        for A, B, C in test_cases:
            # Stagger A: address t -> packed row of N lanes for time step t
            a_stag = stagger_rows(A, N)   # shape [2N-1][N]
            b_stag = stagger_cols(B, N)   # shape [2N-1][N]

            for t in range(total_feed_cycles):
                # Pack lane values: lane 0 in LSBs, lane N-1 in MSBs
                packed_a = 0
                packed_b = 0
                for lane in range(N):
                    packed_a |= (a_stag[t][lane] & ((1<<DW)-1)) << (lane*DW)
                    packed_b |= (b_stag[t][lane] & ((1<<DW)-1)) << (lane*DW)
                fa.write(f"{packed_a:0{N*DW//4}X}\n")
                fb.write(f"{packed_b:0{N*DW//4}X}\n")

            # Gold: row-major C[i][j]
            for i in range(N):
                for j in range(N):
                    fc.write(fmt(C[i][j], AW) + '\n')

    with open(os.path.join(args.outdir, 'tv_meta.hex'), 'w') as fm:
        fm.write(f"{num_cases:08X}\n")
        fm.write(f"{N:08X}\n")
        fm.write(f"{total_feed_cycles:08X}\n")

    print(f"[gen_top] {num_cases} test cases written")
    print(f"  tv_a_rows.hex  ({N*DW}b per row, {total_feed_cycles} rows per matrix = 2N-1 staggered)")
    print(f"  tv_b_rows.hex  ({N*DW}b per row, {total_feed_cycles} rows per matrix = 2N-1 staggered)")
    print(f"  gold_c.hex     ({AW}b per element, {N*N} elements per matrix)")

if __name__ == "__main__":
    main()