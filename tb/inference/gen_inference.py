import sys, os, argparse
 
REQUIRED_FILES = [
    "sv_fc2_a.hex",
    "sv_fc2_b.hex",
    "sv_fc2_gold.hex",
]
 
# vec dir is always relative to this script's location
VEC_DIR = os.path.join(os.path.dirname(__file__), "inference_vectors")
 
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-n", "--num",    type=int, default=48)
    parser.add_argument("-s", "--seed",   type=int, default=42)
    parser.add_argument("--N",            type=int, default=4)
    parser.add_argument("-o", "--outdir", default=".")
    args = parser.parse_args()
 
    print(f"[gen_inference] Checking inference vectors in {VEC_DIR}/")
 
    missing = []
    for fname in REQUIRED_FILES:
        path = os.path.join(VEC_DIR, fname)
        if not os.path.exists(path):
            missing.append(fname)
        elif os.path.getsize(path) == 0:
            missing.append(f"{fname} (empty)")
        else:
            size = os.path.getsize(path)
            print(f"  ✓  {fname:<24} ({size} bytes)")
 
    if missing:
        print("\n[ERROR] Missing inference vector files:")
        for f in missing:
            print(f"  ✗  {f}")
        print("\nRun this first:")
        print("python model/train_and_export.py")
        sys.exit(1)
 
    print(f"[gen_inference] All {len(REQUIRED_FILES)} required files present.")
 
if __name__ == "__main__":
    main()
