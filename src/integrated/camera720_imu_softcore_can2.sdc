create_clock -name clk50m -period 20.000 [get_ports {clk50m}]
create_clock -name cam_pclk -period 23.810 [get_ports {cam_pclk}]
set_false_path -to [get_pins {*udp_reset_sync_?_s*/PRESET}] -setup
set_false_path -to [get_pins {*eth_tx_fifo/fifo_inst/reset_r_?_s*/PRESET}] -setup
