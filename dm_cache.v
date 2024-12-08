`include "dm_cache.h"

module dm_cache (
i_cpu_valid,
i_cpu_rd_wr,
i_cpu_address,
o_cpu_ready,
i_cpu_write_data,
i_cpu_write_strobe,
o_cpu_read_data,
o_cpu_read_valid,
i_cpu_read_ready,


o_mem_valid,
o_mem_rd_wr,
o_mem_address,
i_mem_ready,
o_mem_write_data,
o_mem_write_strobe,
i_mem_read_data,
i_mem_read_valid,
o_mem_read_ready
);



input i_cpu_valid;
input i_cpu_rd_wr;
input [`ADDRESS_WIDTH-1:0] i_cpu_address;


output o_cpu_ready;
input [`WRITE_DATA-1:0] i_cpu_write_data;
input [`WRITE_STROBE-1:0] i_cpu_write_strobe;
ouput [`WRITE_DATA-1:0] o_cpu_read_data;
ouput o_cpu_read_valid;
input i_cpu_read_ready;

ouput o_mem_valid;
ouput o_mem_rd_wr;
ouput [`ADDRESS_WIDTH-1:0] o_mem_address;
input i_mem_ready;
ouput [`WRITE_DATA-1:0] o_mem_write_data;
ouput [`WRITE_STROBE-1:0] o_mem_write_strobe;
input [`WRITE_DATA-1:0] i_mem_read_data;
input i_mem_read_valid;
ouput o_mem_read_ready;


