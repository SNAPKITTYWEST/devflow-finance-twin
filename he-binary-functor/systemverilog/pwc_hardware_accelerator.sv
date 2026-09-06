// =====================================================================
// PWC_HARDWARE_ACCELERATOR - Polynomial Wormhole Constraint
// =====================================================================

module pwc_hardware_accelerator #(
    parameter MAX_WORD_LEN = 256,
    parameter SIMD_WIDTH = 4
)(
    input logic clk,
    input logic rst_n,
    input logic mmio_valid,
    input logic [3:0] mmio_addr,
    input logic [31:0] mmio_wdata,
    output logic [31:0] mmio_rdata,
    output logic mmio_ready,
    output logic worm_commit,
    output logic [31:0] worm_cycles,
    output logic [31:0] worm_hash
);

    typedef enum logic [1:0] {
        IDLE = 2'b00,
        LOAD = 2'b01,
        COMPUTE = 2'b10,
        COMMIT = 2'b11
    } state_t;

    state_t current_state, next_state;

    logic [7:0] input_word [0:MAX_WORD_LEN-1];
    logic [7:0] output_word [0:MAX_WORD_LEN-1];
    logic [$clog2(MAX_WORD_LEN):0] input_len, output_len;
    logic [31:0] matrix_hash;

    function automatic logic [$clog2(MAX_WORD_LEN):0] compress_word(
        input logic [7:0] in_word [0:MAX_WORD_LEN-1],
        input logic [$clog2(MAX_WORD_LEN):0] len,
        output logic [7:0] out_word [0:MAX_WORD_LEN-1]
    );
        logic [$clog2(MAX_WORD_LEN):0] wr_ptr;
        logic [7:0] window [0:2];
        logic match_found;

        wr_ptr = 0;
        match_found = 1'b0;

        for (int i = 0; i < len; i++) begin
            window[0] = window[1];
            window[1] = window[2];
            window[2] = in_word[i];

            if (i >= 2) begin
                logic signed [7:0] a, b, c;
                a = window[0];
                b = window[1];
                c = window[2];

                if (((b == a + 1) || (b == a - 1)) && (c == a)) begin
                    out_word[wr_ptr-2] = b;
                    out_word[wr_ptr-1] = a;
                    out_word[wr_ptr] = b;
                    match_found = 1'b1;
                end else begin
                    out_word[wr_ptr] = in_word[i];
                    wr_ptr++;
                end
            end else begin
                out_word[wr_ptr] = in_word[i];
                wr_ptr++;
            end
        end

        return wr_ptr;
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            input_len <= 0;
            output_len <= 0;
            mmio_ready <= 1'b0;
            worm_commit <= 1'b0;
        end else begin
            current_state <= next_state;

            case (current_state)
                IDLE: begin
                    mmio_ready <= 1'b1;
                    worm_commit <= 1'b0;
                end

                LOAD: begin
                    if (mmio_valid && mmio_addr == 4'h0) begin
                        input_word[input_len] <= mmio_wdata[7:0];
                        input_len <= input_len + 1;
                    end
                end

                COMPUTE: begin
                    output_len <= compress_word(input_word, input_len, output_word);
                    matrix_hash <= 32'hDEADBEEF;
                end

                COMMIT: begin
                    worm_commit <= 1'b1;
                    worm_cycles <= 32'd1;
                    worm_hash <= matrix_hash;
                end
            endcase
        end
    end

    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: if (mmio_valid && mmio_addr == 4'h0) next_state = LOAD;
            LOAD: if (mmio_valid && mmio_addr == 4'h4) next_state = COMPUTE;
            COMPUTE: next_state = COMMIT;
            COMMIT: next_state = IDLE;
        endcase
    end

    always_comb begin
        mmio_rdata = 32'h0;
        case (mmio_addr)
            4'h0: mmio_rdata = {24'h0, input_word[0]};
            4'h4: mmio_rdata = input_len;
            4'h8: mmio_rdata = output_len;
            4'hC: mmio_rdata = matrix_hash;
            default: mmio_rdata = 32'h0;
        endcase
    end

endmodule
