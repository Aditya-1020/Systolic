TB     ?= tb_pe
NUM    ?= 100
SEED   ?= 42
PYTHON ?= python3

MODULE := $(patsubst tb_%,%,$(TB))
STAMP  := .vec_$(MODULE)_n$(NUM)_s$(SEED)

.PHONY: all vectors compile elab run clean

all: run

$(STAMP): tb/gen_$(MODULE).py
	$(PYTHON) $< -n $(NUM) -s $(SEED) -o .
	@find . -maxdepth 1 -name '.vec_$(MODULE)_*' ! -name '$(STAMP)' -delete
	@touch $(STAMP)

vectors: $(STAMP)

compile: vectors
	xvlog -sv $(wildcard rtl/*.sv) tb/$(TB).sv

elab: compile
	xelab $(TB) -s sim_$(MODULE)

run: elab
	xsim sim_$(MODULE) -R

clean:
	rm -rf *.log *.jou *.pb xsim.dir *.wdb sim_* .vec_*