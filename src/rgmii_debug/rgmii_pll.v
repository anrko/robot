// 50 MHz to the 125 MHz GMII/RGMII clock required by 1000BASE-X/GMII.
// This is intentionally independent of the DDR PLL.
module rgmii_pll(input clkin, input reset, output clkout, output lock);
wire clkout1, clkout2, clkout3, clkout4, clkout5, clkout6, clkfbout;
wire gnd = 1'b0;
PLLA pll_i (
    .LOCK(lock), .CLKOUT0(clkout), .CLKOUT1(clkout1), .CLKOUT2(clkout2),
    .CLKOUT3(clkout3), .CLKOUT4(clkout4), .CLKOUT5(clkout5), .CLKOUT6(clkout6),
    .CLKFBOUT(clkfbout), .MDRDO(), .CLKIN(clkin), .CLKFB(gnd), .RESET(reset),
    .PLLPWD(gnd), .RESET_I(gnd), .RESET_O(gnd), .PSSEL(3'b000), .PSDIR(gnd),
    .PSPULSE(gnd), .SSCPOL(gnd), .SSCON(gnd), .SSCMDSEL(7'b0),
    .SSCMDSEL_FRAC(3'b0), .MDCLK(clkin), .MDOPC(2'b0), .MDAINC(gnd),
    .MDWDI(8'b0)
);
defparam pll_i.FCLKIN = "50";
defparam pll_i.IDIV_SEL = 1;
defparam pll_i.FBDIV_SEL = 1;
defparam pll_i.MDIV_SEL = 20;
defparam pll_i.ODIV0_SEL = 8;
defparam pll_i.ODIV1_SEL = 8;
defparam pll_i.ODIV2_SEL = 8;
defparam pll_i.ODIV3_SEL = 8;
defparam pll_i.ODIV4_SEL = 8;
defparam pll_i.ODIV5_SEL = 8;
defparam pll_i.ODIV6_SEL = 8;
defparam pll_i.CLKOUT0_EN = "TRUE";
defparam pll_i.CLKOUT1_EN = "FALSE";
defparam pll_i.CLKOUT2_EN = "FALSE";
defparam pll_i.CLKOUT3_EN = "FALSE";
defparam pll_i.CLKOUT4_EN = "FALSE";
defparam pll_i.CLKOUT5_EN = "FALSE";
defparam pll_i.CLKOUT6_EN = "FALSE";
defparam pll_i.CLKFB_SEL = "INTERNAL";
endmodule
