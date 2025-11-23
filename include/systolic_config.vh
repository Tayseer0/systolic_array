`ifndef SYSTOLIC_CONFIG_VH
`define SYSTOLIC_CONFIG_VH

// Default fractional width (Q1.15) when not overridden by build system.
`ifndef SYSTOLIC_FRAC_WIDTH
`define SYSTOLIC_FRAC_WIDTH 15
`endif

`define SYSTOLIC_INPUT_WIDTH  16
`define SYSTOLIC_RESULT_WIDTH 16
`define SYSTOLIC_ADDR_WIDTH   10

`endif // SYSTOLIC_CONFIG_VH

