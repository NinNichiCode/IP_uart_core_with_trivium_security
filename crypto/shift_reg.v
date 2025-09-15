`timescale 1ns / 1ps
`default_nettype none

// ===== shift_reg.v (RENAMED) =====
module shift_reg #(
    parameter REG_SZ = 93,
    parameter FEED_FWD_IDX = 65,
    parameter FEED_BKWD_IDX = 68
) 
(
    /* Standard control signals */
    input   wire            clk_i,
    input   wire            n_rst_i,
    input   wire            ce_i,
      
    /* Input and output data related signals */
    input   wire    [2:0]   ld_i,
    input   wire    [31:0]  ld_dat_i,
    // RENAMED: 'dat_i' -> 'feedback_from_prev_reg_i'
    input   wire            feedback_from_prev_reg_i,
    // RENAMED: 'dat_o' -> 'feedback_to_next_reg_o'
    output  wire            feedback_to_next_reg_o,
    // RENAMED: 'z_o' -> 'keystream_term_o'
    output  wire            keystream_term_o
);

//////////////////////////////////////////////////////////////////////////////////
// Signal definitions
//////////////////////////////////////////////////////////////////////////////////
reg     [(REG_SZ - 1):0]    state_r; // RENAMED: 'dat_r' -> 'state_r'
wire                        next_state_bit_s; // RENAMED: 'reg_in_s' -> 'next_state_bit_s'

//////////////////////////////////////////////////////////////////////////////////
// Feedback calculation
//////////////////////////////////////////////////////////////////////////////////
// Tính toán bit sẽ được dịch vào thanh ghi ở chu kỳ tiếp theo
assign next_state_bit_s = feedback_from_prev_reg_i ^ state_r[FEED_BKWD_IDX];

//////////////////////////////////////////////////////////////////////////////////
// Shift register process
//////////////////////////////////////////////////////////////////////////////////
always @(posedge clk_i or negedge n_rst_i) begin
    if (!n_rst_i)
        state_r <= 0;
    else begin
        if (ce_i) begin
            /* Dịch thanh ghi */
            state_r <= {state_r[(REG_SZ - 2):0], next_state_bit_s};
        end
        else if (ld_i != 3'b000) begin /* Nạp giá trị từ bên ngoài */
            if (ld_i[0])
                state_r[31:0] <= ld_dat_i;
            else if (ld_i[1])
                state_r[63:32] <= ld_dat_i;
            else if (ld_i[2])
                state_r[79:64] <= ld_dat_i[15:0];
         
            /* Set các bit cao về 0, trừ thanh ghi C */   
            state_r[(REG_SZ - 1):80] <= 0;
            if (REG_SZ == 111)
                state_r[(REG_SZ - 1)-:3] <= 3'b111;
        end
    end
end

//////////////////////////////////////////////////////////////////////////////////
// Output calculations
//////////////////////////////////////////////////////////////////////////////////
// z_o là một thành phần (term) của keystream, ví dụ: t1, t2, t3
assign keystream_term_o = (state_r[REG_SZ - 1] ^ state_r[FEED_FWD_IDX]);
// dat_o là bit phản hồi cho thanh ghi tiếp theo, bao gồm cả cổng AND
assign feedback_to_next_reg_o = keystream_term_o ^ (state_r[REG_SZ - 2] & state_r[REG_SZ - 3]); 

endmodule