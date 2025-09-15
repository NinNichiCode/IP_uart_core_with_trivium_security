`timescale 1ns / 1ps
`default_nettype none

// ===== cipher_engine.v (RENAMED) =====
module cipher_engine(
    /* Standard control signals */
    input   wire            clk_i,
    input   wire            n_rst_i,
    input   wire            ce_i,
    
    /* Data related signals */
    input   wire    [31:0]  ld_dat_i,
    input   wire    [2:0]   ld_reg_a_i,
    input   wire    [2:0]   ld_reg_b_i,
    // RENAMED: 'dat_i' -> 'plaintext_bit_i'
    input   wire            plaintext_bit_i,
    // RENAMED: 'dat_o' -> 'ciphertext_bit_o'
    output  wire            ciphertext_bit_o,
    // ADDED: Output a pure keystream bit for observation
    output  wire            keystream_bit_o
);

//////////////////////////////////////////////////////////////////////////////////
// Signal definitions
//////////////////////////////////////////////////////////////////////////////////
wire    feedback_from_a_s;    /* Feedback bit from reg_a */
wire    feedback_from_b_s;    /* Feedback bit from reg_b */
wire    feedback_from_c_s;    /* Feedback bit from reg_c */
wire    keystream_term_a_s;   /* Keystream term from reg_a (t1) */
wire    keystream_term_b_s;   /* Keystream term from reg_b (t2) */
wire    keystream_term_c_s;   /* Keystream term from reg_c (t3) */
wire    final_keystream_bit_s;/* The final, combined keystream bit */

//////////////////////////////////////////////////////////////////////////////////
// Module instantiations
//////////////////////////////////////////////////////////////////////////////////
shift_reg #(
        .REG_SZ(93), .FEED_FWD_IDX(65), .FEED_BKWD_IDX(68)
    ) 
    reg_a(
        .clk_i(clk_i), .n_rst_i(n_rst_i), .ce_i(ce_i),
        .ld_i(ld_reg_a_i), .ld_dat_i(ld_dat_i),
        .feedback_from_prev_reg_i(feedback_from_c_s), // Input from C
        .feedback_to_next_reg_o(feedback_from_a_s),   // Output to B
        .keystream_term_o(keystream_term_a_s)
    );
   
shift_reg #(
        .REG_SZ(84), .FEED_FWD_IDX(68), .FEED_BKWD_IDX(77)
    ) 
    reg_b(
        .clk_i(clk_i), .n_rst_i(n_rst_i), .ce_i(ce_i),
        .ld_i(ld_reg_b_i), .ld_dat_i(ld_dat_i),
        .feedback_from_prev_reg_i(feedback_from_a_s), // Input from A
        .feedback_to_next_reg_o(feedback_from_b_s),   // Output to C
        .keystream_term_o(keystream_term_b_s)
    );
   
shift_reg #(
        .REG_SZ(111), .FEED_FWD_IDX(65), .FEED_BKWD_IDX(86)
    ) 
    reg_c(
        .clk_i(clk_i), .n_rst_i(n_rst_i), .ce_i(ce_i),
        .ld_i(ld_reg_b_i), .ld_dat_i(0),
        .feedback_from_prev_reg_i(feedback_from_b_s), // Input from B
        .feedback_to_next_reg_o(feedback_from_c_s),   // Output to A
        .keystream_term_o(keystream_term_c_s)
    );
   
//////////////////////////////////////////////////////////////////////////////////
// Output calculations
//////////////////////////////////////////////////////////////////////////////////
assign final_keystream_bit_s = keystream_term_a_s ^ keystream_term_b_s ^ keystream_term_c_s;
assign ciphertext_bit_o = plaintext_bit_i ^ final_keystream_bit_s;

// Expose the pure keystream for observation
assign keystream_bit_o = final_keystream_bit_s;

endmodule