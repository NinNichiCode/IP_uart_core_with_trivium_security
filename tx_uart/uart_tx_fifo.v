///////UART_FIFO

`timescale 1ns / 1ps
`default_nettype none

// Thay thế toàn bộ module uart_16550_tx.v bằng code này

module uart_tx_fifo(
    input   wire        clk,
    input   wire        rst,
    input   wire        en,
    input   wire        push_in,
    input   wire        pop_in,
    input   wire [7:0]  din,
    input   wire [3:0]  threshold,
    output  wire [7:0]  dout, // Nếu dout được gán trong khối assign
    // output reg [7:0]  dout, // Nếu dout được gán trong khối always
    output  wire        empty,
    output  wire        full,
    output  wire        overrun,
    output  wire        underrun,
    output  wire        thre_trigger
);

reg [7:0] mem[0:15];
reg [4:0] count; 

wire push, pop;

// --- Logic xác định push, pop thực sự ---
assign push = push_in & ~full & en;
assign pop  = pop_in  & ~empty & en;

// --- Logic xác định trạng thái FIFO ---
assign empty = (count == 0);
assign full  = (count == 16);
assign dout  = mem[0];

// --- Bộ đếm số phần tử trong FIFO ---
always @(posedge clk or posedge rst) begin
    if (rst) begin
        count <= 0;
    end else begin
        case({push, pop})
            2'b01: count <= count - 1; // Pop
            2'b10: count <= count + 1; // Push
            default: count <= count;   // Cả hai hoặc không có gì
        endcase
    end
end

// --- Logic bộ nhớ FIFO và DEBUG ---
integer i;
always @(posedge clk) begin
    if (rst) begin
        // không cần reset mem
    end else begin
        // ======================= DEBUG LOGIC START =======================
        // In ra trạng thái trước khi hành động
        // if (push || pop) begin
        //     $display("FIFO DEBUG @%0t ns: Event(push=%b, pop=%b). Count truoc: %d", $time, push, pop, count);
        // end
        // ======================= DEBUG LOGIC END =======================

        if (pop && !push) begin // Chỉ POP
            for (i = 0; i < 15; i = i + 1) begin
                mem[i] <= mem[i+1];
            end
            mem[15] <= 8'h00;
        end 
        else if (push && !pop) begin // Chỉ PUSH
            // Dữ liệu mới được ghi vào cuối hàng đợi (vị trí `count`)
            mem[count] <= din;
        end
        else if (push && pop) begin // Cả PUSH và POP
            // Dịch chuyển lên trước
            for (i = 0; i < 15; i = i + 1) begin
                mem[i] <= mem[i+1];
            end
            // Ghi dữ liệu mới vào vị trí cuối cùng. Vì count không đổi,
            // vị trí cuối cùng của hàng đợi trước khi dịch là `count-1`
            mem[count-1] <= din;
        end
    end
end

// Hàm để in ra nội dung của FIFO (chỉ dùng cho debug)
// task print_fifo_content;
//     integer j;
//     string fifo_str;
//     begin
//         fifo_str = "[";
//         for (j = 0; j < count; j = j + 1) begin
//             fifo_str = {fifo_str, $sformatf(" 0x%h", mem[j])};
//         end
//         fifo_str = {fifo_str, " ]"};
//         $display("FIFO DEBUG: Noi dung FIFO: %s", fifo_str);
//     end
// endtask

// Monitor để theo dõi FIFO
// always @(posedge clk) begin
//     if (push || pop) begin
//         #1; // Đợi 1 chút để các giá trị mới được cập nhật
//         print_fifo_content;
//     end
// end

// --- Logic Overrun/Underrun ---
reg underrun_t = 0;
always @(posedge clk or posedge rst) begin
    if(rst) underrun_t <= 1'b0;
    // Underrun xảy ra nếu có yêu cầu pop khi FIFO đã rỗng
    else if(pop_in == 1'b1 && empty == 1'b1) underrun_t <= 1'b1;
    else underrun_t <= 1'b0;
end

reg overrun_t = 1'b0;
always @(posedge clk or posedge rst) begin
    if(rst) overrun_t <= 1'b0;
    // Overrun xảy ra nếu có yêu cầu push khi FIFO đã đầy
    else if (push_in == 1'b1 && full == 1'b1) overrun_t <= 1'b1;
    else overrun_t <= 1'b0;
end

// --- Logic Threshold ---
reg thre_t = 1'b0;
always @(posedge clk or posedge rst) begin
    if(rst) thre_t <= 1'b0;
    // Trigger khi số phần tử vượt ngưỡng
    else    thre_t <= (count >= threshold);
end

assign overrun = overrun_t;
assign underrun = underrun_t;
assign thre_trigger = thre_t;

endmodule