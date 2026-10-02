# The OV5640 RAW 720p init table runs the DVP pixel clock at approximately 42 MHz.
# Match the official 1080p reference project's practice: define the sensor PCLK
# as a timing clock so Gowin P&R builds its clock network for capture registers.
create_clock -name clk50m -period 20.000 [get_ports {clk50m}]
create_clock -name cam_pclk -period 23.810 [get_ports {cam_pclk}]
