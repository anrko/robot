open_project camera720.gprj
set_option -enable_dsrm 1
set_option -use_cpu_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -synthesis_tool gowinsynthesis
set_option -top_module top_camera720
set_option -output_base_name camera720
run all
