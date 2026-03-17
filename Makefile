TB     ?= tb_top
NUM    ?= 10
SEED   ?= 42
N      ?= 4
PYTHON ?= python3

MODULE := $(patsubst tb_%,%,$(TB))
STAMP  := .vec_$(MODULE)_n$(NUM)_s$(SEED)_N$(N)

.PHONY: all vectors compile elab run clean openlane-shell n_sweep

all: run

openlane-shell:
	@if [ -n "$$IN_NIX_SHELL" ] || pgrep -f "nix-shell.*$(OL_DIR)" > /dev/null; then \
		echo "Already in Nix shell or one running for $(OL_DIR)"; \
	else \
		cd $(OL_DIR) && nix-shell; \
	fi

run-pd-flow:
	openlane design/systolic_array/config.json

$(STAMP): tb/$(MODULE)/gen_$(MODULE).py
	PYTHONPATH=scripts $(PYTHON) $< -n $(NUM) -s $(SEED) --N $(N) -o .
	@find . -maxdepth 1 -name '.vec_$(MODULE)_*' ! -name '$(STAMP)' -delete
	@touch $(STAMP)

vectors: $(STAMP)

compile: vectors
	xvlog -sv $(wildcard rtl/*.sv) tb/$(MODULE)/$(TB).sv \
	    -d N=$(N) \
	    -d NUM=$(NUM)

elab: compile
	xelab $(TB) -s sim_$(MODULE)

run: elab
	xsim sim_$(MODULE) -R

clean:
	rm -rf *.log *.jou *.pb xsim.dir *.wdb sim_* .vec_* \
	       scripts/__pycache__ *.hex tb/__pycache__

NS := 2 8 16 32 64

n_sweep:
	$(foreach n,$(NS),$(MAKE) N=$(n) clean run;)