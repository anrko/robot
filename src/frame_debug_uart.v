module frame_debug_uart #(
    parameter CLOCK_HZ = 75000000,
    parameter BAUD = 115200
)(
    input wire clk,
    input wire rst_n,
    input wire calib_done,
    input wire pll_lock,
    input wire ddr_reset_n,
    input wire pll_stop,
    input wire ddr_rst,
    input wire [7:0] dbg_vector1,
    input wire [15:0] dbg_vector2,
    input wire [11:0] dbg_vector3,
    input wire [31:0] dbg_vector4,
    input wire [15:0] vfb_overflow_count,
    input wire [15:0] vfb_underflow_count,
    input wire [31:0] write_cmd_req_count,
    input wire [31:0] write_cmd_accept_count,
    input wire [31:0] read_cmd_req_count,
    input wire [31:0] read_cmd_accept_count,
    input wire [31:0] write_data_accept_count,
    input wire [31:0] read_data_count,
    input wire frame_vs,
    input wire pixel_valid,
    input wire [9:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire [15:0] pixel_data,
    output wire uart_tx
);
    // The 64x64 crop crosses the center color-bar boundary at x=640.
    localparam X0 = 10'd608;
    localparam Y0 = 10'd328;
    localparam WAIT_FRAME = 3'd0;
    localparam STATUS = 3'd1;
    localparam HEADER = 3'd2;
    localparam PIXELS = 3'd3;
    localparam ROW_CR = 3'd4;
    localparam ROW_LF = 3'd5;
    localparam TRAILER = 3'd6;
    localparam BUS_DIAG = 3'd7;

    reg [15:0] crop [0:4095];
    reg [15:0] read_pixel;
    reg [11:0] pixel_index;
    reg [1:0] nibble_index;
    reg [12:0] captured;
    reg [15:0] checksum;
    reg [6:0] char_index;
    reg [2:0] state;
    reg capturing;
    reg complete;
    reg vs_prev;
    reg calib_meta, calib_sync;
    reg [3:0] diag_meta, diag_sync;
    reg [7:0] dbg1_meta, dbg1_sync;
    reg [15:0] dbg2_meta, dbg2_sync;
    reg [11:0] dbg3_meta, dbg3_sync;
    reg [31:0] dbg4_meta, dbg4_sync;
    reg [15:0] overflow_meta, overflow_sync;
    reg [15:0] underflow_meta, underflow_sync;
    reg [31:0] wcq_meta, wcq_sync, wca_meta, wca_sync;
    reg [31:0] rcq_meta, rcq_sync, rca_meta, rca_sync;
    reg [31:0] wda_meta, wda_sync, rdd_meta, rdd_sync;
    reg [31:0] second_counter;
    reg stop_prev;
    reg stop_low_seen;
    reg [7:0] stop_edges;
    reg pll_prev;
    reg [7:0] pll_drop_count;
    reg drst_prev;
    reg [7:0] drst_edges;
    wire second_tick = second_counter == CLOCK_HZ - 1;
    wire vs_rise = frame_vs && !vs_prev;
    wire crop_valid = pixel_valid && pixel_x >= X0 && pixel_x < X0 + 10'd64 &&
                      pixel_y >= Y0 && pixel_y < Y0 + 10'd64;
    wire [5:0] crop_dx = pixel_x[5:0] - X0[5:0];
    wire [5:0] crop_dy = pixel_y[5:0] - Y0[5:0];
    wire [11:0] crop_addr = {crop_dy, crop_dx};

    function [7:0] hex_char;
        input [3:0] value;
        begin
            hex_char = value < 10 ? 8'h30 + value : 8'h41 + value - 10;
        end
    endfunction

    function [7:0] hex32_char;
        input [31:0] value;
        input [2:0] digit;
        begin
            case (digit)
                3'd0: hex32_char = hex_char(value[31:28]);
                3'd1: hex32_char = hex_char(value[27:24]);
                3'd2: hex32_char = hex_char(value[23:20]);
                3'd3: hex32_char = hex_char(value[19:16]);
                3'd4: hex32_char = hex_char(value[15:12]);
                3'd5: hex32_char = hex_char(value[11:8]);
                3'd6: hex32_char = hex_char(value[7:4]);
                default: hex32_char = hex_char(value[3:0]);
            endcase
        end
    endfunction

    wire uart_busy;
    wire uart_send = state != WAIT_FRAME && !uart_busy;
    reg [7:0] uart_data;

    debug_uart_tx #(.CLOCK_HZ(CLOCK_HZ), .BAUD(BAUD)) sender (
        .clk(clk), .rst_n(rst_n), .send(uart_send),
        .data(uart_data), .tx(uart_tx), .busy(uart_busy)
    );

    always @* begin
        uart_data = 8'h20;
        case (state)
            STATUS: case (char_index)
                0: uart_data = "C";
                1: uart_data = "A";
                2: uart_data = "L";
                3: uart_data = "=";
                4: uart_data = calib_sync ? "1" : "0";
                5: uart_data = " ";
                6: uart_data = "C";
                7: uart_data = "O";
                8: uart_data = "U";
                9: uart_data = "N";
                10: uart_data = "T";
                11: uart_data = "=";
                12: uart_data = hex_char({3'b0, captured[12]});
                13: uart_data = hex_char(captured[11:8]);
                14: uart_data = hex_char(captured[7:4]);
                15: uart_data = hex_char(captured[3:0]);
                16: uart_data = " ";
                17: uart_data = "P";
                18: uart_data = "L";
                19: uart_data = "L";
                20: uart_data = "=";
                21: uart_data = diag_sync[3] ? "1" : "0";
                22: uart_data = " ";
                23: uart_data = "R";
                24: uart_data = "S";
                25: uart_data = "T";
                26: uart_data = "N";
                27: uart_data = "=";
                28: uart_data = diag_sync[2] ? "1" : "0";
                29: uart_data = " ";
                30: uart_data = "S";
                31: uart_data = "T";
                32: uart_data = "O";
                33: uart_data = "P";
                34: uart_data = "=";
                35: uart_data = diag_sync[1] ? "1" : "0";
                36: uart_data = " ";
                37: uart_data = "D";
                38: uart_data = "R";
                39: uart_data = "S";
                40: uart_data = "T";
                41: uart_data = "=";
                42: uart_data = diag_sync[0] ? "1" : "0";
                43: uart_data = " ";
                44: uart_data = "D";
                45: uart_data = "B";
                46: uart_data = "G";
                47: uart_data = "1";
                48: uart_data = "=";
                49: uart_data = hex_char(dbg1_sync[7:4]);
                50: uart_data = hex_char(dbg1_sync[3:0]);
                51: uart_data = " ";
                52: uart_data = "D";
                53: uart_data = "B";
                54: uart_data = "G";
                55: uart_data = "2";
                56: uart_data = "=";
                57: uart_data = hex_char(dbg2_sync[15:12]);
                58: uart_data = hex_char(dbg2_sync[11:8]);
                59: uart_data = hex_char(dbg2_sync[7:4]);
                60: uart_data = hex_char(dbg2_sync[3:0]);
                61: uart_data = " ";
                62: uart_data = "D";
                63: uart_data = "B";
                64: uart_data = "G";
                65: uart_data = "3";
                66: uart_data = "=";
                67: uart_data = hex_char(dbg3_sync[11:8]);
                68: uart_data = hex_char(dbg3_sync[7:4]);
                69: uart_data = hex_char(dbg3_sync[3:0]);
                70: uart_data = " ";
                71: uart_data = "D";
                72: uart_data = "B";
                73: uart_data = "G";
                74: uart_data = "4";
                75: uart_data = "=";
                76: uart_data = hex_char(dbg4_sync[31:28]);
                77: uart_data = hex_char(dbg4_sync[27:24]);
                78: uart_data = hex_char(dbg4_sync[23:20]);
                79: uart_data = hex_char(dbg4_sync[19:16]);
                80: uart_data = hex_char(dbg4_sync[15:12]);
                81: uart_data = hex_char(dbg4_sync[11:8]);
                82: uart_data = hex_char(dbg4_sync[7:4]);
                83: uart_data = hex_char(dbg4_sync[3:0]);
                84: uart_data = " ";
                85: uart_data = "S";
                86: uart_data = "L";
                87: uart_data = "O";
                88: uart_data = "W";
                89: uart_data = "=";
                90: uart_data = stop_low_seen ? "1" : "0";
                91: uart_data = " ";
                92: uart_data = "S";
                93: uart_data = "E";
                94: uart_data = "=";
                95: uart_data = hex_char(stop_edges[7:4]);
                96: uart_data = hex_char(stop_edges[3:0]);
                97: uart_data = " ";
                98: uart_data = "P";
                99: uart_data = "D";
                100: uart_data = "=";
                101: uart_data = hex_char(pll_drop_count[7:4]);
                102: uart_data = hex_char(pll_drop_count[3:0]);
                103: uart_data = " ";
                104: uart_data = "R";
                105: uart_data = "E";
                106: uart_data = "=";
                107: uart_data = hex_char(drst_edges[7:4]);
                108: uart_data = hex_char(drst_edges[3:0]);
                109: uart_data = " ";
                110: uart_data = "U";
                111: uart_data = "F";
                112: uart_data = "=";
                113: uart_data = hex_char(underflow_sync[15:12]);
                114: uart_data = hex_char(underflow_sync[11:8]);
                115: uart_data = hex_char(underflow_sync[7:4]);
                116: uart_data = hex_char(underflow_sync[3:0]);
                117: uart_data = " ";
                118: uart_data = "O";
                119: uart_data = "F";
                120: uart_data = "=";
                121: uart_data = hex_char(overflow_sync[15:12]);
                122: uart_data = hex_char(overflow_sync[11:8]);
                123: uart_data = hex_char(overflow_sync[7:4]);
                124: uart_data = hex_char(overflow_sync[3:0]);
                125: uart_data = 8'h0d;
                126: uart_data = 8'h0a;
                default: uart_data = 8'h20;
            endcase
            BUS_DIAG: begin
                case (char_index)
                    0: uart_data = "B"; 1: uart_data = "U"; 2: uart_data = "S";
                    4: uart_data = "W"; 5: uart_data = "Q"; 6: uart_data = "=";
                    16: uart_data = "W"; 17: uart_data = "A"; 18: uart_data = "=";
                    28: uart_data = "R"; 29: uart_data = "Q"; 30: uart_data = "=";
                    40: uart_data = "R"; 41: uart_data = "A"; 42: uart_data = "=";
                    52: uart_data = "W"; 53: uart_data = "D"; 54: uart_data = "=";
                    64: uart_data = "R"; 65: uart_data = "D"; 66: uart_data = "=";
                    75: uart_data = 8'h0d;
                    76: uart_data = 8'h0a;
                    default: begin
                        if (char_index >= 7 && char_index <= 14)
                            uart_data = hex32_char(wcq_sync, char_index - 7);
                        else if (char_index >= 19 && char_index <= 26)
                            uart_data = hex32_char(wca_sync, char_index - 19);
                        else if (char_index >= 31 && char_index <= 38)
                            uart_data = hex32_char(rcq_sync, char_index - 31);
                        else if (char_index >= 43 && char_index <= 50)
                            uart_data = hex32_char(rca_sync, char_index - 43);
                        else if (char_index >= 55 && char_index <= 62)
                            uart_data = hex32_char(wda_sync, char_index - 55);
                        else if (char_index >= 67 && char_index <= 74)
                            uart_data = hex32_char(rdd_sync, char_index - 67);
                    end
                endcase
            end
            HEADER: case (char_index)
                0: uart_data = "F";
                1: uart_data = "R";
                2: uart_data = "A";
                3: uart_data = "M";
                4: uart_data = "E";
                5: uart_data = " ";
                6: uart_data = "6";
                7: uart_data = "4";
                8: uart_data = " ";
                9: uart_data = "6";
                10: uart_data = "4";
                11: uart_data = " ";
                12: uart_data = "R";
                13: uart_data = "G";
                14: uart_data = "B";
                15: uart_data = "5";
                16: uart_data = "6";
                17: uart_data = "5";
                18: uart_data = 8'h0d;
                19: uart_data = 8'h0a;
                default: uart_data = 8'h20;
            endcase
            PIXELS: case (nibble_index)
                0: uart_data = hex_char(read_pixel[15:12]);
                1: uart_data = hex_char(read_pixel[11:8]);
                2: uart_data = hex_char(read_pixel[7:4]);
                3: uart_data = hex_char(read_pixel[3:0]);
            endcase
            ROW_CR: uart_data = 8'h0d;
            ROW_LF: uart_data = 8'h0a;
            TRAILER: case (char_index)
                0: uart_data = "E";
                1: uart_data = "N";
                2: uart_data = "D";
                3: uart_data = " ";
                4: uart_data = hex_char(checksum[15:12]);
                5: uart_data = hex_char(checksum[11:8]);
                6: uart_data = hex_char(checksum[7:4]);
                7: uart_data = hex_char(checksum[3:0]);
                8: uart_data = 8'h0d;
                9: uart_data = 8'h0a;
                default: uart_data = 8'h20;
            endcase
            default: uart_data = 8'h20;
        endcase
    end

    // One clock domain for capture, BRAM readout and UART. Stop writing
    // before streaming so a slow serial transfer cannot tear the frame.
    always @(posedge clk) begin
        read_pixel <= crop[pixel_index];
        if (capturing && calib_sync && crop_valid) crop[crop_addr] <= pixel_data;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= WAIT_FRAME;
            capturing <= 0;
            complete <= 0;
            captured <= 0;
            checksum <= 0;
            pixel_index <= 0;
            nibble_index <= 0;
            char_index <= 0;
            second_counter <= 0;
            vs_prev <= 0;
            calib_meta <= 0;
            calib_sync <= 0;
            diag_meta <= 0;
            diag_sync <= 0;
            dbg1_meta <= 0;
            dbg1_sync <= 0;
            dbg2_meta <= 0;
            dbg2_sync <= 0;
            dbg3_meta <= 0;
            dbg3_sync <= 0;
            dbg4_meta <= 0;
            dbg4_sync <= 0;
            overflow_meta <= 0;
            overflow_sync <= 0;
            underflow_meta <= 0;
            underflow_sync <= 0;
            wcq_meta <= 0; wcq_sync <= 0; wca_meta <= 0; wca_sync <= 0;
            rcq_meta <= 0; rcq_sync <= 0; rca_meta <= 0; rca_sync <= 0;
            wda_meta <= 0; wda_sync <= 0; rdd_meta <= 0; rdd_sync <= 0;
            stop_prev <= 0;
            stop_low_seen <= 0;
            stop_edges <= 0;
            pll_prev <= 0;
            pll_drop_count <= 0;
            drst_prev <= 0;
            drst_edges <= 0;
        end else begin
            calib_meta <= calib_done;
            calib_sync <= calib_meta;
            diag_meta <= {pll_lock, ddr_reset_n, pll_stop, ddr_rst};
            diag_sync <= diag_meta;
            dbg1_meta <= dbg_vector1;
            dbg1_sync <= dbg1_meta;
            dbg2_meta <= dbg_vector2;
            dbg2_sync <= dbg2_meta;
            dbg3_meta <= dbg_vector3;
            dbg3_sync <= dbg3_meta;
            dbg4_meta <= dbg_vector4;
            dbg4_sync <= dbg4_meta;
            overflow_meta <= vfb_overflow_count;
            overflow_sync <= overflow_meta;
            underflow_meta <= vfb_underflow_count;
            underflow_sync <= underflow_meta;
            wcq_meta <= write_cmd_req_count; wcq_sync <= wcq_meta;
            wca_meta <= write_cmd_accept_count; wca_sync <= wca_meta;
            rcq_meta <= read_cmd_req_count; rcq_sync <= rcq_meta;
            rca_meta <= read_cmd_accept_count; rca_sync <= rca_meta;
            wda_meta <= write_data_accept_count; wda_sync <= wda_meta;
            rdd_meta <= read_data_count; rdd_sync <= rdd_meta;
            stop_prev <= diag_sync[1];
            pll_prev <= diag_sync[3];
            drst_prev <= diag_sync[0];
            if (!diag_sync[1]) stop_low_seen <= 1'b1;
            if (diag_sync[1] != stop_prev && stop_edges != 8'hff)
                stop_edges <= stop_edges + 1'b1;
            if (!diag_sync[3] && pll_prev && pll_drop_count != 8'hff)
                pll_drop_count <= pll_drop_count + 1'b1;
            if (diag_sync[0] != drst_prev && drst_edges != 8'hff)
                drst_edges <= drst_edges + 1'b1;
            vs_prev <= frame_vs;
            second_counter <= second_tick ? 0 : second_counter + 1'b1;

            if (capturing && calib_sync && crop_valid && captured < 13'd4096) begin
                captured <= captured + 1'b1;
                checksum <= checksum + pixel_data;
            end

            if (state == WAIT_FRAME) begin
                if (vs_rise && capturing) begin
                    capturing <= 0;
                    complete <= calib_sync && (captured == 13'd4096);
                    char_index <= 0;
                    state <= STATUS;
                end else if (vs_rise && calib_sync && !capturing) begin
                    capturing <= 1;
                    captured <= 0;
                    checksum <= 0;
                end else if (second_tick && !calib_sync && !capturing) begin
                    complete <= 0;
                    captured <= 0;
                    char_index <= 0;
                    state <= STATUS;
                end
            end else if (uart_send) begin
                case (state)
                    STATUS: if (char_index == 126) begin
                        char_index <= 0;
                        state <= BUS_DIAG;
                    end else char_index <= char_index + 1'b1;
                    BUS_DIAG: if (char_index == 76) begin
                        char_index <= 0;
                        if (complete) state <= HEADER;
                        else state <= WAIT_FRAME;
                    end else char_index <= char_index + 1'b1;
                    HEADER: if (char_index == 19) begin
                        char_index <= 0;
                        pixel_index <= 0;
                        nibble_index <= 0;
                        state <= PIXELS;
                    end else char_index <= char_index + 1'b1;
                    PIXELS: if (nibble_index == 3) begin
                        nibble_index <= 0;
                        if (pixel_index == 4095) state <= ROW_CR;
                        else begin
                            pixel_index <= pixel_index + 1'b1;
                            if (pixel_index[5:0] == 63) state <= ROW_CR;
                        end
                    end else nibble_index <= nibble_index + 1'b1;
                    ROW_CR: state <= ROW_LF;
                    ROW_LF: if (pixel_index == 4095) begin
                        state <= TRAILER;
                        char_index <= 0;
                    end else state <= PIXELS;
                    TRAILER: if (char_index == 9) begin
                        state <= WAIT_FRAME;
                        complete <= 0;
                    end else char_index <= char_index + 1'b1;
                    default: state <= WAIT_FRAME;
                endcase
            end
        end
    end
endmodule
