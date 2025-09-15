`timescale 1ns/1ps
`default_nettype none
module uart_16550_top(
    input   wire        clk,
    input   wire        rst,
    input   wire        wr_i,
    input   wire        rd_i,
    input   wire [2:0]  addr_i,
    input   wire [7:0]  cpu_din,
    output  wire        tx
);

  // Nội bộ kết nối giữa các khối
  wire         tx_push;
  wire         fifo_empty, fifo_full, fifo_overrun, fifo_underrun, fifo_thre_trigger;
  wire  [7:0]  fifo_dout;
  wire         fifo_en;
  wire         baud_out;
  wire  [1:0]  wls;
  wire         pen, stb, sticky_parity, eps, set_break, dlab;
  wire         tx_pop;
  
  // --- Khối thanh ghi (regs_uart) ---
  regs_uart regs_inst(
    .clk(clk),
    .rst(rst),
    .wr_i(wr_i),
    .rd_i(rd_i),
    .addr_i(addr_i),
    .din_i(cpu_din),
    .rx_fifo_in(8'h00),      // RX không được dùng trong ví dụ TX
    .rx_fifo_empty_i(1'b1),   // không có dữ liệu RX
    .rx_oe(1'b0),
    .rx_pe(1'b0),
    .rx_fe(1'b0),
    .rx_bi(1'b0),
    .tx_fifo_empty_i(fifo_empty),
    .baud_out(baud_out),
    .tx_push_o(tx_push),
    .rx_pop_o(),             // không dùng RX
    .tx_reset(),             // không dùng tín hiệu reset TX từ bên ngoài
    .rx_reset(),             // không dùng tín hiệu reset RX
    .rx_fifo_threshold(),    // không sử dụng tín hiệu ngưỡng RX
    .dout_o(),               // không đọc dữ liệu từ thanh ghi
    .fifo_en(fifo_en),
    .wls(wls),
    .stb(stb),
    .pen(pen),
    .eps(eps),
    .sticky_parity(sticky_parity),
    .set_break(set_break),
    .dlab(dlab)
  );
  
  // --- Khối FIFO ---
  uart_tx_fifo fifo_inst(
    .clk(clk),
    .rst(rst),
    .en(1'b1),              // luôn enabled
    .push_in(tx_push),
    .pop_in(tx_pop),
    .din(cpu_din),
    .dout(fifo_dout),
    .empty(fifo_empty),
    .full(fifo_full),
    .overrun(fifo_overrun),
    .underrun(fifo_underrun),
    .threshold(4'd8),       // sử dụng hằng số 4-bit
    .thre_trigger(fifo_thre_trigger)
  );
  
  // --- Khối TX Shift Register ---
  uart_tx_top tx_inst(
    .clk(clk),
    .rst(rst),
    .baud_pulse(baud_out),  // lấy tín hiệu baud từ thanh ghi
    .pen(pen),
    .stb(stb),
    .sticky_parity(sticky_parity),
    .eps(eps),
    .set_break(set_break),
    .wls(wls),
    .din(fifo_dout),        // dữ liệu từ FIFO
    .thre(fifo_empty),      // nếu FIFO rỗng => không có dữ liệu
    .pop(tx_pop),           // ra lệnh pop dữ liệu từ FIFO
    .sreg_empty(),          // không sử dụng tín hiệu trạng thái nội bộ của TX
    .tx(tx)
  );
  
endmodule
