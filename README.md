# AdiSystolic
An output-stationary 4x4 systolic array accelerator for inference designed in SystemVerilog, physically implemented on SKY130B via OpenLane 2, and demonstrated running INT8 MNIST inference with cycle-accurate RTL simulation.

<img src="design/layout_image.png" width="800" alt="Klayout screenshot">

## What this is
Manged to mapp the inference all the way down the silicon.
A TinyCNN trained on MNIST (96.82% Float accuracy) is quantized ot INT8 using symmetric quantization. The FC2 inference layer is decomposed into 48 sequential 4x4 matrix multiplications and fed through the systolic array RTL. All 768 accumulator outputs are verified cycle-accurate against a golden model in Vivado Xsim using the same RTL that was implemented in SKY130B.

# Architecture
The array computes `C = A x B` using a 2D grid of MAC processing elements (PE). Data flows right across rows and weights down across columns. Each PE accumulating its partial sum locally across `2N-1` feed cycles draining to final result in `3N` cycles.

Ping-Pong Buffers: While the array is computing one tile, the host loads the next pair into the idle bank. On completion, controller pulses `o_swap` and banks flip (0 cycles are wasted between back-to-back multiplications).

**Controller FSM** 4 States `IDLE, CLEAR, FEED, WAIT`
- CLEAR: resets accumulator to 0.
- FEED: streams 2N-1 staggered rows to the array.
- WAIT: holds until array asserts `done`, pulsing `swap` and returns to `IDLE`.

A shift register inside the array delays clear pulse by `r+c` cycles for `PE[r][c]`, so every PE's accumulator resets exactly when first valid product arrives

**INT8 Inference Map**
FC2 computes `y=W(10*64) @ x(64)`. Mapped onto the systolic array as:
- `A_tile`: weight rows (flows as data)
- `B_tile`: activation slice (replicated as N identical cols)
- `C_out`: is the dot product of A and B tiles

3 row-tiles x 16 col-tiles = 48 matmul tiles per inference pass.


## File Structure
```sh
AdiSystolic/
├── design/         # ASIC design flow files (no bram)
│   └── systolic_array/
│     ├── config.json
│     ├── design.sdc
│     └── src/     # ASIC RTL (no BRAM, ping-pong regfile)
├── model/
│   └── train_and_export.py
├── fpga/            # FPGA constraints
├── Makefile
├── README.md   
├── rtl/            # FPGA RTL (with Xilinx BRAM instantiation)
├── scripts/        # Shared hex vector utilities
├── tb/
│   ├── pe/                   # PE unit testbench
│   ├── systolic_array/       # Array-level testbench
│   ├── top/                  # Full top-level integration testbench
│   └── inference/            # MNIST INT8 inference testbench
│       ├── gen_inference.py  # Vector presence checker (stub for Makefile)
│       └── tb_inference.sv   # 48-tile FC2 inference verification
├── Makefile
└── requirements.txt
```

## Parameters
All parameters are computed in `top_fpga.sv`/`top_asic.sv` and passed and passed as literals to submodules. 
- `$clog2` avoided in port lists for ASIC compatilibility.

| Parameter   | Default | Notes                           |
| ----------- | ------- | --------------------------------|
| N           | 4       | Matrix dimensions (2, 4, 8, 16) |
| DATA_WIDTH  | 8       | Input data width in bits        |
| ACCUM_WIDTH | 32      | Accumulator width in bits       |

- When changing N, update only `localparam` block in `top_asic.sv`.

## Physical Implementation Results
Taped out SKY130B via OpenLan2/OpenROAD

**Area and cell stats**
| Metric                  | Value                          |
| ----------------------- | ------------------------------ |
| Die area                | 1.16 × 1.16 mm                 |
| Core area               | 1,311,620 µm² (0.21 mm² logic) |
| Core utilization        | 20.2%                          |
| Standard cells          | 18,213 logic cells             |
| Sequential cells        | 2,463 flip-flops               |
| Timing repair buffers   | 1,684                          |
| Antenna diodes inserted | 262                            |

**Timing - Post Route STA (9 PVT corners)**
| Corner           | Setup WS (ns) | Hold WS (ns) | Setup Violations | Hold Violations |
| ---------------- | ------------- | ------------ | ---------------- | --------------- |
| nom_tt_025C_1v80 | +12.73        | +0.46        | 0                | 0               |
| nom_ss_100C_1v60 | +7.03         | +0.55        | 0                | 0               |
| nom_ff_n40C_1v95 | +13.71        | +0.12        | 0                | 0               |
| max_ss_100C_1v60 | +6.84         | +0.50        | 0                | 0               |
| max_ff_n40C_1v95 | +13.63        | +0.13        | 0                | 0               |
| min_ss_100C_1v60 | +7.20         | +0.59        | 0                | 0               |
| min_ff_n40C_1v95 | +13.78        | +0.11        | 0                | 0               |

Worst-corner Fmax: (max_ss_100C_1v50): 1000/(20.0 - 6.84) = 76 Mhz
Nominal Fmax: (nom_tt_025C_1v80): 1000/(20.0 - 12.73) = 137 Mhz


## How to Run Inference Simulation
**Setup**
```sh
pip install -r requirements.txt
```
**Train, Quantize and export vectors**
```sh
python model/train_and_export.py
```
Downloads MNIST automatically, trains for 5 epochs, exports INT8 weights and staggered feed vectors to `tb/inference/inference_vectors/`.
**Run RTL simulation**
```sh
make clean && make TB=tb_inference N=4
```
---
## How to Run Matix mulitplication Simulation
```sh
# N=4, 10 random test cases
make clean && make TB=tb_top N=4 NUM=10

# sweep multiple array sizes
make n_sweep
```
---
## How To Run the Physical Flow`
Requires OpenLane2 in a nix-shell environment with SKY130B PDK installed.
```sh
cd design/
openlane systolic_array/config.json
```
Results land in `systolic_array/runs/RUN_<timestamp>/final/`.

**Viewing the GDS**
```sh
klayout final/gds/top_asic.gds \
  -l $PDK_ROOT/sky130A/libs.tech/klayout/tech/sky130A.lyp
```
