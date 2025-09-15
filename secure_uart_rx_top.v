`timescale 1ns / 1ps
`default_nettype none

// =================================================================================
// === MODULE: secure_uart_rx_top.v (PHIÊN BẢN ĐÃ SỬA LỖI)
// === CHỨC NĂNG:
// === 1. Nhận dòng bit nối tiếp (ciphertext).
// === 2. Giải mã bằng Trivium.
// === 3. Cung cấp dữ liệu đã giải mã (plaintext) cho CPU.
// === 4. Quản lý cấu hình và trạng thái theo chuẩn UART 16550.
// === KIẾN TRÚC: "Một FIFO" - Sử dụng Ciphertext FIFO và một thanh ghi đệm RBR.
// =================================================================================
module secure_uart_rx_top (
    // --- Cổng giao tiếp chuẩn ---
    input   wire            clk,
    input   wire            rst,
    // --- Cổng UART ---
    input   wire            rx_i,
    // --- Cổng giao tiếp CPU Bus ---
    input   wire            wr_i,
    input   wire            rd_i,
    input   wire    [4:0]   addr_i,
    input   wire    [7:0]   cpu_din,
    output  reg     [7:0]   cpu_dout,
    // --- Cổng trạng thái ---
    output  wire            is_ready,
    output  wire            dlab_w_debug,

    // --- Cổng debug cho keystream ---
    output  wire            debug_cphr_en_o,
    output  wire            debug_keystream_bit_o
);
    // --- Tham số địa chỉ thanh ghi ---
    localparam ADDR_SEC_CTRL    = 5'h08, ADDR_SEC_STATUS  = 5'h09,
               ADDR_KEY_BASE    = 5'h0A, ADDR_IV_BASE     = 5'h14,
               ADDR_UART_RBR    = 5'h00, ADDR_UART_LSR    = 5'h05;

    // --- Các trạng thái của FSM ---
    localparam [3:0] S_WAIT_CMD      = 4'd0, S_LOAD_KEY      = 4'd1,
                     S_LOAD_IV       = 4'd2, S_START_WARMUP  = 4'd3,
                     S_WAIT_WARMUP   = 4'd4, S_IDLE          = 4'd5,
                     S_START_DECRYPT = 4'd6, S_WAIT_DECRYPT  = 4'd7;

    // --- Các tín hiệu nội bộ ---
    reg [3:0]   current_state_r, next_state_s;
    reg [79:0]  key_reg_r, iv_reg_r;
    reg         init_start_cmd_r;
    wire        n_rst = ~rst;

    reg         trivium_init_r, trivium_proc_r;
    reg [31:0]  trivium_ld_dat_comb;
    reg [2:0]   trivium_ld_reg_a_comb, trivium_ld_reg_b_comb;
    wire [7:0]  plaintext_from_trivium_w;
    wire        trivium_busy_w;
    reg [2:0]   load_counter_r;
    
    wire [7:0]  ciphertext_data_w;
    wire        ct_fifo_empty_w;
    wire        ct_fifo_pop_w;
    
    reg  [7:0]  rbr_reg; 
    reg         rbr_full_flag_r; 
    wire        cpu_reads_rbr = rd_i && (addr_i == ADDR_UART_RBR) && !dlab_w_debug;
    
    wire [7:0]  regs_uart_dout_w;
    wire        wr_to_uart = wr_i && (addr_i < 5'h08);
    wire        rd_from_uart = rd_i && (addr_i < 5'h08);
    
    wire        baud_pulse_w;
    wire [1:0]  wls_w;
    wire        stb_w, pen_w, eps_w, sticky_parity_w;
    wire        rx_pe_w, rx_fe_w, rx_bi_w;

    reg [10:0]  warmup_counter_r; 

    wire        trivium_cphr_en_w;   
    wire        trivium_keystream_w;

    // <<<< THAY ĐỔI 1: Loại bỏ thanh ghi đệm không cần thiết và không an toàn >>>>
    // reg  [7:0]  decrypt_buffer_r;

    // --- Giao diện CPU: Quyết định dữ liệu nào được đưa ra cpu_dout ---
    assign is_ready = (current_state_r == S_IDLE);

    always @(*) begin
        if (cpu_reads_rbr) begin
            cpu_dout = rbr_reg;
        end else if (rd_i && addr_i == ADDR_SEC_STATUS) begin
             cpu_dout = {7'b0, is_ready};
        end else begin
             cpu_dout = regs_uart_dout_w;
        end
    end

    // ======================== KẾT NỐI CÁC KHỐI CON ========================
    
    // --- KHỐI 1: TRIVIUM ENGINE ---
    trivium_top trivium_inst (
        .clk_i(clk), 
        .n_rst_i(n_rst), 
        // <<<< THAY ĐỔI 2: Nối thẳng đầu ra FIFO vào Trivium để đảm bảo dữ liệu đúng >>>>
        .dat_i(ciphertext_data_w), 
        .ld_dat_i(trivium_ld_dat_comb),
        .ld_reg_a_i(trivium_ld_reg_a_comb), 
        .ld_reg_b_i(trivium_ld_reg_b_comb), 
        .init_i(trivium_init_r),
        .proc_i(trivium_proc_r), 
        .dat_o(plaintext_from_trivium_w), 
        .busy_o(trivium_busy_w),
        .keystream_for_tb_o(trivium_keystream_w),
        .debug_cphr_en_o(trivium_cphr_en_w)
    );

    assign debug_cphr_en_o     = trivium_cphr_en_w;
    assign debug_keystream_bit_o = trivium_keystream_w;

    // --- KHỐI 2: LÕI UART RX ---
    uart_rx_core rx_core_inst (
        .clk(clk), .rst(rst), .rx(rx_i),
        .baud_pulse(baud_pulse_w), .wls(wls_w), .stb(stb_w), .pen(pen_w),
        .eps(eps_w), .sticky_parity(sticky_parity_w),
        .pop_from_fsm_i(ct_fifo_pop_w),
        .ciphertext_data_o(ciphertext_data_w),
        .fifo_empty_o(ct_fifo_empty_w),
        .pe_o(rx_pe_w), .fe_o(rx_fe_w), .bi_o(rx_bi_w)
    );
    
    // <<<< THAY ĐỔI 3: Chỉ pop FIFO SAU KHI giải mã xong để giữ dữ liệu ổn định >>>>
    assign ct_fifo_pop_w = (current_state_r == S_WAIT_DECRYPT && !trivium_busy_w);

    // --- KHỐI 3: THANH GHI UART (NGUỒN CẤU HÌNH DUY NHẤT) ---
    // (Không thay đổi)
    regs_uart regs_inst (
        .clk(clk), .rst(rst),
        .wr_i(wr_to_uart), .rd_i(rd_from_uart && !cpu_reads_rbr),
        .addr_i(addr_i[2:0]), .din_i(cpu_din),
        .rx_fifo_in(8'h00), 
        .rx_fifo_empty_i(!rbr_full_flag_r),
        .rx_pe(rx_pe_w), .rx_fe(rx_fe_w), .rx_bi(rx_bi_w),
        .dout_o(regs_uart_dout_w),
        .baud_out(baud_pulse_w),
        .wls(wls_w), .stb(stb_w), .pen(pen_w), .eps(eps_w),
        .sticky_parity(sticky_parity_w), .dlab(dlab_w_debug),
        .tx_fifo_empty_i(1'b1), .tx_push_o(), .rx_pop_o(), .tx_reset(), .rx_reset(), 
        .rx_fifo_threshold(), .fifo_en(), .set_break(), .rx_oe(1'b0)
    );
    
    // ======================== MÁY TRẠNG THÁI (FSM) ========================

    // --- FSM - LOGIC TRẠNG THÁI TIẾP THEO (TỔ HỢP) ---
    // (Không thay đổi)
    always @(*) begin
        next_state_s = current_state_r;
        case (current_state_r)
            S_WAIT_CMD:
                if (init_start_cmd_r) next_state_s = S_LOAD_KEY;
            S_LOAD_KEY:
                if (load_counter_r == 2) next_state_s = S_LOAD_IV;
            S_LOAD_IV:
                if (load_counter_r == 2) next_state_s = S_START_WARMUP;
            S_START_WARMUP:
                next_state_s = S_WAIT_WARMUP;
            S_WAIT_WARMUP:
                if (warmup_counter_r == 1151)
                    next_state_s = S_IDLE;
                else
                    next_state_s = S_WAIT_WARMUP; 
            S_IDLE:
                if (!ct_fifo_empty_w && !rbr_full_flag_r)
                    next_state_s = S_START_DECRYPT;
                else if (init_start_cmd_r)
                    next_state_s = S_LOAD_KEY;
            S_START_DECRYPT:
                next_state_s = S_WAIT_DECRYPT;
            S_WAIT_DECRYPT:
                if (!trivium_busy_w) next_state_s = S_IDLE;
            default: next_state_s = S_WAIT_CMD;
        endcase
    end

    // --- FSM & THANH GHI - LOGIC TUẦN TỰ (THEO CLOCK) ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state_r <= S_WAIT_CMD;
            key_reg_r       <= 80'd0;
            iv_reg_r        <= 80'd0;
            load_counter_r  <= 0;
            init_start_cmd_r<= 1'b0;
            trivium_init_r  <= 1'b0;
            trivium_proc_r  <= 1'b0;
            rbr_full_flag_r <= 1'b0;
            rbr_reg         <= 8'h00;
            warmup_counter_r <= 0;
            // decrypt_buffer_r <= 8'h00; // <<<< THAY ĐỔI: Đã loại bỏ
        end else begin
            current_state_r <= next_state_s;

            // Mặc định các tín hiệu điều khiển là 0
            trivium_init_r  <= 1'b0;
            trivium_proc_r  <= 1'b0;

            // <<<< THAY ĐỔI: Đã loại bỏ logic cập nhật buffer >>>>
            // if (ct_fifo_pop_w) begin
            //     decrypt_buffer_r <= ciphertext_data_w;
            // end
            
            // Xử lý cờ báo RBR đầy và thanh ghi RBR
            if (cpu_reads_rbr) begin
                rbr_full_flag_r <= 1'b0; // CPU đã đọc, RBR đã trống
            end else if (current_state_r == S_WAIT_DECRYPT && next_state_s == S_IDLE) begin
                rbr_full_flag_r <= 1'b1; // Giải mã xong, RBR đầy
                rbr_reg         <= plaintext_from_trivium_w;
            end

            // Logic xử lý theo từng trạng thái
            case (current_state_r)
                S_WAIT_CMD:
                    if (next_state_s == S_LOAD_KEY)
                        load_counter_r <= 0;
                S_LOAD_KEY:
                    if (next_state_s == S_LOAD_IV)
                        load_counter_r <= 0;
                    else
                        load_counter_r <= load_counter_r + 1;
                S_LOAD_IV:
                    if (next_state_s == S_START_WARMUP)
                        load_counter_r <= 0;
                    else
                        load_counter_r <= load_counter_r + 1;
               S_START_WARMUP: begin
                    trivium_init_r <= 1'b1;
                    warmup_counter_r <= 0;
                end
                
                S_WAIT_WARMUP: begin
                    if (next_state_s == S_WAIT_WARMUP)
                        warmup_counter_r <= warmup_counter_r + 1;
                    else
                        warmup_counter_r <= 0;
                end
                S_IDLE:
                    if (next_state_s == S_START_DECRYPT)
                        trivium_proc_r <= 1'b1;
                    else if (next_state_s == S_LOAD_KEY)
                        load_counter_r <= 0;
            endcase
            
            // Logic xử lý các lệnh ghi từ CPU
            if (init_start_cmd_r) init_start_cmd_r <= 1'b0;

            if(wr_i) begin
                if(addr_i == ADDR_SEC_CTRL && cpu_din[0]) init_start_cmd_r <= 1'b1;
                if(addr_i >= ADDR_KEY_BASE && addr_i < ADDR_IV_BASE)
                    key_reg_r[ (addr_i - ADDR_KEY_BASE)*8 +: 8 ] <= cpu_din;
                if(addr_i >= ADDR_IV_BASE)
                    iv_reg_r[ (addr_i - ADDR_IV_BASE)*8 +: 8 ] <= cpu_din;
            end
        end
    end
    
    // --- LOGIC TỔ HỢP ĐỂ NẠP DỮ LIỆU KEY/IV VÀO TRIVIUM ---
    // (Không thay đổi)
    always @(*) begin
        trivium_ld_dat_comb   = 32'd0;
        trivium_ld_reg_a_comb = 3'd0;
        trivium_ld_reg_b_comb = 3'd0;
        
        if (current_state_r == S_LOAD_KEY) begin
            trivium_ld_reg_a_comb[load_counter_r] = 1'b1;
            case (load_counter_r)
                0: trivium_ld_dat_comb = {key_reg_r[31:24], key_reg_r[23:16], key_reg_r[15:8], key_reg_r[7:0]};
                1: trivium_ld_dat_comb = {key_reg_r[63:56], key_reg_r[55:48], key_reg_r[47:40], key_reg_r[39:32]};
                2: trivium_ld_dat_comb = {16'd0, key_reg_r[79:72], key_reg_r[71:64]};
            endcase
        end
        else if (current_state_r == S_LOAD_IV) begin
            trivium_ld_reg_b_comb[load_counter_r] = 1'b1;
            case (load_counter_r)
                0: trivium_ld_dat_comb = {iv_reg_r[31:24], iv_reg_r[23:16], iv_reg_r[15:8], iv_reg_r[7:0]};
                1: trivium_ld_dat_comb = {iv_reg_r[63:56], iv_reg_r[55:48], iv_reg_r[47:40], iv_reg_r[39:32]};
                2: trivium_ld_dat_comb = {16'd0, iv_reg_r[79:72], iv_reg_r[71:64]};
            endcase
        end
    end
endmodule