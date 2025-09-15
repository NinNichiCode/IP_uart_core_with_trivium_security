///////UART_FIFO

`timescale 1ns / 1ps



module uart_rx_fifo(clk,rst,en,push_in,pop_in,din,dout,empty,full,overrun,

underrun,threshold,thre_trigger);

input clk,rst,en,push_in,pop_in;

input [7:0]din;

input [3:0]threshold;

output [7:0]dout;

output empty,full,overrun,underrun;

output thre_trigger;



reg [7:0]mem[0:15];

reg [3:0] waddr = 0;



wire push,pop;

reg empty_t = 1'b1;
always @(posedge clk or posedge rst)
begin
    if(rst) begin
        empty_t <= 1'b1;
    end
    else if (en) begin // Chỉ hoạt động khi được cho phép
        case({push,pop})
            // Trở nên rỗng khi pop phần tử cuối cùng (waddr đang là 1)
            2'b01: if (waddr == 4'h1) empty_t <= 1'b1;
            // Không còn rỗng khi push vào FIFO rỗng
            2'b10: empty_t <= 1'b0;
            // Khi cả push và pop, trạng thái empty không đổi
            // 2'b11: empty_t <= empty_t; 
        endcase
    end else begin
        empty_t <= 1'b1; // Nếu không enable, coi như rỗng
    end
end

reg full_t = 0;
always@(posedge clk or posedge rst)
begin
    if(rst) begin
        full_t<=1'b0;
    end
    else if (en) begin // Chỉ hoạt động khi được cho phép
        case({push,pop})
            // Không còn đầy khi pop ra
            2'b01: full_t <= 1'b0;
            // Trở nên đầy khi push vào phần tử cuối cùng (waddr đang là 15)
            2'b10: if (waddr == 4'hF) full_t <= 1'b1;
            // Khi cả push và pop, trạng thái full không đổi
            // 2'b11: full_t <= full_t;
        endcase
    end else begin
        full_t <= 1'b0; // Nếu không enable, coi như không đầy
    end
end

assign push = push_in & ~full_t;

assign pop = pop_in & ~empty_t;

assign dout = mem[0];



always @(posedge clk or posedge rst)

begin

if(rst)

waddr <= 4'h0;

else begin

case({push,pop})

2'b10: begin

if(waddr!=4'hf && full_t == 1'b0)

waddr <= waddr + 1;

else

waddr <= waddr;

end

2'b01: begin

if(waddr != 4'h0 && empty_t == 1'b0)

waddr <= waddr -1;

else

waddr <= waddr;

end

default: waddr <= waddr;

endcase

end

end

integer i = 0;

always @(posedge clk or posedge rst)

begin

if(rst) begin

for(i = 0; i<16 ; i = i+1)

mem[i] <=0;

end

else begin

case({push,pop})

2'b10:begin

mem[waddr] <= din;

end

2'b01: begin

for(i = 0;i <15 ; i = i+1)begin

mem[i] <= mem[i+1];

end

mem[15] <= 8'h00;

end

2'b11: begin

for(i = 0; i<15 ; i = i+1)begin

mem[i] <= mem[i+1];

end

mem[15] <= 8'h00;

mem[waddr - 1] <= din;

end

default: begin

for(i = 0; i<16; i=i+1)begin

mem[i]<= mem[i];

end

end

endcase

end

end

reg underrun_t = 0;

always @(posedge clk or posedge rst)

begin

if(rst)

underrun_t <= 1'b0;

else if(pop_in == 1'b1 && empty_t ==1'b1)

underrun_t <= 1'b1;

else

underrun_t <= 1'b0;

end

reg overrun_t = 1'b0;

always @(posedge clk or posedge rst)

begin

if(rst)

overrun_t <= 1'b0;

else if (push_in == 1'b1 && full_t == 1'b1)

overrun_t <= 1'b1;

else

overrun_t <= 1'b0;

end

reg thre_t = 1'b0;

always @(posedge clk or posedge rst)

begin

if(rst)

thre_t <= 1'b0;

else if(push^pop)

begin

thre_t <= (waddr >= threshold) ? 1'b1 : 1'b0;

end

end

assign empty = empty_t;

assign full = full_t;

assign overrun = overrun_t;

assign underrun = underrun_t;

assign thre_trigger = thre_t;

endmodule