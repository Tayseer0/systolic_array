### Tool configuration #########################################################
VCS        ?= vcs
VCS_FLAGS  ?= -full64 -sverilog
PYTHON     ?= python3

### Project structure ###########################################################
BUILD_DIR    ?= build
BUILD_STAMP  := $(BUILD_DIR)/.dir_stamp
VEC_DIR      ?= $(BUILD_DIR)
SIM_BIN      := $(BUILD_DIR)/systolic_tb
RTL_SRCS     := $(wildcard rtl/*.v)
TB_SRCS      := tb/tb_systolic_top.sv
PY_SCRIPTS   := scripts/fixed_point_data_gen.py
FRAC_BITS    ?= 15
VALUE_RANGE  ?= 32767
VECTOR_FILES := $(VEC_DIR)/instructions.mem \
                $(VEC_DIR)/dataA.mem \
                $(VEC_DIR)/dataB.mem \
                $(VEC_DIR)/expected.mem
VECTOR_STAMP := $(VEC_DIR)/vectors.stamp
RUN_ARGS     ?= +VEC_DIR=$(VEC_DIR)

.PHONY: build run clean

$(BUILD_STAMP):
	@mkdir -p $(BUILD_DIR)
	@touch $@

$(VECTOR_STAMP): $(BUILD_STAMP) $(PY_SCRIPTS)
	$(PYTHON) $(PY_SCRIPTS) --out-dir $(VEC_DIR) --frac $(FRAC_BITS) --value-range $(VALUE_RANGE)
	touch $(VECTOR_STAMP)

build: $(VECTOR_STAMP) $(SIM_BIN)

$(SIM_BIN): $(BUILD_STAMP) $(RTL_SRCS) $(TB_SRCS)
	$(VCS) $(VCS_FLAGS) $(TB_SRCS) $(RTL_SRCS) -o $@

run: $(VECTOR_STAMP) $(SIM_BIN)
	$(SIM_BIN) $(RUN_ARGS)

###############################################################################
# Cleanup
###############################################################################
clean:
	rm -rf $(BUILD_DIR) csrc verdiLog simv.daidir ucli.key vc_hdrs.h simv

