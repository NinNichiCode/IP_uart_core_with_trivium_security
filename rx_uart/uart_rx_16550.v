`timescale 1ns / 1ps

module uart_rx_16550(
    input clk,
    input rst,
    input baud_pulse,
    input rx,
    input sticky_parity, // để cấu hình parity (ở đây dùng 0 cho kiểm tra lẻ)
    input eps,           // chọn even parity khi sticky_parity=0; ở đây để 0 để dùng odd parity
    input pen,           // enable parity: 1 để kiểm tra parity
    input [1:0] wls,     // chọn số bit dữ liệu: 2'b11 cho 8-bit
    input stb,           // nếu stb=1 thì sử dụng 2 stop bit, nếu 0 thì 1 stop bit
    output reg push,     // khi frame hợp lệ, kích hoạt đẩy dữ liệu ra FIFO
    output reg pe,       // parity error
    output reg fe,       // frame error (stop bit không hợp lệ)
    output reg bi,       // break indicator
    output [7:0] rx_out
);

parameter [2:0] idle   = 3'b000,
                start  = 3'b00001,
                read   = 3'b010,
                parity_state = 3'b011,
                stop   = 3'b100;
                
reg [2:0] state;
reg [2:0] bitcnt;
reg [3:0] count = 0;
reg [7:0] dout = 0;
reg pe_reg;
reg [4:0] stop_cnt = 0; // đếm số stop bit đã nhận

// Phát hiện cạnh xuống (start bit được truyền 0)
reg rx_reg = 1'b1;
always @(posedge clk)
  rx_reg <= rx;
wire fall_edge = rx_reg; // khi rx chuyển từ 1->0 sẽ bắt đầu nhận

always @(posedge clk or posedge rst) begin
  if(rst) begin
    state <= idle;
    push  <= 1'b0;
    pe    <= 1'b0;
    fe    <= 1'b0;
    bi    <= 1'b0;
    bitcnt <= 3'd0;
    count <= 4'd0;
    stop_cnt <= 0;
  end else begin
    push <= 1'b0;  // mặc định không đẩy dữ liệu
    if(baud_pulse) begin
      case(state)
      idle: begin
        if(!fall_edge) begin  // start bit xuất hiện (rx=0)
          state <= start;
          count <= 4'd15;
        end else begin
          state <= idle;
        end
      end
      start: begin
        count <= count - 1;
        if(count == 4'd7) begin
          if(rx == 1'b1) begin
            state <= idle;
            count <= 4'd15;
          end else begin
            state <= start;
          end
        end else if(count == 0) begin
          state <= read;
          count <= 4'd15;
          bitcnt <= {1'b1, wls};  // Ví dụ: với wls=2'b11, bitcnt = 3'b111 (7) - lưu ý: số lần chuyển có thể hiệu chỉnh tùy yêu cầu
        end
      end
      read: begin
        count <= count - 1;
        if(count == 4'd7) begin
          case(wls)
            2'b00: dout <= {3'b000, rx, dout[4:1]};
            2'b01: dout <= {2'b00, rx, dout[5:1]};
            2'b10: dout <= {1'b0, rx, dout[6:1]};
            2'b11: dout <= {dout[6:0], rx};
          endcase
        end else if(count == 0) begin
          if(bitcnt == 0) begin
            // Khi đã nhận xong dữ liệu, kiểm tra parity nếu pen=1
            case({sticky_parity, eps})
              2'b00: pe_reg <= ~^{rx, dout}; // odd parity error detector: nếu tổng số 1 là lẻ thì ~^ = 0 (không lỗi)
              2'b01: pe_reg <=  ^{rx, dout};  // even parity error detector
              2'b10: pe_reg <= ~rx;
              2'b11: pe_reg <=  rx;
            endcase
            if(pen) begin
              state <= parity_state;
              count <= 4'd15;
            end else begin
              state <= stop;
              count <= 4'd15;
              stop_cnt <= 0;
            end
          end else begin
            bitcnt <= bitcnt - 1;
            state <= read;
            count <= 4'd15;
          end
        end
      end
      parity_state: begin
        count <= count - 1;
        if(count == 4'd7) begin
          pe <= pe_reg;
        end else if(count == 0) begin
          state <= stop;
          count <= 4'd15;
          stop_cnt <= 0;
        end
      end
      stop: begin
        count <= count - 1;
        if(count == 4'd7) begin
          // Stop bit phải luôn ở mức 1, nếu không thì báo lỗi frame
          if(rx != 1'b1)
            fe <= 1'b1;
          stop_cnt <= stop_cnt + 1;
        end
        if(count == 0) begin
          // Nếu stb=1 (y/c 2 stop bit) và chưa nhận đủ 2 stop bit, chờ thêm chu kỳ
          if(stb && (stop_cnt < 2)) begin
             count <= 4'd15;
          end else begin
             state <= idle;
             count <= 4'd15;
             stop_cnt <= 0;
             push <= 1'b1;  // kết thúc frame, đẩy dữ liệu ra FIFO
          end
        end
      end
      default: state <= idle;
      endcase
    end
  end
end

assign rx_out = dout;

endmodule
