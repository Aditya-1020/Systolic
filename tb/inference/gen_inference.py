import sys, os, argparse
import math
import numpy as np

DATA_WIDTH  = 8
ACCUM_WIDTH = 48

def fmt(val: int, width_bits: int) -> str:
    hex_digits = width_bits // 4
    return f"{int(val) & ((1 << width_bits) - 1):0{hex_digits}X}"

def clamp8(x):
    return int(np.clip(round(float(x)), -128, 127))

def quantize(M, scale):
    return np.vectorize(clamp8)(np.array(M, dtype=np.float32) / scale).astype(np.int8)

def sym_scale(t):
    m = np.max(np.abs(t))
    return float(m) / 127.0 if m > 0 else 1.0

def ceil_div(a, b):
    return (a + b - 1) // b

def stagger_rows(M, N):
    """Stagger NxN matrix M for row-feed (A). result[t][r] = value at time t for lane r."""
    total = 2 * N - 1
    result = [[0] * N for _ in range(total)]
    for r in range(N):
        for k in range(N):
            result[r + k][r] = int(M[r][k])
    return result

def stagger_cols(M, N):
    """Stagger NxN matrix M for col-feed (B). result[t][c] = value at time t for lane c."""
    total = 2 * N - 1
    result = [[0] * N for _ in range(total)]
    for c in range(N):
        for k in range(N):
            result[c + k][c] = int(M[k][c])
    return result

def load_or_train(out_dir):
    """Load weights from saved .npy if present, else run training."""
    scales_path = os.path.join(out_dir, "scales.npy")
    fc2_w_path  = os.path.join(out_dir, "wq_fc2_flat.npy")
    fc1_q_path  = os.path.join(out_dir, "fc1_q_img0.npy")

    if os.path.exists(scales_path) and os.path.exists(fc2_w_path) and os.path.exists(fc1_q_path):
        print("[gen_inference] Loading cached weights...")
        scales  = np.load(scales_path)
        wq_fc2  = np.load(fc2_w_path).reshape(10, 64)
        fc1_q   = np.load(fc1_q_path)
        return wq_fc2, fc1_q

    # Need to train
    print("[gen_inference] Cached weights not found, running training...")
    try:
        import torch, torch.nn as nn, torch.optim as optim
        from torch.utils.data import DataLoader
        from torchvision import datasets, transforms
    except ImportError:
        sys.exit("pip install torch torchvision")

    T = transforms.Compose([transforms.ToTensor(), transforms.Normalize((0.1307,), (0.3081,))])
    train_ds = datasets.MNIST("./data", train=True,  download=True, transform=T)
    test_ds  = datasets.MNIST("./data", train=False, download=True, transform=T)
    device   = "cuda" if torch.cuda.is_available() else "cpu"

    class TinyCNN(nn.Module):
        def __init__(self):
            super().__init__()
            self.conv1 = nn.Conv2d(1, 8, 3, bias=True)
            self.pool  = nn.MaxPool2d(2)
            self.fc1   = nn.Linear(8*13*13, 64, bias=True)
            self.fc2   = nn.Linear(64, 10, bias=True)
            self.relu  = nn.ReLU()
        def forward(self, x):
            x = self.relu(self.conv1(x)); x = self.pool(x)
            x = x.flatten(1); x = self.relu(self.fc1(x)); return self.fc2(x)

    model = TinyCNN().to(device)
    opt   = optim.Adam(model.parameters(), lr=1e-3)
    loss_fn = nn.CrossEntropyLoss()
    for ep in range(1, 6):
        model.train()
        for xb, yb in DataLoader(train_ds, 256, shuffle=True, num_workers=0):
            xb, yb = xb.to(device), yb.to(device)
            opt.zero_grad(); loss_fn(model(xb), yb).backward(); opt.step()
        print(f"  epoch {ep}/5")
    model.eval()

    # Calibration
    fc1_out_all = []
    fc1_in_all  = []
    def hook_fc1_in(m, inp, out):  fc1_in_all.append(inp[0].detach().cpu())
    def hook_fc1_out(m, inp, out): fc1_out_all.append(out.detach().cpu())
    h1 = model.fc1.register_forward_hook(hook_fc1_in)
    h2 = model.fc1.register_forward_hook(hook_fc1_out)
    with torch.no_grad():
        n = 0
        for xb, _ in DataLoader(train_ds, 128, shuffle=True, num_workers=0):
            model(xb.to(device)); n += len(xb)
            if n >= 512: break
    h1.remove(); h2.remove()

    s_fc1_in  = sym_scale(torch.cat(fc1_in_all).numpy())
    s_fc1_out = sym_scale(np.maximum(0, torch.cat(fc1_out_all).numpy()))
    s_fc2_w   = sym_scale(model.fc2.weight.data.cpu().numpy())
    wq_fc2    = quantize(model.fc2.weight.data.cpu().numpy(), s_fc2_w)

    # Get fc1_q for first test image
    xb0, _ = next(iter(DataLoader(test_ds, 1, shuffle=False)))
    calib_fc1_in = []
    def hook(m, inp, out): calib_fc1_in.append(inp[0].detach().cpu())
    h = model.fc1.register_forward_hook(hook)
    with torch.no_grad(): model(xb0.to(device))
    h.remove()
    fc1_relu = np.maximum(0, calib_fc1_in[0].numpy().flatten())
    fc1_f32  = fc1_relu * (s_fc2_w * s_fc1_in)   # rescale for fc2 input
    fc1_q    = quantize(fc1_f32, s_fc1_out)

    # Cache for future runs
    os.makedirs(out_dir, exist_ok=True)
    np.save(scales_path, np.array([s_fc2_w, s_fc1_in, s_fc1_out]))
    np.save(fc2_w_path,  wq_fc2)
    np.save(fc1_q_path,  fc1_q)

    return wq_fc2, fc1_q


