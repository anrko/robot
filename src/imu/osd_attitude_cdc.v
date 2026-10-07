// Bundled-data mailbox: hold all 51 bits until the destination acknowledges.
// Only toggle bits cross through synchronisers. Capture a coherent snapshot,
// then change the displayed snapshot on frame_start, never mid-frame.
module osd_attitude_cdc (
    input wire src_clk,input wire src_rst_n,
    input wire src_valid,output wire src_ready,input wire [50:0] src_payload,
    input wire dst_clk,input wire dst_rst_n,input wire frame_start,
    output reg [50:0] frame_payload
);
    reg [50:0] held,pending;
    reg request,acknowledge,seen;
    (* syn_preserve=1 *) reg ack_meta,ack_sync;
    (* syn_preserve=1 *) reg request_meta,request_sync;
    assign src_ready=request==ack_sync;
    always @(posedge src_clk or negedge src_rst_n) begin
        if(!src_rst_n) begin held<=0;request<=0;ack_meta<=0;ack_sync<=0;end
        else begin
            ack_meta<=acknowledge;ack_sync<=ack_meta;
            if(src_valid && src_ready) begin held<=src_payload;request<=~request;end
        end
    end
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if(!dst_rst_n) begin
            request_meta<=0;request_sync<=0;seen<=0;acknowledge<=0;pending<=0;frame_payload<=0;
        end else begin
            request_meta<=request;request_sync<=request_meta;
            if(request_sync!=seen) begin
                pending<=held;seen<=request_sync;acknowledge<=request_sync;
            end
            if(frame_start) frame_payload<=pending;
        end
    end
endmodule
