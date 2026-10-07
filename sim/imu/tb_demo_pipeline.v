`timescale 1ns/1ps
module tb_demo_pipeline;
    reg clk=0,pclk=0,rst_n=0;
    always #10 clk=~clk;
    always #7 pclk=~pclk;
    wire sv,sr,av,ar;
    wire signed [31:0] ax,ay,az,wx,wy,wz;
    wire [31:0] dt;
    wire [50:0] payload,frame_payload;
    reg [11:0] frame_counter=0;
    wire frame_start=frame_counter==4095;
    always @(posedge pclk) if(!rst_n) frame_counter<=0;else frame_counter<=frame_counter+1'b1;
    imu_demo_source #(.CYCLES_PER_SAMPLE(2000)) source(.clk(clk),.rst_n(rst_n),
        .valid(sv),.ready(sr),.ax(ax),.ay(ay),.az(az),.wx(wx),.wy(wy),.wz(wz),.dt_q24(dt));
    attitude_pipeline pipeline(.clk(clk),.rst_n(rst_n),.sample_valid(sv),.sample_ready(sr),
        .ax(ax),.ay(ay),.az(az),.wx(wx),.wy(wy),.wz(wz),.dt_q24(dt),
        .attitude_valid(av),.attitude_ready(ar),.attitude_payload(payload));
    osd_attitude_cdc cdc(.src_clk(clk),.src_rst_n(rst_n),.src_valid(av),.src_ready(ar),
        .src_payload(payload),.dst_clk(pclk),.dst_rst_n(rst_n),
        .frame_start(frame_start),.frame_payload(frame_payload));
    wire [15:0] pixel;
    attitude_osd_rgb565 #(.DEMO_MODE(1)) osd(.pixel_x(12'd166),.pixel_y(12'd55),.pixel_in(16'hF800),
        .roll_bcd(frame_payload[49:34]),.roll_negative(frame_payload[50]),
        .pitch_bcd(frame_payload[32:17]),.pitch_negative(frame_payload[33]),
        .yaw_bcd(frame_payload[15:0]),.yaw_negative(frame_payload[16]),.pixel_out(pixel));
    reg [50:0] previous=0;
    reg frame_previous=0;
    always @(negedge pclk) begin
        if(rst_n && !frame_previous && frame_payload!==previous) $fatal(1,"demo changed OSD mid-frame");
        previous=frame_payload;
    end
    always @(posedge pclk) frame_previous<=frame_start;
    integer fo,count=0,input_count=0;
    reg [1023:0] output_path;
    initial begin
        if(!$value$plusargs("OUTPUT=%s",output_path)) $fatal(1,"missing output path");
        fo=$fopen(output_path,"w");repeat(4) @(negedge clk);rst_n=1;
    end
    always @(posedge clk) if(rst_n) begin
        if(sv && sr) input_count=input_count+1;
        if(av && ar) begin
            $fwrite(fo,"%0d,%0d,%0d,%0d,%0d,%0d\n",count,payload,
                pipeline.u_filter.qw,pipeline.u_filter.qx,pipeline.u_filter.qy,pipeline.u_filter.qz);
            count=count+1;
            if(count==2048) begin
                if(input_count!=2048) $fatal(1,"demo dropped/duplicated sample");
                if((^pixel)===1'bx) $fatal(1,"unknown OSD output");
                $fclose(fo);$display("PASS: 2048 samples through ROM -> Madgwick -> Euler -> BCD -> CDC -> OSD");$finish;
            end
        end
    end
    initial begin #100000000;$fatal(1,"demo pipeline timeout");end
endmodule
