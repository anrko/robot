/////////////////////////////////////////////////////////////////////////////////
// Company       : 武汉芯路恒科技有限公司
//                 http://xiaomeige.taobao.com
// Web           : http://www.corecourse.cn
// 
// Create Date   : 2019/05/01 00:00:00
// Module Name   : ov5640_udp_gmii
// Description   : 摄像头采集，以太网UDP协议发送
// 
// Dependencies  : 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments；
// 
/////////////////////////////////////////////////////////////////////////////////

module ov5640_udp_rgmii(
 output [15:0] af_status,
  output imu_reset_n,
  input attitude_valid,
  output attitude_ready,
  input [50:0] attitude_payload,
  //System clock reset
  input       clk50m        , //系统时钟输入，50MHz
  input       reset_n       , //复位信号输入
 // eth interface
  output 			rgmii_gtxc,
  output [3:0]      rgmii_txd,
  output 			rgmii_txen,
  output 			eth_mdc,
  inout 			eth_mdio,
  output 			eth_rst_n,
	
  //camera interface
  output      camera_sclk   ,
  inout       camera_sdat   ,
  input       camera_vsync  ,
  input       camera_href   ,
  input       camera_pclk   ,
  output      camera_xclk   ,
  input  [7:0]camera_data   ,
  output      camera_pwdn   ,
  output      camera_rst_n  ,
  //led
  output      led         
);
  //*****************************
  //Set IMAGE Size  
  parameter IMAGE_WIDTH  = 1920;
  parameter IMAGE_HEIGHT = 1080;
  //Set ETH 
  parameter DST_MAC   = 48'hFF_FF_FF_FF_FF_FF;
  parameter SRC_MAC   = 48'h00_0a_35_01_fe_c0;
  parameter DST_IP    = 32'hc0_a8_00_03;
  parameter SRC_IP    = 32'hc0_a8_00_02;
  parameter DST_PORT  = 16'd6102;
  parameter SRC_PORT  = 16'd5000;
  parameter OSD_DEMO  = 0;
  //*****************************
  //clock
  wire          pll_locked;
  wire          loc_clk50m;
  wire          loc_clk125m;
  wire          loc_clk24m;
  //reset
  wire          g_rst_p;
  // PLL lock is generated in the 50 MHz domain. Release the UDP reset only
  // after three 125 MHz edges, so CRC/state registers meet recovery timing.
  reg [2:0] udp_reset_sync;
  wire udp_reset_p=udp_reset_sync[2];
  always @(posedge loc_clk125m or posedge g_rst_p)
    if(g_rst_p) udp_reset_sync<=3'b111;
    else udp_reset_sync<={udp_reset_sync[1:0],1'b0};
  //camera interface
  wire          camera_init_done;
  wire          pclk_bufg_o;
  wire [15:0]   image_data;
  wire          image_data_valid;
  wire          image_data_hs;
  wire          image_data_vs;
  wire [11:0]   image_data_xaddr;
  wire [11:0]   image_data_yaddr;
  wire [15:0]   image_data_osd;

  wire [50:0] osd_frame_payload;
  reg camera_vsync_d;
  reg [1:0] osd_reset_sync;
  assign imu_reset_n=~g_rst_p;
  always @(posedge pclk_bufg_o or posedge g_rst_p)
    if(g_rst_p) begin camera_vsync_d<=0;osd_reset_sync<=0;end
    else begin camera_vsync_d<=camera_vsync;osd_reset_sync<={osd_reset_sync[0],1'b1};end
  osd_attitude_cdc u_osd_cdc(
    .src_clk(clk50m),.src_rst_n(~g_rst_p),.src_valid(attitude_valid),
    .src_ready(attitude_ready),.src_payload(attitude_payload),
    .dst_clk(pclk_bufg_o),.dst_rst_n(osd_reset_sync[1]),
    .frame_start(camera_vsync && !camera_vsync_d),.frame_payload(osd_frame_payload));

  reg           pixel_data_valid;
  reg  [15:0]   pixel_data;

  wire          tx_en_pulse;
  wire          tx_done;
  wire          fifo_rd;
  wire [7:0]    fifo_dout;
  // Each captured pixel is RGB565 (2 bytes); prepend a 16-bit row index.
  localparam [15:0] UDP_PAYLOAD_LENGTH = IMAGE_WIDTH * 2 + 2;

  assign g_rst_p     = ~pll_locked;
  assign led         = camera_init_done;


        Gowin_PLL your_instance_name(
        .clkin(clk50m), //input  clkin
        .clkout0(loc_clk50m), //output  clkout0
        .clkout1(loc_clk125m), //output  clkout1
        .clkout2(loc_clk24m), //output  clkout2
        .lock(pll_locked), //output  lock
        .mdclk(clk50m), //input  mdclk
        .reset(~reset_n) //input  reset
    );


	wire phy_init;
	phy_reg_config phy_reg_config_inst(
		.Clk(loc_clk50m),
		.Rst_n(~g_rst_p),
		.Phy_rst_n(eth_rst_n),		
		.mdc(eth_mdc),
		.mdio(eth_mdio),
		.Phy_init_done(phy_init)
	);

  assign camera_xclk = loc_clk24m;

  camera_init
  #(
    .CAMERA_TYPE ( "ov5640"    ),//"ov5640" or "ov7725"
    .IMAGE_TYPE  ( 0            ),// 0: RGB; 1: JPEG
    .IMAGE_WIDTH ( IMAGE_WIDTH  ),// 图片宽度
    .IMAGE_HEIGHT( IMAGE_HEIGHT ),// 图片高度
    .IMAGE_FLIP_EN  ( 1            ),// 0: 不翻转，1: 上下翻转
    .IMAGE_MIRROR_EN( 0            ) // 0: 不镜像，1: 左右镜像
  )camera_init
  (
    .Clk         (loc_clk50m       ),
    .Rst_n       (~g_rst_p         ),
    .af_status(af_status),
.Init_Done   (camera_init_done ),
    .camera_rst_n(camera_rst_n     ),
    .camera_pwdn (camera_pwdn      ),
    .i2c_sclk    (camera_sclk      ),
    .i2c_sdat    (camera_sdat      )
   );


  assign pclk_bufg_o = camera_pclk;

  DVP_Capture DVP_Capture(
    .Rst_p      (g_rst_p          ),//input
    .PCLK       (pclk_bufg_o      ),//input
    .Vsync      (camera_vsync     ),//input
    .Href       (camera_href      ),//input
    .Data       (camera_data      ),//input     [7:0]

    .ImageState (                 ),//output reg
    .DataValid  (image_data_valid ),//output
    .DataPixel  (image_data       ),//output    [15:0]
    .DataHs     (image_data_hs    ),//output
    .DataVs     (image_data_vs    ),//output
    .Xaddr      (image_data_xaddr ),//output    [11:0]
    .Yaddr      (image_data_yaddr ) //output    [11:0]
  );

  // Add the text before line framing/FIFO insertion so the OSD only changes
  // camera pixels; the 16-bit row-index word remains untouched.
  attitude_osd_rgb565 #(.DEMO_MODE(OSD_DEMO)) u_attitude_osd (
    .pixel_x        (image_data_xaddr),
    .pixel_y        (image_data_yaddr),
    .pixel_in       (image_data),
    .roll_bcd       (osd_frame_payload[49:34]),
    .roll_negative  (osd_frame_payload[50]),
    .pitch_bcd      (osd_frame_payload[32:17]),
    .pitch_negative (osd_frame_payload[33]),
    .yaw_bcd        (osd_frame_payload[15:0]),
    .yaw_negative   (osd_frame_payload[16]),
    .pixel_out      (image_data_osd)
  );

