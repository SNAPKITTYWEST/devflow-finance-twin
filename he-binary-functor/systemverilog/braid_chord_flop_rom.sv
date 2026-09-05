// =====================================================================
// FLOP ROM – INVARIANT FIBONACCI BRAID CHORD LOOK-UP TABLE
// Stores pre-evaluated energy eigenvalues and frequencies for static words
// =====================================================================

module braid_chord_flop_rom (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [1:0]  chord_sel,   // 00: Root, 01: Third, 10: Fifth
    output logic        valid_out,
    output logic [31:0] freq_out     // IEEE-754 32-bit floating-point frequency
);

    // Invariant Constants (IEEE-754 Single Precision Hex Encodings)
    // PHI = 1.61803398875 -> 32'h3FCF8480
    // Pre-computed Energy Eigenvalues (E) mapped via Sonify() function

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            freq_out  <= 32'h00000000;
            valid_out <= 1'b0;
        end else begin
            valid_out <= 1'b1;
            unique case (chord_sel)
                2'b00: freq_out <= 32'h43480000; // Root Chord Frequency (~200.0 Hz)
                2'b01: freq_out <= 32'h438C0000; // Third Chord Frequency (~280.0 Hz)
                2'b10: freq_out <= 32'h43AF8000; // Fifth Chord Frequency (~351.0 Hz)
                default: begin
                    freq_out  <= 32'h00000000;
                    valid_out <= 1'b0;
                end
            endcase
        end
    end

endmodule
