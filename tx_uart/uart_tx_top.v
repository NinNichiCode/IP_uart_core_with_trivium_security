`timescale 1ns / 1ps
`default_nettype none
module uart_tx_top(
    // Inputs
    input wire clk,
    input wire rst,
    input wire baud_pulse,
    input wire pen,
    input wire stb,
    input wire sticky_parity,
    input wire eps,
    input wire set_break,
    input wire [1:0] wls,
    input wire [7:0] din,
    input wire thre,
    // Outputs
    output reg pop,
    output reg sreg_empty,
    output reg tx
);



// Internal registers
reg [7:0] shift_reg;
reg tx_data;
reg d_parity;
reg [3:0] bitcnt;
reg [4:0] count;

reg pop_next;

// State machine definition
parameter [2:0] FSM_IDLE   = 3'b000;
parameter [2:0] FSM_START  = 3'b001;
parameter [2:0] FSM_SEND   = 3'b010;
parameter [2:0] FSM_PARITY = 3'b011;
parameter [2:0] FSM_STOP   = 3'b100;
reg [2:0] state;

// Parity output logic
wire parity_out;
assign parity_out = (sticky_parity) ? ((eps) ? 1'b0 : 1'b1) : ((eps) ? d_parity : ~d_parity);

// Main State Machine Logic
always @(posedge clk or posedge rst) begin
    if (rst) begin
        state      <= FSM_IDLE;
        count      <= 0;
        bitcnt     <= 0;
        shift_reg  <= 8'h00;
        sreg_empty <= 1'b1;
        tx_data    <= 1'b1;
        pop <= 1'b0;
        pop_next <= 1'b0;
    end else begin
        pop <= pop_next;   // ghi giá trị pop_next vào pop ở mỗi chu kỳ
        pop_next <= 1'b0;  // tự động reset về 0 sau khi set 1 chu kỳ

        if (baud_pulse) begin
            case (state)
                FSM_IDLE: begin
                    if (count > 0) begin
                        count <= count - 1;
                    end else if (thre == 1'b0) begin
                        pop_next <= 1'b1;   // set pop lên 1 chu kỳ
                        shift_reg <= din;

                        case(wls)
                            2'b00: d_parity <= ^din[4:0];
                            2'b01: d_parity <= ^din[5:0];
                            2'b10: d_parity <= ^din[6:0];
                            2'b11: d_parity <= ^din[7:0];
                        endcase

                        tx_data <= 1'b0;
                        count <= 5'd15;
                        bitcnt <= wls + 5;
                        sreg_empty <= 1'b0;
                        state <= FSM_START;
                    end
                end
            
            FSM_START: begin
                if (count > 0) begin
                    count <= count - 1;
                end else begin
                    tx_data <= shift_reg[0];
                    shift_reg <= shift_reg >> 1;
                    count <= 5'd15;
                    state <= FSM_SEND;
                end
            end

            FSM_SEND: begin
                if (count > 0) begin
                    count <= count - 1;
                end else begin
                    if (bitcnt > 1) begin
                        bitcnt <= bitcnt - 1;
                        tx_data <= shift_reg[0];
                        shift_reg <= shift_reg >> 1;
                        count <= 5'd15;
                        state <= FSM_SEND;
                    end else begin
                        sreg_empty <= 1'b1;
                        if (pen == 1'b1) begin
                            tx_data <= parity_out;
                            count <= 5'd15;
                            state <= FSM_PARITY;
                        end else begin
                            tx_data <= 1'b1;
                            count <= (stb == 1'b0) ? 5'd15 : 5'd31; // Đơn giản hóa logic
                            state <= FSM_STOP;
                        end
                    end
                end
            end

            FSM_PARITY: begin
                if (count > 0) begin
                    count <= count - 1;
                end else begin
                    tx_data <= 1'b1;
                    count <= (stb == 1'b0) ? 5'd15 : 5'd31; // Đơn giản hóa logic
                    state <= FSM_STOP;
                end
            end
            
            FSM_STOP: begin
                if (count > 0) begin
                    count <= count - 1;
                end else begin
                    // **SỬA LỖI:** Khi quay về IDLE, nạp count cho 1 chu kỳ nghỉ
                    count <= 5'd15; 
                    state <= FSM_IDLE;
                end
            end

            default: state <= FSM_IDLE;
        endcase
    end
end
end

// Final output driver
always @(posedge clk or posedge rst) begin
    if (rst) begin
        tx <= 1'b1;
    end else begin
        tx <= tx_data & ~set_break;
    end
end

endmodule