//-------------------------------------------
  //对摄像头采集数据每行加上行号，2byte
  reg        image_data_hs_dly1;
  reg [15:0] image_data_dly1;
  reg        image_data_valid_dly1;

  always@(posedge pclk_bufg_o)
  begin
    image_data_hs_dly1    <= image_data_hs;
    //image_data_dly1       <= image_data_xaddr; //use to sim
    image_data_dly1       <= image_data_osd;
    image_data_valid_dly1 <= image_data_valid;
  end

  always@(posedge pclk_bufg_o or posedge g_rst_p)
  if(g_rst_p)
    pixel_data <= 0;
  else if(~image_data_hs_dly1 && image_data_hs)
    pixel_data <= image_data_yaddr - 1'b1;    //add_row_num
  else if(image_data_valid_dly1)
    pixel_data <= image_data_dly1;

  always@(posedge pclk_bufg_o or posedge g_rst_p)
  if(g_rst_p)
    pixel_data_valid <= 0;
  else if(~image_data_hs_dly1 && image_data_hs)
    pixel_data_valid <= 1;
  else if(image_data_valid_dly1)
    pixel_data_valid <= 1;
  else
    pixel_data_valid <= 0;
//-------------------------------------------

  eth_tx_ctrl
  #(
    .PAYLOAD_DATA_BYTE (2              ),
    // FIFO input is 16 bits: one row-index word plus IMAGE_WIDTH pixel words.
    .PAYLOAD_LENGTH    (IMAGE_WIDTH + 1 )
  )eth_tx_ctrl_inst
  (
    .reset_p          (g_rst_p          ),

    .clk              (pclk_bufg_o      ),
    .data_i           ({pixel_data[7:0],pixel_data[15:8]}       ),
    .data_valid_i     (pixel_data_valid),

    .eth_txfifo_rd_clk(loc_clk125m      ),
    .tx_en_pulse      (tx_en_pulse      ),
    .tx_done          (tx_done          ),
    .eth_txfifo_rden  (fifo_rd          ),
    .eth_txfifo_dout  (fifo_dout        )
  );
  
  wire[7:0] gmii_txd;
  wire gmii_tx_clk;
  wire gmii_txen;
  

  //eth udp 1g
  eth_udp_tx_gmii eth_udp_tx_gmii(
    .clk125m      (loc_clk125m           ),
    .reset_p      (udp_reset_p           ),

    .tx_en_pulse  (tx_en_pulse           ),
    .tx_done      (tx_done               ),
    
    .dst_mac      (DST_MAC               ),
    .src_mac      (SRC_MAC               ),
    .dst_ip       (DST_IP                ),
    .src_ip       (SRC_IP                ),
    .dst_port     (DST_PORT              ),
    .src_port     (SRC_PORT              ),
    
    .data_length  (UDP_PAYLOAD_LENGTH    ),
    
    .payload_req_o(fifo_rd               ),
    .payload_dat_i(fifo_dout             ),

    .gmii_tx_clk  (gmii_tx_clk           ),
    .gmii_txen    (gmii_txen             ),
    .gmii_txd     (gmii_txd              )
  );
  
   gmii_to_rgmii gmii_to_rgmii(
  .reset_n(reset_n),

  .gmii_tx_clk(gmii_tx_clk),
  .gmii_txd(gmii_txd),
  .gmii_txen(gmii_txen),
  .gmii_txer(1'b0),

  .rgmii_tx_clk(rgmii_gtxc),
  .rgmii_txd(rgmii_txd),
  .rgmii_txen(rgmii_txen)
);

endmodule
