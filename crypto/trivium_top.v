`timescale 1ns / 1ps
`default_nettype none

// ===== trivium_top.v (UPDATED) =====
module trivium_top(
    input   wire            clk_i,
    input   wire            n_rst_i,
    input   wire    [7:0]   dat_i, // Giữ nguyên tên: Plaintext byte input
    input   wire    [31:0]  ld_dat_i,
    input   wire    [2:0]   ld_reg_a_i,
    input   wire    [2:0]   ld_reg_b_i,   
    input   wire            init_i,
    input   wire            proc_i,
    output  reg     [7:0]   dat_o, // Giữ nguyên tên: Ciphertext byte output
    output  wire            busy_o,
    output  wire            keystream_for_tb_o, // RENAMED: 'keystream_bit_o' for clarity
    output  wire debug_cphr_en_o
    );

    reg     [2:0]   next_state_s;
    reg     [2:0]   cur_state_r;
    reg     [10:0]  cntr_r;
    reg             cphr_en_r;
    // RENAMED: 'dat_r' -> 'plaintext_buffer_r'
    reg     [7:0]   plaintext_buffer_r;
    wire            ciphertext_bit_from_engine_s;
    wire            keystream_bit_from_engine_s;
     reg init_req_r;
    assign debug_cphr_en_o = cphr_en_r; // Nối ra ngoài

    parameter   IDLE_e = 0, WARMUP_e = 1, WAIT_PROC_e = 2, PROC_e = 3;

    cipher_engine cphr(
        .clk_i(clk_i), .n_rst_i(n_rst_i), .ce_i(cphr_en_r),
        .ld_dat_i(ld_dat_i), .ld_reg_a_i(ld_reg_a_i), .ld_reg_b_i(ld_reg_b_i),
        // Pass the current plaintext bit to the engine
        .plaintext_bit_i(plaintext_buffer_r[0]),
        // Receive the resulting ciphertext bit
        .ciphertext_bit_o(ciphertext_bit_from_engine_s),
        // Receive the pure keystream bit for observation
        .keystream_bit_o(keystream_bit_from_engine_s)
    );

    // Expose the pure keystream bit to the testbench
    assign keystream_for_tb_o = keystream_bit_from_engine_s;

    // assign busy_o = cphr_en_r;
     assign busy_o = (cur_state_r != IDLE_e) && (cur_state_r != WAIT_PROC_e); 
    initial cur_state_r = IDLE_e;

    always @(*) begin
        case (cur_state_r)
            IDLE_e: next_state_s = init_i ? WARMUP_e : IDLE_e;
            WARMUP_e: next_state_s = (cntr_r == 1151) ? WAIT_PROC_e : WARMUP_e;
            WAIT_PROC_e: next_state_s = proc_i ? PROC_e : (init_i ? WARMUP_e : WAIT_PROC_e);
            PROC_e: next_state_s = (cntr_r == 7) ? WAIT_PROC_e : PROC_e;
            default: next_state_s = IDLE_e;
        endcase
    end

    always @(posedge clk_i or negedge n_rst_i) begin
        if (!n_rst_i) begin
            cntr_r <= 0; cur_state_r <= IDLE_e; cphr_en_r <= 1'b0;
            dat_o <= 0; plaintext_buffer_r <= 0;
        end else begin
            cur_state_r <= next_state_s;
          
            case (cur_state_r)
                IDLE_e: begin
                    if (next_state_s == WARMUP_e) cphr_en_r <= 1'b1;
                end
                WARMUP_e: begin
                    if (next_state_s == WAIT_PROC_e) begin
                        cntr_r <= 0; cphr_en_r <= 1'b0;
                    end else begin
                        cntr_r <= cntr_r + 1;
                    end
                end
                WAIT_PROC_e: begin
                    if (next_state_s == PROC_e) begin
                        cphr_en_r <= 1'b1;
                        // Load the plaintext byte into the buffer
                        plaintext_buffer_r <= dat_i;
                    end else if (next_state_s == WARMUP_e) begin
                        cphr_en_r <= 1'b1;
                    end
                end
                PROC_e: begin
                    cphr_en_r <= 1'b1;
                    if (next_state_s == WAIT_PROC_e) begin
                        cphr_en_r <= 1'b0;
                        cntr_r <= 0;
                    end else begin
                        cntr_r <= cntr_r + 1;
                    end
                    // Shift the plaintext buffer to present the next bit
                    plaintext_buffer_r <= {1'b0, plaintext_buffer_r[7:1]};
                    // Assemble the output ciphertext byte from the bits coming from the engine
                    dat_o <= {ciphertext_bit_from_engine_s, dat_o[7:1]};
                end
            endcase
        end
    end
endmodule