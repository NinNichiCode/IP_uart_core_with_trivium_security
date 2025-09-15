// FILE: secure_uart_tx_top.v 
`timescale 1ns / 1ps
`default_nettype none

module secure_uart_tx_top (
    input   wire            clk,
    input   wire            rst,
    input   wire            wr_i,
    input   wire            rd_i,
    input   wire    [4:0]   addr_i,
    input   wire    [7:0]   cpu_din,
    output  reg     [7:0]   cpu_dout,
    output  wire            tx,
    output  wire            uart_busy,
    output  wire            debug_keystream_bit,
    output  wire            debug_trivium_cphr_en
);

    localparam ADDR_SEC_CTRL    = 5'h08, ADDR_SEC_STATUS  = 5'h09,
               ADDR_KEY_BASE    = 5'h0A, ADDR_IV_BASE     = 5'h14,
               ADDR_UART_THR    = 5'h00, ADDR_UART_LCR    = 5'h03;

    localparam [3:0] S_WAIT_CMD      = 4'd0, S_LOAD_KEY      = 4'd1,
                     S_LOAD_IV       = 4'd2, S_START_WARMUP  = 4'd3,
                     S_WAIT_WARMUP   = 4'd4, S_IDLE          = 4'd5,
                     S_START_ENCRYPT = 4'd6, S_WAIT_ENCRYPT  = 4'd7,
                     S_FIFO_PUSH     = 4'd8;

    reg [3:0] current_state_r, next_state_s;
    reg [79:0] key_reg_r, iv_reg_r;
    reg        init_start_cmd_r;
    wire       is_ready;
    wire       n_rst = ~rst;
    reg [2:0]  load_counter_r;
    reg [10:0] wait_counter_r;
    reg        trivium_init_r, trivium_proc_r;
    wire [31:0] trivium_ld_dat;
    wire [2:0]  trivium_ld_reg_a, trivium_ld_reg_b;
    wire [7:0]  ciphertext_from_trivium_w;
    wire        trivium_busy_w;
    reg  [7:0]  plaintext_buffer_r;
    wire        uart_tx_push_w;
    wire [7:0]  uart_fifo_din_w;
    wire        uart_fifo_empty_w, uart_fifo_full_w, uart_tx_pop_w;
    wire        uart_baud_out_w, uart_dlab_w;
    wire [1:0]  uart_wls_w;
    wire        uart_pen_w, uart_stb_w, uart_sticky_parity_w, uart_eps_w, uart_set_break_w;
    wire [7:0]  uart_fifo_dout_w;
    wire        cpu_writes_to_thr = wr_i & (addr_i[2:0] == 3'b000) & (addr_i[4:3]==2'b00) & ~uart_dlab_w;
    wire        wr_to_uart = wr_i && (addr_i < 5'h08);
    wire        rd_from_uart = rd_i && (addr_i < 5'h08);
    wire        trivium_cphr_en_w;   
    wire        trivium_keystream_w;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            key_reg_r <= 80'd0;
            iv_reg_r  <= 80'd0;
            init_start_cmd_r <= 1'b0;
        end else begin
            if (init_start_cmd_r) init_start_cmd_r <= 1'b0;
            
            if (wr_i && addr_i >= 5'h08) begin
                case (addr_i)
                    ADDR_SEC_CTRL: if (cpu_din[0]) init_start_cmd_r <= 1'b1;
                    
                    ADDR_KEY_BASE+0: key_reg_r[7:0]   <= cpu_din;
                    ADDR_KEY_BASE+1: key_reg_r[15:8]  <= cpu_din;
                    ADDR_KEY_BASE+2: key_reg_r[23:16] <= cpu_din;
                    ADDR_KEY_BASE+3: key_reg_r[31:24] <= cpu_din;
                    ADDR_KEY_BASE+4: key_reg_r[39:32] <= cpu_din;
                    ADDR_KEY_BASE+5: key_reg_r[47:40] <= cpu_din;
                    ADDR_KEY_BASE+6: key_reg_r[55:48] <= cpu_din;
                    ADDR_KEY_BASE+7: key_reg_r[63:56] <= cpu_din;
                    ADDR_KEY_BASE+8: key_reg_r[71:64] <= cpu_din;
                    ADDR_KEY_BASE+9: key_reg_r[79:72] <= cpu_din;
                    
                    ADDR_IV_BASE+0:  iv_reg_r[7:0]    <= cpu_din;
                    ADDR_IV_BASE+1:  iv_reg_r[15:8]   <= cpu_din;
                    ADDR_IV_BASE+2:  iv_reg_r[23:16]  <= cpu_din;
                    ADDR_IV_BASE+3:  iv_reg_r[31:24]  <= cpu_din;
                    ADDR_IV_BASE+4:  iv_reg_r[39:32]  <= cpu_din;
                    ADDR_IV_BASE+5:  iv_reg_r[47:40]  <= cpu_din;
                    ADDR_IV_BASE+6:  iv_reg_r[55:48]  <= cpu_din;
                    ADDR_IV_BASE+7:  iv_reg_r[63:56]  <= cpu_din;
                    ADDR_IV_BASE+8:  iv_reg_r[71:64]  <= cpu_din;
                    ADDR_IV_BASE+9:  iv_reg_r[79:72]  <= cpu_din;
                endcase
            end
        end
    end
    
    assign is_ready = (current_state_r == S_IDLE);
    assign uart_busy = !is_ready;

    always @(*) begin
        cpu_dout = 8'h00;
        if (rd_i) begin
            case(addr_i)
                ADDR_SEC_STATUS: cpu_dout = {7'b0, is_ready};
                default: cpu_dout = 8'h00;
            endcase
        end
    end

    trivium_top trivium_inst (
        .clk_i(clk), .n_rst_i(n_rst), .dat_i(plaintext_buffer_r), .ld_dat_i(trivium_ld_dat),
        .ld_reg_a_i(trivium_ld_reg_a), .ld_reg_b_i(trivium_ld_reg_b), .init_i(trivium_init_r),
        .proc_i(trivium_proc_r), .dat_o(ciphertext_from_trivium_w), .busy_o(trivium_busy_w), 
        .keystream_for_tb_o (trivium_keystream_w),
        .debug_cphr_en_o (trivium_cphr_en_w)
    );
    
    regs_uart regs_inst (
        .clk(clk), .rst(rst), .wr_i(wr_to_uart), .rd_i(rd_from_uart), .addr_i(addr_i[2:0]), .din_i(cpu_din),
        .rx_fifo_in(8'h00), .rx_fifo_empty_i(1'b1), .rx_oe(1'b0), .rx_pe(1'b0), .rx_fe(1'b0), .rx_bi(1'b0),
        .tx_fifo_empty_i(uart_fifo_empty_w), .baud_out(uart_baud_out_w),
        .tx_push_o(), .rx_pop_o(), .tx_reset(), .rx_reset(), .rx_fifo_threshold(), .dout_o(), .fifo_en(),
        .wls(uart_wls_w), .stb(uart_stb_w), .pen(uart_pen_w), .eps(uart_eps_w),
        .sticky_parity(uart_sticky_parity_w), .set_break(uart_set_break_w), .dlab(uart_dlab_w)
    );
    
    uart_tx_fifo fifo_inst (
        .clk(clk), .rst(rst), .en(1'b1), .push_in(uart_tx_push_w), .pop_in(uart_tx_pop_w),
        .din(uart_fifo_din_w), .dout(uart_fifo_dout_w), .empty(uart_fifo_empty_w), .full(uart_fifo_full_w),
        .overrun(), .underrun(), .threshold(4'd8), .thre_trigger()
    );
  
    uart_tx_top tx_inst (
        .clk(clk), .rst(rst), .baud_pulse(uart_baud_out_w), .pen(uart_pen_w), .stb(uart_stb_w),
        .sticky_parity(uart_sticky_parity_w), .eps(uart_eps_w), .set_break(uart_set_break_w),
        .wls(uart_wls_w), .din(uart_fifo_dout_w), .thre(uart_fifo_empty_w), .pop(uart_tx_pop_w),
        .sreg_empty(), .tx(tx)
    );
    
    assign uart_fifo_din_w = ciphertext_from_trivium_w;
    assign uart_tx_push_w  = (current_state_r == S_FIFO_PUSH);

    assign debug_keystream_bit = trivium_keystream_w;
    assign debug_trivium_cphr_en = trivium_cphr_en_w;
    
    reg [31:0] trivium_ld_dat_comb;
    reg [2:0]  trivium_ld_reg_a_comb;
    reg [2:0]  trivium_ld_reg_b_comb;

    assign trivium_ld_dat   = trivium_ld_dat_comb;
    assign trivium_ld_reg_a = trivium_ld_reg_a_comb;
    assign trivium_ld_reg_b = trivium_ld_reg_b_comb;

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

    always @(*) begin
        next_state_s = current_state_r;
        case (current_state_r)
            S_WAIT_CMD:
                if (init_start_cmd_r) next_state_s = S_LOAD_KEY;       
            S_LOAD_KEY:
                if (load_counter_r == 2 )  next_state_s = S_LOAD_IV;
            S_LOAD_IV:
                if (load_counter_r == 2) next_state_s = S_START_WARMUP;
            S_START_WARMUP:
                next_state_s = S_WAIT_WARMUP;
            S_WAIT_WARMUP:
                if (wait_counter_r == 1151) next_state_s = S_IDLE;
            S_IDLE: begin
                if (cpu_writes_to_thr && !uart_fifo_full_w) 
                    next_state_s = S_START_ENCRYPT;
                else if (init_start_cmd_r) 
                    next_state_s = S_LOAD_KEY;
            end
            S_START_ENCRYPT:
                next_state_s = S_WAIT_ENCRYPT;
            S_WAIT_ENCRYPT:
                if (wait_counter_r == 8) next_state_s = S_FIFO_PUSH;
            S_FIFO_PUSH:
                next_state_s = S_IDLE;
            default: next_state_s = S_WAIT_CMD;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state_r    <= S_WAIT_CMD;
            trivium_init_r     <= 1'b0;
            trivium_proc_r     <= 1'b0;
            load_counter_r     <= 0;
            wait_counter_r     <= 0;
            plaintext_buffer_r <= 0;
        end else begin
            current_state_r <= next_state_s;
            trivium_init_r <= 1'b0;
            trivium_proc_r <= 1'b0;
           case (current_state_r)
                S_WAIT_CMD:
                    if (next_state_s == S_LOAD_KEY) load_counter_r <= 0;
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
                    wait_counter_r <= 0;
                end
                S_WAIT_WARMUP:
                    if (next_state_s == S_IDLE)
                        wait_counter_r <= 0;
                    else
                        wait_counter_r <= wait_counter_r + 1;
                S_IDLE:
                    if (next_state_s == S_START_ENCRYPT)
                        plaintext_buffer_r <= cpu_din;
                    else if (next_state_s == S_LOAD_KEY)
                        load_counter_r <= 0;
                S_START_ENCRYPT: begin
                    trivium_proc_r <= 1'b1;
                    wait_counter_r <= 0;
                end
                S_WAIT_ENCRYPT:
                    if (next_state_s == S_FIFO_PUSH)
                        wait_counter_r <= 0;
                    else
                        wait_counter_r <= wait_counter_r + 1;
                default: ;
            endcase
        end
    end

endmodule