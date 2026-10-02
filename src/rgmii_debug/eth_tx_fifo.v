// Device-independent asynchronous byte FIFO for the RGMII bring-up.
// The copied encrypted FIFO IP caused RP0007 (SSRAM unavailable) on GW5AT.
module eth_tx_fifo (
    input [15:0] Data, input Reset, input WrClk, input RdClk,
    input WrEn, input RdEn, output [13:0] Rnum,
    output Almost_Empty, output Almost_Full, output [7:0] Q,
    output Empty, output Full
);
localparam AW = 12;
(* ram_style = "distributed" *) reg [7:0] mem [0:(1<<AW)-1];
reg [AW:0] wbin, rbin;
reg [AW:0] rgray_w1, rgray_w2, wgray_r1, wgray_r2;
wire [AW:0] used_bytes = wbin - rbin;
wire [AW:0] wbin_next = wbin + (WrEn ? 2 : 0);
wire [AW:0] rbin_next = rbin + (RdEn ? 1 : 0);
assign Rnum = {1'b0, used_bytes};
assign Q = mem[rbin[AW-1:0]];
assign Empty = (used_bytes == 0);
assign Full = (used_bytes >= ((1<<AW)-2));
assign Almost_Empty = (used_bytes < 16);
assign Almost_Full = (used_bytes > ((1<<AW)-64));
always @(posedge WrClk or posedge Reset) begin
    if (Reset) begin wbin <= 0; rgray_w1 <= 0; rgray_w2 <= 0; end
    else begin
        rgray_w1 <= rbin; rgray_w2 <= rgray_w1;
        if (WrEn && !Full) begin
            mem[wbin[AW-1:0]] <= Data[7:0];
            mem[wbin[AW-1:0] + 1'b1] <= Data[15:8];
            wbin <= wbin_next;
        end
    end
end
always @(posedge RdClk or posedge Reset) begin
    if (Reset) begin rbin <= 0; wgray_r1 <= 0; wgray_r2 <= 0; end
    else begin
        wgray_r1 <= wbin; wgray_r2 <= wgray_r1;
        if (RdEn && !Empty) rbin <= rbin_next;
    end
end
endmodule
