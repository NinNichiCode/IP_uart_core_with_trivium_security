/////CSR_REGISTER STACK

`timescale 1ns / 1ps
`default_nettype none

// Fifo control register

`define rx_trigger fcr[7:6]

`define dma_mode fcr[3]

`define tx_rst fcr[2]

`define rx_rst fcr[1]

`define fifo_ena fcr[0]



//line control register

`define dlab lcr[7]

`define set_break lcr[6]

`define sticky_parity lcr[5]

`define eps lcr[4]

`define pen lcr[3]

`define stb lcr[2]

`define wls lcr[1:0]



//line status register

`define rx_fifo_error lsr[7]

`define temt lsr[6]

`define thre lsr[5]

`define bi lsr[4]

`define fe lsr[3]

`define pe lsr[2]

`define oe lsr[1]

`define dr lsr[0]



module regs_uart(
    input   wire        clk,
    input   wire        rst,
    input   wire        wr_i,
    input   wire        rd_i,
    input   wire [2:0]  addr_i,
    input   wire [7:0]  din_i,
    input   wire [7:0]  rx_fifo_in,
    input   wire        rx_fifo_empty_i,
    input   wire        rx_oe,
    input   wire        rx_pe,
    input   wire        rx_fe,
    input   wire        rx_bi,
    input   wire        tx_fifo_empty_i,
    output  wire        baud_out,
    output  wire        tx_push_o,
    output  wire        rx_pop_o,
    output  wire        tx_reset,
    output  wire        rx_reset,
    output  wire [3:0]  rx_fifo_threshold,
    output  reg  [7:0]  dout_o, // Giữ nguyên vì đã đúng
    output  wire        fifo_en,
    output  wire [1:0]  wls,
    output  wire        stb,
    output  wire        pen,
    output  wire        eps,
    output  wire        sticky_parity,
    output  wire        set_break,
    output  wire        dlab
  );


wire dlab_i;

wire tx_fifo_wr;
// ,tx_push_o;

//write into tx_fifo

assign tx_fifo_wr = (wr_i && (addr_i == 3'b000) && (dlab_i == 1'b0))? 1'b1: 1'b0;

assign tx_push_o = tx_fifo_wr;

//read from rx fifo

wire rx_fifo_rd;
// ,rx_pop_o;

assign rx_fifo_rd = (rd_i && (addr_i == 3'b000) && (dlab_i == 1'b0))? 1'b1: 1'b0;

assign rx_pop_o = rx_fifo_rd;

reg [7:0]rx_data;

always @(posedge clk)

begin

if(rx_pop_o)

rx_data <= rx_fifo_in;

end

//baud generation logic

reg [7:0]dmsb,dlsb;

wire [15:0] divisior_latch;

always @(posedge clk)

begin

if(wr_i && (addr_i == 3'b000) && (dlab_i == 1'b1))

begin

dlsb <= din_i;

end

else if(wr_i && (addr_i == 3'b001) && (dlab_i == 1'b1))

begin

dmsb <= din_i;

end

end

assign divisior_latch = {dmsb,dlsb};

reg update_baud;

reg [15:0]baud_cnt = 0;

reg baud_pulse = 0;



always @(posedge clk)

begin

