module top #(
    // 强制使用内部测试图模式
    parameter USE_TPG = "true",
    parameter USE_1280 = "true"
)(
    input                  clk,          // 50MHz 时钟
    input                  rst_n,        // 系统复位按键
    
    // 状态指示灯
    output [7:0]           state_led,
    output                 uart_tx,
    // FPGA -> RK3588 GMAC1, board-level RGMII connection (no cable needed)
    output                 rgmii_tx_clk,
    output [3:0]           rgmii_txd,
    output                 rgmii_tx_ctl,

    // DDR3L 接口 (必须重新生成为 32-bit DDR3L)
    output [15-1:0]        ddr_addr,     // DDR address pins A[14:0]
    output [3-1:0]         ddr_bank,     // BANK_WIDTH=3
    output                 ddr_cs,
    output                 ddr_ras,
    output                 ddr_cas,
    output                 ddr_we,
    output                 ddr_ck,
    output                 ddr_ck_n,
    output                 ddr_cke,
    output                 ddr_odt,
    output                 ddr_reset_n,
    output [4-1:0]         ddr_dm,       // DM_WIDTH=4
    inout  [32-1:0]        ddr_dq,       // DQ_WIDTH=32
    inout  [4-1:0]         ddr_dqs,      // DQS_WIDTH=4
    inout  [4-1:0]         ddr_dqs_n     // DQS_WIDTH=4
);

    // ==========================================
    // 1. 系统时钟域与复位
    // ==========================================
    wire video_clk;         // 视频时钟 (比如 74.25MHz)
    wire memory_clk;        // DDR 接口时钟 (比如 400MHz)
    wire dma_clk;           // 用户逻辑/DMA 时钟
    wire video_pll_lock;
    wire DDR_pll_lock;
    wire init_calib_complete;
    reg [1:0] ddr_rst_n_sync_ff;
    wire ddr_rst_n_sync = ddr_rst_n_sync_ff[1];

    // The DDR IP requires reset deassertion to be synchronized to its clk input.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ddr_rst_n_sync_ff <= 2'b00;
        else
            ddr_rst_n_sync_ff <= {ddr_rst_n_sync_ff[0], 1'b1};
    end
    
    // Gowin PLL 实例化：根据您的配置产生 3 路时钟
    Gowin_PLL Gowin_PLL_m0(
        .clkin      (clk),          // 50M 输入
        .mdclk      (clk),          // PLL_INIT mDRP initialization clock
        .reset      (~rst_n),       // 复位
        .lock       (video_pll_lock), // video PLL lock
        .clkout0    (video_clk),    // 产生 75M 视频时钟
        .clkout2    ()
    );

    wire ddr_pll_stop;
    wire mdrp_inc;
    wire [1:0] mdrp_op;
    wire [7:0] mdrp_wdata;
    wire [7:0] mdrp_rdata;
    reg ddr_pll_lock_r;
    reg ddr_pll_lock_rr;
    reg ddr_pll_stop_r;
    reg mdrp_wr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ddr_pll_lock_r <= 1'b0;
            ddr_pll_lock_rr <= 1'b0;
            ddr_pll_stop_r <= 1'b1;
            mdrp_wr <= 1'b0;
        end else begin
            ddr_pll_lock_r <= DDR_pll_lock;
            ddr_pll_lock_rr <= ddr_pll_lock_r;
            ddr_pll_stop_r <= ddr_pll_stop;
            mdrp_wr <= ddr_pll_lock_rr && (ddr_pll_stop != ddr_pll_stop_r);
        end
    end

    pll_mDRP_intf ddr_pll_gate_ctrl (
        .clk        (clk),
        .rst_n      (ddr_rst_n_sync),
        .pll_lock   (ddr_pll_lock_rr),
        .wr         (mdrp_wr),
        .mdrp_inc   (mdrp_inc),
        .mdrp_op    (mdrp_op),
        .mdrp_wdata (mdrp_wdata),
        .mdrp_rdata (mdrp_rdata)
    );

    ddr_pll ddr_clock_pll_inst (
        .clkin           (clk),
        .clkout0         (),
        .clkout1         (),
        .clkout2         (memory_clk),
        .lock            (DDR_pll_lock),
        .mdopc           (mdrp_op),
        .mdainc          (mdrp_inc),
        .mdwdi           (mdrp_wdata),
        .mdrdo           (mdrp_rdata),
        .pll_init_bypass (ddr_pll_lock_rr),
        .mdclk           (clk),
        .reset           (~rst_n)
    );

    // ==========================================
    // 2. 前端生产者：测试图形生成 (1280x720)
    // ==========================================
    wire        tp0_vs_in;
    wire        tp0_hs_in;
    wire        tp0_de_in;
    wire [7:0]  tp0_data_r;
    wire [7:0]  tp0_data_g;
    wire [7:0]  tp0_data_b;

    testpattern testpattern_inst_1280 (
        .I_pxl_clk   (clk),
        .I_rst_n     (rst_n),
        .I_mode      (3'b000),      // 000 为彩条模式
        .I_single_r  (8'd255),
        .I_single_g  (8'd255),
        .I_single_b  (8'd255),
        .I_h_total   (12'd1650),
        .I_h_sync    (12'd40),
        .I_h_bporch  (12'd220),
        .I_h_res     (12'd1280),
        .I_v_total   (12'd750),
        .I_v_sync    (12'd5),
        .I_v_bporch  (12'd20),
        .I_v_res     (12'd720),
        .I_hs_pol    (1'b1),
        .I_vs_pol    (1'b1),
        .O_de        (tp0_de_in),
        .O_hs        (tp0_hs_in),
        .O_vs        (tp0_vs_in),
        .O_data_r    (tp0_data_r),
        .O_data_g    (tp0_data_g),
        .O_data_b    (tp0_data_b)
    );

    // 封装写端数据：RGB565 格式
    // Match Gowin's VFB reference topology: producer and consumer use
    // independent clocks so their frame-pointer updates cannot be coincident.
    wire fb_vin_clk   = clk;
    wire fb_vin_vsync = tp0_vs_in;
    wire fb_vin_de    = tp0_de_in;
    wire [15:0] fb_vin_data = {tp0_data_r[7:3], tp0_data_g[7:2], tp0_data_b[7:3]};

    // First Ethernet bring-up intentionally bypasses DDR.  The sender buffers
    // each RGB565 line in an asynchronous FIFO and emits one UDP packet/line.
    rgb565_udp_sender rgb565_udp_sender_inst (
        .clk50       (clk),
        .rst_n       (rst_n),
        .pixel_data  (fb_vin_data),
        .pixel_valid (fb_vin_de),
        .rgmii_tx_clk(rgmii_tx_clk),
        .rgmii_txd   (rgmii_txd),
        .rgmii_tx_ctl(rgmii_tx_ctl)
    );


    // ==========================================
    // 3. 后端消费者：读时序发生器 (未来被 PCIe DMA 替代)
    // ==========================================
    wire [10:0]  lcd_x, lcd_y;
    reg  [10:0]  lcd_x_d1, lcd_x_d2;
    reg  [10:0]  lcd_y_d1, lcd_y_d2;
    wire        syn_off0_hs, syn_off0_vs;
    wire        out_de;

    // 产生一个假的读取请求，模拟下游在吃数据
    vga_timing #(
        .H_ACTIVE(16'd1280), 
        .H_FP(16'd110),
        .H_SYNC(16'd40),
        .H_BP(16'd220),
        .V_ACTIVE(16'd720),
        .V_FP(16'd5),
        .V_SYNC(16'd5),
        .V_BP(16'd20),  
        .HS_POL(1'b1),      
        .VS_POL(1'b1)
    ) vga_timing_m0(
        .clk        (video_clk),
        .rst        (~rst_n),
        .active_x   (lcd_x),
        .active_y   (lcd_y),
        .hs         (syn_off0_hs),
        .vs         (syn_off0_vs),
        .de         (out_de)
    );

    // VFB specifies O_vout0_den/data two clocks after I_vout0_de. Delay the
    // requested coordinates by the same amount before probing returned data.
    always @(posedge video_clk or negedge rst_n) begin
        if (!rst_n) begin
            lcd_x_d1 <= 11'd0;
            lcd_x_d2 <= 11'd0;
            lcd_y_d1 <= 11'd0;
            lcd_y_d2 <= 11'd0;
        end else begin
            lcd_x_d1 <= lcd_x;
            lcd_x_d2 <= lcd_x_d1;
            lcd_y_d1 <= lcd_y;
            lcd_y_d2 <= lcd_y_d1;
        end
    end

    // ==========================================
    // 4. 数据缓存中心 (Video Frame Buffer & DDR3L)
    // ==========================================
    wire        off0_syn_de;
    wire [15:0] off0_syn_data;
    wire        vfb_vin_fifo_full;
    wire        vfb_vout_fifo_empty;
    reg  [15:0] vfb_overflow_count;
    reg  [15:0] vfb_underflow_count;
    wire ddr_internal_rst;
    wire [7:0] ddr_dbg_vector1;
    wire [15:0] ddr_dbg_vector2;
    wire [11:0] ddr_dbg_vector3;
    wire [31:0] ddr_dbg_vector4;

    // 连接 VFB 与 DDR3 的 AXI 握手信号
    wire        cmd_ready, cmd_en, wr_data_rdy, wr_data_en, wr_data_end, rd_data_valid, rd_data_end;
    wire        ddr_sr_ack, ddr_ref_ack;
    wire [2:0]  cmd;
    wire [27:0] addr;
    wire [255:0] wr_data;  // 数据位宽依您生成的 DDR IP 而定，32位通常配 256
    wire [31:0]  wr_data_mask;
    wire [255:0] rd_data;
    reg [31:0] write_cmd_req_count, write_cmd_accept_count;
    reg [31:0] read_cmd_req_count, read_cmd_accept_count;
    reg [31:0] write_data_accept_count, read_data_count;
    wire [13:0] ddr_addr_core;
    assign ddr_addr[13:0] = ddr_addr_core;
    assign ddr_addr[14] = 1'b0; // A14 is reserved for this x16 geometry; keep it defined.

    always @(posedge dma_clk or negedge rst_n) begin
        if (!rst_n) begin
            write_cmd_req_count <= 32'd0;
            write_cmd_accept_count <= 32'd0;
            read_cmd_req_count <= 32'd0;
            read_cmd_accept_count <= 32'd0;
            write_data_accept_count <= 32'd0;
            read_data_count <= 32'd0;
        end else begin
            if (cmd_en && !cmd[0])
                write_cmd_req_count <= write_cmd_req_count + 32'd1;
            if (cmd_en && cmd_ready && !cmd[0])
                write_cmd_accept_count <= write_cmd_accept_count + 32'd1;
            if (cmd_en && cmd[0])
                read_cmd_req_count <= read_cmd_req_count + 32'd1;
            if (cmd_en && cmd_ready && cmd[0])
                read_cmd_accept_count <= read_cmd_accept_count + 32'd1;
            if (wr_data_en && wr_data_rdy)
                write_data_accept_count <= write_data_accept_count + 32'd1;
            if (rd_data_valid)
                read_data_count <= read_data_count + 32'd1;
        end
    end

    Video_Frame_Buffer_Top Video_Frame_Buffer_Top_inst ( 
        .I_rst_n              (init_calib_complete),
        .I_dma_clk            (dma_clk),
        .I_wr_halt            (1'd0), 
        .I_rd_halt            (1'd0),

        // 写端口 (生产者)
        .I_vin0_clk           (fb_vin_clk),
        .I_vin0_vs_n          (~fb_vin_vsync),
        .I_vin0_de            (fb_vin_de),
        .I_vin0_data          (fb_vin_data),
        .O_vin0_fifo_full     (vfb_vin_fifo_full),

        // 读端口 (消费者)           
        .I_vout0_clk          (video_clk),
        .I_vout0_vs_n         (~syn_off0_vs),
        .I_vout0_de           (out_de),
        .O_vout0_den          (off0_syn_de),
        .O_vout0_data         (off0_syn_data),
        .O_vout0_fifo_empty   (vfb_vout_fifo_empty),

        // 与 DDR3 握手
        .I_cmd_ready          (cmd_ready),
        .O_cmd                (cmd),
        .O_cmd_en             (cmd_en),
        .O_addr               (addr),
        .I_wr_data_rdy        (wr_data_rdy),
        .O_wr_data_en         (wr_data_en),
        .O_wr_data_end        (wr_data_end),
        .O_wr_data            (wr_data),
        .O_wr_data_mask       (wr_data_mask),
        .I_rd_data_valid      (rd_data_valid),
        .I_rd_data_end        (rd_data_end),
        .I_rd_data            (rd_data),
        .I_init_calib_complete(init_calib_complete)
    ); 

    always @(posedge fb_vin_clk or negedge rst_n) begin
        if (!rst_n)
            vfb_overflow_count <= 16'd0;
        else if (fb_vin_de && vfb_vin_fifo_full && vfb_overflow_count != 16'hffff)
            vfb_overflow_count <= vfb_overflow_count + 16'd1;
    end

    always @(posedge video_clk or negedge rst_n) begin
        if (!rst_n)
            vfb_underflow_count <= 16'd0;
        else if (out_de && vfb_vout_fifo_empty && vfb_underflow_count != 16'hffff)
            vfb_underflow_count <= vfb_underflow_count + 16'd1;
    end

    // Capture only the DDR readback, never the test pattern's input stream.
    frame_debug_uart #(.CLOCK_HZ(75000000), .BAUD(115200)) frame_debug_inst (
        .clk(video_clk), .rst_n(rst_n),
        .calib_done(init_calib_complete), .pll_lock(DDR_pll_lock),
        .ddr_reset_n(ddr_reset_n), .pll_stop(ddr_pll_stop),
        .ddr_rst(ddr_internal_rst),
        .dbg_vector1(ddr_dbg_vector1), .dbg_vector2(ddr_dbg_vector2),
        .dbg_vector3(ddr_dbg_vector3), .dbg_vector4(ddr_dbg_vector4),
        .vfb_overflow_count(vfb_overflow_count),
        .vfb_underflow_count(vfb_underflow_count),
        .write_cmd_req_count(write_cmd_req_count),
        .write_cmd_accept_count(write_cmd_accept_count),
        .read_cmd_req_count(read_cmd_req_count),
        .read_cmd_accept_count(read_cmd_accept_count),
        .write_data_accept_count(write_data_accept_count),
        .read_data_count(read_data_count),
        .frame_vs(syn_off0_vs),
        .pixel_valid(off0_syn_de), .pixel_x(lcd_x_d2[9:0]),
        .pixel_y(lcd_y_d2[9:0]), .pixel_data(off0_syn_data),
        .uart_tx(uart_tx)
    );

    DDR3_d u_ddr3 (
        .clk                  (clk),
        .memory_clk           (memory_clk),
        .pll_stop             (ddr_pll_stop),
        .pll_lock             (DDR_pll_lock),
        .rst_n                (ddr_rst_n_sync),
        .cmd_ready            (cmd_ready),
        .cmd                  (cmd),
        .cmd_en               (cmd_en),
        .addr                 (addr),
        .wr_data_rdy          (wr_data_rdy),
        .wr_data              (wr_data),
        .wr_data_en           (wr_data_en),
        .wr_data_end          (wr_data_end),
        .wr_data_mask         (wr_data_mask),
        .rd_data              (rd_data),
        .rd_data_valid        (rd_data_valid),
        .rd_data_end          (rd_data_end),
        .sr_req               (1'b0),
        .ref_req              (1'b0),
        .sr_ack               (ddr_sr_ack),
        .ref_ack              (ddr_ref_ack),
        .init_calib_complete  (init_calib_complete),
        .clk_out              (dma_clk),
        .ddr_rst              (ddr_internal_rst),
        .burst                (1'b1),
        .dbg_vector1_out      (ddr_dbg_vector1),
        .dbg_vector2_out      (ddr_dbg_vector2),
        .dbg_vector3_out      (ddr_dbg_vector3),
        .dbg_vector4_out      (ddr_dbg_vector4),

        // 物理管脚
        .O_ddr_addr           (ddr_addr_core),
        .O_ddr_ba             (ddr_bank),
        .O_ddr_cs_n           (ddr_cs),
        .O_ddr_ras_n          (ddr_ras),
        .O_ddr_cas_n          (ddr_cas),
        .O_ddr_we_n           (ddr_we),
        .O_ddr_clk            (ddr_ck),
        .O_ddr_clk_n          (ddr_ck_n),
        .O_ddr_cke            (ddr_cke),
        .O_ddr_odt            (ddr_odt),
        .O_ddr_reset_n        (ddr_reset_n),
        .O_ddr_dqm            (ddr_dm),
        .IO_ddr_dq            (ddr_dq),
        .IO_ddr_dqs           (ddr_dqs),
        .IO_ddr_dqs_n         (ddr_dqs_n)
    );

    // ==========================================
    // 5. 探针与状态指示灯 (代替显示器验证通路)
    // ==========================================
    reg [15:0] center_pixel_probe;

    // 当读取到屏幕正中心时 (X=640, Y=360)，捕获那个时刻的像素值
    always @(posedge video_clk or negedge rst_n) begin
        if (!rst_n) begin
            center_pixel_probe <= 16'd0;
        end else if (off0_syn_de && (lcd_x_d2 == 11'd640) && (lcd_y_d2 == 11'd360)) begin
            center_pixel_probe <= off0_syn_data;
        end
    end

    // 将系统核心状态暴露在 LED 上
    // led[0]: DDR3 初始化完成指示 (高亮代表正常)
    // led[1]: 探针捕获到了非黑色的数据 (验证整条读取通路有数据流出)
    // led[7]: 存活心跳灯 (0.5秒闪烁)
    reg [25:0] heartbeat;
    always @(posedge clk) heartbeat <= heartbeat + 26'd1;

    assign state_led[0] = ~init_calib_complete; // 低电平点亮，初始化完成变暗
    assign state_led[1] = ~(center_pixel_probe != 16'd0); // 读到了数据变暗
    assign state_led[2] = ~DDR_pll_lock;   // On when PLL reports locked
    assign state_led[3] = ~ddr_reset_n;    // On when DDR RESET_N is released
    assign state_led[4] = ~ddr_pll_stop;   // Raw PLL_STOP level, on for 1
    assign state_led[5] = ~ddr_internal_rst;// Raw DDR_RST level, on for 1
    assign state_led[6] = 1'b1; // 闲置
    assign state_led[7] = heartbeat[25]; // 呼吸闪烁证明 FPGA 未挂死

endmodule
