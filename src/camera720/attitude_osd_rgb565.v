// Small, vendor-independent RGB565 text overlay for the OV5640 stream.
// Angle digits are packed BCD: {hundreds, tens, ones, tenths}.
module attitude_osd_rgb565 #(
    parameter [11:0] PANEL_X = 12'd24,
    parameter [11:0] PANEL_Y = 12'd24
)(
    input  wire [11:0] pixel_x,
    input  wire [11:0] pixel_y,
    input  wire [15:0] pixel_in,
    input  wire [15:0] roll_bcd,
    input  wire        roll_negative,
    input  wire [15:0] pitch_bcd,
    input  wire        pitch_negative,
    input  wire [15:0] yaw_bcd,
    input  wire        yaw_negative,
    output reg  [15:0] pixel_out
);

    localparam [11:0] PANEL_WIDTH  = 12'd256;
    localparam [11:0] PANEL_HEIGHT = 12'd104;
    localparam [15:0] PANEL_TINT   = 16'h0841;
    localparam [15:0] PANEL_EDGE   = 16'h4D9F;
    localparam [15:0] LABEL_COLOR  = 16'h5EFF;
    localparam [15:0] TEXT_COLOR   = 16'hFFDF;
    localparam [15:0] ACCENT_COLOR = 16'hFDC0;

    wire panel_active = (pixel_x >= PANEL_X) &&
                        (pixel_x < PANEL_X + PANEL_WIDTH) &&
                        (pixel_y >= PANEL_Y) &&
                        (pixel_y < PANEL_Y + PANEL_HEIGHT);
    wire [11:0] panel_x = pixel_x - PANEL_X;
    wire [11:0] panel_y = pixel_y - PANEL_Y;
    wire [11:0] text_x = panel_x - 12'd8;

    reg [7:0] ascii_char;
    reg [4:0] glyph_bits;
    reg [3:0] char_index;
    reg [2:0] glyph_row_index;
    reg [2:0] glyph_column_index;
    reg [2:0] line_index;
    reg       text_row_active;
    reg       glyph_pixel;
    reg [11:0] line_y_offset;
    reg [15:0] glyph_color;
    reg [15:0] blended_background;
    reg        panel_detail;

    function [7:0] digit_ascii;
        input [3:0] digit;
        begin
            if (digit <= 4'd9)
                digit_ascii = 8'h30 + digit;
            else
                digit_ascii = 8'h20;
        end
    endfunction

    function [4:0] glyph_row;
        input [7:0] ch;
        input [2:0] row;
        reg [34:0] bitmap;
        begin
            case (ch)
                8'h30: bitmap = {5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110}; // 0
                8'h31: bitmap = {5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110}; // 1
                8'h32: bitmap = {5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111}; // 2
                8'h33: bitmap = {5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110}; // 3
                8'h34: bitmap = {5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010}; // 4
                8'h35: bitmap = {5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110}; // 5
                8'h36: bitmap = {5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110}; // 6
                8'h37: bitmap = {5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000}; // 7
                8'h38: bitmap = {5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110}; // 8
                8'h39: bitmap = {5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110}; // 9
                8'h41: bitmap = {5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001}; // A
                8'h43: bitmap = {5'b01110,5'b10001,5'b10000,5'b10000,5'b10000,5'b10001,5'b01110}; // C
                8'h48: bitmap = {5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001}; // H
                8'h49: bitmap = {5'b01110,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110}; // I
                8'h4D: bitmap = {5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001}; // M
                8'h4C: bitmap = {5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111}; // L
                8'h4F: bitmap = {5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110}; // O
                8'h50: bitmap = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000}; // P
                8'h52: bitmap = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001}; // R
                8'h54: bitmap = {5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100}; // T
                8'h55: bitmap = {5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110}; // U
                8'h57: bitmap = {5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b10101,5'b01010}; // W
                8'h59: bitmap = {5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100}; // Y
                8'h44: bitmap = {5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110}; // D
                8'h45: bitmap = {5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111}; // E
                8'h2F: bitmap = {5'b00001,5'b00010,5'b00100,5'b01000,5'b10000,5'b00000,5'b00000}; // /
                8'h3A: bitmap = {5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000}; // :
                8'h2B: bitmap = {5'b00000,5'b00100,5'b00100,5'b11111,5'b00100,5'b00100,5'b00000}; // +
                8'h2D: bitmap = {5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000}; // -
                8'h2E: bitmap = {5'b00000,5'b00000,5'b00000,5'b00000,5'b00000,5'b00110,5'b00110}; // .
                8'hB0: bitmap = {5'b00110,5'b01001,5'b01001,5'b00110,5'b00000,5'b00000,5'b00000}; // degree
                default: bitmap = 35'd0;
            endcase
            glyph_row = bitmap[34 - row * 5 -: 5];
        end
    endfunction

    always @* begin
        ascii_char = 8'h20;
        char_index = text_x[7:4];
        line_index = 3'd0;
        glyph_row_index = 3'd0;
        glyph_column_index = text_x[3:1];
        text_row_active = 1'b0;
        line_y_offset = 12'd0;
        glyph_color = TEXT_COLOR;
        panel_detail = 1'b0;

        // A dark translucent tint preserves the image beneath the telemetry.
        blended_background = {
            ((pixel_in[15:11] >> 1) + (PANEL_TINT[15:11] >> 1)),
            ((pixel_in[10:5]  >> 1) + (PANEL_TINT[10:5]  >> 1)),
            ((pixel_in[4:0]   >> 1) + (PANEL_TINT[4:0]   >> 1))
        };

        if ((panel_y >= 12'd8) && (panel_y < 12'd22)) begin
            line_index = 3'd0;
            line_y_offset = panel_y - 12'd8;
            text_row_active = 1'b1;
        end else if ((panel_y >= 12'd31) && (panel_y < 12'd45)) begin
            line_index = 3'd1;
            line_y_offset = panel_y - 12'd31;
            text_row_active = 1'b1;
        end else if ((panel_y >= 12'd54) && (panel_y < 12'd68)) begin
            line_index = 3'd2;
            line_y_offset = panel_y - 12'd54;
            text_row_active = 1'b1;
        end else if ((panel_y >= 12'd77) && (panel_y < 12'd91)) begin
            line_index = 3'd3;
            line_y_offset = panel_y - 12'd77;
            text_row_active = 1'b1;
        end
        glyph_row_index = line_y_offset[3:1];

        case (line_index)
            3'd0: begin
                case (char_index)
                    4'd0: ascii_char = 8'h49; // IMU / ATTITUDE
                    4'd1: ascii_char = 8'h4D;
                    4'd2: ascii_char = 8'h55;
                    4'd4: ascii_char = 8'h2F;
                    4'd6: ascii_char = 8'h41;
                    4'd7: ascii_char = 8'h54;
                    4'd8: ascii_char = 8'h54;
                    4'd9: ascii_char = 8'h49;
                    4'd10: ascii_char = 8'h54;
                    4'd11: ascii_char = 8'h55;
                    4'd12: ascii_char = 8'h44;
                    4'd13: ascii_char = 8'h45;
                    default: ascii_char = 8'h20;
                endcase
                glyph_color = LABEL_COLOR;
            end
            3'd1: begin
                case (char_index)
                    4'd0: ascii_char = 8'h52; // ROLL
                    4'd1: ascii_char = 8'h4F;
                    4'd2,4'd3: ascii_char = 8'h4C;
                    4'd5: ascii_char = 8'h3A;
                    4'd7: ascii_char = roll_negative ? 8'h2D : 8'h2B;
                    4'd8: ascii_char = digit_ascii(roll_bcd[15:12]);
                    4'd9: ascii_char = digit_ascii(roll_bcd[11:8]);
                    4'd10: ascii_char = digit_ascii(roll_bcd[7:4]);
                    4'd11: ascii_char = 8'h2E;
                    4'd12: ascii_char = digit_ascii(roll_bcd[3:0]);
                    4'd13: ascii_char = 8'hB0;
                    default: ascii_char = 8'h20;
                endcase
                if (char_index < 4'd6) glyph_color = LABEL_COLOR;
                else if (char_index == 4'd13) glyph_color = ACCENT_COLOR;
            end
            3'd2: begin
                case (char_index)
                    4'd0: ascii_char = 8'h50; // PITCH
                    4'd1: ascii_char = 8'h49;
                    4'd2: ascii_char = 8'h54;
                    4'd3: ascii_char = 8'h43;
                    4'd4: ascii_char = 8'h48;
                    4'd5: ascii_char = 8'h3A;
                    4'd7: ascii_char = pitch_negative ? 8'h2D : 8'h2B;
                    4'd8: ascii_char = digit_ascii(pitch_bcd[15:12]);
                    4'd9: ascii_char = digit_ascii(pitch_bcd[11:8]);
                    4'd10: ascii_char = digit_ascii(pitch_bcd[7:4]);
                    4'd11: ascii_char = 8'h2E;
                    4'd12: ascii_char = digit_ascii(pitch_bcd[3:0]);
                    4'd13: ascii_char = 8'hB0;
                    default: ascii_char = 8'h20;
                endcase
                if (char_index < 4'd6) glyph_color = LABEL_COLOR;
                else if (char_index == 4'd13) glyph_color = ACCENT_COLOR;
            end
            3'd3: begin
                case (char_index)
                    4'd0: ascii_char = 8'h59; // YAW
                    4'd1: ascii_char = 8'h41;
                    4'd2: ascii_char = 8'h57;
                    4'd5: ascii_char = 8'h3A;
                    4'd7: ascii_char = yaw_negative ? 8'h2D : 8'h2B;
                    4'd8: ascii_char = digit_ascii(yaw_bcd[15:12]);
                    4'd9: ascii_char = digit_ascii(yaw_bcd[11:8]);
                    4'd10: ascii_char = digit_ascii(yaw_bcd[7:4]);
                    4'd11: ascii_char = 8'h2E;
                    4'd12: ascii_char = digit_ascii(yaw_bcd[3:0]);
                    4'd13: ascii_char = 8'hB0;
                    default: ascii_char = 8'h20;
                endcase
                if (char_index < 4'd6) glyph_color = LABEL_COLOR;
                else if (char_index == 4'd13) glyph_color = ACCENT_COLOR;
            end
            default: ascii_char = 8'h20;
        endcase

        glyph_bits = glyph_row(ascii_char, glyph_row_index);
        glyph_pixel = 1'b0;
        if (text_row_active && (text_x < 12'd240) &&
            (glyph_column_index >= 3'd1) && (glyph_column_index <= 3'd5))
            glyph_pixel = glyph_bits[5 - glyph_column_index];

        panel_detail = (panel_x == 12'd0) || (panel_x == 12'd1) ||
                       (panel_y == 12'd0) || (panel_y == 12'd1) ||
                       ((panel_y >= 12'd25) && (panel_y <= 12'd26)) ||
                       ((panel_y >= 12'd48) && (panel_y <= 12'd49)) ||
                       ((panel_y >= 12'd71) && (panel_y <= 12'd72));
        if (panel_active && glyph_pixel)
            pixel_out = glyph_color;
        else if (panel_active && (panel_x < 12'd3))
            pixel_out = LABEL_COLOR;
        else if (panel_active && panel_detail)
            pixel_out = PANEL_EDGE;
        else if (panel_active)
            pixel_out = blended_background;
        else
            pixel_out = pixel_in;
    end
endmodule