if(wr_i && dlab_i == 1'b1 && (addr_i == 3'b000 || addr_i == 3'b001))

begin

update_baud <= 1'b1;

end

else

update_baud <= 1'b0;

end

///baud counter

always @(posedge clk or posedge rst)

begin

if(rst)

baud_cnt <= 16'h0000;

else if(update_baud || baud_cnt == 16'h0000)

baud_cnt <= divisior_latch - 1;

else

baud_cnt <= baud_cnt - 1;

end

always @(posedge clk)

begin

baud_pulse <= |divisior_latch & ~|baud_cnt;

end

assign baud_out = baud_pulse;

///defination of registers

reg [7:0]fcr; // addr = 010,write

reg [7:0]lcr; // addr = 011,write

reg [7:0]lsr; // addr = 101,read

reg [7:0]scr; // addr = 111, ?

// assigning the FCR

always @(posedge clk or posedge rst)

begin

if(rst)

fcr <= 8'h06;

else if(wr_i == 1'b1 && addr_i == 3'b010)

fcr <= din_i;

else

begin

`tx_rst <= 1'b0;

`rx_rst <= 1'b0;

end

end

assign tx_reset = `tx_rst;

assign rx_reset = `rx_rst;

// setting the threshold value of fifo

reg [3:0]rx_fifo_th_count = 0;

always @(posedge clk)

begin

if(`fifo_ena == 1'b0)

rx_fifo_th_count <= 4'd0;

else

case(`rx_trigger)

2'b00: rx_fifo_th_count <= 4'd1;

2'b01: rx_fifo_th_count <= 4'd4;

2'b10: rx_fifo_th_count <= 4'd8;

2'b11: rx_fifo_th_count <= 4'd14;

endcase

end

assign rx_fifo_threshold = rx_fifo_th_count;

//setting line control register

reg [7:0] lcr_temp;

always @(posedge clk or posedge rst)

begin

if(rst)

begin

lcr <= 8'h00;

end

else if(wr_i == 1'b1 && addr_i == 3'b011)

begin

lcr <= din_i;

end

end

assign dlab_i = `dlab;

wire read_lcr;

assign read_lcr = ((rd_i == 1) &&(addr_i == 3'h3))? 1'b1:1'b0;

always @(posedge clk)

begin

if(read_lcr)

begin

lcr_temp <= lcr;

end

end


  // Định nghĩa thanh ghi LCR
always @(posedge clk or posedge rst) begin
  if (rst) begin
    lcr <= 8'h00;
  end else if (wr_i == 1'b1 && addr_i == 3'b011) begin
    lcr <= din_i;
  end
end

assign dlab = lcr[7]; // Kết nối tín hiệu DLAB với ngõ ra


//setting line status register

wire [7:0] lsr_next;

// Dùng assign để tính toán từng bit của lsr_next một cách rõ ràng
assign lsr_next[0] = ~rx_fifo_empty_i; // DR
assign lsr_next[1] = rx_oe;             // OE
assign lsr_next[2] = rx_pe;             // PE
assign lsr_next[3] = rx_fe;             // FE
assign lsr_next[4] = rx_bi;             // BI
assign lsr_next[5] = tx_fifo_empty_i;   // THRE (Trong thiết kế RX, tx_fifo_empty_i luôn là 1)
assign lsr_next[6] = tx_fifo_empty_i;   // TEMT (Trong thiết kế RX, tx_fifo_empty_i luôn là 1)
assign lsr_next[7] = (rx_oe | rx_pe | rx_fe | rx_bi); // RX FIFO Error

// KHỐI ALWAYS BÂY GIỜ RẤT ĐƠN GIẢN VÀ AN TOÀN
always @(posedge clk or posedge rst) begin
    if (rst) begin
        lsr <= 8'h60; // Giá trị khởi tạo: THRE=1, TEMT=1
    end else begin
        lsr <= lsr_next; // Gán toàn bộ 8 bit trong một lần, không tạo latch
    end
end

///setting scr

always @(posedge clk or posedge rst)

begin

if(rst)

begin

scr <= 8'h00;

end

else if(wr_i == 1'b1 && addr_i == 3'h7)

begin

scr <= din_i;

end

end

reg [7:0]scr_temp;

wire read_scr;

assign read_scr = (rd_i ==1'b1 && addr_i == 3'h7)? 1'b1 : 1'b0;

always @(posedge clk)

begin

if(read_scr)

begin

scr_temp <=scr;

end

end



//defining the output of the register stack

always @(*) begin // Dùng always tổ hợp
    case(addr_i)
        3'h0: dout_o = dlab_i ? dlsb: rx_data;
        3'h1: dout_o = dlab_i ? dmsb : 8'h00;
        3'h2: dout_o = 8'h00; // IIR (đọc)
        3'h3: dout_o = lcr; // Đọc LCR trực tiếp
        3'h4: dout_o = 8'h00; // MCR
        3'h5: dout_o = lsr; // <<<< ĐỌC LSR TRỰC TIẾP >>>>
        3'h6: dout_o = 8'h00; // MSR
        3'h7: dout_o = scr; // Đọc SCR trực tiếp
        default: dout_o = 8'h00;
    endcase
end

assign fifo_en = `fifo_ena;

assign wls = `wls;

assign stb = `stb;

assign pen = `pen;

assign eps = `eps;

assign sticky_parity = `sticky_parity;

assign set_break = `set_break;

endmodule