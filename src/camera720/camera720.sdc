# The OV5640 RAW 720p init table runs the DVP pixel clock at approximately 42 MHz.
# Match the official 1080p reference project's practice: define the sensor PCLK
# as a timing clock so Gowin P&R builds its clock network for capture registers.
create_clock -name clk50m -period 20.000 [get_ports {clk50m}]
create_clock -name cam_pclk -period 23.810 [get_ports {cam_pclk}]

# Async assertion into reset-release synchronisers has no clock phase relation.
# Scope these exceptions to the synchronisers' asynchronous PRESET inputs only.
# The synchroniser Q -> UDP/state-register reset paths are still timed.
# Gowin SUG940 5.4.1: -setup also applies to recovery checks.
set_false_path -to [get_pins {*udp_reset_sync_?_s*/PRESET}] -setup
# The vendor dual-clock FIFO contains its own read-domain reset synchronisers.
set_false_path -to [get_pins {*eth_tx_fifo/fifo_inst/reset_r_?_s*/PRESET}] -setup
