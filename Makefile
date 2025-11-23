VCS        ?= vcs
VCS_FLAGS  ?= -full64 -sverilog
PYTHON     ?= python3

FRAC_WIDTH ?= 15
BUILD_DIR  ?= build
SIM_BIN    := $(BUILD_DIR)/systolic_tb
RTL_SRCS   := $(wildcard rtl/*.v)
TB_SRCS    := tb/tb_systolic_top.sv

VLOG_FLAGS := +incdir+include +define+SYSTOLIC_FRAC_WIDTH=$(FRAC_WIDTH)

.PHONY: run clean

run:
	@mkdir -p $(BUILD_DIR)
	$(PYTHON) scripts/fixed_point_data_gen.py --frac $(FRAC_WIDTH)
	$(VCS) $(VCS_FLAGS) $(VLOG_FLAGS) $(TB_SRCS) $(RTL_SRCS) -o $(SIM_BIN)
	$(SIM_BIN)

clean:
	rm -rf $(BUILD_DIR) csrc verdiLog simv.daidir ucli.key vc_hdrs.h simv