def generate_vectors(N: int, out_dir: str):
    """Generate sv_fc2_a_N<N>.hex, sv_fc2_b_N<N>.hex, sv_fc2_gold_N<N>.hex."""

    cache_dir = os.path.join(out_dir, "inference_vectors")
    os.makedirs(cache_dir, exist_ok=True)

    out_a    = os.path.join(cache_dir, f"sv_fc2_a_N{N}.hex")
    out_b    = os.path.join(cache_dir, f"sv_fc2_b_N{N}.hex")
    out_gold = os.path.join(cache_dir, f"sv_fc2_gold_N{N}.hex")

    if all(os.path.exists(p) and os.path.getsize(p) > 0 for p in [out_a, out_b, out_gold]):
        print(f"[gen_inference] N={N}: vectors already present, skipping generation.")
        return

    wq_fc2, fc1_q = load_or_train(cache_dir)


    W_ROWS, W_COLS = wq_fc2.shape
    PAD_ROWS = ceil_div(W_ROWS, N) * N
    PAD_COLS = ceil_div(W_COLS, N) * N

    N_ROW_TILES = PAD_ROWS // N
    N_COL_TILES = PAD_COLS // N
    N_TILES     = N_ROW_TILES * N_COL_TILES
    FEED_ROWS   = 2 * N - 1

    # Pad weight matrix and activation vector
    wq_pad  = np.pad(wq_fc2, ((0, PAD_ROWS - W_ROWS), (0, PAD_COLS - W_COLS)), constant_values=0).astype(np.int8)
    fc1_pad = np.pad(fc1_q, (0, PAD_COLS - W_COLS), constant_values=0).astype(np.int8)

    print(f"[gen_inference] N={N}: W={W_ROWS}x{W_COLS} → padded {PAD_ROWS}x{PAD_COLS}")
    print(f"[gen_inference] N={N}: {N_ROW_TILES} row-tiles x {N_COL_TILES} col-tiles = {N_TILES} tiles")

    with open(out_a, 'w') as fa, open(out_b, 'w') as fb, open(out_gold, 'w') as fg:
        for rt in range(N_ROW_TILES):
            for ct in range(N_COL_TILES):
                A = wq_pad[rt*N:(rt+1)*N, ct*N:(ct+1)*N].astype(np.int32)
                b_vec = fc1_pad[ct*N:(ct+1)*N].astype(np.int32)
                B = np.tile(b_vec.reshape(N, 1), (1, N))
                C = A @ B

                as_ = stagger_rows(A, N)
                bs_ = stagger_cols(B, N)

                for t in range(FEED_ROWS):
                    pa = pb = 0
                    for lane in range(N):
                        pa |= (int(as_[t][lane]) & 0xFF) << (lane * DATA_WIDTH)
                        pb |= (int(bs_[t][lane]) & 0xFF) << (lane * DATA_WIDTH)
                    fa.write(f"{pa:0{N*DATA_WIDTH//4}X}\n")
                    fb.write(f"{pb:0{N*DATA_WIDTH//4}X}\n")

                for r in range(N):
                    for c in range(N):
                        fg.write(fmt(int(C[r, c]), ACCUM_WIDTH) + "\n")

    total_feed = N_TILES * FEED_ROWS
    total_gold = N_TILES * N * N
    print(f"[gen_inference] N={N}: wrote {total_feed} feed rows, {total_gold} gold elements")
    print(f"  {out_a}")
    print(f"  {out_b}")
    print(f"  {out_gold}")


def main():
    parser = argparse.ArgumentParser(description="Generate FC2 inference vectors for tb_inference.sv")
    parser.add_argument("-n", "--num", type=int, default=48)
    parser.add_argument("-s", "--seed", type=int, default=42)
    parser.add_argument("--N", type=int, default=4)
    parser.add_argument("-o", "--outdir", default=".")
    args = parser.parse_args()
    generate_vectors(args.N, args.outdir)

if __name__ == "__main__":
    main()