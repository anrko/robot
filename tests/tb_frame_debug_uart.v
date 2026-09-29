`timescale 1ns/1ps
module tb_frame_debug_uart;
    reg clk = 0, rst_n = 0, calib = 0, vs = 0, valid = 0;
    reg pll_lock = 1, ddr_reset_n = 1, pll_stop = 0, ddr_rst = 0;
    reg [7:0] dbg1 = 8'hAB;
    reg [15:0] dbg2 = 16'h1BCD;
    reg [11:0] dbg3 = 12'hABC;
    reg [31:0] dbg4 = 32'h12345678;
    reg [9:0] x = 0, y = 0;
    reg [15:0] pixel = 0;
    wire tx;
    always #5 clk = ~clk;

    frame_debug_uart #(.CLOCK_HZ(1000), .BAUD(100)) dut (
        .clk(clk), .rst_n(rst_n), .calib_done(calib), .frame_vs(vs),
        .pll_lock(pll_lock), .ddr_reset_n(ddr_reset_n),
        .pll_stop(pll_stop), .ddr_rst(ddr_rst),
        .dbg_vector1(dbg1), .dbg_vector2(dbg2),
        .dbg_vector3(dbg3), .dbg_vector4(dbg4),
        .pixel_valid(valid), .pixel_x(x), .pixel_y(y),
        .pixel_data(pixel), .uart_tx(tx)
    );

    reg [7:0] received [0:17000];
    integer length = 0, bitnum, i, row, col, sum = 0;
    reg [7:0] byte_value;
    always begin
        @(negedge tx);
        #150;
        byte_value = 0;
        for (bitnum = 0; bitnum < 8; bitnum = bitnum + 1) begin
            byte_value[bitnum] = tx;
            #100;
        end
        if (tx !== 1'b1) $fatal(1, "invalid stop bit");
        if (length > 17000) $fatal(1, "too many bytes");
        received[length] = byte_value;
        length = length + 1;
    end

    task pulse_vs;
    begin
        @(negedge clk); vs = 1;
        @(negedge clk); vs = 0;
    end
    endtask

    initial begin
        #30; rst_n = 1; calib = 1;
        repeat (4) @(negedge clk);
        pulse_vs();
        for (row = 328; row < 392; row = row + 1)
            for (col = 608; col < 672; col = col + 1) begin
                @(negedge clk);
                valid = 1; x = col; y = row;
                pixel = col < 640 ? 16'h07E0 : 16'hF800;
                sum = (sum + pixel) & 16'hFFFF;
            end
        @(negedge clk); valid = 0;
        pulse_vs();
        wait (dut.state == dut.WAIT_FRAME && dut.complete == 0);
        wait (dut.uart_busy == 0);
        repeat (20) @(negedge clk);
        if (length != 16628) $fatal(1, "byte count %0d", length);
        if (received[0] != "C" || received[4] != "1" ||
            received[12] != "1" || received[13] != "0" ||
            received[14] != "0" || received[15] != "0")
            $fatal(1, "status or captured count wrong");
        if (received[21] != "1" || received[28] != "1" ||
            received[35] != "0" || received[42] != "0")
            $fatal(1, "PLL/DDR diagnostic status wrong");
        if (received[49] != "A" || received[50] != "B" ||
            received[57] != "1" || received[60] != "D" ||
            received[67] != "A" || received[68] != "B" ||
            received[76] != "1" || received[83] != "8")
            $fatal(1, "DDR PHY debug vectors wrong");
        if (received[86] != "F" || received[106] != "0" ||
            received[107] != "7" || received[108] != "E" || received[109] != "0" ||
            received[234] != "F" || received[235] != "8")
            $fatal(1, "header / first row data wrong");
        if (received[length-10] != "E" || received[length-9] != "N")
            $fatal(1, "missing trailer");
        $display("PASS: 4096 RGB565 pixels, %0d UART bytes, checksum %04X", length, sum);
        $finish;
    end
    initial begin #50000000; $fatal(1, "test timeout"); end
endmodule
