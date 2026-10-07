open_project camera720_imu_demo.gprj
set_option -enable_dsrm 1
set_option -use_cpu_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -synthesis_tool gowinsynthesis
set_option -top_module top_camera720_imu_demo
set_option -output_base_name camera720_imu_demo
run all
