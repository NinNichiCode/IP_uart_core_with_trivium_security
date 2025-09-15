`timescale 1ns/1ps
`default_nettype none 

module uart_rx_core(
    input   wire          clk,
    input   wire          rst,
    input   wire          rx,

    // --- CÁC CHÂN INPUT CẤU HÌNH ---
    input   wire          baud_pulse,
    input   wire  [1:0]   wls,
    input   wire          stb,
    input   wire          pen,
    input   wire          eps,
    input   wire          sticky_parity,

    // --- GIAO TIẾP VỚI FSM BÊN NGOÀI ---
    input   wire          pop_from_fsm_i,
    output  wire  [7:0]   ciphertext_data_o,
    output  wire          fifo_empty_o,
    
    // --- CÁC CHÂN OUTPUT LỖI ---
    output  wire          pe_o,
    output  wire          fe_o,
    output  wire          bi_o
);
    // --- Dây nối nội bộ ---
    // Các dây nối này không phải là cổng nên không cần khai báo lại
    wire rx_push;
    wire [7:0] rx_out;

    // --- KHỐI 1: DESERIALIZER (uart_rx_16550) ---
    uart_rx_16550 u_rx (
        .clk(clk), .rst(rst), .rx(rx),
        .baud_pulse(baud_pulse), 
        .wls(wls), 
        .stb(stb), 
        .pen(pen),
        .eps(eps), 
        .sticky_parity(sticky_parity),
        .push(rx_push), 
        .pe(pe_o), // Nối thẳng dây output của u_rx ra output của module này
        .fe(fe_o), 
        .bi(bi_o),
        .rx_out(rx_out)
    );
  
    // --- KHỐI 2: CIPHERTEXT FIFO (uart_rx_fifo) ---
    uart_rx_fifo u_fifo (
        .clk(clk), .rst(rst), .en(1'b1),
        .push_in(rx_push),
        .pop_in(pop_from_fsm_i),
        .din(rx_out),
        .dout(ciphertext_data_o),
        .empty(fifo_empty_o),
        .full(), .overrun(), .underrun(), .threshold(4'd0), .thre_trigger()
    );
endmodule