open_project can_motor.gprj
set_option -enable_dsrm 1
set_option -use_cpu_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -synthesis_tool gowinsynthesis
set_option -top_module top_can_motor
set_option -output_base_name can_motor
run all
