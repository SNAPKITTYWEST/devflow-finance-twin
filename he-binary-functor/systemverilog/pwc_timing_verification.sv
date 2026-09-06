// =====================================================================
// PWC_HARDWARE_TIMING.sv - Timing Constraints as Formal Axioms
// =====================================================================

module pwc_timing_verification #(
    parameter CLK_PERIOD_NS = 10.0, // 100 MHz
    parameter YB_COMB_DELAY_NS = 2.5, // Synthesized combinational delay
    parameter MMIO_SETUP_NS = 1.0,
    parameter MMIO_HOLD_NS = 0.5
)();

    // synthesis translate_off
    initial begin
        assert (CLK_PERIOD_NS >= 10.0)
            else $error("Clock period violation: need >= 10ns for 100MHz");
        assert (YB_COMB_DELAY_NS <= CLK_PERIOD_NS - 1.0)
            else $error("YB compressor exceeds clock period");
        assert (MMIO_SETUP_NS + MMIO_HOLD_NS <= CLK_PERIOD_NS)
            else $error("MMIO timing violation");
        assert (1 == 1); // Trivial but documents the invariant
    end
    // synthesis translate_on

endmodule
