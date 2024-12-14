/*
MIT License

Copyright (c) 2024 Elsie Rezinold Y

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/
module tw_associative #(
    parameter ADDRESS_WIDTH =64,
    parameter WRITE_DATA=64,
    parameter BLOCK_SIZE_BYTE=64,
    parameter BLOCK_SIZE_BITS=6,
    parameter BLOCK_NUMBER_BITS=10,
    parameter SET_BITS = 1,
    parameter BLOCK_NUMBER = 512,
    parameter CACHE_SIZE=64*1024
)(
clk,
rst_n,
i_cpu_valid,
i_cpu_rd_wr,
i_cpu_address,
i_cpu_wr_data,
o_cpu_rd_data,
o_cpu_busy,

o_mem_rd_en,
o_mem_rd_address,
o_mem_wr_en,
o_mem_wr_address,
o_mem_wr_data,
i_mem_rd_data,
i_mem_rd_valid
);

input clk;
input rst_n;
localparam TAG_WIDTH = ADDRESS_WIDTH-(BLOCK_NUMBER_BITS - SET_BITS)-BLOCK_SIZE_BITS;
localparam BLOCK_ADDRESS_HIGH = ADDRESS_WIDTH-TAG_WIDTH-1;
localparam BLOCK_ADDRESS_LOW = BLOCK_SIZE_BITS; 
localparam TAG_HIGH = ADDRESS_WIDTH-1;
localparam TAG_LOW = BLOCK_ADDRESS_HIGH +1; 
input i_cpu_valid;
input i_cpu_rd_wr;
input [ADDRESS_WIDTH-1:0] i_cpu_address;

input [WRITE_DATA*8-1:0] i_cpu_wr_data;
output reg [WRITE_DATA*8-1:0] o_cpu_rd_data;
output reg o_cpu_busy;
output o_mem_rd_en;
output [ADDRESS_WIDTH-1:0] o_mem_rd_address;
output reg o_mem_wr_en;
output reg [ADDRESS_WIDTH-1:0] o_mem_wr_address;
output reg [WRITE_DATA*8-1:0] o_mem_wr_data;
input [WRITE_DATA*8-1:0] i_mem_rd_data;
input i_mem_rd_valid;

reg [BLOCK_SIZE_BYTE*8-1:0] cache_block_1 [0:BLOCK_NUMBER-1];
reg valid_bit_1 [0:BLOCK_NUMBER-1];
reg dirty_bit_1 [0:BLOCK_NUMBER-1];
reg [TAG_WIDTH-1:0] tag_address_1[0:BLOCK_NUMBER-1];
reg lru_counter_1 [0:BLOCK_NUMBER-1];
localparam CACHE_ACCESS=0,MISS=1;
reg [BLOCK_SIZE_BYTE*8-1:0] cache_block_2 [0:BLOCK_NUMBER-1];
reg valid_bit_2 [0:BLOCK_NUMBER-1];
reg dirty_bit_2 [0:BLOCK_NUMBER-1];
reg [TAG_WIDTH-1:0] tag_address_2[0:BLOCK_NUMBER-1];
reg lru_counter_2 [0:BLOCK_NUMBER-1];

reg cs,ns;
wire miss;
reg handled; 

assign miss = i_cpu_valid && !i_cpu_rd_wr && ((i_cpu_address[TAG_HIGH:TAG_LOW]!=tag_address_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) || !valid_bit_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]])
                                          && ((i_cpu_address[TAG_HIGH:TAG_LOW]!=tag_address_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) || !valid_bit_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]);

//assign hit  = i_cpu_valid&((i_cpu_address[TAG_HIGH:TAG_LOW]==tag_address[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]])&valid_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]); 

always@(posedge clk or negedge rst_n) begin
    if(!rst_n)
        cs <= 0;
    else    
        cs <= ns;
end



always @(*) begin
    ns = 0;
    case(cs)
    CACHE_ACCESS: begin 
        if(miss) begin
            ns = MISS;
        end
    end
    MISS: begin
        if(handled) begin
            ns = CACHE_ACCESS;
        end 
        else begin
            ns = MISS;
        end
    end
    endcase
end
assign o_mem_rd_en = miss;
assign o_mem_rd_address = i_cpu_address;
always@(posedge clk or negedge rst_n) begin
    if(rst_n) begin
        case(cs)
        CACHE_ACCESS: begin
            handled <=0;
            if(i_cpu_valid & !i_cpu_rd_wr) begin
                o_mem_wr_en <=0;
                if((i_cpu_address[TAG_HIGH:TAG_LOW]==tag_address_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) && valid_bit_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                    //rd hit 
                    //BLOCK 1
                    o_cpu_rd_data                                                       <= cache_block_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]];
                    o_cpu_busy                                                          <= 0;
                    lru_counter_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]  <= 0;
                    lru_counter_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]  <= 1;                
                end
                else if((i_cpu_address[TAG_HIGH:TAG_LOW]==tag_address_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) && valid_bit_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                    //rd hit 
                    //BLOCK 2
                    o_cpu_rd_data                                                       <= cache_block_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]];
                    o_cpu_busy                                                          <= 0;
                    lru_counter_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]  <= 1;
                    lru_counter_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]  <= 0;                
                end
                else begin
                    o_cpu_busy       <= 1;
                end
            end
            else if(i_cpu_valid & i_cpu_rd_wr) begin
                if((i_cpu_address[TAG_HIGH:TAG_LOW]==tag_address_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) && valid_bit_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                    //wr hit
                    //block 1
                    cache_block_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]  <= i_cpu_wr_data;
                    dirty_bit_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]    <= 1;
                    o_cpu_busy                                                          <= 0;
                    o_mem_wr_en                                                         <= 0;
                    lru_counter_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]  <= 0;
                    lru_counter_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]  <= 1;                
                end
                else if((i_cpu_address[TAG_HIGH:TAG_LOW]==tag_address_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) && valid_bit_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                    //wr hit
                    //block 2
                    cache_block_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]  <= i_cpu_wr_data;
                    dirty_bit_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]    <= 1;
                    o_cpu_busy                                                          <= 0;
                    o_mem_wr_en                                                         <= 0;
                    lru_counter_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]  <= 0;
                    lru_counter_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]  <= 1;                
                end
                else begin
                    //wr miss
                    //wr allocate
                    if(!valid_bit_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                        //block 1
                        cache_block_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_cpu_wr_data;
                        tag_address_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_cpu_address[TAG_HIGH:TAG_LOW];
                        dirty_bit_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]         <=   1;
                        valid_bit_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]         <=   1;
                        o_cpu_busy                                                             <=   0;
                        o_mem_wr_en                                                            <=   0;
                        lru_counter_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]  <= 1;
                        lru_counter_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]  <= 0;                
                    end
                    else if(!valid_bit_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                        cache_block_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_cpu_wr_data;
                        tag_address_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_cpu_address[TAG_HIGH:TAG_LOW];
                        dirty_bit_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]         <=   1;
                        valid_bit_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]         <=   1;
                        o_cpu_busy                                                             <=   0;
                        o_mem_wr_en                                                            <=   0;
                        lru_counter_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]  <= 0;
                        lru_counter_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]  <= 1;                
                    
                    end
                    else if(lru_counter_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                        if(dirty_bit_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                            o_mem_wr_data <= cache_block_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]];
                            o_mem_wr_address <= {tag_address_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]],i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW],6'd0};
                            o_mem_wr_en <= 1;
                        end
                        cache_block_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_cpu_wr_data;
                        tag_address_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_cpu_address[TAG_HIGH:TAG_LOW];
                        dirty_bit_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]         <=   1;
                        o_cpu_busy                                                             <=   0;
                        lru_counter_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]  <= 1;
                        lru_counter_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]  <= 0;                
                    
                    end
                    else if(lru_counter_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                        if(dirty_bit_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                            o_mem_wr_data <= cache_block_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]];
                            o_mem_wr_address <= {tag_address_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]],i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW],6'd0};
                            o_mem_wr_en <= 1;
                        end
                        cache_block_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_cpu_wr_data;
                        tag_address_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_cpu_address[TAG_HIGH:TAG_LOW];
                        dirty_bit_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]         <=   1;
                        o_cpu_busy                                                             <=   0;
                        lru_counter_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]  <= 0;
                        lru_counter_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]  <= 1;                
                    end
                end
            end
        end
        MISS: begin
            if(!valid_bit_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                if(i_mem_rd_valid) begin                
                    cache_block_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_mem_rd_data;
                    tag_address_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_cpu_address[TAG_HIGH:TAG_LOW];
                    dirty_bit_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]         <=   0;
                    valid_bit_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]         <=   1;
                    handled                                                                  <=   1;
                    lru_counter_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   1;
                    lru_counter_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   0;                
                
                end
            end
            else if(!valid_bit_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                if(i_mem_rd_valid) begin                
                    cache_block_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_mem_rd_data;
                    tag_address_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_cpu_address[TAG_HIGH:TAG_LOW];
                    dirty_bit_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]         <=   0;
                    valid_bit_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]         <=   1;
                    handled                                                                  <=   1;
                    lru_counter_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   0;
                    lru_counter_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   1;                
                
                end
            end
            else if(lru_counter_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                if(i_mem_rd_valid) begin                
                    if(dirty_bit_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                        o_mem_wr_data <= cache_block_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]];
                        o_mem_wr_address <= {tag_address_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]],i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW],6'd0};;
                        o_mem_wr_en <= 1;
                    end
                    cache_block_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_mem_rd_data;
                    tag_address_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_cpu_address[TAG_HIGH:TAG_LOW];
                    dirty_bit_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]         <=   0;
                    handled                                                                  <=   1;
                    lru_counter_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   1;
                    lru_counter_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   0;                
                
                end
            end
            else if(lru_counter_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                if(i_mem_rd_valid) begin                
                    if(dirty_bit_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                        o_mem_wr_data <= cache_block_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]];
                        o_mem_wr_address <= {tag_address_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]],i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW],6'd0};
                        o_mem_wr_en <= 1;
                    end
                    cache_block_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_mem_rd_data;
                    tag_address_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_cpu_address[TAG_HIGH:TAG_LOW];
                    dirty_bit_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]         <=   0;
                    handled                                                                  <=   1;
                    lru_counter_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   1;
                    lru_counter_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   0;                
                
                end
            end
        end
        endcase
    end
    else if(!rst_n) begin
        o_cpu_rd_data<=0;
        o_cpu_busy<=0;
        o_mem_wr_address<=0;
        o_mem_wr_en<=0;
        o_mem_wr_data<=0;
        valid_bit_1[0]  <=   0;dirty_bit_1[0] <= 0;tag_address_1[0] <= 0;cache_block_1[0] <= 0;lru_counter_1[0] <= 0;valid_bit_2[0]  <=   0;dirty_bit_2[0] <= 0;tag_address_2[0] <= 0;cache_block_2[0] <= 0;lru_counter_2[0] <= 0;
        valid_bit_1[1]  <=   0;dirty_bit_1[1] <= 0;tag_address_1[1] <= 0;cache_block_1[1] <= 0;lru_counter_1[1] <= 0;valid_bit_2[1]  <=   0;dirty_bit_2[1] <= 0;tag_address_2[1] <= 0;cache_block_2[1] <= 0;lru_counter_2[1] <= 0;
        valid_bit_1[2]  <=   0;dirty_bit_1[2] <= 0;tag_address_1[2] <= 0;cache_block_1[2] <= 0;lru_counter_1[2] <= 0;valid_bit_2[2]  <=   0;dirty_bit_2[2] <= 0;tag_address_2[2] <= 0;cache_block_2[2] <= 0;lru_counter_2[2] <= 0;
        valid_bit_1[3]  <=   0;dirty_bit_1[3] <= 0;tag_address_1[3] <= 0;cache_block_1[3] <= 0;lru_counter_1[3] <= 0;valid_bit_2[3]  <=   0;dirty_bit_2[3] <= 0;tag_address_2[3] <= 0;cache_block_2[3] <= 0;lru_counter_2[3] <= 0;
        valid_bit_1[4]  <=   0;dirty_bit_1[4] <= 0;tag_address_1[4] <= 0;cache_block_1[4] <= 0;lru_counter_1[4] <= 0;valid_bit_2[4]  <=   0;dirty_bit_2[4] <= 0;tag_address_2[4] <= 0;cache_block_2[4] <= 0;lru_counter_2[4] <= 0;
        valid_bit_1[5]  <=   0;dirty_bit_1[5] <= 0;tag_address_1[5] <= 0;cache_block_1[5] <= 0;lru_counter_1[5] <= 0;valid_bit_2[5]  <=   0;dirty_bit_2[5] <= 0;tag_address_2[5] <= 0;cache_block_2[5] <= 0;lru_counter_2[5] <= 0;
        valid_bit_1[6]  <=   0;dirty_bit_1[6] <= 0;tag_address_1[6] <= 0;cache_block_1[6] <= 0;lru_counter_1[6] <= 0;valid_bit_2[6]  <=   0;dirty_bit_2[6] <= 0;tag_address_2[6] <= 0;cache_block_2[6] <= 0;lru_counter_2[6] <= 0;
        valid_bit_1[7]  <=   0;dirty_bit_1[7] <= 0;tag_address_1[7] <= 0;cache_block_1[7] <= 0;lru_counter_1[7] <= 0;valid_bit_2[7]  <=   0;dirty_bit_2[7] <= 0;tag_address_2[7] <= 0;cache_block_2[7] <= 0;lru_counter_2[7] <= 0;
        valid_bit_1[8]  <=   0;dirty_bit_1[8] <= 0;tag_address_1[8] <= 0;cache_block_1[8] <= 0;lru_counter_1[8] <= 0;valid_bit_2[8]  <=   0;dirty_bit_2[8] <= 0;tag_address_2[8] <= 0;cache_block_2[8] <= 0;lru_counter_2[8] <= 0;
        valid_bit_1[9]  <=   0;dirty_bit_1[9] <= 0;tag_address_1[9] <= 0;cache_block_1[9] <= 0;lru_counter_1[9] <= 0;valid_bit_2[9]  <=   0;dirty_bit_2[9] <= 0;tag_address_2[9] <= 0;cache_block_2[9] <= 0;lru_counter_2[9] <= 0;
        valid_bit_1[10]  <=   0;dirty_bit_1[10] <= 0;tag_address_1[10] <= 0;cache_block_1[10] <= 0;lru_counter_1[10] <= 0;valid_bit_2[10]  <=   0;dirty_bit_2[10] <= 0;tag_address_2[10] <= 0;cache_block_2[10] <= 0;lru_counter_2[10] <= 0;
        valid_bit_1[11]  <=   0;dirty_bit_1[11] <= 0;tag_address_1[11] <= 0;cache_block_1[11] <= 0;lru_counter_1[11] <= 0;valid_bit_2[11]  <=   0;dirty_bit_2[11] <= 0;tag_address_2[11] <= 0;cache_block_2[11] <= 0;lru_counter_2[11] <= 0;
        valid_bit_1[12]  <=   0;dirty_bit_1[12] <= 0;tag_address_1[12] <= 0;cache_block_1[12] <= 0;lru_counter_1[12] <= 0;valid_bit_2[12]  <=   0;dirty_bit_2[12] <= 0;tag_address_2[12] <= 0;cache_block_2[12] <= 0;lru_counter_2[12] <= 0;
        valid_bit_1[13]  <=   0;dirty_bit_1[13] <= 0;tag_address_1[13] <= 0;cache_block_1[13] <= 0;lru_counter_1[13] <= 0;valid_bit_2[13]  <=   0;dirty_bit_2[13] <= 0;tag_address_2[13] <= 0;cache_block_2[13] <= 0;lru_counter_2[13] <= 0;
        valid_bit_1[14]  <=   0;dirty_bit_1[14] <= 0;tag_address_1[14] <= 0;cache_block_1[14] <= 0;lru_counter_1[14] <= 0;valid_bit_2[14]  <=   0;dirty_bit_2[14] <= 0;tag_address_2[14] <= 0;cache_block_2[14] <= 0;lru_counter_2[14] <= 0;
        valid_bit_1[15]  <=   0;dirty_bit_1[15] <= 0;tag_address_1[15] <= 0;cache_block_1[15] <= 0;lru_counter_1[15] <= 0;valid_bit_2[15]  <=   0;dirty_bit_2[15] <= 0;tag_address_2[15] <= 0;cache_block_2[15] <= 0;lru_counter_2[15] <= 0;
        valid_bit_1[16]  <=   0;dirty_bit_1[16] <= 0;tag_address_1[16] <= 0;cache_block_1[16] <= 0;lru_counter_1[16] <= 0;valid_bit_2[16]  <=   0;dirty_bit_2[16] <= 0;tag_address_2[16] <= 0;cache_block_2[16] <= 0;lru_counter_2[16] <= 0;
        valid_bit_1[17]  <=   0;dirty_bit_1[17] <= 0;tag_address_1[17] <= 0;cache_block_1[17] <= 0;lru_counter_1[17] <= 0;valid_bit_2[17]  <=   0;dirty_bit_2[17] <= 0;tag_address_2[17] <= 0;cache_block_2[17] <= 0;lru_counter_2[17] <= 0;
        valid_bit_1[18]  <=   0;dirty_bit_1[18] <= 0;tag_address_1[18] <= 0;cache_block_1[18] <= 0;lru_counter_1[18] <= 0;valid_bit_2[18]  <=   0;dirty_bit_2[18] <= 0;tag_address_2[18] <= 0;cache_block_2[18] <= 0;lru_counter_2[18] <= 0;
        valid_bit_1[19]  <=   0;dirty_bit_1[19] <= 0;tag_address_1[19] <= 0;cache_block_1[19] <= 0;lru_counter_1[19] <= 0;valid_bit_2[19]  <=   0;dirty_bit_2[19] <= 0;tag_address_2[19] <= 0;cache_block_2[19] <= 0;lru_counter_2[19] <= 0;
        valid_bit_1[20]  <=   0;dirty_bit_1[20] <= 0;tag_address_1[20] <= 0;cache_block_1[20] <= 0;lru_counter_1[20] <= 0;valid_bit_2[20]  <=   0;dirty_bit_2[20] <= 0;tag_address_2[20] <= 0;cache_block_2[20] <= 0;lru_counter_2[20] <= 0;
        valid_bit_1[21]  <=   0;dirty_bit_1[21] <= 0;tag_address_1[21] <= 0;cache_block_1[21] <= 0;lru_counter_1[21] <= 0;valid_bit_2[21]  <=   0;dirty_bit_2[21] <= 0;tag_address_2[21] <= 0;cache_block_2[21] <= 0;lru_counter_2[21] <= 0;
        valid_bit_1[22]  <=   0;dirty_bit_1[22] <= 0;tag_address_1[22] <= 0;cache_block_1[22] <= 0;lru_counter_1[22] <= 0;valid_bit_2[22]  <=   0;dirty_bit_2[22] <= 0;tag_address_2[22] <= 0;cache_block_2[22] <= 0;lru_counter_2[22] <= 0;
        valid_bit_1[23]  <=   0;dirty_bit_1[23] <= 0;tag_address_1[23] <= 0;cache_block_1[23] <= 0;lru_counter_1[23] <= 0;valid_bit_2[23]  <=   0;dirty_bit_2[23] <= 0;tag_address_2[23] <= 0;cache_block_2[23] <= 0;lru_counter_2[23] <= 0;
        valid_bit_1[24]  <=   0;dirty_bit_1[24] <= 0;tag_address_1[24] <= 0;cache_block_1[24] <= 0;lru_counter_1[24] <= 0;valid_bit_2[24]  <=   0;dirty_bit_2[24] <= 0;tag_address_2[24] <= 0;cache_block_2[24] <= 0;lru_counter_2[24] <= 0;
        valid_bit_1[25]  <=   0;dirty_bit_1[25] <= 0;tag_address_1[25] <= 0;cache_block_1[25] <= 0;lru_counter_1[25] <= 0;valid_bit_2[25]  <=   0;dirty_bit_2[25] <= 0;tag_address_2[25] <= 0;cache_block_2[25] <= 0;lru_counter_2[25] <= 0;
        valid_bit_1[26]  <=   0;dirty_bit_1[26] <= 0;tag_address_1[26] <= 0;cache_block_1[26] <= 0;lru_counter_1[26] <= 0;valid_bit_2[26]  <=   0;dirty_bit_2[26] <= 0;tag_address_2[26] <= 0;cache_block_2[26] <= 0;lru_counter_2[26] <= 0;
        valid_bit_1[27]  <=   0;dirty_bit_1[27] <= 0;tag_address_1[27] <= 0;cache_block_1[27] <= 0;lru_counter_1[27] <= 0;valid_bit_2[27]  <=   0;dirty_bit_2[27] <= 0;tag_address_2[27] <= 0;cache_block_2[27] <= 0;lru_counter_2[27] <= 0;
        valid_bit_1[28]  <=   0;dirty_bit_1[28] <= 0;tag_address_1[28] <= 0;cache_block_1[28] <= 0;lru_counter_1[28] <= 0;valid_bit_2[28]  <=   0;dirty_bit_2[28] <= 0;tag_address_2[28] <= 0;cache_block_2[28] <= 0;lru_counter_2[28] <= 0;
        valid_bit_1[29]  <=   0;dirty_bit_1[29] <= 0;tag_address_1[29] <= 0;cache_block_1[29] <= 0;lru_counter_1[29] <= 0;valid_bit_2[29]  <=   0;dirty_bit_2[29] <= 0;tag_address_2[29] <= 0;cache_block_2[29] <= 0;lru_counter_2[29] <= 0;
        valid_bit_1[30]  <=   0;dirty_bit_1[30] <= 0;tag_address_1[30] <= 0;cache_block_1[30] <= 0;lru_counter_1[30] <= 0;valid_bit_2[30]  <=   0;dirty_bit_2[30] <= 0;tag_address_2[30] <= 0;cache_block_2[30] <= 0;lru_counter_2[30] <= 0;
        valid_bit_1[31]  <=   0;dirty_bit_1[31] <= 0;tag_address_1[31] <= 0;cache_block_1[31] <= 0;lru_counter_1[31] <= 0;valid_bit_2[31]  <=   0;dirty_bit_2[31] <= 0;tag_address_2[31] <= 0;cache_block_2[31] <= 0;lru_counter_2[31] <= 0;
        valid_bit_1[32]  <=   0;dirty_bit_1[32] <= 0;tag_address_1[32] <= 0;cache_block_1[32] <= 0;lru_counter_1[32] <= 0;valid_bit_2[32]  <=   0;dirty_bit_2[32] <= 0;tag_address_2[32] <= 0;cache_block_2[32] <= 0;lru_counter_2[32] <= 0;
        valid_bit_1[33]  <=   0;dirty_bit_1[33] <= 0;tag_address_1[33] <= 0;cache_block_1[33] <= 0;lru_counter_1[33] <= 0;valid_bit_2[33]  <=   0;dirty_bit_2[33] <= 0;tag_address_2[33] <= 0;cache_block_2[33] <= 0;lru_counter_2[33] <= 0;
        valid_bit_1[34]  <=   0;dirty_bit_1[34] <= 0;tag_address_1[34] <= 0;cache_block_1[34] <= 0;lru_counter_1[34] <= 0;valid_bit_2[34]  <=   0;dirty_bit_2[34] <= 0;tag_address_2[34] <= 0;cache_block_2[34] <= 0;lru_counter_2[34] <= 0;
        valid_bit_1[35]  <=   0;dirty_bit_1[35] <= 0;tag_address_1[35] <= 0;cache_block_1[35] <= 0;lru_counter_1[35] <= 0;valid_bit_2[35]  <=   0;dirty_bit_2[35] <= 0;tag_address_2[35] <= 0;cache_block_2[35] <= 0;lru_counter_2[35] <= 0;
        valid_bit_1[36]  <=   0;dirty_bit_1[36] <= 0;tag_address_1[36] <= 0;cache_block_1[36] <= 0;lru_counter_1[36] <= 0;valid_bit_2[36]  <=   0;dirty_bit_2[36] <= 0;tag_address_2[36] <= 0;cache_block_2[36] <= 0;lru_counter_2[36] <= 0;
        valid_bit_1[37]  <=   0;dirty_bit_1[37] <= 0;tag_address_1[37] <= 0;cache_block_1[37] <= 0;lru_counter_1[37] <= 0;valid_bit_2[37]  <=   0;dirty_bit_2[37] <= 0;tag_address_2[37] <= 0;cache_block_2[37] <= 0;lru_counter_2[37] <= 0;
        valid_bit_1[38]  <=   0;dirty_bit_1[38] <= 0;tag_address_1[38] <= 0;cache_block_1[38] <= 0;lru_counter_1[38] <= 0;valid_bit_2[38]  <=   0;dirty_bit_2[38] <= 0;tag_address_2[38] <= 0;cache_block_2[38] <= 0;lru_counter_2[38] <= 0;
        valid_bit_1[39]  <=   0;dirty_bit_1[39] <= 0;tag_address_1[39] <= 0;cache_block_1[39] <= 0;lru_counter_1[39] <= 0;valid_bit_2[39]  <=   0;dirty_bit_2[39] <= 0;tag_address_2[39] <= 0;cache_block_2[39] <= 0;lru_counter_2[39] <= 0;
        valid_bit_1[40]  <=   0;dirty_bit_1[40] <= 0;tag_address_1[40] <= 0;cache_block_1[40] <= 0;lru_counter_1[40] <= 0;valid_bit_2[40]  <=   0;dirty_bit_2[40] <= 0;tag_address_2[40] <= 0;cache_block_2[40] <= 0;lru_counter_2[40] <= 0;
        valid_bit_1[41]  <=   0;dirty_bit_1[41] <= 0;tag_address_1[41] <= 0;cache_block_1[41] <= 0;lru_counter_1[41] <= 0;valid_bit_2[41]  <=   0;dirty_bit_2[41] <= 0;tag_address_2[41] <= 0;cache_block_2[41] <= 0;lru_counter_2[41] <= 0;
        valid_bit_1[42]  <=   0;dirty_bit_1[42] <= 0;tag_address_1[42] <= 0;cache_block_1[42] <= 0;lru_counter_1[42] <= 0;valid_bit_2[42]  <=   0;dirty_bit_2[42] <= 0;tag_address_2[42] <= 0;cache_block_2[42] <= 0;lru_counter_2[42] <= 0;
        valid_bit_1[43]  <=   0;dirty_bit_1[43] <= 0;tag_address_1[43] <= 0;cache_block_1[43] <= 0;lru_counter_1[43] <= 0;valid_bit_2[43]  <=   0;dirty_bit_2[43] <= 0;tag_address_2[43] <= 0;cache_block_2[43] <= 0;lru_counter_2[43] <= 0;
        valid_bit_1[44]  <=   0;dirty_bit_1[44] <= 0;tag_address_1[44] <= 0;cache_block_1[44] <= 0;lru_counter_1[44] <= 0;valid_bit_2[44]  <=   0;dirty_bit_2[44] <= 0;tag_address_2[44] <= 0;cache_block_2[44] <= 0;lru_counter_2[44] <= 0;
        valid_bit_1[45]  <=   0;dirty_bit_1[45] <= 0;tag_address_1[45] <= 0;cache_block_1[45] <= 0;lru_counter_1[45] <= 0;valid_bit_2[45]  <=   0;dirty_bit_2[45] <= 0;tag_address_2[45] <= 0;cache_block_2[45] <= 0;lru_counter_2[45] <= 0;
        valid_bit_1[46]  <=   0;dirty_bit_1[46] <= 0;tag_address_1[46] <= 0;cache_block_1[46] <= 0;lru_counter_1[46] <= 0;valid_bit_2[46]  <=   0;dirty_bit_2[46] <= 0;tag_address_2[46] <= 0;cache_block_2[46] <= 0;lru_counter_2[46] <= 0;
        valid_bit_1[47]  <=   0;dirty_bit_1[47] <= 0;tag_address_1[47] <= 0;cache_block_1[47] <= 0;lru_counter_1[47] <= 0;valid_bit_2[47]  <=   0;dirty_bit_2[47] <= 0;tag_address_2[47] <= 0;cache_block_2[47] <= 0;lru_counter_2[47] <= 0;
        valid_bit_1[48]  <=   0;dirty_bit_1[48] <= 0;tag_address_1[48] <= 0;cache_block_1[48] <= 0;lru_counter_1[48] <= 0;valid_bit_2[48]  <=   0;dirty_bit_2[48] <= 0;tag_address_2[48] <= 0;cache_block_2[48] <= 0;lru_counter_2[48] <= 0;
        valid_bit_1[49]  <=   0;dirty_bit_1[49] <= 0;tag_address_1[49] <= 0;cache_block_1[49] <= 0;lru_counter_1[49] <= 0;valid_bit_2[49]  <=   0;dirty_bit_2[49] <= 0;tag_address_2[49] <= 0;cache_block_2[49] <= 0;lru_counter_2[49] <= 0;
        valid_bit_1[50]  <=   0;dirty_bit_1[50] <= 0;tag_address_1[50] <= 0;cache_block_1[50] <= 0;lru_counter_1[50] <= 0;valid_bit_2[50]  <=   0;dirty_bit_2[50] <= 0;tag_address_2[50] <= 0;cache_block_2[50] <= 0;lru_counter_2[50] <= 0;
        valid_bit_1[51]  <=   0;dirty_bit_1[51] <= 0;tag_address_1[51] <= 0;cache_block_1[51] <= 0;lru_counter_1[51] <= 0;valid_bit_2[51]  <=   0;dirty_bit_2[51] <= 0;tag_address_2[51] <= 0;cache_block_2[51] <= 0;lru_counter_2[51] <= 0;
        valid_bit_1[52]  <=   0;dirty_bit_1[52] <= 0;tag_address_1[52] <= 0;cache_block_1[52] <= 0;lru_counter_1[52] <= 0;valid_bit_2[52]  <=   0;dirty_bit_2[52] <= 0;tag_address_2[52] <= 0;cache_block_2[52] <= 0;lru_counter_2[52] <= 0;
        valid_bit_1[53]  <=   0;dirty_bit_1[53] <= 0;tag_address_1[53] <= 0;cache_block_1[53] <= 0;lru_counter_1[53] <= 0;valid_bit_2[53]  <=   0;dirty_bit_2[53] <= 0;tag_address_2[53] <= 0;cache_block_2[53] <= 0;lru_counter_2[53] <= 0;
        valid_bit_1[54]  <=   0;dirty_bit_1[54] <= 0;tag_address_1[54] <= 0;cache_block_1[54] <= 0;lru_counter_1[54] <= 0;valid_bit_2[54]  <=   0;dirty_bit_2[54] <= 0;tag_address_2[54] <= 0;cache_block_2[54] <= 0;lru_counter_2[54] <= 0;
        valid_bit_1[55]  <=   0;dirty_bit_1[55] <= 0;tag_address_1[55] <= 0;cache_block_1[55] <= 0;lru_counter_1[55] <= 0;valid_bit_2[55]  <=   0;dirty_bit_2[55] <= 0;tag_address_2[55] <= 0;cache_block_2[55] <= 0;lru_counter_2[55] <= 0;
        valid_bit_1[56]  <=   0;dirty_bit_1[56] <= 0;tag_address_1[56] <= 0;cache_block_1[56] <= 0;lru_counter_1[56] <= 0;valid_bit_2[56]  <=   0;dirty_bit_2[56] <= 0;tag_address_2[56] <= 0;cache_block_2[56] <= 0;lru_counter_2[56] <= 0;
        valid_bit_1[57]  <=   0;dirty_bit_1[57] <= 0;tag_address_1[57] <= 0;cache_block_1[57] <= 0;lru_counter_1[57] <= 0;valid_bit_2[57]  <=   0;dirty_bit_2[57] <= 0;tag_address_2[57] <= 0;cache_block_2[57] <= 0;lru_counter_2[57] <= 0;
        valid_bit_1[58]  <=   0;dirty_bit_1[58] <= 0;tag_address_1[58] <= 0;cache_block_1[58] <= 0;lru_counter_1[58] <= 0;valid_bit_2[58]  <=   0;dirty_bit_2[58] <= 0;tag_address_2[58] <= 0;cache_block_2[58] <= 0;lru_counter_2[58] <= 0;
        valid_bit_1[59]  <=   0;dirty_bit_1[59] <= 0;tag_address_1[59] <= 0;cache_block_1[59] <= 0;lru_counter_1[59] <= 0;valid_bit_2[59]  <=   0;dirty_bit_2[59] <= 0;tag_address_2[59] <= 0;cache_block_2[59] <= 0;lru_counter_2[59] <= 0;
        valid_bit_1[60]  <=   0;dirty_bit_1[60] <= 0;tag_address_1[60] <= 0;cache_block_1[60] <= 0;lru_counter_1[60] <= 0;valid_bit_2[60]  <=   0;dirty_bit_2[60] <= 0;tag_address_2[60] <= 0;cache_block_2[60] <= 0;lru_counter_2[60] <= 0;
        valid_bit_1[61]  <=   0;dirty_bit_1[61] <= 0;tag_address_1[61] <= 0;cache_block_1[61] <= 0;lru_counter_1[61] <= 0;valid_bit_2[61]  <=   0;dirty_bit_2[61] <= 0;tag_address_2[61] <= 0;cache_block_2[61] <= 0;lru_counter_2[61] <= 0;
        valid_bit_1[62]  <=   0;dirty_bit_1[62] <= 0;tag_address_1[62] <= 0;cache_block_1[62] <= 0;lru_counter_1[62] <= 0;valid_bit_2[62]  <=   0;dirty_bit_2[62] <= 0;tag_address_2[62] <= 0;cache_block_2[62] <= 0;lru_counter_2[62] <= 0;
        valid_bit_1[63]  <=   0;dirty_bit_1[63] <= 0;tag_address_1[63] <= 0;cache_block_1[63] <= 0;lru_counter_1[63] <= 0;valid_bit_2[63]  <=   0;dirty_bit_2[63] <= 0;tag_address_2[63] <= 0;cache_block_2[63] <= 0;lru_counter_2[63] <= 0;
        valid_bit_1[64]  <=   0;dirty_bit_1[64] <= 0;tag_address_1[64] <= 0;cache_block_1[64] <= 0;lru_counter_1[64] <= 0;valid_bit_2[64]  <=   0;dirty_bit_2[64] <= 0;tag_address_2[64] <= 0;cache_block_2[64] <= 0;lru_counter_2[64] <= 0;
        valid_bit_1[65]  <=   0;dirty_bit_1[65] <= 0;tag_address_1[65] <= 0;cache_block_1[65] <= 0;lru_counter_1[65] <= 0;valid_bit_2[65]  <=   0;dirty_bit_2[65] <= 0;tag_address_2[65] <= 0;cache_block_2[65] <= 0;lru_counter_2[65] <= 0;
        valid_bit_1[66]  <=   0;dirty_bit_1[66] <= 0;tag_address_1[66] <= 0;cache_block_1[66] <= 0;lru_counter_1[66] <= 0;valid_bit_2[66]  <=   0;dirty_bit_2[66] <= 0;tag_address_2[66] <= 0;cache_block_2[66] <= 0;lru_counter_2[66] <= 0;
        valid_bit_1[67]  <=   0;dirty_bit_1[67] <= 0;tag_address_1[67] <= 0;cache_block_1[67] <= 0;lru_counter_1[67] <= 0;valid_bit_2[67]  <=   0;dirty_bit_2[67] <= 0;tag_address_2[67] <= 0;cache_block_2[67] <= 0;lru_counter_2[67] <= 0;
        valid_bit_1[68]  <=   0;dirty_bit_1[68] <= 0;tag_address_1[68] <= 0;cache_block_1[68] <= 0;lru_counter_1[68] <= 0;valid_bit_2[68]  <=   0;dirty_bit_2[68] <= 0;tag_address_2[68] <= 0;cache_block_2[68] <= 0;lru_counter_2[68] <= 0;
        valid_bit_1[69]  <=   0;dirty_bit_1[69] <= 0;tag_address_1[69] <= 0;cache_block_1[69] <= 0;lru_counter_1[69] <= 0;valid_bit_2[69]  <=   0;dirty_bit_2[69] <= 0;tag_address_2[69] <= 0;cache_block_2[69] <= 0;lru_counter_2[69] <= 0;
        valid_bit_1[70]  <=   0;dirty_bit_1[70] <= 0;tag_address_1[70] <= 0;cache_block_1[70] <= 0;lru_counter_1[70] <= 0;valid_bit_2[70]  <=   0;dirty_bit_2[70] <= 0;tag_address_2[70] <= 0;cache_block_2[70] <= 0;lru_counter_2[70] <= 0;
        valid_bit_1[71]  <=   0;dirty_bit_1[71] <= 0;tag_address_1[71] <= 0;cache_block_1[71] <= 0;lru_counter_1[71] <= 0;valid_bit_2[71]  <=   0;dirty_bit_2[71] <= 0;tag_address_2[71] <= 0;cache_block_2[71] <= 0;lru_counter_2[71] <= 0;
        valid_bit_1[72]  <=   0;dirty_bit_1[72] <= 0;tag_address_1[72] <= 0;cache_block_1[72] <= 0;lru_counter_1[72] <= 0;valid_bit_2[72]  <=   0;dirty_bit_2[72] <= 0;tag_address_2[72] <= 0;cache_block_2[72] <= 0;lru_counter_2[72] <= 0;
        valid_bit_1[73]  <=   0;dirty_bit_1[73] <= 0;tag_address_1[73] <= 0;cache_block_1[73] <= 0;lru_counter_1[73] <= 0;valid_bit_2[73]  <=   0;dirty_bit_2[73] <= 0;tag_address_2[73] <= 0;cache_block_2[73] <= 0;lru_counter_2[73] <= 0;
        valid_bit_1[74]  <=   0;dirty_bit_1[74] <= 0;tag_address_1[74] <= 0;cache_block_1[74] <= 0;lru_counter_1[74] <= 0;valid_bit_2[74]  <=   0;dirty_bit_2[74] <= 0;tag_address_2[74] <= 0;cache_block_2[74] <= 0;lru_counter_2[74] <= 0;
        valid_bit_1[75]  <=   0;dirty_bit_1[75] <= 0;tag_address_1[75] <= 0;cache_block_1[75] <= 0;lru_counter_1[75] <= 0;valid_bit_2[75]  <=   0;dirty_bit_2[75] <= 0;tag_address_2[75] <= 0;cache_block_2[75] <= 0;lru_counter_2[75] <= 0;
        valid_bit_1[76]  <=   0;dirty_bit_1[76] <= 0;tag_address_1[76] <= 0;cache_block_1[76] <= 0;lru_counter_1[76] <= 0;valid_bit_2[76]  <=   0;dirty_bit_2[76] <= 0;tag_address_2[76] <= 0;cache_block_2[76] <= 0;lru_counter_2[76] <= 0;
        valid_bit_1[77]  <=   0;dirty_bit_1[77] <= 0;tag_address_1[77] <= 0;cache_block_1[77] <= 0;lru_counter_1[77] <= 0;valid_bit_2[77]  <=   0;dirty_bit_2[77] <= 0;tag_address_2[77] <= 0;cache_block_2[77] <= 0;lru_counter_2[77] <= 0;
        valid_bit_1[78]  <=   0;dirty_bit_1[78] <= 0;tag_address_1[78] <= 0;cache_block_1[78] <= 0;lru_counter_1[78] <= 0;valid_bit_2[78]  <=   0;dirty_bit_2[78] <= 0;tag_address_2[78] <= 0;cache_block_2[78] <= 0;lru_counter_2[78] <= 0;
        valid_bit_1[79]  <=   0;dirty_bit_1[79] <= 0;tag_address_1[79] <= 0;cache_block_1[79] <= 0;lru_counter_1[79] <= 0;valid_bit_2[79]  <=   0;dirty_bit_2[79] <= 0;tag_address_2[79] <= 0;cache_block_2[79] <= 0;lru_counter_2[79] <= 0;
        valid_bit_1[80]  <=   0;dirty_bit_1[80] <= 0;tag_address_1[80] <= 0;cache_block_1[80] <= 0;lru_counter_1[80] <= 0;valid_bit_2[80]  <=   0;dirty_bit_2[80] <= 0;tag_address_2[80] <= 0;cache_block_2[80] <= 0;lru_counter_2[80] <= 0;
        valid_bit_1[81]  <=   0;dirty_bit_1[81] <= 0;tag_address_1[81] <= 0;cache_block_1[81] <= 0;lru_counter_1[81] <= 0;valid_bit_2[81]  <=   0;dirty_bit_2[81] <= 0;tag_address_2[81] <= 0;cache_block_2[81] <= 0;lru_counter_2[81] <= 0;
        valid_bit_1[82]  <=   0;dirty_bit_1[82] <= 0;tag_address_1[82] <= 0;cache_block_1[82] <= 0;lru_counter_1[82] <= 0;valid_bit_2[82]  <=   0;dirty_bit_2[82] <= 0;tag_address_2[82] <= 0;cache_block_2[82] <= 0;lru_counter_2[82] <= 0;
        valid_bit_1[83]  <=   0;dirty_bit_1[83] <= 0;tag_address_1[83] <= 0;cache_block_1[83] <= 0;lru_counter_1[83] <= 0;valid_bit_2[83]  <=   0;dirty_bit_2[83] <= 0;tag_address_2[83] <= 0;cache_block_2[83] <= 0;lru_counter_2[83] <= 0;
        valid_bit_1[84]  <=   0;dirty_bit_1[84] <= 0;tag_address_1[84] <= 0;cache_block_1[84] <= 0;lru_counter_1[84] <= 0;valid_bit_2[84]  <=   0;dirty_bit_2[84] <= 0;tag_address_2[84] <= 0;cache_block_2[84] <= 0;lru_counter_2[84] <= 0;
        valid_bit_1[85]  <=   0;dirty_bit_1[85] <= 0;tag_address_1[85] <= 0;cache_block_1[85] <= 0;lru_counter_1[85] <= 0;valid_bit_2[85]  <=   0;dirty_bit_2[85] <= 0;tag_address_2[85] <= 0;cache_block_2[85] <= 0;lru_counter_2[85] <= 0;
        valid_bit_1[86]  <=   0;dirty_bit_1[86] <= 0;tag_address_1[86] <= 0;cache_block_1[86] <= 0;lru_counter_1[86] <= 0;valid_bit_2[86]  <=   0;dirty_bit_2[86] <= 0;tag_address_2[86] <= 0;cache_block_2[86] <= 0;lru_counter_2[86] <= 0;
        valid_bit_1[87]  <=   0;dirty_bit_1[87] <= 0;tag_address_1[87] <= 0;cache_block_1[87] <= 0;lru_counter_1[87] <= 0;valid_bit_2[87]  <=   0;dirty_bit_2[87] <= 0;tag_address_2[87] <= 0;cache_block_2[87] <= 0;lru_counter_2[87] <= 0;
        valid_bit_1[88]  <=   0;dirty_bit_1[88] <= 0;tag_address_1[88] <= 0;cache_block_1[88] <= 0;lru_counter_1[88] <= 0;valid_bit_2[88]  <=   0;dirty_bit_2[88] <= 0;tag_address_2[88] <= 0;cache_block_2[88] <= 0;lru_counter_2[88] <= 0;
        valid_bit_1[89]  <=   0;dirty_bit_1[89] <= 0;tag_address_1[89] <= 0;cache_block_1[89] <= 0;lru_counter_1[89] <= 0;valid_bit_2[89]  <=   0;dirty_bit_2[89] <= 0;tag_address_2[89] <= 0;cache_block_2[89] <= 0;lru_counter_2[89] <= 0;
        valid_bit_1[90]  <=   0;dirty_bit_1[90] <= 0;tag_address_1[90] <= 0;cache_block_1[90] <= 0;lru_counter_1[90] <= 0;valid_bit_2[90]  <=   0;dirty_bit_2[90] <= 0;tag_address_2[90] <= 0;cache_block_2[90] <= 0;lru_counter_2[90] <= 0;
        valid_bit_1[91]  <=   0;dirty_bit_1[91] <= 0;tag_address_1[91] <= 0;cache_block_1[91] <= 0;lru_counter_1[91] <= 0;valid_bit_2[91]  <=   0;dirty_bit_2[91] <= 0;tag_address_2[91] <= 0;cache_block_2[91] <= 0;lru_counter_2[91] <= 0;
        valid_bit_1[92]  <=   0;dirty_bit_1[92] <= 0;tag_address_1[92] <= 0;cache_block_1[92] <= 0;lru_counter_1[92] <= 0;valid_bit_2[92]  <=   0;dirty_bit_2[92] <= 0;tag_address_2[92] <= 0;cache_block_2[92] <= 0;lru_counter_2[92] <= 0;
        valid_bit_1[93]  <=   0;dirty_bit_1[93] <= 0;tag_address_1[93] <= 0;cache_block_1[93] <= 0;lru_counter_1[93] <= 0;valid_bit_2[93]  <=   0;dirty_bit_2[93] <= 0;tag_address_2[93] <= 0;cache_block_2[93] <= 0;lru_counter_2[93] <= 0;
        valid_bit_1[94]  <=   0;dirty_bit_1[94] <= 0;tag_address_1[94] <= 0;cache_block_1[94] <= 0;lru_counter_1[94] <= 0;valid_bit_2[94]  <=   0;dirty_bit_2[94] <= 0;tag_address_2[94] <= 0;cache_block_2[94] <= 0;lru_counter_2[94] <= 0;
        valid_bit_1[95]  <=   0;dirty_bit_1[95] <= 0;tag_address_1[95] <= 0;cache_block_1[95] <= 0;lru_counter_1[95] <= 0;valid_bit_2[95]  <=   0;dirty_bit_2[95] <= 0;tag_address_2[95] <= 0;cache_block_2[95] <= 0;lru_counter_2[95] <= 0;
        valid_bit_1[96]  <=   0;dirty_bit_1[96] <= 0;tag_address_1[96] <= 0;cache_block_1[96] <= 0;lru_counter_1[96] <= 0;valid_bit_2[96]  <=   0;dirty_bit_2[96] <= 0;tag_address_2[96] <= 0;cache_block_2[96] <= 0;lru_counter_2[96] <= 0;
        valid_bit_1[97]  <=   0;dirty_bit_1[97] <= 0;tag_address_1[97] <= 0;cache_block_1[97] <= 0;lru_counter_1[97] <= 0;valid_bit_2[97]  <=   0;dirty_bit_2[97] <= 0;tag_address_2[97] <= 0;cache_block_2[97] <= 0;lru_counter_2[97] <= 0;
        valid_bit_1[98]  <=   0;dirty_bit_1[98] <= 0;tag_address_1[98] <= 0;cache_block_1[98] <= 0;lru_counter_1[98] <= 0;valid_bit_2[98]  <=   0;dirty_bit_2[98] <= 0;tag_address_2[98] <= 0;cache_block_2[98] <= 0;lru_counter_2[98] <= 0;
        valid_bit_1[99]  <=   0;dirty_bit_1[99] <= 0;tag_address_1[99] <= 0;cache_block_1[99] <= 0;lru_counter_1[99] <= 0;valid_bit_2[99]  <=   0;dirty_bit_2[99] <= 0;tag_address_2[99] <= 0;cache_block_2[99] <= 0;lru_counter_2[99] <= 0;
        valid_bit_1[100]  <=   0;dirty_bit_1[100] <= 0;tag_address_1[100] <= 0;cache_block_1[100] <= 0;lru_counter_1[100] <= 0;valid_bit_2[100]  <=   0;dirty_bit_2[100] <= 0;tag_address_2[100] <= 0;cache_block_2[100] <= 0;lru_counter_2[100] <= 0;
        valid_bit_1[101]  <=   0;dirty_bit_1[101] <= 0;tag_address_1[101] <= 0;cache_block_1[101] <= 0;lru_counter_1[101] <= 0;valid_bit_2[101]  <=   0;dirty_bit_2[101] <= 0;tag_address_2[101] <= 0;cache_block_2[101] <= 0;lru_counter_2[101] <= 0;
        valid_bit_1[102]  <=   0;dirty_bit_1[102] <= 0;tag_address_1[102] <= 0;cache_block_1[102] <= 0;lru_counter_1[102] <= 0;valid_bit_2[102]  <=   0;dirty_bit_2[102] <= 0;tag_address_2[102] <= 0;cache_block_2[102] <= 0;lru_counter_2[102] <= 0;
        valid_bit_1[103]  <=   0;dirty_bit_1[103] <= 0;tag_address_1[103] <= 0;cache_block_1[103] <= 0;lru_counter_1[103] <= 0;valid_bit_2[103]  <=   0;dirty_bit_2[103] <= 0;tag_address_2[103] <= 0;cache_block_2[103] <= 0;lru_counter_2[103] <= 0;
        valid_bit_1[104]  <=   0;dirty_bit_1[104] <= 0;tag_address_1[104] <= 0;cache_block_1[104] <= 0;lru_counter_1[104] <= 0;valid_bit_2[104]  <=   0;dirty_bit_2[104] <= 0;tag_address_2[104] <= 0;cache_block_2[104] <= 0;lru_counter_2[104] <= 0;
        valid_bit_1[105]  <=   0;dirty_bit_1[105] <= 0;tag_address_1[105] <= 0;cache_block_1[105] <= 0;lru_counter_1[105] <= 0;valid_bit_2[105]  <=   0;dirty_bit_2[105] <= 0;tag_address_2[105] <= 0;cache_block_2[105] <= 0;lru_counter_2[105] <= 0;
        valid_bit_1[106]  <=   0;dirty_bit_1[106] <= 0;tag_address_1[106] <= 0;cache_block_1[106] <= 0;lru_counter_1[106] <= 0;valid_bit_2[106]  <=   0;dirty_bit_2[106] <= 0;tag_address_2[106] <= 0;cache_block_2[106] <= 0;lru_counter_2[106] <= 0;
        valid_bit_1[107]  <=   0;dirty_bit_1[107] <= 0;tag_address_1[107] <= 0;cache_block_1[107] <= 0;lru_counter_1[107] <= 0;valid_bit_2[107]  <=   0;dirty_bit_2[107] <= 0;tag_address_2[107] <= 0;cache_block_2[107] <= 0;lru_counter_2[107] <= 0;
        valid_bit_1[108]  <=   0;dirty_bit_1[108] <= 0;tag_address_1[108] <= 0;cache_block_1[108] <= 0;lru_counter_1[108] <= 0;valid_bit_2[108]  <=   0;dirty_bit_2[108] <= 0;tag_address_2[108] <= 0;cache_block_2[108] <= 0;lru_counter_2[108] <= 0;
        valid_bit_1[109]  <=   0;dirty_bit_1[109] <= 0;tag_address_1[109] <= 0;cache_block_1[109] <= 0;lru_counter_1[109] <= 0;valid_bit_2[109]  <=   0;dirty_bit_2[109] <= 0;tag_address_2[109] <= 0;cache_block_2[109] <= 0;lru_counter_2[109] <= 0;
        valid_bit_1[110]  <=   0;dirty_bit_1[110] <= 0;tag_address_1[110] <= 0;cache_block_1[110] <= 0;lru_counter_1[110] <= 0;valid_bit_2[110]  <=   0;dirty_bit_2[110] <= 0;tag_address_2[110] <= 0;cache_block_2[110] <= 0;lru_counter_2[110] <= 0;
        valid_bit_1[111]  <=   0;dirty_bit_1[111] <= 0;tag_address_1[111] <= 0;cache_block_1[111] <= 0;lru_counter_1[111] <= 0;valid_bit_2[111]  <=   0;dirty_bit_2[111] <= 0;tag_address_2[111] <= 0;cache_block_2[111] <= 0;lru_counter_2[111] <= 0;
        valid_bit_1[112]  <=   0;dirty_bit_1[112] <= 0;tag_address_1[112] <= 0;cache_block_1[112] <= 0;lru_counter_1[112] <= 0;valid_bit_2[112]  <=   0;dirty_bit_2[112] <= 0;tag_address_2[112] <= 0;cache_block_2[112] <= 0;lru_counter_2[112] <= 0;
        valid_bit_1[113]  <=   0;dirty_bit_1[113] <= 0;tag_address_1[113] <= 0;cache_block_1[113] <= 0;lru_counter_1[113] <= 0;valid_bit_2[113]  <=   0;dirty_bit_2[113] <= 0;tag_address_2[113] <= 0;cache_block_2[113] <= 0;lru_counter_2[113] <= 0;
        valid_bit_1[114]  <=   0;dirty_bit_1[114] <= 0;tag_address_1[114] <= 0;cache_block_1[114] <= 0;lru_counter_1[114] <= 0;valid_bit_2[114]  <=   0;dirty_bit_2[114] <= 0;tag_address_2[114] <= 0;cache_block_2[114] <= 0;lru_counter_2[114] <= 0;
        valid_bit_1[115]  <=   0;dirty_bit_1[115] <= 0;tag_address_1[115] <= 0;cache_block_1[115] <= 0;lru_counter_1[115] <= 0;valid_bit_2[115]  <=   0;dirty_bit_2[115] <= 0;tag_address_2[115] <= 0;cache_block_2[115] <= 0;lru_counter_2[115] <= 0;
        valid_bit_1[116]  <=   0;dirty_bit_1[116] <= 0;tag_address_1[116] <= 0;cache_block_1[116] <= 0;lru_counter_1[116] <= 0;valid_bit_2[116]  <=   0;dirty_bit_2[116] <= 0;tag_address_2[116] <= 0;cache_block_2[116] <= 0;lru_counter_2[116] <= 0;
        valid_bit_1[117]  <=   0;dirty_bit_1[117] <= 0;tag_address_1[117] <= 0;cache_block_1[117] <= 0;lru_counter_1[117] <= 0;valid_bit_2[117]  <=   0;dirty_bit_2[117] <= 0;tag_address_2[117] <= 0;cache_block_2[117] <= 0;lru_counter_2[117] <= 0;
        valid_bit_1[118]  <=   0;dirty_bit_1[118] <= 0;tag_address_1[118] <= 0;cache_block_1[118] <= 0;lru_counter_1[118] <= 0;valid_bit_2[118]  <=   0;dirty_bit_2[118] <= 0;tag_address_2[118] <= 0;cache_block_2[118] <= 0;lru_counter_2[118] <= 0;
        valid_bit_1[119]  <=   0;dirty_bit_1[119] <= 0;tag_address_1[119] <= 0;cache_block_1[119] <= 0;lru_counter_1[119] <= 0;valid_bit_2[119]  <=   0;dirty_bit_2[119] <= 0;tag_address_2[119] <= 0;cache_block_2[119] <= 0;lru_counter_2[119] <= 0;
        valid_bit_1[120]  <=   0;dirty_bit_1[120] <= 0;tag_address_1[120] <= 0;cache_block_1[120] <= 0;lru_counter_1[120] <= 0;valid_bit_2[120]  <=   0;dirty_bit_2[120] <= 0;tag_address_2[120] <= 0;cache_block_2[120] <= 0;lru_counter_2[120] <= 0;
        valid_bit_1[121]  <=   0;dirty_bit_1[121] <= 0;tag_address_1[121] <= 0;cache_block_1[121] <= 0;lru_counter_1[121] <= 0;valid_bit_2[121]  <=   0;dirty_bit_2[121] <= 0;tag_address_2[121] <= 0;cache_block_2[121] <= 0;lru_counter_2[121] <= 0;
        valid_bit_1[122]  <=   0;dirty_bit_1[122] <= 0;tag_address_1[122] <= 0;cache_block_1[122] <= 0;lru_counter_1[122] <= 0;valid_bit_2[122]  <=   0;dirty_bit_2[122] <= 0;tag_address_2[122] <= 0;cache_block_2[122] <= 0;lru_counter_2[122] <= 0;
        valid_bit_1[123]  <=   0;dirty_bit_1[123] <= 0;tag_address_1[123] <= 0;cache_block_1[123] <= 0;lru_counter_1[123] <= 0;valid_bit_2[123]  <=   0;dirty_bit_2[123] <= 0;tag_address_2[123] <= 0;cache_block_2[123] <= 0;lru_counter_2[123] <= 0;
        valid_bit_1[124]  <=   0;dirty_bit_1[124] <= 0;tag_address_1[124] <= 0;cache_block_1[124] <= 0;lru_counter_1[124] <= 0;valid_bit_2[124]  <=   0;dirty_bit_2[124] <= 0;tag_address_2[124] <= 0;cache_block_2[124] <= 0;lru_counter_2[124] <= 0;
        valid_bit_1[125]  <=   0;dirty_bit_1[125] <= 0;tag_address_1[125] <= 0;cache_block_1[125] <= 0;lru_counter_1[125] <= 0;valid_bit_2[125]  <=   0;dirty_bit_2[125] <= 0;tag_address_2[125] <= 0;cache_block_2[125] <= 0;lru_counter_2[125] <= 0;
        valid_bit_1[126]  <=   0;dirty_bit_1[126] <= 0;tag_address_1[126] <= 0;cache_block_1[126] <= 0;lru_counter_1[126] <= 0;valid_bit_2[126]  <=   0;dirty_bit_2[126] <= 0;tag_address_2[126] <= 0;cache_block_2[126] <= 0;lru_counter_2[126] <= 0;
        valid_bit_1[127]  <=   0;dirty_bit_1[127] <= 0;tag_address_1[127] <= 0;cache_block_1[127] <= 0;lru_counter_1[127] <= 0;valid_bit_2[127]  <=   0;dirty_bit_2[127] <= 0;tag_address_2[127] <= 0;cache_block_2[127] <= 0;lru_counter_2[127] <= 0;
        valid_bit_1[128]  <=   0;dirty_bit_1[128] <= 0;tag_address_1[128] <= 0;cache_block_1[128] <= 0;lru_counter_1[128] <= 0;valid_bit_2[128]  <=   0;dirty_bit_2[128] <= 0;tag_address_2[128] <= 0;cache_block_2[128] <= 0;lru_counter_2[128] <= 0;
        valid_bit_1[129]  <=   0;dirty_bit_1[129] <= 0;tag_address_1[129] <= 0;cache_block_1[129] <= 0;lru_counter_1[129] <= 0;valid_bit_2[129]  <=   0;dirty_bit_2[129] <= 0;tag_address_2[129] <= 0;cache_block_2[129] <= 0;lru_counter_2[129] <= 0;
        valid_bit_1[130]  <=   0;dirty_bit_1[130] <= 0;tag_address_1[130] <= 0;cache_block_1[130] <= 0;lru_counter_1[130] <= 0;valid_bit_2[130]  <=   0;dirty_bit_2[130] <= 0;tag_address_2[130] <= 0;cache_block_2[130] <= 0;lru_counter_2[130] <= 0;
        valid_bit_1[131]  <=   0;dirty_bit_1[131] <= 0;tag_address_1[131] <= 0;cache_block_1[131] <= 0;lru_counter_1[131] <= 0;valid_bit_2[131]  <=   0;dirty_bit_2[131] <= 0;tag_address_2[131] <= 0;cache_block_2[131] <= 0;lru_counter_2[131] <= 0;
        valid_bit_1[132]  <=   0;dirty_bit_1[132] <= 0;tag_address_1[132] <= 0;cache_block_1[132] <= 0;lru_counter_1[132] <= 0;valid_bit_2[132]  <=   0;dirty_bit_2[132] <= 0;tag_address_2[132] <= 0;cache_block_2[132] <= 0;lru_counter_2[132] <= 0;
        valid_bit_1[133]  <=   0;dirty_bit_1[133] <= 0;tag_address_1[133] <= 0;cache_block_1[133] <= 0;lru_counter_1[133] <= 0;valid_bit_2[133]  <=   0;dirty_bit_2[133] <= 0;tag_address_2[133] <= 0;cache_block_2[133] <= 0;lru_counter_2[133] <= 0;
        valid_bit_1[134]  <=   0;dirty_bit_1[134] <= 0;tag_address_1[134] <= 0;cache_block_1[134] <= 0;lru_counter_1[134] <= 0;valid_bit_2[134]  <=   0;dirty_bit_2[134] <= 0;tag_address_2[134] <= 0;cache_block_2[134] <= 0;lru_counter_2[134] <= 0;
        valid_bit_1[135]  <=   0;dirty_bit_1[135] <= 0;tag_address_1[135] <= 0;cache_block_1[135] <= 0;lru_counter_1[135] <= 0;valid_bit_2[135]  <=   0;dirty_bit_2[135] <= 0;tag_address_2[135] <= 0;cache_block_2[135] <= 0;lru_counter_2[135] <= 0;
        valid_bit_1[136]  <=   0;dirty_bit_1[136] <= 0;tag_address_1[136] <= 0;cache_block_1[136] <= 0;lru_counter_1[136] <= 0;valid_bit_2[136]  <=   0;dirty_bit_2[136] <= 0;tag_address_2[136] <= 0;cache_block_2[136] <= 0;lru_counter_2[136] <= 0;
        valid_bit_1[137]  <=   0;dirty_bit_1[137] <= 0;tag_address_1[137] <= 0;cache_block_1[137] <= 0;lru_counter_1[137] <= 0;valid_bit_2[137]  <=   0;dirty_bit_2[137] <= 0;tag_address_2[137] <= 0;cache_block_2[137] <= 0;lru_counter_2[137] <= 0;
        valid_bit_1[138]  <=   0;dirty_bit_1[138] <= 0;tag_address_1[138] <= 0;cache_block_1[138] <= 0;lru_counter_1[138] <= 0;valid_bit_2[138]  <=   0;dirty_bit_2[138] <= 0;tag_address_2[138] <= 0;cache_block_2[138] <= 0;lru_counter_2[138] <= 0;
        valid_bit_1[139]  <=   0;dirty_bit_1[139] <= 0;tag_address_1[139] <= 0;cache_block_1[139] <= 0;lru_counter_1[139] <= 0;valid_bit_2[139]  <=   0;dirty_bit_2[139] <= 0;tag_address_2[139] <= 0;cache_block_2[139] <= 0;lru_counter_2[139] <= 0;
        valid_bit_1[140]  <=   0;dirty_bit_1[140] <= 0;tag_address_1[140] <= 0;cache_block_1[140] <= 0;lru_counter_1[140] <= 0;valid_bit_2[140]  <=   0;dirty_bit_2[140] <= 0;tag_address_2[140] <= 0;cache_block_2[140] <= 0;lru_counter_2[140] <= 0;
        valid_bit_1[141]  <=   0;dirty_bit_1[141] <= 0;tag_address_1[141] <= 0;cache_block_1[141] <= 0;lru_counter_1[141] <= 0;valid_bit_2[141]  <=   0;dirty_bit_2[141] <= 0;tag_address_2[141] <= 0;cache_block_2[141] <= 0;lru_counter_2[141] <= 0;
        valid_bit_1[142]  <=   0;dirty_bit_1[142] <= 0;tag_address_1[142] <= 0;cache_block_1[142] <= 0;lru_counter_1[142] <= 0;valid_bit_2[142]  <=   0;dirty_bit_2[142] <= 0;tag_address_2[142] <= 0;cache_block_2[142] <= 0;lru_counter_2[142] <= 0;
        valid_bit_1[143]  <=   0;dirty_bit_1[143] <= 0;tag_address_1[143] <= 0;cache_block_1[143] <= 0;lru_counter_1[143] <= 0;valid_bit_2[143]  <=   0;dirty_bit_2[143] <= 0;tag_address_2[143] <= 0;cache_block_2[143] <= 0;lru_counter_2[143] <= 0;
        valid_bit_1[144]  <=   0;dirty_bit_1[144] <= 0;tag_address_1[144] <= 0;cache_block_1[144] <= 0;lru_counter_1[144] <= 0;valid_bit_2[144]  <=   0;dirty_bit_2[144] <= 0;tag_address_2[144] <= 0;cache_block_2[144] <= 0;lru_counter_2[144] <= 0;
        valid_bit_1[145]  <=   0;dirty_bit_1[145] <= 0;tag_address_1[145] <= 0;cache_block_1[145] <= 0;lru_counter_1[145] <= 0;valid_bit_2[145]  <=   0;dirty_bit_2[145] <= 0;tag_address_2[145] <= 0;cache_block_2[145] <= 0;lru_counter_2[145] <= 0;
        valid_bit_1[146]  <=   0;dirty_bit_1[146] <= 0;tag_address_1[146] <= 0;cache_block_1[146] <= 0;lru_counter_1[146] <= 0;valid_bit_2[146]  <=   0;dirty_bit_2[146] <= 0;tag_address_2[146] <= 0;cache_block_2[146] <= 0;lru_counter_2[146] <= 0;
        valid_bit_1[147]  <=   0;dirty_bit_1[147] <= 0;tag_address_1[147] <= 0;cache_block_1[147] <= 0;lru_counter_1[147] <= 0;valid_bit_2[147]  <=   0;dirty_bit_2[147] <= 0;tag_address_2[147] <= 0;cache_block_2[147] <= 0;lru_counter_2[147] <= 0;
        valid_bit_1[148]  <=   0;dirty_bit_1[148] <= 0;tag_address_1[148] <= 0;cache_block_1[148] <= 0;lru_counter_1[148] <= 0;valid_bit_2[148]  <=   0;dirty_bit_2[148] <= 0;tag_address_2[148] <= 0;cache_block_2[148] <= 0;lru_counter_2[148] <= 0;
        valid_bit_1[149]  <=   0;dirty_bit_1[149] <= 0;tag_address_1[149] <= 0;cache_block_1[149] <= 0;lru_counter_1[149] <= 0;valid_bit_2[149]  <=   0;dirty_bit_2[149] <= 0;tag_address_2[149] <= 0;cache_block_2[149] <= 0;lru_counter_2[149] <= 0;
        valid_bit_1[150]  <=   0;dirty_bit_1[150] <= 0;tag_address_1[150] <= 0;cache_block_1[150] <= 0;lru_counter_1[150] <= 0;valid_bit_2[150]  <=   0;dirty_bit_2[150] <= 0;tag_address_2[150] <= 0;cache_block_2[150] <= 0;lru_counter_2[150] <= 0;
        valid_bit_1[151]  <=   0;dirty_bit_1[151] <= 0;tag_address_1[151] <= 0;cache_block_1[151] <= 0;lru_counter_1[151] <= 0;valid_bit_2[151]  <=   0;dirty_bit_2[151] <= 0;tag_address_2[151] <= 0;cache_block_2[151] <= 0;lru_counter_2[151] <= 0;
        valid_bit_1[152]  <=   0;dirty_bit_1[152] <= 0;tag_address_1[152] <= 0;cache_block_1[152] <= 0;lru_counter_1[152] <= 0;valid_bit_2[152]  <=   0;dirty_bit_2[152] <= 0;tag_address_2[152] <= 0;cache_block_2[152] <= 0;lru_counter_2[152] <= 0;
        valid_bit_1[153]  <=   0;dirty_bit_1[153] <= 0;tag_address_1[153] <= 0;cache_block_1[153] <= 0;lru_counter_1[153] <= 0;valid_bit_2[153]  <=   0;dirty_bit_2[153] <= 0;tag_address_2[153] <= 0;cache_block_2[153] <= 0;lru_counter_2[153] <= 0;
        valid_bit_1[154]  <=   0;dirty_bit_1[154] <= 0;tag_address_1[154] <= 0;cache_block_1[154] <= 0;lru_counter_1[154] <= 0;valid_bit_2[154]  <=   0;dirty_bit_2[154] <= 0;tag_address_2[154] <= 0;cache_block_2[154] <= 0;lru_counter_2[154] <= 0;
        valid_bit_1[155]  <=   0;dirty_bit_1[155] <= 0;tag_address_1[155] <= 0;cache_block_1[155] <= 0;lru_counter_1[155] <= 0;valid_bit_2[155]  <=   0;dirty_bit_2[155] <= 0;tag_address_2[155] <= 0;cache_block_2[155] <= 0;lru_counter_2[155] <= 0;
        valid_bit_1[156]  <=   0;dirty_bit_1[156] <= 0;tag_address_1[156] <= 0;cache_block_1[156] <= 0;lru_counter_1[156] <= 0;valid_bit_2[156]  <=   0;dirty_bit_2[156] <= 0;tag_address_2[156] <= 0;cache_block_2[156] <= 0;lru_counter_2[156] <= 0;
        valid_bit_1[157]  <=   0;dirty_bit_1[157] <= 0;tag_address_1[157] <= 0;cache_block_1[157] <= 0;lru_counter_1[157] <= 0;valid_bit_2[157]  <=   0;dirty_bit_2[157] <= 0;tag_address_2[157] <= 0;cache_block_2[157] <= 0;lru_counter_2[157] <= 0;
        valid_bit_1[158]  <=   0;dirty_bit_1[158] <= 0;tag_address_1[158] <= 0;cache_block_1[158] <= 0;lru_counter_1[158] <= 0;valid_bit_2[158]  <=   0;dirty_bit_2[158] <= 0;tag_address_2[158] <= 0;cache_block_2[158] <= 0;lru_counter_2[158] <= 0;
        valid_bit_1[159]  <=   0;dirty_bit_1[159] <= 0;tag_address_1[159] <= 0;cache_block_1[159] <= 0;lru_counter_1[159] <= 0;valid_bit_2[159]  <=   0;dirty_bit_2[159] <= 0;tag_address_2[159] <= 0;cache_block_2[159] <= 0;lru_counter_2[159] <= 0;
        valid_bit_1[160]  <=   0;dirty_bit_1[160] <= 0;tag_address_1[160] <= 0;cache_block_1[160] <= 0;lru_counter_1[160] <= 0;valid_bit_2[160]  <=   0;dirty_bit_2[160] <= 0;tag_address_2[160] <= 0;cache_block_2[160] <= 0;lru_counter_2[160] <= 0;
        valid_bit_1[161]  <=   0;dirty_bit_1[161] <= 0;tag_address_1[161] <= 0;cache_block_1[161] <= 0;lru_counter_1[161] <= 0;valid_bit_2[161]  <=   0;dirty_bit_2[161] <= 0;tag_address_2[161] <= 0;cache_block_2[161] <= 0;lru_counter_2[161] <= 0;
        valid_bit_1[162]  <=   0;dirty_bit_1[162] <= 0;tag_address_1[162] <= 0;cache_block_1[162] <= 0;lru_counter_1[162] <= 0;valid_bit_2[162]  <=   0;dirty_bit_2[162] <= 0;tag_address_2[162] <= 0;cache_block_2[162] <= 0;lru_counter_2[162] <= 0;
        valid_bit_1[163]  <=   0;dirty_bit_1[163] <= 0;tag_address_1[163] <= 0;cache_block_1[163] <= 0;lru_counter_1[163] <= 0;valid_bit_2[163]  <=   0;dirty_bit_2[163] <= 0;tag_address_2[163] <= 0;cache_block_2[163] <= 0;lru_counter_2[163] <= 0;
        valid_bit_1[164]  <=   0;dirty_bit_1[164] <= 0;tag_address_1[164] <= 0;cache_block_1[164] <= 0;lru_counter_1[164] <= 0;valid_bit_2[164]  <=   0;dirty_bit_2[164] <= 0;tag_address_2[164] <= 0;cache_block_2[164] <= 0;lru_counter_2[164] <= 0;
        valid_bit_1[165]  <=   0;dirty_bit_1[165] <= 0;tag_address_1[165] <= 0;cache_block_1[165] <= 0;lru_counter_1[165] <= 0;valid_bit_2[165]  <=   0;dirty_bit_2[165] <= 0;tag_address_2[165] <= 0;cache_block_2[165] <= 0;lru_counter_2[165] <= 0;
        valid_bit_1[166]  <=   0;dirty_bit_1[166] <= 0;tag_address_1[166] <= 0;cache_block_1[166] <= 0;lru_counter_1[166] <= 0;valid_bit_2[166]  <=   0;dirty_bit_2[166] <= 0;tag_address_2[166] <= 0;cache_block_2[166] <= 0;lru_counter_2[166] <= 0;
        valid_bit_1[167]  <=   0;dirty_bit_1[167] <= 0;tag_address_1[167] <= 0;cache_block_1[167] <= 0;lru_counter_1[167] <= 0;valid_bit_2[167]  <=   0;dirty_bit_2[167] <= 0;tag_address_2[167] <= 0;cache_block_2[167] <= 0;lru_counter_2[167] <= 0;
        valid_bit_1[168]  <=   0;dirty_bit_1[168] <= 0;tag_address_1[168] <= 0;cache_block_1[168] <= 0;lru_counter_1[168] <= 0;valid_bit_2[168]  <=   0;dirty_bit_2[168] <= 0;tag_address_2[168] <= 0;cache_block_2[168] <= 0;lru_counter_2[168] <= 0;
        valid_bit_1[169]  <=   0;dirty_bit_1[169] <= 0;tag_address_1[169] <= 0;cache_block_1[169] <= 0;lru_counter_1[169] <= 0;valid_bit_2[169]  <=   0;dirty_bit_2[169] <= 0;tag_address_2[169] <= 0;cache_block_2[169] <= 0;lru_counter_2[169] <= 0;
        valid_bit_1[170]  <=   0;dirty_bit_1[170] <= 0;tag_address_1[170] <= 0;cache_block_1[170] <= 0;lru_counter_1[170] <= 0;valid_bit_2[170]  <=   0;dirty_bit_2[170] <= 0;tag_address_2[170] <= 0;cache_block_2[170] <= 0;lru_counter_2[170] <= 0;
        valid_bit_1[171]  <=   0;dirty_bit_1[171] <= 0;tag_address_1[171] <= 0;cache_block_1[171] <= 0;lru_counter_1[171] <= 0;valid_bit_2[171]  <=   0;dirty_bit_2[171] <= 0;tag_address_2[171] <= 0;cache_block_2[171] <= 0;lru_counter_2[171] <= 0;
        valid_bit_1[172]  <=   0;dirty_bit_1[172] <= 0;tag_address_1[172] <= 0;cache_block_1[172] <= 0;lru_counter_1[172] <= 0;valid_bit_2[172]  <=   0;dirty_bit_2[172] <= 0;tag_address_2[172] <= 0;cache_block_2[172] <= 0;lru_counter_2[172] <= 0;
        valid_bit_1[173]  <=   0;dirty_bit_1[173] <= 0;tag_address_1[173] <= 0;cache_block_1[173] <= 0;lru_counter_1[173] <= 0;valid_bit_2[173]  <=   0;dirty_bit_2[173] <= 0;tag_address_2[173] <= 0;cache_block_2[173] <= 0;lru_counter_2[173] <= 0;
        valid_bit_1[174]  <=   0;dirty_bit_1[174] <= 0;tag_address_1[174] <= 0;cache_block_1[174] <= 0;lru_counter_1[174] <= 0;valid_bit_2[174]  <=   0;dirty_bit_2[174] <= 0;tag_address_2[174] <= 0;cache_block_2[174] <= 0;lru_counter_2[174] <= 0;
        valid_bit_1[175]  <=   0;dirty_bit_1[175] <= 0;tag_address_1[175] <= 0;cache_block_1[175] <= 0;lru_counter_1[175] <= 0;valid_bit_2[175]  <=   0;dirty_bit_2[175] <= 0;tag_address_2[175] <= 0;cache_block_2[175] <= 0;lru_counter_2[175] <= 0;
        valid_bit_1[176]  <=   0;dirty_bit_1[176] <= 0;tag_address_1[176] <= 0;cache_block_1[176] <= 0;lru_counter_1[176] <= 0;valid_bit_2[176]  <=   0;dirty_bit_2[176] <= 0;tag_address_2[176] <= 0;cache_block_2[176] <= 0;lru_counter_2[176] <= 0;
        valid_bit_1[177]  <=   0;dirty_bit_1[177] <= 0;tag_address_1[177] <= 0;cache_block_1[177] <= 0;lru_counter_1[177] <= 0;valid_bit_2[177]  <=   0;dirty_bit_2[177] <= 0;tag_address_2[177] <= 0;cache_block_2[177] <= 0;lru_counter_2[177] <= 0;
        valid_bit_1[178]  <=   0;dirty_bit_1[178] <= 0;tag_address_1[178] <= 0;cache_block_1[178] <= 0;lru_counter_1[178] <= 0;valid_bit_2[178]  <=   0;dirty_bit_2[178] <= 0;tag_address_2[178] <= 0;cache_block_2[178] <= 0;lru_counter_2[178] <= 0;
        valid_bit_1[179]  <=   0;dirty_bit_1[179] <= 0;tag_address_1[179] <= 0;cache_block_1[179] <= 0;lru_counter_1[179] <= 0;valid_bit_2[179]  <=   0;dirty_bit_2[179] <= 0;tag_address_2[179] <= 0;cache_block_2[179] <= 0;lru_counter_2[179] <= 0;
        valid_bit_1[180]  <=   0;dirty_bit_1[180] <= 0;tag_address_1[180] <= 0;cache_block_1[180] <= 0;lru_counter_1[180] <= 0;valid_bit_2[180]  <=   0;dirty_bit_2[180] <= 0;tag_address_2[180] <= 0;cache_block_2[180] <= 0;lru_counter_2[180] <= 0;
        valid_bit_1[181]  <=   0;dirty_bit_1[181] <= 0;tag_address_1[181] <= 0;cache_block_1[181] <= 0;lru_counter_1[181] <= 0;valid_bit_2[181]  <=   0;dirty_bit_2[181] <= 0;tag_address_2[181] <= 0;cache_block_2[181] <= 0;lru_counter_2[181] <= 0;
        valid_bit_1[182]  <=   0;dirty_bit_1[182] <= 0;tag_address_1[182] <= 0;cache_block_1[182] <= 0;lru_counter_1[182] <= 0;valid_bit_2[182]  <=   0;dirty_bit_2[182] <= 0;tag_address_2[182] <= 0;cache_block_2[182] <= 0;lru_counter_2[182] <= 0;
        valid_bit_1[183]  <=   0;dirty_bit_1[183] <= 0;tag_address_1[183] <= 0;cache_block_1[183] <= 0;lru_counter_1[183] <= 0;valid_bit_2[183]  <=   0;dirty_bit_2[183] <= 0;tag_address_2[183] <= 0;cache_block_2[183] <= 0;lru_counter_2[183] <= 0;
        valid_bit_1[184]  <=   0;dirty_bit_1[184] <= 0;tag_address_1[184] <= 0;cache_block_1[184] <= 0;lru_counter_1[184] <= 0;valid_bit_2[184]  <=   0;dirty_bit_2[184] <= 0;tag_address_2[184] <= 0;cache_block_2[184] <= 0;lru_counter_2[184] <= 0;
        valid_bit_1[185]  <=   0;dirty_bit_1[185] <= 0;tag_address_1[185] <= 0;cache_block_1[185] <= 0;lru_counter_1[185] <= 0;valid_bit_2[185]  <=   0;dirty_bit_2[185] <= 0;tag_address_2[185] <= 0;cache_block_2[185] <= 0;lru_counter_2[185] <= 0;
        valid_bit_1[186]  <=   0;dirty_bit_1[186] <= 0;tag_address_1[186] <= 0;cache_block_1[186] <= 0;lru_counter_1[186] <= 0;valid_bit_2[186]  <=   0;dirty_bit_2[186] <= 0;tag_address_2[186] <= 0;cache_block_2[186] <= 0;lru_counter_2[186] <= 0;
        valid_bit_1[187]  <=   0;dirty_bit_1[187] <= 0;tag_address_1[187] <= 0;cache_block_1[187] <= 0;lru_counter_1[187] <= 0;valid_bit_2[187]  <=   0;dirty_bit_2[187] <= 0;tag_address_2[187] <= 0;cache_block_2[187] <= 0;lru_counter_2[187] <= 0;
        valid_bit_1[188]  <=   0;dirty_bit_1[188] <= 0;tag_address_1[188] <= 0;cache_block_1[188] <= 0;lru_counter_1[188] <= 0;valid_bit_2[188]  <=   0;dirty_bit_2[188] <= 0;tag_address_2[188] <= 0;cache_block_2[188] <= 0;lru_counter_2[188] <= 0;
        valid_bit_1[189]  <=   0;dirty_bit_1[189] <= 0;tag_address_1[189] <= 0;cache_block_1[189] <= 0;lru_counter_1[189] <= 0;valid_bit_2[189]  <=   0;dirty_bit_2[189] <= 0;tag_address_2[189] <= 0;cache_block_2[189] <= 0;lru_counter_2[189] <= 0;
        valid_bit_1[190]  <=   0;dirty_bit_1[190] <= 0;tag_address_1[190] <= 0;cache_block_1[190] <= 0;lru_counter_1[190] <= 0;valid_bit_2[190]  <=   0;dirty_bit_2[190] <= 0;tag_address_2[190] <= 0;cache_block_2[190] <= 0;lru_counter_2[190] <= 0;
        valid_bit_1[191]  <=   0;dirty_bit_1[191] <= 0;tag_address_1[191] <= 0;cache_block_1[191] <= 0;lru_counter_1[191] <= 0;valid_bit_2[191]  <=   0;dirty_bit_2[191] <= 0;tag_address_2[191] <= 0;cache_block_2[191] <= 0;lru_counter_2[191] <= 0;
        valid_bit_1[192]  <=   0;dirty_bit_1[192] <= 0;tag_address_1[192] <= 0;cache_block_1[192] <= 0;lru_counter_1[192] <= 0;valid_bit_2[192]  <=   0;dirty_bit_2[192] <= 0;tag_address_2[192] <= 0;cache_block_2[192] <= 0;lru_counter_2[192] <= 0;
        valid_bit_1[193]  <=   0;dirty_bit_1[193] <= 0;tag_address_1[193] <= 0;cache_block_1[193] <= 0;lru_counter_1[193] <= 0;valid_bit_2[193]  <=   0;dirty_bit_2[193] <= 0;tag_address_2[193] <= 0;cache_block_2[193] <= 0;lru_counter_2[193] <= 0;
        valid_bit_1[194]  <=   0;dirty_bit_1[194] <= 0;tag_address_1[194] <= 0;cache_block_1[194] <= 0;lru_counter_1[194] <= 0;valid_bit_2[194]  <=   0;dirty_bit_2[194] <= 0;tag_address_2[194] <= 0;cache_block_2[194] <= 0;lru_counter_2[194] <= 0;
        valid_bit_1[195]  <=   0;dirty_bit_1[195] <= 0;tag_address_1[195] <= 0;cache_block_1[195] <= 0;lru_counter_1[195] <= 0;valid_bit_2[195]  <=   0;dirty_bit_2[195] <= 0;tag_address_2[195] <= 0;cache_block_2[195] <= 0;lru_counter_2[195] <= 0;
        valid_bit_1[196]  <=   0;dirty_bit_1[196] <= 0;tag_address_1[196] <= 0;cache_block_1[196] <= 0;lru_counter_1[196] <= 0;valid_bit_2[196]  <=   0;dirty_bit_2[196] <= 0;tag_address_2[196] <= 0;cache_block_2[196] <= 0;lru_counter_2[196] <= 0;
        valid_bit_1[197]  <=   0;dirty_bit_1[197] <= 0;tag_address_1[197] <= 0;cache_block_1[197] <= 0;lru_counter_1[197] <= 0;valid_bit_2[197]  <=   0;dirty_bit_2[197] <= 0;tag_address_2[197] <= 0;cache_block_2[197] <= 0;lru_counter_2[197] <= 0;
        valid_bit_1[198]  <=   0;dirty_bit_1[198] <= 0;tag_address_1[198] <= 0;cache_block_1[198] <= 0;lru_counter_1[198] <= 0;valid_bit_2[198]  <=   0;dirty_bit_2[198] <= 0;tag_address_2[198] <= 0;cache_block_2[198] <= 0;lru_counter_2[198] <= 0;
        valid_bit_1[199]  <=   0;dirty_bit_1[199] <= 0;tag_address_1[199] <= 0;cache_block_1[199] <= 0;lru_counter_1[199] <= 0;valid_bit_2[199]  <=   0;dirty_bit_2[199] <= 0;tag_address_2[199] <= 0;cache_block_2[199] <= 0;lru_counter_2[199] <= 0;
        valid_bit_1[200]  <=   0;dirty_bit_1[200] <= 0;tag_address_1[200] <= 0;cache_block_1[200] <= 0;lru_counter_1[200] <= 0;valid_bit_2[200]  <=   0;dirty_bit_2[200] <= 0;tag_address_2[200] <= 0;cache_block_2[200] <= 0;lru_counter_2[200] <= 0;
        valid_bit_1[201]  <=   0;dirty_bit_1[201] <= 0;tag_address_1[201] <= 0;cache_block_1[201] <= 0;lru_counter_1[201] <= 0;valid_bit_2[201]  <=   0;dirty_bit_2[201] <= 0;tag_address_2[201] <= 0;cache_block_2[201] <= 0;lru_counter_2[201] <= 0;
        valid_bit_1[202]  <=   0;dirty_bit_1[202] <= 0;tag_address_1[202] <= 0;cache_block_1[202] <= 0;lru_counter_1[202] <= 0;valid_bit_2[202]  <=   0;dirty_bit_2[202] <= 0;tag_address_2[202] <= 0;cache_block_2[202] <= 0;lru_counter_2[202] <= 0;
        valid_bit_1[203]  <=   0;dirty_bit_1[203] <= 0;tag_address_1[203] <= 0;cache_block_1[203] <= 0;lru_counter_1[203] <= 0;valid_bit_2[203]  <=   0;dirty_bit_2[203] <= 0;tag_address_2[203] <= 0;cache_block_2[203] <= 0;lru_counter_2[203] <= 0;
        valid_bit_1[204]  <=   0;dirty_bit_1[204] <= 0;tag_address_1[204] <= 0;cache_block_1[204] <= 0;lru_counter_1[204] <= 0;valid_bit_2[204]  <=   0;dirty_bit_2[204] <= 0;tag_address_2[204] <= 0;cache_block_2[204] <= 0;lru_counter_2[204] <= 0;
        valid_bit_1[205]  <=   0;dirty_bit_1[205] <= 0;tag_address_1[205] <= 0;cache_block_1[205] <= 0;lru_counter_1[205] <= 0;valid_bit_2[205]  <=   0;dirty_bit_2[205] <= 0;tag_address_2[205] <= 0;cache_block_2[205] <= 0;lru_counter_2[205] <= 0;
        valid_bit_1[206]  <=   0;dirty_bit_1[206] <= 0;tag_address_1[206] <= 0;cache_block_1[206] <= 0;lru_counter_1[206] <= 0;valid_bit_2[206]  <=   0;dirty_bit_2[206] <= 0;tag_address_2[206] <= 0;cache_block_2[206] <= 0;lru_counter_2[206] <= 0;
        valid_bit_1[207]  <=   0;dirty_bit_1[207] <= 0;tag_address_1[207] <= 0;cache_block_1[207] <= 0;lru_counter_1[207] <= 0;valid_bit_2[207]  <=   0;dirty_bit_2[207] <= 0;tag_address_2[207] <= 0;cache_block_2[207] <= 0;lru_counter_2[207] <= 0;
        valid_bit_1[208]  <=   0;dirty_bit_1[208] <= 0;tag_address_1[208] <= 0;cache_block_1[208] <= 0;lru_counter_1[208] <= 0;valid_bit_2[208]  <=   0;dirty_bit_2[208] <= 0;tag_address_2[208] <= 0;cache_block_2[208] <= 0;lru_counter_2[208] <= 0;
        valid_bit_1[209]  <=   0;dirty_bit_1[209] <= 0;tag_address_1[209] <= 0;cache_block_1[209] <= 0;lru_counter_1[209] <= 0;valid_bit_2[209]  <=   0;dirty_bit_2[209] <= 0;tag_address_2[209] <= 0;cache_block_2[209] <= 0;lru_counter_2[209] <= 0;
        valid_bit_1[210]  <=   0;dirty_bit_1[210] <= 0;tag_address_1[210] <= 0;cache_block_1[210] <= 0;lru_counter_1[210] <= 0;valid_bit_2[210]  <=   0;dirty_bit_2[210] <= 0;tag_address_2[210] <= 0;cache_block_2[210] <= 0;lru_counter_2[210] <= 0;
        valid_bit_1[211]  <=   0;dirty_bit_1[211] <= 0;tag_address_1[211] <= 0;cache_block_1[211] <= 0;lru_counter_1[211] <= 0;valid_bit_2[211]  <=   0;dirty_bit_2[211] <= 0;tag_address_2[211] <= 0;cache_block_2[211] <= 0;lru_counter_2[211] <= 0;
        valid_bit_1[212]  <=   0;dirty_bit_1[212] <= 0;tag_address_1[212] <= 0;cache_block_1[212] <= 0;lru_counter_1[212] <= 0;valid_bit_2[212]  <=   0;dirty_bit_2[212] <= 0;tag_address_2[212] <= 0;cache_block_2[212] <= 0;lru_counter_2[212] <= 0;
        valid_bit_1[213]  <=   0;dirty_bit_1[213] <= 0;tag_address_1[213] <= 0;cache_block_1[213] <= 0;lru_counter_1[213] <= 0;valid_bit_2[213]  <=   0;dirty_bit_2[213] <= 0;tag_address_2[213] <= 0;cache_block_2[213] <= 0;lru_counter_2[213] <= 0;
        valid_bit_1[214]  <=   0;dirty_bit_1[214] <= 0;tag_address_1[214] <= 0;cache_block_1[214] <= 0;lru_counter_1[214] <= 0;valid_bit_2[214]  <=   0;dirty_bit_2[214] <= 0;tag_address_2[214] <= 0;cache_block_2[214] <= 0;lru_counter_2[214] <= 0;
        valid_bit_1[215]  <=   0;dirty_bit_1[215] <= 0;tag_address_1[215] <= 0;cache_block_1[215] <= 0;lru_counter_1[215] <= 0;valid_bit_2[215]  <=   0;dirty_bit_2[215] <= 0;tag_address_2[215] <= 0;cache_block_2[215] <= 0;lru_counter_2[215] <= 0;
        valid_bit_1[216]  <=   0;dirty_bit_1[216] <= 0;tag_address_1[216] <= 0;cache_block_1[216] <= 0;lru_counter_1[216] <= 0;valid_bit_2[216]  <=   0;dirty_bit_2[216] <= 0;tag_address_2[216] <= 0;cache_block_2[216] <= 0;lru_counter_2[216] <= 0;
        valid_bit_1[217]  <=   0;dirty_bit_1[217] <= 0;tag_address_1[217] <= 0;cache_block_1[217] <= 0;lru_counter_1[217] <= 0;valid_bit_2[217]  <=   0;dirty_bit_2[217] <= 0;tag_address_2[217] <= 0;cache_block_2[217] <= 0;lru_counter_2[217] <= 0;
        valid_bit_1[218]  <=   0;dirty_bit_1[218] <= 0;tag_address_1[218] <= 0;cache_block_1[218] <= 0;lru_counter_1[218] <= 0;valid_bit_2[218]  <=   0;dirty_bit_2[218] <= 0;tag_address_2[218] <= 0;cache_block_2[218] <= 0;lru_counter_2[218] <= 0;
        valid_bit_1[219]  <=   0;dirty_bit_1[219] <= 0;tag_address_1[219] <= 0;cache_block_1[219] <= 0;lru_counter_1[219] <= 0;valid_bit_2[219]  <=   0;dirty_bit_2[219] <= 0;tag_address_2[219] <= 0;cache_block_2[219] <= 0;lru_counter_2[219] <= 0;
        valid_bit_1[220]  <=   0;dirty_bit_1[220] <= 0;tag_address_1[220] <= 0;cache_block_1[220] <= 0;lru_counter_1[220] <= 0;valid_bit_2[220]  <=   0;dirty_bit_2[220] <= 0;tag_address_2[220] <= 0;cache_block_2[220] <= 0;lru_counter_2[220] <= 0;
        valid_bit_1[221]  <=   0;dirty_bit_1[221] <= 0;tag_address_1[221] <= 0;cache_block_1[221] <= 0;lru_counter_1[221] <= 0;valid_bit_2[221]  <=   0;dirty_bit_2[221] <= 0;tag_address_2[221] <= 0;cache_block_2[221] <= 0;lru_counter_2[221] <= 0;
        valid_bit_1[222]  <=   0;dirty_bit_1[222] <= 0;tag_address_1[222] <= 0;cache_block_1[222] <= 0;lru_counter_1[222] <= 0;valid_bit_2[222]  <=   0;dirty_bit_2[222] <= 0;tag_address_2[222] <= 0;cache_block_2[222] <= 0;lru_counter_2[222] <= 0;
        valid_bit_1[223]  <=   0;dirty_bit_1[223] <= 0;tag_address_1[223] <= 0;cache_block_1[223] <= 0;lru_counter_1[223] <= 0;valid_bit_2[223]  <=   0;dirty_bit_2[223] <= 0;tag_address_2[223] <= 0;cache_block_2[223] <= 0;lru_counter_2[223] <= 0;
        valid_bit_1[224]  <=   0;dirty_bit_1[224] <= 0;tag_address_1[224] <= 0;cache_block_1[224] <= 0;lru_counter_1[224] <= 0;valid_bit_2[224]  <=   0;dirty_bit_2[224] <= 0;tag_address_2[224] <= 0;cache_block_2[224] <= 0;lru_counter_2[224] <= 0;
        valid_bit_1[225]  <=   0;dirty_bit_1[225] <= 0;tag_address_1[225] <= 0;cache_block_1[225] <= 0;lru_counter_1[225] <= 0;valid_bit_2[225]  <=   0;dirty_bit_2[225] <= 0;tag_address_2[225] <= 0;cache_block_2[225] <= 0;lru_counter_2[225] <= 0;
        valid_bit_1[226]  <=   0;dirty_bit_1[226] <= 0;tag_address_1[226] <= 0;cache_block_1[226] <= 0;lru_counter_1[226] <= 0;valid_bit_2[226]  <=   0;dirty_bit_2[226] <= 0;tag_address_2[226] <= 0;cache_block_2[226] <= 0;lru_counter_2[226] <= 0;
        valid_bit_1[227]  <=   0;dirty_bit_1[227] <= 0;tag_address_1[227] <= 0;cache_block_1[227] <= 0;lru_counter_1[227] <= 0;valid_bit_2[227]  <=   0;dirty_bit_2[227] <= 0;tag_address_2[227] <= 0;cache_block_2[227] <= 0;lru_counter_2[227] <= 0;
        valid_bit_1[228]  <=   0;dirty_bit_1[228] <= 0;tag_address_1[228] <= 0;cache_block_1[228] <= 0;lru_counter_1[228] <= 0;valid_bit_2[228]  <=   0;dirty_bit_2[228] <= 0;tag_address_2[228] <= 0;cache_block_2[228] <= 0;lru_counter_2[228] <= 0;
        valid_bit_1[229]  <=   0;dirty_bit_1[229] <= 0;tag_address_1[229] <= 0;cache_block_1[229] <= 0;lru_counter_1[229] <= 0;valid_bit_2[229]  <=   0;dirty_bit_2[229] <= 0;tag_address_2[229] <= 0;cache_block_2[229] <= 0;lru_counter_2[229] <= 0;
        valid_bit_1[230]  <=   0;dirty_bit_1[230] <= 0;tag_address_1[230] <= 0;cache_block_1[230] <= 0;lru_counter_1[230] <= 0;valid_bit_2[230]  <=   0;dirty_bit_2[230] <= 0;tag_address_2[230] <= 0;cache_block_2[230] <= 0;lru_counter_2[230] <= 0;
        valid_bit_1[231]  <=   0;dirty_bit_1[231] <= 0;tag_address_1[231] <= 0;cache_block_1[231] <= 0;lru_counter_1[231] <= 0;valid_bit_2[231]  <=   0;dirty_bit_2[231] <= 0;tag_address_2[231] <= 0;cache_block_2[231] <= 0;lru_counter_2[231] <= 0;
        valid_bit_1[232]  <=   0;dirty_bit_1[232] <= 0;tag_address_1[232] <= 0;cache_block_1[232] <= 0;lru_counter_1[232] <= 0;valid_bit_2[232]  <=   0;dirty_bit_2[232] <= 0;tag_address_2[232] <= 0;cache_block_2[232] <= 0;lru_counter_2[232] <= 0;
        valid_bit_1[233]  <=   0;dirty_bit_1[233] <= 0;tag_address_1[233] <= 0;cache_block_1[233] <= 0;lru_counter_1[233] <= 0;valid_bit_2[233]  <=   0;dirty_bit_2[233] <= 0;tag_address_2[233] <= 0;cache_block_2[233] <= 0;lru_counter_2[233] <= 0;
        valid_bit_1[234]  <=   0;dirty_bit_1[234] <= 0;tag_address_1[234] <= 0;cache_block_1[234] <= 0;lru_counter_1[234] <= 0;valid_bit_2[234]  <=   0;dirty_bit_2[234] <= 0;tag_address_2[234] <= 0;cache_block_2[234] <= 0;lru_counter_2[234] <= 0;
        valid_bit_1[235]  <=   0;dirty_bit_1[235] <= 0;tag_address_1[235] <= 0;cache_block_1[235] <= 0;lru_counter_1[235] <= 0;valid_bit_2[235]  <=   0;dirty_bit_2[235] <= 0;tag_address_2[235] <= 0;cache_block_2[235] <= 0;lru_counter_2[235] <= 0;
        valid_bit_1[236]  <=   0;dirty_bit_1[236] <= 0;tag_address_1[236] <= 0;cache_block_1[236] <= 0;lru_counter_1[236] <= 0;valid_bit_2[236]  <=   0;dirty_bit_2[236] <= 0;tag_address_2[236] <= 0;cache_block_2[236] <= 0;lru_counter_2[236] <= 0;
        valid_bit_1[237]  <=   0;dirty_bit_1[237] <= 0;tag_address_1[237] <= 0;cache_block_1[237] <= 0;lru_counter_1[237] <= 0;valid_bit_2[237]  <=   0;dirty_bit_2[237] <= 0;tag_address_2[237] <= 0;cache_block_2[237] <= 0;lru_counter_2[237] <= 0;
        valid_bit_1[238]  <=   0;dirty_bit_1[238] <= 0;tag_address_1[238] <= 0;cache_block_1[238] <= 0;lru_counter_1[238] <= 0;valid_bit_2[238]  <=   0;dirty_bit_2[238] <= 0;tag_address_2[238] <= 0;cache_block_2[238] <= 0;lru_counter_2[238] <= 0;
        valid_bit_1[239]  <=   0;dirty_bit_1[239] <= 0;tag_address_1[239] <= 0;cache_block_1[239] <= 0;lru_counter_1[239] <= 0;valid_bit_2[239]  <=   0;dirty_bit_2[239] <= 0;tag_address_2[239] <= 0;cache_block_2[239] <= 0;lru_counter_2[239] <= 0;
        valid_bit_1[240]  <=   0;dirty_bit_1[240] <= 0;tag_address_1[240] <= 0;cache_block_1[240] <= 0;lru_counter_1[240] <= 0;valid_bit_2[240]  <=   0;dirty_bit_2[240] <= 0;tag_address_2[240] <= 0;cache_block_2[240] <= 0;lru_counter_2[240] <= 0;
        valid_bit_1[241]  <=   0;dirty_bit_1[241] <= 0;tag_address_1[241] <= 0;cache_block_1[241] <= 0;lru_counter_1[241] <= 0;valid_bit_2[241]  <=   0;dirty_bit_2[241] <= 0;tag_address_2[241] <= 0;cache_block_2[241] <= 0;lru_counter_2[241] <= 0;
        valid_bit_1[242]  <=   0;dirty_bit_1[242] <= 0;tag_address_1[242] <= 0;cache_block_1[242] <= 0;lru_counter_1[242] <= 0;valid_bit_2[242]  <=   0;dirty_bit_2[242] <= 0;tag_address_2[242] <= 0;cache_block_2[242] <= 0;lru_counter_2[242] <= 0;
        valid_bit_1[243]  <=   0;dirty_bit_1[243] <= 0;tag_address_1[243] <= 0;cache_block_1[243] <= 0;lru_counter_1[243] <= 0;valid_bit_2[243]  <=   0;dirty_bit_2[243] <= 0;tag_address_2[243] <= 0;cache_block_2[243] <= 0;lru_counter_2[243] <= 0;
        valid_bit_1[244]  <=   0;dirty_bit_1[244] <= 0;tag_address_1[244] <= 0;cache_block_1[244] <= 0;lru_counter_1[244] <= 0;valid_bit_2[244]  <=   0;dirty_bit_2[244] <= 0;tag_address_2[244] <= 0;cache_block_2[244] <= 0;lru_counter_2[244] <= 0;
        valid_bit_1[245]  <=   0;dirty_bit_1[245] <= 0;tag_address_1[245] <= 0;cache_block_1[245] <= 0;lru_counter_1[245] <= 0;valid_bit_2[245]  <=   0;dirty_bit_2[245] <= 0;tag_address_2[245] <= 0;cache_block_2[245] <= 0;lru_counter_2[245] <= 0;
        valid_bit_1[246]  <=   0;dirty_bit_1[246] <= 0;tag_address_1[246] <= 0;cache_block_1[246] <= 0;lru_counter_1[246] <= 0;valid_bit_2[246]  <=   0;dirty_bit_2[246] <= 0;tag_address_2[246] <= 0;cache_block_2[246] <= 0;lru_counter_2[246] <= 0;
        valid_bit_1[247]  <=   0;dirty_bit_1[247] <= 0;tag_address_1[247] <= 0;cache_block_1[247] <= 0;lru_counter_1[247] <= 0;valid_bit_2[247]  <=   0;dirty_bit_2[247] <= 0;tag_address_2[247] <= 0;cache_block_2[247] <= 0;lru_counter_2[247] <= 0;
        valid_bit_1[248]  <=   0;dirty_bit_1[248] <= 0;tag_address_1[248] <= 0;cache_block_1[248] <= 0;lru_counter_1[248] <= 0;valid_bit_2[248]  <=   0;dirty_bit_2[248] <= 0;tag_address_2[248] <= 0;cache_block_2[248] <= 0;lru_counter_2[248] <= 0;
        valid_bit_1[249]  <=   0;dirty_bit_1[249] <= 0;tag_address_1[249] <= 0;cache_block_1[249] <= 0;lru_counter_1[249] <= 0;valid_bit_2[249]  <=   0;dirty_bit_2[249] <= 0;tag_address_2[249] <= 0;cache_block_2[249] <= 0;lru_counter_2[249] <= 0;
        valid_bit_1[250]  <=   0;dirty_bit_1[250] <= 0;tag_address_1[250] <= 0;cache_block_1[250] <= 0;lru_counter_1[250] <= 0;valid_bit_2[250]  <=   0;dirty_bit_2[250] <= 0;tag_address_2[250] <= 0;cache_block_2[250] <= 0;lru_counter_2[250] <= 0;
        valid_bit_1[251]  <=   0;dirty_bit_1[251] <= 0;tag_address_1[251] <= 0;cache_block_1[251] <= 0;lru_counter_1[251] <= 0;valid_bit_2[251]  <=   0;dirty_bit_2[251] <= 0;tag_address_2[251] <= 0;cache_block_2[251] <= 0;lru_counter_2[251] <= 0;
        valid_bit_1[252]  <=   0;dirty_bit_1[252] <= 0;tag_address_1[252] <= 0;cache_block_1[252] <= 0;lru_counter_1[252] <= 0;valid_bit_2[252]  <=   0;dirty_bit_2[252] <= 0;tag_address_2[252] <= 0;cache_block_2[252] <= 0;lru_counter_2[252] <= 0;
        valid_bit_1[253]  <=   0;dirty_bit_1[253] <= 0;tag_address_1[253] <= 0;cache_block_1[253] <= 0;lru_counter_1[253] <= 0;valid_bit_2[253]  <=   0;dirty_bit_2[253] <= 0;tag_address_2[253] <= 0;cache_block_2[253] <= 0;lru_counter_2[253] <= 0;
        valid_bit_1[254]  <=   0;dirty_bit_1[254] <= 0;tag_address_1[254] <= 0;cache_block_1[254] <= 0;lru_counter_1[254] <= 0;valid_bit_2[254]  <=   0;dirty_bit_2[254] <= 0;tag_address_2[254] <= 0;cache_block_2[254] <= 0;lru_counter_2[254] <= 0;
        valid_bit_1[255]  <=   0;dirty_bit_1[255] <= 0;tag_address_1[255] <= 0;cache_block_1[255] <= 0;lru_counter_1[255] <= 0;valid_bit_2[255]  <=   0;dirty_bit_2[255] <= 0;tag_address_2[255] <= 0;cache_block_2[255] <= 0;lru_counter_2[255] <= 0;
        valid_bit_1[256]  <=   0;dirty_bit_1[256] <= 0;tag_address_1[256] <= 0;cache_block_1[256] <= 0;lru_counter_1[256] <= 0;valid_bit_2[256]  <=   0;dirty_bit_2[256] <= 0;tag_address_2[256] <= 0;cache_block_2[256] <= 0;lru_counter_2[256] <= 0;
        valid_bit_1[257]  <=   0;dirty_bit_1[257] <= 0;tag_address_1[257] <= 0;cache_block_1[257] <= 0;lru_counter_1[257] <= 0;valid_bit_2[257]  <=   0;dirty_bit_2[257] <= 0;tag_address_2[257] <= 0;cache_block_2[257] <= 0;lru_counter_2[257] <= 0;
        valid_bit_1[258]  <=   0;dirty_bit_1[258] <= 0;tag_address_1[258] <= 0;cache_block_1[258] <= 0;lru_counter_1[258] <= 0;valid_bit_2[258]  <=   0;dirty_bit_2[258] <= 0;tag_address_2[258] <= 0;cache_block_2[258] <= 0;lru_counter_2[258] <= 0;
        valid_bit_1[259]  <=   0;dirty_bit_1[259] <= 0;tag_address_1[259] <= 0;cache_block_1[259] <= 0;lru_counter_1[259] <= 0;valid_bit_2[259]  <=   0;dirty_bit_2[259] <= 0;tag_address_2[259] <= 0;cache_block_2[259] <= 0;lru_counter_2[259] <= 0;
        valid_bit_1[260]  <=   0;dirty_bit_1[260] <= 0;tag_address_1[260] <= 0;cache_block_1[260] <= 0;lru_counter_1[260] <= 0;valid_bit_2[260]  <=   0;dirty_bit_2[260] <= 0;tag_address_2[260] <= 0;cache_block_2[260] <= 0;lru_counter_2[260] <= 0;
        valid_bit_1[261]  <=   0;dirty_bit_1[261] <= 0;tag_address_1[261] <= 0;cache_block_1[261] <= 0;lru_counter_1[261] <= 0;valid_bit_2[261]  <=   0;dirty_bit_2[261] <= 0;tag_address_2[261] <= 0;cache_block_2[261] <= 0;lru_counter_2[261] <= 0;
        valid_bit_1[262]  <=   0;dirty_bit_1[262] <= 0;tag_address_1[262] <= 0;cache_block_1[262] <= 0;lru_counter_1[262] <= 0;valid_bit_2[262]  <=   0;dirty_bit_2[262] <= 0;tag_address_2[262] <= 0;cache_block_2[262] <= 0;lru_counter_2[262] <= 0;
        valid_bit_1[263]  <=   0;dirty_bit_1[263] <= 0;tag_address_1[263] <= 0;cache_block_1[263] <= 0;lru_counter_1[263] <= 0;valid_bit_2[263]  <=   0;dirty_bit_2[263] <= 0;tag_address_2[263] <= 0;cache_block_2[263] <= 0;lru_counter_2[263] <= 0;
        valid_bit_1[264]  <=   0;dirty_bit_1[264] <= 0;tag_address_1[264] <= 0;cache_block_1[264] <= 0;lru_counter_1[264] <= 0;valid_bit_2[264]  <=   0;dirty_bit_2[264] <= 0;tag_address_2[264] <= 0;cache_block_2[264] <= 0;lru_counter_2[264] <= 0;
        valid_bit_1[265]  <=   0;dirty_bit_1[265] <= 0;tag_address_1[265] <= 0;cache_block_1[265] <= 0;lru_counter_1[265] <= 0;valid_bit_2[265]  <=   0;dirty_bit_2[265] <= 0;tag_address_2[265] <= 0;cache_block_2[265] <= 0;lru_counter_2[265] <= 0;
        valid_bit_1[266]  <=   0;dirty_bit_1[266] <= 0;tag_address_1[266] <= 0;cache_block_1[266] <= 0;lru_counter_1[266] <= 0;valid_bit_2[266]  <=   0;dirty_bit_2[266] <= 0;tag_address_2[266] <= 0;cache_block_2[266] <= 0;lru_counter_2[266] <= 0;
        valid_bit_1[267]  <=   0;dirty_bit_1[267] <= 0;tag_address_1[267] <= 0;cache_block_1[267] <= 0;lru_counter_1[267] <= 0;valid_bit_2[267]  <=   0;dirty_bit_2[267] <= 0;tag_address_2[267] <= 0;cache_block_2[267] <= 0;lru_counter_2[267] <= 0;
        valid_bit_1[268]  <=   0;dirty_bit_1[268] <= 0;tag_address_1[268] <= 0;cache_block_1[268] <= 0;lru_counter_1[268] <= 0;valid_bit_2[268]  <=   0;dirty_bit_2[268] <= 0;tag_address_2[268] <= 0;cache_block_2[268] <= 0;lru_counter_2[268] <= 0;
        valid_bit_1[269]  <=   0;dirty_bit_1[269] <= 0;tag_address_1[269] <= 0;cache_block_1[269] <= 0;lru_counter_1[269] <= 0;valid_bit_2[269]  <=   0;dirty_bit_2[269] <= 0;tag_address_2[269] <= 0;cache_block_2[269] <= 0;lru_counter_2[269] <= 0;
        valid_bit_1[270]  <=   0;dirty_bit_1[270] <= 0;tag_address_1[270] <= 0;cache_block_1[270] <= 0;lru_counter_1[270] <= 0;valid_bit_2[270]  <=   0;dirty_bit_2[270] <= 0;tag_address_2[270] <= 0;cache_block_2[270] <= 0;lru_counter_2[270] <= 0;
        valid_bit_1[271]  <=   0;dirty_bit_1[271] <= 0;tag_address_1[271] <= 0;cache_block_1[271] <= 0;lru_counter_1[271] <= 0;valid_bit_2[271]  <=   0;dirty_bit_2[271] <= 0;tag_address_2[271] <= 0;cache_block_2[271] <= 0;lru_counter_2[271] <= 0;
        valid_bit_1[272]  <=   0;dirty_bit_1[272] <= 0;tag_address_1[272] <= 0;cache_block_1[272] <= 0;lru_counter_1[272] <= 0;valid_bit_2[272]  <=   0;dirty_bit_2[272] <= 0;tag_address_2[272] <= 0;cache_block_2[272] <= 0;lru_counter_2[272] <= 0;
        valid_bit_1[273]  <=   0;dirty_bit_1[273] <= 0;tag_address_1[273] <= 0;cache_block_1[273] <= 0;lru_counter_1[273] <= 0;valid_bit_2[273]  <=   0;dirty_bit_2[273] <= 0;tag_address_2[273] <= 0;cache_block_2[273] <= 0;lru_counter_2[273] <= 0;
        valid_bit_1[274]  <=   0;dirty_bit_1[274] <= 0;tag_address_1[274] <= 0;cache_block_1[274] <= 0;lru_counter_1[274] <= 0;valid_bit_2[274]  <=   0;dirty_bit_2[274] <= 0;tag_address_2[274] <= 0;cache_block_2[274] <= 0;lru_counter_2[274] <= 0;
        valid_bit_1[275]  <=   0;dirty_bit_1[275] <= 0;tag_address_1[275] <= 0;cache_block_1[275] <= 0;lru_counter_1[275] <= 0;valid_bit_2[275]  <=   0;dirty_bit_2[275] <= 0;tag_address_2[275] <= 0;cache_block_2[275] <= 0;lru_counter_2[275] <= 0;
        valid_bit_1[276]  <=   0;dirty_bit_1[276] <= 0;tag_address_1[276] <= 0;cache_block_1[276] <= 0;lru_counter_1[276] <= 0;valid_bit_2[276]  <=   0;dirty_bit_2[276] <= 0;tag_address_2[276] <= 0;cache_block_2[276] <= 0;lru_counter_2[276] <= 0;
        valid_bit_1[277]  <=   0;dirty_bit_1[277] <= 0;tag_address_1[277] <= 0;cache_block_1[277] <= 0;lru_counter_1[277] <= 0;valid_bit_2[277]  <=   0;dirty_bit_2[277] <= 0;tag_address_2[277] <= 0;cache_block_2[277] <= 0;lru_counter_2[277] <= 0;
        valid_bit_1[278]  <=   0;dirty_bit_1[278] <= 0;tag_address_1[278] <= 0;cache_block_1[278] <= 0;lru_counter_1[278] <= 0;valid_bit_2[278]  <=   0;dirty_bit_2[278] <= 0;tag_address_2[278] <= 0;cache_block_2[278] <= 0;lru_counter_2[278] <= 0;
        valid_bit_1[279]  <=   0;dirty_bit_1[279] <= 0;tag_address_1[279] <= 0;cache_block_1[279] <= 0;lru_counter_1[279] <= 0;valid_bit_2[279]  <=   0;dirty_bit_2[279] <= 0;tag_address_2[279] <= 0;cache_block_2[279] <= 0;lru_counter_2[279] <= 0;
        valid_bit_1[280]  <=   0;dirty_bit_1[280] <= 0;tag_address_1[280] <= 0;cache_block_1[280] <= 0;lru_counter_1[280] <= 0;valid_bit_2[280]  <=   0;dirty_bit_2[280] <= 0;tag_address_2[280] <= 0;cache_block_2[280] <= 0;lru_counter_2[280] <= 0;
        valid_bit_1[281]  <=   0;dirty_bit_1[281] <= 0;tag_address_1[281] <= 0;cache_block_1[281] <= 0;lru_counter_1[281] <= 0;valid_bit_2[281]  <=   0;dirty_bit_2[281] <= 0;tag_address_2[281] <= 0;cache_block_2[281] <= 0;lru_counter_2[281] <= 0;
        valid_bit_1[282]  <=   0;dirty_bit_1[282] <= 0;tag_address_1[282] <= 0;cache_block_1[282] <= 0;lru_counter_1[282] <= 0;valid_bit_2[282]  <=   0;dirty_bit_2[282] <= 0;tag_address_2[282] <= 0;cache_block_2[282] <= 0;lru_counter_2[282] <= 0;
        valid_bit_1[283]  <=   0;dirty_bit_1[283] <= 0;tag_address_1[283] <= 0;cache_block_1[283] <= 0;lru_counter_1[283] <= 0;valid_bit_2[283]  <=   0;dirty_bit_2[283] <= 0;tag_address_2[283] <= 0;cache_block_2[283] <= 0;lru_counter_2[283] <= 0;
        valid_bit_1[284]  <=   0;dirty_bit_1[284] <= 0;tag_address_1[284] <= 0;cache_block_1[284] <= 0;lru_counter_1[284] <= 0;valid_bit_2[284]  <=   0;dirty_bit_2[284] <= 0;tag_address_2[284] <= 0;cache_block_2[284] <= 0;lru_counter_2[284] <= 0;
        valid_bit_1[285]  <=   0;dirty_bit_1[285] <= 0;tag_address_1[285] <= 0;cache_block_1[285] <= 0;lru_counter_1[285] <= 0;valid_bit_2[285]  <=   0;dirty_bit_2[285] <= 0;tag_address_2[285] <= 0;cache_block_2[285] <= 0;lru_counter_2[285] <= 0;
        valid_bit_1[286]  <=   0;dirty_bit_1[286] <= 0;tag_address_1[286] <= 0;cache_block_1[286] <= 0;lru_counter_1[286] <= 0;valid_bit_2[286]  <=   0;dirty_bit_2[286] <= 0;tag_address_2[286] <= 0;cache_block_2[286] <= 0;lru_counter_2[286] <= 0;
        valid_bit_1[287]  <=   0;dirty_bit_1[287] <= 0;tag_address_1[287] <= 0;cache_block_1[287] <= 0;lru_counter_1[287] <= 0;valid_bit_2[287]  <=   0;dirty_bit_2[287] <= 0;tag_address_2[287] <= 0;cache_block_2[287] <= 0;lru_counter_2[287] <= 0;
        valid_bit_1[288]  <=   0;dirty_bit_1[288] <= 0;tag_address_1[288] <= 0;cache_block_1[288] <= 0;lru_counter_1[288] <= 0;valid_bit_2[288]  <=   0;dirty_bit_2[288] <= 0;tag_address_2[288] <= 0;cache_block_2[288] <= 0;lru_counter_2[288] <= 0;
        valid_bit_1[289]  <=   0;dirty_bit_1[289] <= 0;tag_address_1[289] <= 0;cache_block_1[289] <= 0;lru_counter_1[289] <= 0;valid_bit_2[289]  <=   0;dirty_bit_2[289] <= 0;tag_address_2[289] <= 0;cache_block_2[289] <= 0;lru_counter_2[289] <= 0;
        valid_bit_1[290]  <=   0;dirty_bit_1[290] <= 0;tag_address_1[290] <= 0;cache_block_1[290] <= 0;lru_counter_1[290] <= 0;valid_bit_2[290]  <=   0;dirty_bit_2[290] <= 0;tag_address_2[290] <= 0;cache_block_2[290] <= 0;lru_counter_2[290] <= 0;
        valid_bit_1[291]  <=   0;dirty_bit_1[291] <= 0;tag_address_1[291] <= 0;cache_block_1[291] <= 0;lru_counter_1[291] <= 0;valid_bit_2[291]  <=   0;dirty_bit_2[291] <= 0;tag_address_2[291] <= 0;cache_block_2[291] <= 0;lru_counter_2[291] <= 0;
        valid_bit_1[292]  <=   0;dirty_bit_1[292] <= 0;tag_address_1[292] <= 0;cache_block_1[292] <= 0;lru_counter_1[292] <= 0;valid_bit_2[292]  <=   0;dirty_bit_2[292] <= 0;tag_address_2[292] <= 0;cache_block_2[292] <= 0;lru_counter_2[292] <= 0;
        valid_bit_1[293]  <=   0;dirty_bit_1[293] <= 0;tag_address_1[293] <= 0;cache_block_1[293] <= 0;lru_counter_1[293] <= 0;valid_bit_2[293]  <=   0;dirty_bit_2[293] <= 0;tag_address_2[293] <= 0;cache_block_2[293] <= 0;lru_counter_2[293] <= 0;
        valid_bit_1[294]  <=   0;dirty_bit_1[294] <= 0;tag_address_1[294] <= 0;cache_block_1[294] <= 0;lru_counter_1[294] <= 0;valid_bit_2[294]  <=   0;dirty_bit_2[294] <= 0;tag_address_2[294] <= 0;cache_block_2[294] <= 0;lru_counter_2[294] <= 0;
        valid_bit_1[295]  <=   0;dirty_bit_1[295] <= 0;tag_address_1[295] <= 0;cache_block_1[295] <= 0;lru_counter_1[295] <= 0;valid_bit_2[295]  <=   0;dirty_bit_2[295] <= 0;tag_address_2[295] <= 0;cache_block_2[295] <= 0;lru_counter_2[295] <= 0;
        valid_bit_1[296]  <=   0;dirty_bit_1[296] <= 0;tag_address_1[296] <= 0;cache_block_1[296] <= 0;lru_counter_1[296] <= 0;valid_bit_2[296]  <=   0;dirty_bit_2[296] <= 0;tag_address_2[296] <= 0;cache_block_2[296] <= 0;lru_counter_2[296] <= 0;
        valid_bit_1[297]  <=   0;dirty_bit_1[297] <= 0;tag_address_1[297] <= 0;cache_block_1[297] <= 0;lru_counter_1[297] <= 0;valid_bit_2[297]  <=   0;dirty_bit_2[297] <= 0;tag_address_2[297] <= 0;cache_block_2[297] <= 0;lru_counter_2[297] <= 0;
        valid_bit_1[298]  <=   0;dirty_bit_1[298] <= 0;tag_address_1[298] <= 0;cache_block_1[298] <= 0;lru_counter_1[298] <= 0;valid_bit_2[298]  <=   0;dirty_bit_2[298] <= 0;tag_address_2[298] <= 0;cache_block_2[298] <= 0;lru_counter_2[298] <= 0;
        valid_bit_1[299]  <=   0;dirty_bit_1[299] <= 0;tag_address_1[299] <= 0;cache_block_1[299] <= 0;lru_counter_1[299] <= 0;valid_bit_2[299]  <=   0;dirty_bit_2[299] <= 0;tag_address_2[299] <= 0;cache_block_2[299] <= 0;lru_counter_2[299] <= 0;
        valid_bit_1[300]  <=   0;dirty_bit_1[300] <= 0;tag_address_1[300] <= 0;cache_block_1[300] <= 0;lru_counter_1[300] <= 0;valid_bit_2[300]  <=   0;dirty_bit_2[300] <= 0;tag_address_2[300] <= 0;cache_block_2[300] <= 0;lru_counter_2[300] <= 0;
        valid_bit_1[301]  <=   0;dirty_bit_1[301] <= 0;tag_address_1[301] <= 0;cache_block_1[301] <= 0;lru_counter_1[301] <= 0;valid_bit_2[301]  <=   0;dirty_bit_2[301] <= 0;tag_address_2[301] <= 0;cache_block_2[301] <= 0;lru_counter_2[301] <= 0;
        valid_bit_1[302]  <=   0;dirty_bit_1[302] <= 0;tag_address_1[302] <= 0;cache_block_1[302] <= 0;lru_counter_1[302] <= 0;valid_bit_2[302]  <=   0;dirty_bit_2[302] <= 0;tag_address_2[302] <= 0;cache_block_2[302] <= 0;lru_counter_2[302] <= 0;
        valid_bit_1[303]  <=   0;dirty_bit_1[303] <= 0;tag_address_1[303] <= 0;cache_block_1[303] <= 0;lru_counter_1[303] <= 0;valid_bit_2[303]  <=   0;dirty_bit_2[303] <= 0;tag_address_2[303] <= 0;cache_block_2[303] <= 0;lru_counter_2[303] <= 0;
        valid_bit_1[304]  <=   0;dirty_bit_1[304] <= 0;tag_address_1[304] <= 0;cache_block_1[304] <= 0;lru_counter_1[304] <= 0;valid_bit_2[304]  <=   0;dirty_bit_2[304] <= 0;tag_address_2[304] <= 0;cache_block_2[304] <= 0;lru_counter_2[304] <= 0;
        valid_bit_1[305]  <=   0;dirty_bit_1[305] <= 0;tag_address_1[305] <= 0;cache_block_1[305] <= 0;lru_counter_1[305] <= 0;valid_bit_2[305]  <=   0;dirty_bit_2[305] <= 0;tag_address_2[305] <= 0;cache_block_2[305] <= 0;lru_counter_2[305] <= 0;
        valid_bit_1[306]  <=   0;dirty_bit_1[306] <= 0;tag_address_1[306] <= 0;cache_block_1[306] <= 0;lru_counter_1[306] <= 0;valid_bit_2[306]  <=   0;dirty_bit_2[306] <= 0;tag_address_2[306] <= 0;cache_block_2[306] <= 0;lru_counter_2[306] <= 0;
        valid_bit_1[307]  <=   0;dirty_bit_1[307] <= 0;tag_address_1[307] <= 0;cache_block_1[307] <= 0;lru_counter_1[307] <= 0;valid_bit_2[307]  <=   0;dirty_bit_2[307] <= 0;tag_address_2[307] <= 0;cache_block_2[307] <= 0;lru_counter_2[307] <= 0;
        valid_bit_1[308]  <=   0;dirty_bit_1[308] <= 0;tag_address_1[308] <= 0;cache_block_1[308] <= 0;lru_counter_1[308] <= 0;valid_bit_2[308]  <=   0;dirty_bit_2[308] <= 0;tag_address_2[308] <= 0;cache_block_2[308] <= 0;lru_counter_2[308] <= 0;
        valid_bit_1[309]  <=   0;dirty_bit_1[309] <= 0;tag_address_1[309] <= 0;cache_block_1[309] <= 0;lru_counter_1[309] <= 0;valid_bit_2[309]  <=   0;dirty_bit_2[309] <= 0;tag_address_2[309] <= 0;cache_block_2[309] <= 0;lru_counter_2[309] <= 0;
        valid_bit_1[310]  <=   0;dirty_bit_1[310] <= 0;tag_address_1[310] <= 0;cache_block_1[310] <= 0;lru_counter_1[310] <= 0;valid_bit_2[310]  <=   0;dirty_bit_2[310] <= 0;tag_address_2[310] <= 0;cache_block_2[310] <= 0;lru_counter_2[310] <= 0;
        valid_bit_1[311]  <=   0;dirty_bit_1[311] <= 0;tag_address_1[311] <= 0;cache_block_1[311] <= 0;lru_counter_1[311] <= 0;valid_bit_2[311]  <=   0;dirty_bit_2[311] <= 0;tag_address_2[311] <= 0;cache_block_2[311] <= 0;lru_counter_2[311] <= 0;
        valid_bit_1[312]  <=   0;dirty_bit_1[312] <= 0;tag_address_1[312] <= 0;cache_block_1[312] <= 0;lru_counter_1[312] <= 0;valid_bit_2[312]  <=   0;dirty_bit_2[312] <= 0;tag_address_2[312] <= 0;cache_block_2[312] <= 0;lru_counter_2[312] <= 0;
        valid_bit_1[313]  <=   0;dirty_bit_1[313] <= 0;tag_address_1[313] <= 0;cache_block_1[313] <= 0;lru_counter_1[313] <= 0;valid_bit_2[313]  <=   0;dirty_bit_2[313] <= 0;tag_address_2[313] <= 0;cache_block_2[313] <= 0;lru_counter_2[313] <= 0;
        valid_bit_1[314]  <=   0;dirty_bit_1[314] <= 0;tag_address_1[314] <= 0;cache_block_1[314] <= 0;lru_counter_1[314] <= 0;valid_bit_2[314]  <=   0;dirty_bit_2[314] <= 0;tag_address_2[314] <= 0;cache_block_2[314] <= 0;lru_counter_2[314] <= 0;
        valid_bit_1[315]  <=   0;dirty_bit_1[315] <= 0;tag_address_1[315] <= 0;cache_block_1[315] <= 0;lru_counter_1[315] <= 0;valid_bit_2[315]  <=   0;dirty_bit_2[315] <= 0;tag_address_2[315] <= 0;cache_block_2[315] <= 0;lru_counter_2[315] <= 0;
        valid_bit_1[316]  <=   0;dirty_bit_1[316] <= 0;tag_address_1[316] <= 0;cache_block_1[316] <= 0;lru_counter_1[316] <= 0;valid_bit_2[316]  <=   0;dirty_bit_2[316] <= 0;tag_address_2[316] <= 0;cache_block_2[316] <= 0;lru_counter_2[316] <= 0;
        valid_bit_1[317]  <=   0;dirty_bit_1[317] <= 0;tag_address_1[317] <= 0;cache_block_1[317] <= 0;lru_counter_1[317] <= 0;valid_bit_2[317]  <=   0;dirty_bit_2[317] <= 0;tag_address_2[317] <= 0;cache_block_2[317] <= 0;lru_counter_2[317] <= 0;
        valid_bit_1[318]  <=   0;dirty_bit_1[318] <= 0;tag_address_1[318] <= 0;cache_block_1[318] <= 0;lru_counter_1[318] <= 0;valid_bit_2[318]  <=   0;dirty_bit_2[318] <= 0;tag_address_2[318] <= 0;cache_block_2[318] <= 0;lru_counter_2[318] <= 0;
        valid_bit_1[319]  <=   0;dirty_bit_1[319] <= 0;tag_address_1[319] <= 0;cache_block_1[319] <= 0;lru_counter_1[319] <= 0;valid_bit_2[319]  <=   0;dirty_bit_2[319] <= 0;tag_address_2[319] <= 0;cache_block_2[319] <= 0;lru_counter_2[319] <= 0;
        valid_bit_1[320]  <=   0;dirty_bit_1[320] <= 0;tag_address_1[320] <= 0;cache_block_1[320] <= 0;lru_counter_1[320] <= 0;valid_bit_2[320]  <=   0;dirty_bit_2[320] <= 0;tag_address_2[320] <= 0;cache_block_2[320] <= 0;lru_counter_2[320] <= 0;
        valid_bit_1[321]  <=   0;dirty_bit_1[321] <= 0;tag_address_1[321] <= 0;cache_block_1[321] <= 0;lru_counter_1[321] <= 0;valid_bit_2[321]  <=   0;dirty_bit_2[321] <= 0;tag_address_2[321] <= 0;cache_block_2[321] <= 0;lru_counter_2[321] <= 0;
        valid_bit_1[322]  <=   0;dirty_bit_1[322] <= 0;tag_address_1[322] <= 0;cache_block_1[322] <= 0;lru_counter_1[322] <= 0;valid_bit_2[322]  <=   0;dirty_bit_2[322] <= 0;tag_address_2[322] <= 0;cache_block_2[322] <= 0;lru_counter_2[322] <= 0;
        valid_bit_1[323]  <=   0;dirty_bit_1[323] <= 0;tag_address_1[323] <= 0;cache_block_1[323] <= 0;lru_counter_1[323] <= 0;valid_bit_2[323]  <=   0;dirty_bit_2[323] <= 0;tag_address_2[323] <= 0;cache_block_2[323] <= 0;lru_counter_2[323] <= 0;
        valid_bit_1[324]  <=   0;dirty_bit_1[324] <= 0;tag_address_1[324] <= 0;cache_block_1[324] <= 0;lru_counter_1[324] <= 0;valid_bit_2[324]  <=   0;dirty_bit_2[324] <= 0;tag_address_2[324] <= 0;cache_block_2[324] <= 0;lru_counter_2[324] <= 0;
        valid_bit_1[325]  <=   0;dirty_bit_1[325] <= 0;tag_address_1[325] <= 0;cache_block_1[325] <= 0;lru_counter_1[325] <= 0;valid_bit_2[325]  <=   0;dirty_bit_2[325] <= 0;tag_address_2[325] <= 0;cache_block_2[325] <= 0;lru_counter_2[325] <= 0;
        valid_bit_1[326]  <=   0;dirty_bit_1[326] <= 0;tag_address_1[326] <= 0;cache_block_1[326] <= 0;lru_counter_1[326] <= 0;valid_bit_2[326]  <=   0;dirty_bit_2[326] <= 0;tag_address_2[326] <= 0;cache_block_2[326] <= 0;lru_counter_2[326] <= 0;
        valid_bit_1[327]  <=   0;dirty_bit_1[327] <= 0;tag_address_1[327] <= 0;cache_block_1[327] <= 0;lru_counter_1[327] <= 0;valid_bit_2[327]  <=   0;dirty_bit_2[327] <= 0;tag_address_2[327] <= 0;cache_block_2[327] <= 0;lru_counter_2[327] <= 0;
        valid_bit_1[328]  <=   0;dirty_bit_1[328] <= 0;tag_address_1[328] <= 0;cache_block_1[328] <= 0;lru_counter_1[328] <= 0;valid_bit_2[328]  <=   0;dirty_bit_2[328] <= 0;tag_address_2[328] <= 0;cache_block_2[328] <= 0;lru_counter_2[328] <= 0;
        valid_bit_1[329]  <=   0;dirty_bit_1[329] <= 0;tag_address_1[329] <= 0;cache_block_1[329] <= 0;lru_counter_1[329] <= 0;valid_bit_2[329]  <=   0;dirty_bit_2[329] <= 0;tag_address_2[329] <= 0;cache_block_2[329] <= 0;lru_counter_2[329] <= 0;
        valid_bit_1[330]  <=   0;dirty_bit_1[330] <= 0;tag_address_1[330] <= 0;cache_block_1[330] <= 0;lru_counter_1[330] <= 0;valid_bit_2[330]  <=   0;dirty_bit_2[330] <= 0;tag_address_2[330] <= 0;cache_block_2[330] <= 0;lru_counter_2[330] <= 0;
        valid_bit_1[331]  <=   0;dirty_bit_1[331] <= 0;tag_address_1[331] <= 0;cache_block_1[331] <= 0;lru_counter_1[331] <= 0;valid_bit_2[331]  <=   0;dirty_bit_2[331] <= 0;tag_address_2[331] <= 0;cache_block_2[331] <= 0;lru_counter_2[331] <= 0;
        valid_bit_1[332]  <=   0;dirty_bit_1[332] <= 0;tag_address_1[332] <= 0;cache_block_1[332] <= 0;lru_counter_1[332] <= 0;valid_bit_2[332]  <=   0;dirty_bit_2[332] <= 0;tag_address_2[332] <= 0;cache_block_2[332] <= 0;lru_counter_2[332] <= 0;
        valid_bit_1[333]  <=   0;dirty_bit_1[333] <= 0;tag_address_1[333] <= 0;cache_block_1[333] <= 0;lru_counter_1[333] <= 0;valid_bit_2[333]  <=   0;dirty_bit_2[333] <= 0;tag_address_2[333] <= 0;cache_block_2[333] <= 0;lru_counter_2[333] <= 0;
        valid_bit_1[334]  <=   0;dirty_bit_1[334] <= 0;tag_address_1[334] <= 0;cache_block_1[334] <= 0;lru_counter_1[334] <= 0;valid_bit_2[334]  <=   0;dirty_bit_2[334] <= 0;tag_address_2[334] <= 0;cache_block_2[334] <= 0;lru_counter_2[334] <= 0;
        valid_bit_1[335]  <=   0;dirty_bit_1[335] <= 0;tag_address_1[335] <= 0;cache_block_1[335] <= 0;lru_counter_1[335] <= 0;valid_bit_2[335]  <=   0;dirty_bit_2[335] <= 0;tag_address_2[335] <= 0;cache_block_2[335] <= 0;lru_counter_2[335] <= 0;
        valid_bit_1[336]  <=   0;dirty_bit_1[336] <= 0;tag_address_1[336] <= 0;cache_block_1[336] <= 0;lru_counter_1[336] <= 0;valid_bit_2[336]  <=   0;dirty_bit_2[336] <= 0;tag_address_2[336] <= 0;cache_block_2[336] <= 0;lru_counter_2[336] <= 0;
        valid_bit_1[337]  <=   0;dirty_bit_1[337] <= 0;tag_address_1[337] <= 0;cache_block_1[337] <= 0;lru_counter_1[337] <= 0;valid_bit_2[337]  <=   0;dirty_bit_2[337] <= 0;tag_address_2[337] <= 0;cache_block_2[337] <= 0;lru_counter_2[337] <= 0;
        valid_bit_1[338]  <=   0;dirty_bit_1[338] <= 0;tag_address_1[338] <= 0;cache_block_1[338] <= 0;lru_counter_1[338] <= 0;valid_bit_2[338]  <=   0;dirty_bit_2[338] <= 0;tag_address_2[338] <= 0;cache_block_2[338] <= 0;lru_counter_2[338] <= 0;
        valid_bit_1[339]  <=   0;dirty_bit_1[339] <= 0;tag_address_1[339] <= 0;cache_block_1[339] <= 0;lru_counter_1[339] <= 0;valid_bit_2[339]  <=   0;dirty_bit_2[339] <= 0;tag_address_2[339] <= 0;cache_block_2[339] <= 0;lru_counter_2[339] <= 0;
        valid_bit_1[340]  <=   0;dirty_bit_1[340] <= 0;tag_address_1[340] <= 0;cache_block_1[340] <= 0;lru_counter_1[340] <= 0;valid_bit_2[340]  <=   0;dirty_bit_2[340] <= 0;tag_address_2[340] <= 0;cache_block_2[340] <= 0;lru_counter_2[340] <= 0;
        valid_bit_1[341]  <=   0;dirty_bit_1[341] <= 0;tag_address_1[341] <= 0;cache_block_1[341] <= 0;lru_counter_1[341] <= 0;valid_bit_2[341]  <=   0;dirty_bit_2[341] <= 0;tag_address_2[341] <= 0;cache_block_2[341] <= 0;lru_counter_2[341] <= 0;
        valid_bit_1[342]  <=   0;dirty_bit_1[342] <= 0;tag_address_1[342] <= 0;cache_block_1[342] <= 0;lru_counter_1[342] <= 0;valid_bit_2[342]  <=   0;dirty_bit_2[342] <= 0;tag_address_2[342] <= 0;cache_block_2[342] <= 0;lru_counter_2[342] <= 0;
        valid_bit_1[343]  <=   0;dirty_bit_1[343] <= 0;tag_address_1[343] <= 0;cache_block_1[343] <= 0;lru_counter_1[343] <= 0;valid_bit_2[343]  <=   0;dirty_bit_2[343] <= 0;tag_address_2[343] <= 0;cache_block_2[343] <= 0;lru_counter_2[343] <= 0;
        valid_bit_1[344]  <=   0;dirty_bit_1[344] <= 0;tag_address_1[344] <= 0;cache_block_1[344] <= 0;lru_counter_1[344] <= 0;valid_bit_2[344]  <=   0;dirty_bit_2[344] <= 0;tag_address_2[344] <= 0;cache_block_2[344] <= 0;lru_counter_2[344] <= 0;
        valid_bit_1[345]  <=   0;dirty_bit_1[345] <= 0;tag_address_1[345] <= 0;cache_block_1[345] <= 0;lru_counter_1[345] <= 0;valid_bit_2[345]  <=   0;dirty_bit_2[345] <= 0;tag_address_2[345] <= 0;cache_block_2[345] <= 0;lru_counter_2[345] <= 0;
        valid_bit_1[346]  <=   0;dirty_bit_1[346] <= 0;tag_address_1[346] <= 0;cache_block_1[346] <= 0;lru_counter_1[346] <= 0;valid_bit_2[346]  <=   0;dirty_bit_2[346] <= 0;tag_address_2[346] <= 0;cache_block_2[346] <= 0;lru_counter_2[346] <= 0;
        valid_bit_1[347]  <=   0;dirty_bit_1[347] <= 0;tag_address_1[347] <= 0;cache_block_1[347] <= 0;lru_counter_1[347] <= 0;valid_bit_2[347]  <=   0;dirty_bit_2[347] <= 0;tag_address_2[347] <= 0;cache_block_2[347] <= 0;lru_counter_2[347] <= 0;
        valid_bit_1[348]  <=   0;dirty_bit_1[348] <= 0;tag_address_1[348] <= 0;cache_block_1[348] <= 0;lru_counter_1[348] <= 0;valid_bit_2[348]  <=   0;dirty_bit_2[348] <= 0;tag_address_2[348] <= 0;cache_block_2[348] <= 0;lru_counter_2[348] <= 0;
        valid_bit_1[349]  <=   0;dirty_bit_1[349] <= 0;tag_address_1[349] <= 0;cache_block_1[349] <= 0;lru_counter_1[349] <= 0;valid_bit_2[349]  <=   0;dirty_bit_2[349] <= 0;tag_address_2[349] <= 0;cache_block_2[349] <= 0;lru_counter_2[349] <= 0;
        valid_bit_1[350]  <=   0;dirty_bit_1[350] <= 0;tag_address_1[350] <= 0;cache_block_1[350] <= 0;lru_counter_1[350] <= 0;valid_bit_2[350]  <=   0;dirty_bit_2[350] <= 0;tag_address_2[350] <= 0;cache_block_2[350] <= 0;lru_counter_2[350] <= 0;
        valid_bit_1[351]  <=   0;dirty_bit_1[351] <= 0;tag_address_1[351] <= 0;cache_block_1[351] <= 0;lru_counter_1[351] <= 0;valid_bit_2[351]  <=   0;dirty_bit_2[351] <= 0;tag_address_2[351] <= 0;cache_block_2[351] <= 0;lru_counter_2[351] <= 0;
        valid_bit_1[352]  <=   0;dirty_bit_1[352] <= 0;tag_address_1[352] <= 0;cache_block_1[352] <= 0;lru_counter_1[352] <= 0;valid_bit_2[352]  <=   0;dirty_bit_2[352] <= 0;tag_address_2[352] <= 0;cache_block_2[352] <= 0;lru_counter_2[352] <= 0;
        valid_bit_1[353]  <=   0;dirty_bit_1[353] <= 0;tag_address_1[353] <= 0;cache_block_1[353] <= 0;lru_counter_1[353] <= 0;valid_bit_2[353]  <=   0;dirty_bit_2[353] <= 0;tag_address_2[353] <= 0;cache_block_2[353] <= 0;lru_counter_2[353] <= 0;
        valid_bit_1[354]  <=   0;dirty_bit_1[354] <= 0;tag_address_1[354] <= 0;cache_block_1[354] <= 0;lru_counter_1[354] <= 0;valid_bit_2[354]  <=   0;dirty_bit_2[354] <= 0;tag_address_2[354] <= 0;cache_block_2[354] <= 0;lru_counter_2[354] <= 0;
        valid_bit_1[355]  <=   0;dirty_bit_1[355] <= 0;tag_address_1[355] <= 0;cache_block_1[355] <= 0;lru_counter_1[355] <= 0;valid_bit_2[355]  <=   0;dirty_bit_2[355] <= 0;tag_address_2[355] <= 0;cache_block_2[355] <= 0;lru_counter_2[355] <= 0;
        valid_bit_1[356]  <=   0;dirty_bit_1[356] <= 0;tag_address_1[356] <= 0;cache_block_1[356] <= 0;lru_counter_1[356] <= 0;valid_bit_2[356]  <=   0;dirty_bit_2[356] <= 0;tag_address_2[356] <= 0;cache_block_2[356] <= 0;lru_counter_2[356] <= 0;
        valid_bit_1[357]  <=   0;dirty_bit_1[357] <= 0;tag_address_1[357] <= 0;cache_block_1[357] <= 0;lru_counter_1[357] <= 0;valid_bit_2[357]  <=   0;dirty_bit_2[357] <= 0;tag_address_2[357] <= 0;cache_block_2[357] <= 0;lru_counter_2[357] <= 0;
        valid_bit_1[358]  <=   0;dirty_bit_1[358] <= 0;tag_address_1[358] <= 0;cache_block_1[358] <= 0;lru_counter_1[358] <= 0;valid_bit_2[358]  <=   0;dirty_bit_2[358] <= 0;tag_address_2[358] <= 0;cache_block_2[358] <= 0;lru_counter_2[358] <= 0;
        valid_bit_1[359]  <=   0;dirty_bit_1[359] <= 0;tag_address_1[359] <= 0;cache_block_1[359] <= 0;lru_counter_1[359] <= 0;valid_bit_2[359]  <=   0;dirty_bit_2[359] <= 0;tag_address_2[359] <= 0;cache_block_2[359] <= 0;lru_counter_2[359] <= 0;
        valid_bit_1[360]  <=   0;dirty_bit_1[360] <= 0;tag_address_1[360] <= 0;cache_block_1[360] <= 0;lru_counter_1[360] <= 0;valid_bit_2[360]  <=   0;dirty_bit_2[360] <= 0;tag_address_2[360] <= 0;cache_block_2[360] <= 0;lru_counter_2[360] <= 0;
        valid_bit_1[361]  <=   0;dirty_bit_1[361] <= 0;tag_address_1[361] <= 0;cache_block_1[361] <= 0;lru_counter_1[361] <= 0;valid_bit_2[361]  <=   0;dirty_bit_2[361] <= 0;tag_address_2[361] <= 0;cache_block_2[361] <= 0;lru_counter_2[361] <= 0;
        valid_bit_1[362]  <=   0;dirty_bit_1[362] <= 0;tag_address_1[362] <= 0;cache_block_1[362] <= 0;lru_counter_1[362] <= 0;valid_bit_2[362]  <=   0;dirty_bit_2[362] <= 0;tag_address_2[362] <= 0;cache_block_2[362] <= 0;lru_counter_2[362] <= 0;
        valid_bit_1[363]  <=   0;dirty_bit_1[363] <= 0;tag_address_1[363] <= 0;cache_block_1[363] <= 0;lru_counter_1[363] <= 0;valid_bit_2[363]  <=   0;dirty_bit_2[363] <= 0;tag_address_2[363] <= 0;cache_block_2[363] <= 0;lru_counter_2[363] <= 0;
        valid_bit_1[364]  <=   0;dirty_bit_1[364] <= 0;tag_address_1[364] <= 0;cache_block_1[364] <= 0;lru_counter_1[364] <= 0;valid_bit_2[364]  <=   0;dirty_bit_2[364] <= 0;tag_address_2[364] <= 0;cache_block_2[364] <= 0;lru_counter_2[364] <= 0;
        valid_bit_1[365]  <=   0;dirty_bit_1[365] <= 0;tag_address_1[365] <= 0;cache_block_1[365] <= 0;lru_counter_1[365] <= 0;valid_bit_2[365]  <=   0;dirty_bit_2[365] <= 0;tag_address_2[365] <= 0;cache_block_2[365] <= 0;lru_counter_2[365] <= 0;
        valid_bit_1[366]  <=   0;dirty_bit_1[366] <= 0;tag_address_1[366] <= 0;cache_block_1[366] <= 0;lru_counter_1[366] <= 0;valid_bit_2[366]  <=   0;dirty_bit_2[366] <= 0;tag_address_2[366] <= 0;cache_block_2[366] <= 0;lru_counter_2[366] <= 0;
        valid_bit_1[367]  <=   0;dirty_bit_1[367] <= 0;tag_address_1[367] <= 0;cache_block_1[367] <= 0;lru_counter_1[367] <= 0;valid_bit_2[367]  <=   0;dirty_bit_2[367] <= 0;tag_address_2[367] <= 0;cache_block_2[367] <= 0;lru_counter_2[367] <= 0;
        valid_bit_1[368]  <=   0;dirty_bit_1[368] <= 0;tag_address_1[368] <= 0;cache_block_1[368] <= 0;lru_counter_1[368] <= 0;valid_bit_2[368]  <=   0;dirty_bit_2[368] <= 0;tag_address_2[368] <= 0;cache_block_2[368] <= 0;lru_counter_2[368] <= 0;
        valid_bit_1[369]  <=   0;dirty_bit_1[369] <= 0;tag_address_1[369] <= 0;cache_block_1[369] <= 0;lru_counter_1[369] <= 0;valid_bit_2[369]  <=   0;dirty_bit_2[369] <= 0;tag_address_2[369] <= 0;cache_block_2[369] <= 0;lru_counter_2[369] <= 0;
        valid_bit_1[370]  <=   0;dirty_bit_1[370] <= 0;tag_address_1[370] <= 0;cache_block_1[370] <= 0;lru_counter_1[370] <= 0;valid_bit_2[370]  <=   0;dirty_bit_2[370] <= 0;tag_address_2[370] <= 0;cache_block_2[370] <= 0;lru_counter_2[370] <= 0;
        valid_bit_1[371]  <=   0;dirty_bit_1[371] <= 0;tag_address_1[371] <= 0;cache_block_1[371] <= 0;lru_counter_1[371] <= 0;valid_bit_2[371]  <=   0;dirty_bit_2[371] <= 0;tag_address_2[371] <= 0;cache_block_2[371] <= 0;lru_counter_2[371] <= 0;
        valid_bit_1[372]  <=   0;dirty_bit_1[372] <= 0;tag_address_1[372] <= 0;cache_block_1[372] <= 0;lru_counter_1[372] <= 0;valid_bit_2[372]  <=   0;dirty_bit_2[372] <= 0;tag_address_2[372] <= 0;cache_block_2[372] <= 0;lru_counter_2[372] <= 0;
        valid_bit_1[373]  <=   0;dirty_bit_1[373] <= 0;tag_address_1[373] <= 0;cache_block_1[373] <= 0;lru_counter_1[373] <= 0;valid_bit_2[373]  <=   0;dirty_bit_2[373] <= 0;tag_address_2[373] <= 0;cache_block_2[373] <= 0;lru_counter_2[373] <= 0;
        valid_bit_1[374]  <=   0;dirty_bit_1[374] <= 0;tag_address_1[374] <= 0;cache_block_1[374] <= 0;lru_counter_1[374] <= 0;valid_bit_2[374]  <=   0;dirty_bit_2[374] <= 0;tag_address_2[374] <= 0;cache_block_2[374] <= 0;lru_counter_2[374] <= 0;
        valid_bit_1[375]  <=   0;dirty_bit_1[375] <= 0;tag_address_1[375] <= 0;cache_block_1[375] <= 0;lru_counter_1[375] <= 0;valid_bit_2[375]  <=   0;dirty_bit_2[375] <= 0;tag_address_2[375] <= 0;cache_block_2[375] <= 0;lru_counter_2[375] <= 0;
        valid_bit_1[376]  <=   0;dirty_bit_1[376] <= 0;tag_address_1[376] <= 0;cache_block_1[376] <= 0;lru_counter_1[376] <= 0;valid_bit_2[376]  <=   0;dirty_bit_2[376] <= 0;tag_address_2[376] <= 0;cache_block_2[376] <= 0;lru_counter_2[376] <= 0;
        valid_bit_1[377]  <=   0;dirty_bit_1[377] <= 0;tag_address_1[377] <= 0;cache_block_1[377] <= 0;lru_counter_1[377] <= 0;valid_bit_2[377]  <=   0;dirty_bit_2[377] <= 0;tag_address_2[377] <= 0;cache_block_2[377] <= 0;lru_counter_2[377] <= 0;
        valid_bit_1[378]  <=   0;dirty_bit_1[378] <= 0;tag_address_1[378] <= 0;cache_block_1[378] <= 0;lru_counter_1[378] <= 0;valid_bit_2[378]  <=   0;dirty_bit_2[378] <= 0;tag_address_2[378] <= 0;cache_block_2[378] <= 0;lru_counter_2[378] <= 0;
        valid_bit_1[379]  <=   0;dirty_bit_1[379] <= 0;tag_address_1[379] <= 0;cache_block_1[379] <= 0;lru_counter_1[379] <= 0;valid_bit_2[379]  <=   0;dirty_bit_2[379] <= 0;tag_address_2[379] <= 0;cache_block_2[379] <= 0;lru_counter_2[379] <= 0;
        valid_bit_1[380]  <=   0;dirty_bit_1[380] <= 0;tag_address_1[380] <= 0;cache_block_1[380] <= 0;lru_counter_1[380] <= 0;valid_bit_2[380]  <=   0;dirty_bit_2[380] <= 0;tag_address_2[380] <= 0;cache_block_2[380] <= 0;lru_counter_2[380] <= 0;
        valid_bit_1[381]  <=   0;dirty_bit_1[381] <= 0;tag_address_1[381] <= 0;cache_block_1[381] <= 0;lru_counter_1[381] <= 0;valid_bit_2[381]  <=   0;dirty_bit_2[381] <= 0;tag_address_2[381] <= 0;cache_block_2[381] <= 0;lru_counter_2[381] <= 0;
        valid_bit_1[382]  <=   0;dirty_bit_1[382] <= 0;tag_address_1[382] <= 0;cache_block_1[382] <= 0;lru_counter_1[382] <= 0;valid_bit_2[382]  <=   0;dirty_bit_2[382] <= 0;tag_address_2[382] <= 0;cache_block_2[382] <= 0;lru_counter_2[382] <= 0;
        valid_bit_1[383]  <=   0;dirty_bit_1[383] <= 0;tag_address_1[383] <= 0;cache_block_1[383] <= 0;lru_counter_1[383] <= 0;valid_bit_2[383]  <=   0;dirty_bit_2[383] <= 0;tag_address_2[383] <= 0;cache_block_2[383] <= 0;lru_counter_2[383] <= 0;
        valid_bit_1[384]  <=   0;dirty_bit_1[384] <= 0;tag_address_1[384] <= 0;cache_block_1[384] <= 0;lru_counter_1[384] <= 0;valid_bit_2[384]  <=   0;dirty_bit_2[384] <= 0;tag_address_2[384] <= 0;cache_block_2[384] <= 0;lru_counter_2[384] <= 0;
        valid_bit_1[385]  <=   0;dirty_bit_1[385] <= 0;tag_address_1[385] <= 0;cache_block_1[385] <= 0;lru_counter_1[385] <= 0;valid_bit_2[385]  <=   0;dirty_bit_2[385] <= 0;tag_address_2[385] <= 0;cache_block_2[385] <= 0;lru_counter_2[385] <= 0;
        valid_bit_1[386]  <=   0;dirty_bit_1[386] <= 0;tag_address_1[386] <= 0;cache_block_1[386] <= 0;lru_counter_1[386] <= 0;valid_bit_2[386]  <=   0;dirty_bit_2[386] <= 0;tag_address_2[386] <= 0;cache_block_2[386] <= 0;lru_counter_2[386] <= 0;
        valid_bit_1[387]  <=   0;dirty_bit_1[387] <= 0;tag_address_1[387] <= 0;cache_block_1[387] <= 0;lru_counter_1[387] <= 0;valid_bit_2[387]  <=   0;dirty_bit_2[387] <= 0;tag_address_2[387] <= 0;cache_block_2[387] <= 0;lru_counter_2[387] <= 0;
        valid_bit_1[388]  <=   0;dirty_bit_1[388] <= 0;tag_address_1[388] <= 0;cache_block_1[388] <= 0;lru_counter_1[388] <= 0;valid_bit_2[388]  <=   0;dirty_bit_2[388] <= 0;tag_address_2[388] <= 0;cache_block_2[388] <= 0;lru_counter_2[388] <= 0;
        valid_bit_1[389]  <=   0;dirty_bit_1[389] <= 0;tag_address_1[389] <= 0;cache_block_1[389] <= 0;lru_counter_1[389] <= 0;valid_bit_2[389]  <=   0;dirty_bit_2[389] <= 0;tag_address_2[389] <= 0;cache_block_2[389] <= 0;lru_counter_2[389] <= 0;
        valid_bit_1[390]  <=   0;dirty_bit_1[390] <= 0;tag_address_1[390] <= 0;cache_block_1[390] <= 0;lru_counter_1[390] <= 0;valid_bit_2[390]  <=   0;dirty_bit_2[390] <= 0;tag_address_2[390] <= 0;cache_block_2[390] <= 0;lru_counter_2[390] <= 0;
        valid_bit_1[391]  <=   0;dirty_bit_1[391] <= 0;tag_address_1[391] <= 0;cache_block_1[391] <= 0;lru_counter_1[391] <= 0;valid_bit_2[391]  <=   0;dirty_bit_2[391] <= 0;tag_address_2[391] <= 0;cache_block_2[391] <= 0;lru_counter_2[391] <= 0;
        valid_bit_1[392]  <=   0;dirty_bit_1[392] <= 0;tag_address_1[392] <= 0;cache_block_1[392] <= 0;lru_counter_1[392] <= 0;valid_bit_2[392]  <=   0;dirty_bit_2[392] <= 0;tag_address_2[392] <= 0;cache_block_2[392] <= 0;lru_counter_2[392] <= 0;
        valid_bit_1[393]  <=   0;dirty_bit_1[393] <= 0;tag_address_1[393] <= 0;cache_block_1[393] <= 0;lru_counter_1[393] <= 0;valid_bit_2[393]  <=   0;dirty_bit_2[393] <= 0;tag_address_2[393] <= 0;cache_block_2[393] <= 0;lru_counter_2[393] <= 0;
        valid_bit_1[394]  <=   0;dirty_bit_1[394] <= 0;tag_address_1[394] <= 0;cache_block_1[394] <= 0;lru_counter_1[394] <= 0;valid_bit_2[394]  <=   0;dirty_bit_2[394] <= 0;tag_address_2[394] <= 0;cache_block_2[394] <= 0;lru_counter_2[394] <= 0;
        valid_bit_1[395]  <=   0;dirty_bit_1[395] <= 0;tag_address_1[395] <= 0;cache_block_1[395] <= 0;lru_counter_1[395] <= 0;valid_bit_2[395]  <=   0;dirty_bit_2[395] <= 0;tag_address_2[395] <= 0;cache_block_2[395] <= 0;lru_counter_2[395] <= 0;
        valid_bit_1[396]  <=   0;dirty_bit_1[396] <= 0;tag_address_1[396] <= 0;cache_block_1[396] <= 0;lru_counter_1[396] <= 0;valid_bit_2[396]  <=   0;dirty_bit_2[396] <= 0;tag_address_2[396] <= 0;cache_block_2[396] <= 0;lru_counter_2[396] <= 0;
        valid_bit_1[397]  <=   0;dirty_bit_1[397] <= 0;tag_address_1[397] <= 0;cache_block_1[397] <= 0;lru_counter_1[397] <= 0;valid_bit_2[397]  <=   0;dirty_bit_2[397] <= 0;tag_address_2[397] <= 0;cache_block_2[397] <= 0;lru_counter_2[397] <= 0;
        valid_bit_1[398]  <=   0;dirty_bit_1[398] <= 0;tag_address_1[398] <= 0;cache_block_1[398] <= 0;lru_counter_1[398] <= 0;valid_bit_2[398]  <=   0;dirty_bit_2[398] <= 0;tag_address_2[398] <= 0;cache_block_2[398] <= 0;lru_counter_2[398] <= 0;
        valid_bit_1[399]  <=   0;dirty_bit_1[399] <= 0;tag_address_1[399] <= 0;cache_block_1[399] <= 0;lru_counter_1[399] <= 0;valid_bit_2[399]  <=   0;dirty_bit_2[399] <= 0;tag_address_2[399] <= 0;cache_block_2[399] <= 0;lru_counter_2[399] <= 0;
        valid_bit_1[400]  <=   0;dirty_bit_1[400] <= 0;tag_address_1[400] <= 0;cache_block_1[400] <= 0;lru_counter_1[400] <= 0;valid_bit_2[400]  <=   0;dirty_bit_2[400] <= 0;tag_address_2[400] <= 0;cache_block_2[400] <= 0;lru_counter_2[400] <= 0;
        valid_bit_1[401]  <=   0;dirty_bit_1[401] <= 0;tag_address_1[401] <= 0;cache_block_1[401] <= 0;lru_counter_1[401] <= 0;valid_bit_2[401]  <=   0;dirty_bit_2[401] <= 0;tag_address_2[401] <= 0;cache_block_2[401] <= 0;lru_counter_2[401] <= 0;
        valid_bit_1[402]  <=   0;dirty_bit_1[402] <= 0;tag_address_1[402] <= 0;cache_block_1[402] <= 0;lru_counter_1[402] <= 0;valid_bit_2[402]  <=   0;dirty_bit_2[402] <= 0;tag_address_2[402] <= 0;cache_block_2[402] <= 0;lru_counter_2[402] <= 0;
        valid_bit_1[403]  <=   0;dirty_bit_1[403] <= 0;tag_address_1[403] <= 0;cache_block_1[403] <= 0;lru_counter_1[403] <= 0;valid_bit_2[403]  <=   0;dirty_bit_2[403] <= 0;tag_address_2[403] <= 0;cache_block_2[403] <= 0;lru_counter_2[403] <= 0;
        valid_bit_1[404]  <=   0;dirty_bit_1[404] <= 0;tag_address_1[404] <= 0;cache_block_1[404] <= 0;lru_counter_1[404] <= 0;valid_bit_2[404]  <=   0;dirty_bit_2[404] <= 0;tag_address_2[404] <= 0;cache_block_2[404] <= 0;lru_counter_2[404] <= 0;
        valid_bit_1[405]  <=   0;dirty_bit_1[405] <= 0;tag_address_1[405] <= 0;cache_block_1[405] <= 0;lru_counter_1[405] <= 0;valid_bit_2[405]  <=   0;dirty_bit_2[405] <= 0;tag_address_2[405] <= 0;cache_block_2[405] <= 0;lru_counter_2[405] <= 0;
        valid_bit_1[406]  <=   0;dirty_bit_1[406] <= 0;tag_address_1[406] <= 0;cache_block_1[406] <= 0;lru_counter_1[406] <= 0;valid_bit_2[406]  <=   0;dirty_bit_2[406] <= 0;tag_address_2[406] <= 0;cache_block_2[406] <= 0;lru_counter_2[406] <= 0;
        valid_bit_1[407]  <=   0;dirty_bit_1[407] <= 0;tag_address_1[407] <= 0;cache_block_1[407] <= 0;lru_counter_1[407] <= 0;valid_bit_2[407]  <=   0;dirty_bit_2[407] <= 0;tag_address_2[407] <= 0;cache_block_2[407] <= 0;lru_counter_2[407] <= 0;
        valid_bit_1[408]  <=   0;dirty_bit_1[408] <= 0;tag_address_1[408] <= 0;cache_block_1[408] <= 0;lru_counter_1[408] <= 0;valid_bit_2[408]  <=   0;dirty_bit_2[408] <= 0;tag_address_2[408] <= 0;cache_block_2[408] <= 0;lru_counter_2[408] <= 0;
        valid_bit_1[409]  <=   0;dirty_bit_1[409] <= 0;tag_address_1[409] <= 0;cache_block_1[409] <= 0;lru_counter_1[409] <= 0;valid_bit_2[409]  <=   0;dirty_bit_2[409] <= 0;tag_address_2[409] <= 0;cache_block_2[409] <= 0;lru_counter_2[409] <= 0;
        valid_bit_1[410]  <=   0;dirty_bit_1[410] <= 0;tag_address_1[410] <= 0;cache_block_1[410] <= 0;lru_counter_1[410] <= 0;valid_bit_2[410]  <=   0;dirty_bit_2[410] <= 0;tag_address_2[410] <= 0;cache_block_2[410] <= 0;lru_counter_2[410] <= 0;
        valid_bit_1[411]  <=   0;dirty_bit_1[411] <= 0;tag_address_1[411] <= 0;cache_block_1[411] <= 0;lru_counter_1[411] <= 0;valid_bit_2[411]  <=   0;dirty_bit_2[411] <= 0;tag_address_2[411] <= 0;cache_block_2[411] <= 0;lru_counter_2[411] <= 0;
        valid_bit_1[412]  <=   0;dirty_bit_1[412] <= 0;tag_address_1[412] <= 0;cache_block_1[412] <= 0;lru_counter_1[412] <= 0;valid_bit_2[412]  <=   0;dirty_bit_2[412] <= 0;tag_address_2[412] <= 0;cache_block_2[412] <= 0;lru_counter_2[412] <= 0;
        valid_bit_1[413]  <=   0;dirty_bit_1[413] <= 0;tag_address_1[413] <= 0;cache_block_1[413] <= 0;lru_counter_1[413] <= 0;valid_bit_2[413]  <=   0;dirty_bit_2[413] <= 0;tag_address_2[413] <= 0;cache_block_2[413] <= 0;lru_counter_2[413] <= 0;
        valid_bit_1[414]  <=   0;dirty_bit_1[414] <= 0;tag_address_1[414] <= 0;cache_block_1[414] <= 0;lru_counter_1[414] <= 0;valid_bit_2[414]  <=   0;dirty_bit_2[414] <= 0;tag_address_2[414] <= 0;cache_block_2[414] <= 0;lru_counter_2[414] <= 0;
        valid_bit_1[415]  <=   0;dirty_bit_1[415] <= 0;tag_address_1[415] <= 0;cache_block_1[415] <= 0;lru_counter_1[415] <= 0;valid_bit_2[415]  <=   0;dirty_bit_2[415] <= 0;tag_address_2[415] <= 0;cache_block_2[415] <= 0;lru_counter_2[415] <= 0;
        valid_bit_1[416]  <=   0;dirty_bit_1[416] <= 0;tag_address_1[416] <= 0;cache_block_1[416] <= 0;lru_counter_1[416] <= 0;valid_bit_2[416]  <=   0;dirty_bit_2[416] <= 0;tag_address_2[416] <= 0;cache_block_2[416] <= 0;lru_counter_2[416] <= 0;
        valid_bit_1[417]  <=   0;dirty_bit_1[417] <= 0;tag_address_1[417] <= 0;cache_block_1[417] <= 0;lru_counter_1[417] <= 0;valid_bit_2[417]  <=   0;dirty_bit_2[417] <= 0;tag_address_2[417] <= 0;cache_block_2[417] <= 0;lru_counter_2[417] <= 0;
        valid_bit_1[418]  <=   0;dirty_bit_1[418] <= 0;tag_address_1[418] <= 0;cache_block_1[418] <= 0;lru_counter_1[418] <= 0;valid_bit_2[418]  <=   0;dirty_bit_2[418] <= 0;tag_address_2[418] <= 0;cache_block_2[418] <= 0;lru_counter_2[418] <= 0;
        valid_bit_1[419]  <=   0;dirty_bit_1[419] <= 0;tag_address_1[419] <= 0;cache_block_1[419] <= 0;lru_counter_1[419] <= 0;valid_bit_2[419]  <=   0;dirty_bit_2[419] <= 0;tag_address_2[419] <= 0;cache_block_2[419] <= 0;lru_counter_2[419] <= 0;
        valid_bit_1[420]  <=   0;dirty_bit_1[420] <= 0;tag_address_1[420] <= 0;cache_block_1[420] <= 0;lru_counter_1[420] <= 0;valid_bit_2[420]  <=   0;dirty_bit_2[420] <= 0;tag_address_2[420] <= 0;cache_block_2[420] <= 0;lru_counter_2[420] <= 0;
        valid_bit_1[421]  <=   0;dirty_bit_1[421] <= 0;tag_address_1[421] <= 0;cache_block_1[421] <= 0;lru_counter_1[421] <= 0;valid_bit_2[421]  <=   0;dirty_bit_2[421] <= 0;tag_address_2[421] <= 0;cache_block_2[421] <= 0;lru_counter_2[421] <= 0;
        valid_bit_1[422]  <=   0;dirty_bit_1[422] <= 0;tag_address_1[422] <= 0;cache_block_1[422] <= 0;lru_counter_1[422] <= 0;valid_bit_2[422]  <=   0;dirty_bit_2[422] <= 0;tag_address_2[422] <= 0;cache_block_2[422] <= 0;lru_counter_2[422] <= 0;
        valid_bit_1[423]  <=   0;dirty_bit_1[423] <= 0;tag_address_1[423] <= 0;cache_block_1[423] <= 0;lru_counter_1[423] <= 0;valid_bit_2[423]  <=   0;dirty_bit_2[423] <= 0;tag_address_2[423] <= 0;cache_block_2[423] <= 0;lru_counter_2[423] <= 0;
        valid_bit_1[424]  <=   0;dirty_bit_1[424] <= 0;tag_address_1[424] <= 0;cache_block_1[424] <= 0;lru_counter_1[424] <= 0;valid_bit_2[424]  <=   0;dirty_bit_2[424] <= 0;tag_address_2[424] <= 0;cache_block_2[424] <= 0;lru_counter_2[424] <= 0;
        valid_bit_1[425]  <=   0;dirty_bit_1[425] <= 0;tag_address_1[425] <= 0;cache_block_1[425] <= 0;lru_counter_1[425] <= 0;valid_bit_2[425]  <=   0;dirty_bit_2[425] <= 0;tag_address_2[425] <= 0;cache_block_2[425] <= 0;lru_counter_2[425] <= 0;
        valid_bit_1[426]  <=   0;dirty_bit_1[426] <= 0;tag_address_1[426] <= 0;cache_block_1[426] <= 0;lru_counter_1[426] <= 0;valid_bit_2[426]  <=   0;dirty_bit_2[426] <= 0;tag_address_2[426] <= 0;cache_block_2[426] <= 0;lru_counter_2[426] <= 0;
        valid_bit_1[427]  <=   0;dirty_bit_1[427] <= 0;tag_address_1[427] <= 0;cache_block_1[427] <= 0;lru_counter_1[427] <= 0;valid_bit_2[427]  <=   0;dirty_bit_2[427] <= 0;tag_address_2[427] <= 0;cache_block_2[427] <= 0;lru_counter_2[427] <= 0;
        valid_bit_1[428]  <=   0;dirty_bit_1[428] <= 0;tag_address_1[428] <= 0;cache_block_1[428] <= 0;lru_counter_1[428] <= 0;valid_bit_2[428]  <=   0;dirty_bit_2[428] <= 0;tag_address_2[428] <= 0;cache_block_2[428] <= 0;lru_counter_2[428] <= 0;
        valid_bit_1[429]  <=   0;dirty_bit_1[429] <= 0;tag_address_1[429] <= 0;cache_block_1[429] <= 0;lru_counter_1[429] <= 0;valid_bit_2[429]  <=   0;dirty_bit_2[429] <= 0;tag_address_2[429] <= 0;cache_block_2[429] <= 0;lru_counter_2[429] <= 0;
        valid_bit_1[430]  <=   0;dirty_bit_1[430] <= 0;tag_address_1[430] <= 0;cache_block_1[430] <= 0;lru_counter_1[430] <= 0;valid_bit_2[430]  <=   0;dirty_bit_2[430] <= 0;tag_address_2[430] <= 0;cache_block_2[430] <= 0;lru_counter_2[430] <= 0;
        valid_bit_1[431]  <=   0;dirty_bit_1[431] <= 0;tag_address_1[431] <= 0;cache_block_1[431] <= 0;lru_counter_1[431] <= 0;valid_bit_2[431]  <=   0;dirty_bit_2[431] <= 0;tag_address_2[431] <= 0;cache_block_2[431] <= 0;lru_counter_2[431] <= 0;
        valid_bit_1[432]  <=   0;dirty_bit_1[432] <= 0;tag_address_1[432] <= 0;cache_block_1[432] <= 0;lru_counter_1[432] <= 0;valid_bit_2[432]  <=   0;dirty_bit_2[432] <= 0;tag_address_2[432] <= 0;cache_block_2[432] <= 0;lru_counter_2[432] <= 0;
        valid_bit_1[433]  <=   0;dirty_bit_1[433] <= 0;tag_address_1[433] <= 0;cache_block_1[433] <= 0;lru_counter_1[433] <= 0;valid_bit_2[433]  <=   0;dirty_bit_2[433] <= 0;tag_address_2[433] <= 0;cache_block_2[433] <= 0;lru_counter_2[433] <= 0;
        valid_bit_1[434]  <=   0;dirty_bit_1[434] <= 0;tag_address_1[434] <= 0;cache_block_1[434] <= 0;lru_counter_1[434] <= 0;valid_bit_2[434]  <=   0;dirty_bit_2[434] <= 0;tag_address_2[434] <= 0;cache_block_2[434] <= 0;lru_counter_2[434] <= 0;
        valid_bit_1[435]  <=   0;dirty_bit_1[435] <= 0;tag_address_1[435] <= 0;cache_block_1[435] <= 0;lru_counter_1[435] <= 0;valid_bit_2[435]  <=   0;dirty_bit_2[435] <= 0;tag_address_2[435] <= 0;cache_block_2[435] <= 0;lru_counter_2[435] <= 0;
        valid_bit_1[436]  <=   0;dirty_bit_1[436] <= 0;tag_address_1[436] <= 0;cache_block_1[436] <= 0;lru_counter_1[436] <= 0;valid_bit_2[436]  <=   0;dirty_bit_2[436] <= 0;tag_address_2[436] <= 0;cache_block_2[436] <= 0;lru_counter_2[436] <= 0;
        valid_bit_1[437]  <=   0;dirty_bit_1[437] <= 0;tag_address_1[437] <= 0;cache_block_1[437] <= 0;lru_counter_1[437] <= 0;valid_bit_2[437]  <=   0;dirty_bit_2[437] <= 0;tag_address_2[437] <= 0;cache_block_2[437] <= 0;lru_counter_2[437] <= 0;
        valid_bit_1[438]  <=   0;dirty_bit_1[438] <= 0;tag_address_1[438] <= 0;cache_block_1[438] <= 0;lru_counter_1[438] <= 0;valid_bit_2[438]  <=   0;dirty_bit_2[438] <= 0;tag_address_2[438] <= 0;cache_block_2[438] <= 0;lru_counter_2[438] <= 0;
        valid_bit_1[439]  <=   0;dirty_bit_1[439] <= 0;tag_address_1[439] <= 0;cache_block_1[439] <= 0;lru_counter_1[439] <= 0;valid_bit_2[439]  <=   0;dirty_bit_2[439] <= 0;tag_address_2[439] <= 0;cache_block_2[439] <= 0;lru_counter_2[439] <= 0;
        valid_bit_1[440]  <=   0;dirty_bit_1[440] <= 0;tag_address_1[440] <= 0;cache_block_1[440] <= 0;lru_counter_1[440] <= 0;valid_bit_2[440]  <=   0;dirty_bit_2[440] <= 0;tag_address_2[440] <= 0;cache_block_2[440] <= 0;lru_counter_2[440] <= 0;
        valid_bit_1[441]  <=   0;dirty_bit_1[441] <= 0;tag_address_1[441] <= 0;cache_block_1[441] <= 0;lru_counter_1[441] <= 0;valid_bit_2[441]  <=   0;dirty_bit_2[441] <= 0;tag_address_2[441] <= 0;cache_block_2[441] <= 0;lru_counter_2[441] <= 0;
        valid_bit_1[442]  <=   0;dirty_bit_1[442] <= 0;tag_address_1[442] <= 0;cache_block_1[442] <= 0;lru_counter_1[442] <= 0;valid_bit_2[442]  <=   0;dirty_bit_2[442] <= 0;tag_address_2[442] <= 0;cache_block_2[442] <= 0;lru_counter_2[442] <= 0;
        valid_bit_1[443]  <=   0;dirty_bit_1[443] <= 0;tag_address_1[443] <= 0;cache_block_1[443] <= 0;lru_counter_1[443] <= 0;valid_bit_2[443]  <=   0;dirty_bit_2[443] <= 0;tag_address_2[443] <= 0;cache_block_2[443] <= 0;lru_counter_2[443] <= 0;
        valid_bit_1[444]  <=   0;dirty_bit_1[444] <= 0;tag_address_1[444] <= 0;cache_block_1[444] <= 0;lru_counter_1[444] <= 0;valid_bit_2[444]  <=   0;dirty_bit_2[444] <= 0;tag_address_2[444] <= 0;cache_block_2[444] <= 0;lru_counter_2[444] <= 0;
        valid_bit_1[445]  <=   0;dirty_bit_1[445] <= 0;tag_address_1[445] <= 0;cache_block_1[445] <= 0;lru_counter_1[445] <= 0;valid_bit_2[445]  <=   0;dirty_bit_2[445] <= 0;tag_address_2[445] <= 0;cache_block_2[445] <= 0;lru_counter_2[445] <= 0;
        valid_bit_1[446]  <=   0;dirty_bit_1[446] <= 0;tag_address_1[446] <= 0;cache_block_1[446] <= 0;lru_counter_1[446] <= 0;valid_bit_2[446]  <=   0;dirty_bit_2[446] <= 0;tag_address_2[446] <= 0;cache_block_2[446] <= 0;lru_counter_2[446] <= 0;
        valid_bit_1[447]  <=   0;dirty_bit_1[447] <= 0;tag_address_1[447] <= 0;cache_block_1[447] <= 0;lru_counter_1[447] <= 0;valid_bit_2[447]  <=   0;dirty_bit_2[447] <= 0;tag_address_2[447] <= 0;cache_block_2[447] <= 0;lru_counter_2[447] <= 0;
        valid_bit_1[448]  <=   0;dirty_bit_1[448] <= 0;tag_address_1[448] <= 0;cache_block_1[448] <= 0;lru_counter_1[448] <= 0;valid_bit_2[448]  <=   0;dirty_bit_2[448] <= 0;tag_address_2[448] <= 0;cache_block_2[448] <= 0;lru_counter_2[448] <= 0;
        valid_bit_1[449]  <=   0;dirty_bit_1[449] <= 0;tag_address_1[449] <= 0;cache_block_1[449] <= 0;lru_counter_1[449] <= 0;valid_bit_2[449]  <=   0;dirty_bit_2[449] <= 0;tag_address_2[449] <= 0;cache_block_2[449] <= 0;lru_counter_2[449] <= 0;
        valid_bit_1[450]  <=   0;dirty_bit_1[450] <= 0;tag_address_1[450] <= 0;cache_block_1[450] <= 0;lru_counter_1[450] <= 0;valid_bit_2[450]  <=   0;dirty_bit_2[450] <= 0;tag_address_2[450] <= 0;cache_block_2[450] <= 0;lru_counter_2[450] <= 0;
        valid_bit_1[451]  <=   0;dirty_bit_1[451] <= 0;tag_address_1[451] <= 0;cache_block_1[451] <= 0;lru_counter_1[451] <= 0;valid_bit_2[451]  <=   0;dirty_bit_2[451] <= 0;tag_address_2[451] <= 0;cache_block_2[451] <= 0;lru_counter_2[451] <= 0;
        valid_bit_1[452]  <=   0;dirty_bit_1[452] <= 0;tag_address_1[452] <= 0;cache_block_1[452] <= 0;lru_counter_1[452] <= 0;valid_bit_2[452]  <=   0;dirty_bit_2[452] <= 0;tag_address_2[452] <= 0;cache_block_2[452] <= 0;lru_counter_2[452] <= 0;
        valid_bit_1[453]  <=   0;dirty_bit_1[453] <= 0;tag_address_1[453] <= 0;cache_block_1[453] <= 0;lru_counter_1[453] <= 0;valid_bit_2[453]  <=   0;dirty_bit_2[453] <= 0;tag_address_2[453] <= 0;cache_block_2[453] <= 0;lru_counter_2[453] <= 0;
        valid_bit_1[454]  <=   0;dirty_bit_1[454] <= 0;tag_address_1[454] <= 0;cache_block_1[454] <= 0;lru_counter_1[454] <= 0;valid_bit_2[454]  <=   0;dirty_bit_2[454] <= 0;tag_address_2[454] <= 0;cache_block_2[454] <= 0;lru_counter_2[454] <= 0;
        valid_bit_1[455]  <=   0;dirty_bit_1[455] <= 0;tag_address_1[455] <= 0;cache_block_1[455] <= 0;lru_counter_1[455] <= 0;valid_bit_2[455]  <=   0;dirty_bit_2[455] <= 0;tag_address_2[455] <= 0;cache_block_2[455] <= 0;lru_counter_2[455] <= 0;
        valid_bit_1[456]  <=   0;dirty_bit_1[456] <= 0;tag_address_1[456] <= 0;cache_block_1[456] <= 0;lru_counter_1[456] <= 0;valid_bit_2[456]  <=   0;dirty_bit_2[456] <= 0;tag_address_2[456] <= 0;cache_block_2[456] <= 0;lru_counter_2[456] <= 0;
        valid_bit_1[457]  <=   0;dirty_bit_1[457] <= 0;tag_address_1[457] <= 0;cache_block_1[457] <= 0;lru_counter_1[457] <= 0;valid_bit_2[457]  <=   0;dirty_bit_2[457] <= 0;tag_address_2[457] <= 0;cache_block_2[457] <= 0;lru_counter_2[457] <= 0;
        valid_bit_1[458]  <=   0;dirty_bit_1[458] <= 0;tag_address_1[458] <= 0;cache_block_1[458] <= 0;lru_counter_1[458] <= 0;valid_bit_2[458]  <=   0;dirty_bit_2[458] <= 0;tag_address_2[458] <= 0;cache_block_2[458] <= 0;lru_counter_2[458] <= 0;
        valid_bit_1[459]  <=   0;dirty_bit_1[459] <= 0;tag_address_1[459] <= 0;cache_block_1[459] <= 0;lru_counter_1[459] <= 0;valid_bit_2[459]  <=   0;dirty_bit_2[459] <= 0;tag_address_2[459] <= 0;cache_block_2[459] <= 0;lru_counter_2[459] <= 0;
        valid_bit_1[460]  <=   0;dirty_bit_1[460] <= 0;tag_address_1[460] <= 0;cache_block_1[460] <= 0;lru_counter_1[460] <= 0;valid_bit_2[460]  <=   0;dirty_bit_2[460] <= 0;tag_address_2[460] <= 0;cache_block_2[460] <= 0;lru_counter_2[460] <= 0;
        valid_bit_1[461]  <=   0;dirty_bit_1[461] <= 0;tag_address_1[461] <= 0;cache_block_1[461] <= 0;lru_counter_1[461] <= 0;valid_bit_2[461]  <=   0;dirty_bit_2[461] <= 0;tag_address_2[461] <= 0;cache_block_2[461] <= 0;lru_counter_2[461] <= 0;
        valid_bit_1[462]  <=   0;dirty_bit_1[462] <= 0;tag_address_1[462] <= 0;cache_block_1[462] <= 0;lru_counter_1[462] <= 0;valid_bit_2[462]  <=   0;dirty_bit_2[462] <= 0;tag_address_2[462] <= 0;cache_block_2[462] <= 0;lru_counter_2[462] <= 0;
        valid_bit_1[463]  <=   0;dirty_bit_1[463] <= 0;tag_address_1[463] <= 0;cache_block_1[463] <= 0;lru_counter_1[463] <= 0;valid_bit_2[463]  <=   0;dirty_bit_2[463] <= 0;tag_address_2[463] <= 0;cache_block_2[463] <= 0;lru_counter_2[463] <= 0;
        valid_bit_1[464]  <=   0;dirty_bit_1[464] <= 0;tag_address_1[464] <= 0;cache_block_1[464] <= 0;lru_counter_1[464] <= 0;valid_bit_2[464]  <=   0;dirty_bit_2[464] <= 0;tag_address_2[464] <= 0;cache_block_2[464] <= 0;lru_counter_2[464] <= 0;
        valid_bit_1[465]  <=   0;dirty_bit_1[465] <= 0;tag_address_1[465] <= 0;cache_block_1[465] <= 0;lru_counter_1[465] <= 0;valid_bit_2[465]  <=   0;dirty_bit_2[465] <= 0;tag_address_2[465] <= 0;cache_block_2[465] <= 0;lru_counter_2[465] <= 0;
        valid_bit_1[466]  <=   0;dirty_bit_1[466] <= 0;tag_address_1[466] <= 0;cache_block_1[466] <= 0;lru_counter_1[466] <= 0;valid_bit_2[466]  <=   0;dirty_bit_2[466] <= 0;tag_address_2[466] <= 0;cache_block_2[466] <= 0;lru_counter_2[466] <= 0;
        valid_bit_1[467]  <=   0;dirty_bit_1[467] <= 0;tag_address_1[467] <= 0;cache_block_1[467] <= 0;lru_counter_1[467] <= 0;valid_bit_2[467]  <=   0;dirty_bit_2[467] <= 0;tag_address_2[467] <= 0;cache_block_2[467] <= 0;lru_counter_2[467] <= 0;
        valid_bit_1[468]  <=   0;dirty_bit_1[468] <= 0;tag_address_1[468] <= 0;cache_block_1[468] <= 0;lru_counter_1[468] <= 0;valid_bit_2[468]  <=   0;dirty_bit_2[468] <= 0;tag_address_2[468] <= 0;cache_block_2[468] <= 0;lru_counter_2[468] <= 0;
        valid_bit_1[469]  <=   0;dirty_bit_1[469] <= 0;tag_address_1[469] <= 0;cache_block_1[469] <= 0;lru_counter_1[469] <= 0;valid_bit_2[469]  <=   0;dirty_bit_2[469] <= 0;tag_address_2[469] <= 0;cache_block_2[469] <= 0;lru_counter_2[469] <= 0;
        valid_bit_1[470]  <=   0;dirty_bit_1[470] <= 0;tag_address_1[470] <= 0;cache_block_1[470] <= 0;lru_counter_1[470] <= 0;valid_bit_2[470]  <=   0;dirty_bit_2[470] <= 0;tag_address_2[470] <= 0;cache_block_2[470] <= 0;lru_counter_2[470] <= 0;
        valid_bit_1[471]  <=   0;dirty_bit_1[471] <= 0;tag_address_1[471] <= 0;cache_block_1[471] <= 0;lru_counter_1[471] <= 0;valid_bit_2[471]  <=   0;dirty_bit_2[471] <= 0;tag_address_2[471] <= 0;cache_block_2[471] <= 0;lru_counter_2[471] <= 0;
        valid_bit_1[472]  <=   0;dirty_bit_1[472] <= 0;tag_address_1[472] <= 0;cache_block_1[472] <= 0;lru_counter_1[472] <= 0;valid_bit_2[472]  <=   0;dirty_bit_2[472] <= 0;tag_address_2[472] <= 0;cache_block_2[472] <= 0;lru_counter_2[472] <= 0;
        valid_bit_1[473]  <=   0;dirty_bit_1[473] <= 0;tag_address_1[473] <= 0;cache_block_1[473] <= 0;lru_counter_1[473] <= 0;valid_bit_2[473]  <=   0;dirty_bit_2[473] <= 0;tag_address_2[473] <= 0;cache_block_2[473] <= 0;lru_counter_2[473] <= 0;
        valid_bit_1[474]  <=   0;dirty_bit_1[474] <= 0;tag_address_1[474] <= 0;cache_block_1[474] <= 0;lru_counter_1[474] <= 0;valid_bit_2[474]  <=   0;dirty_bit_2[474] <= 0;tag_address_2[474] <= 0;cache_block_2[474] <= 0;lru_counter_2[474] <= 0;
        valid_bit_1[475]  <=   0;dirty_bit_1[475] <= 0;tag_address_1[475] <= 0;cache_block_1[475] <= 0;lru_counter_1[475] <= 0;valid_bit_2[475]  <=   0;dirty_bit_2[475] <= 0;tag_address_2[475] <= 0;cache_block_2[475] <= 0;lru_counter_2[475] <= 0;
        valid_bit_1[476]  <=   0;dirty_bit_1[476] <= 0;tag_address_1[476] <= 0;cache_block_1[476] <= 0;lru_counter_1[476] <= 0;valid_bit_2[476]  <=   0;dirty_bit_2[476] <= 0;tag_address_2[476] <= 0;cache_block_2[476] <= 0;lru_counter_2[476] <= 0;
        valid_bit_1[477]  <=   0;dirty_bit_1[477] <= 0;tag_address_1[477] <= 0;cache_block_1[477] <= 0;lru_counter_1[477] <= 0;valid_bit_2[477]  <=   0;dirty_bit_2[477] <= 0;tag_address_2[477] <= 0;cache_block_2[477] <= 0;lru_counter_2[477] <= 0;
        valid_bit_1[478]  <=   0;dirty_bit_1[478] <= 0;tag_address_1[478] <= 0;cache_block_1[478] <= 0;lru_counter_1[478] <= 0;valid_bit_2[478]  <=   0;dirty_bit_2[478] <= 0;tag_address_2[478] <= 0;cache_block_2[478] <= 0;lru_counter_2[478] <= 0;
        valid_bit_1[479]  <=   0;dirty_bit_1[479] <= 0;tag_address_1[479] <= 0;cache_block_1[479] <= 0;lru_counter_1[479] <= 0;valid_bit_2[479]  <=   0;dirty_bit_2[479] <= 0;tag_address_2[479] <= 0;cache_block_2[479] <= 0;lru_counter_2[479] <= 0;
        valid_bit_1[480]  <=   0;dirty_bit_1[480] <= 0;tag_address_1[480] <= 0;cache_block_1[480] <= 0;lru_counter_1[480] <= 0;valid_bit_2[480]  <=   0;dirty_bit_2[480] <= 0;tag_address_2[480] <= 0;cache_block_2[480] <= 0;lru_counter_2[480] <= 0;
        valid_bit_1[481]  <=   0;dirty_bit_1[481] <= 0;tag_address_1[481] <= 0;cache_block_1[481] <= 0;lru_counter_1[481] <= 0;valid_bit_2[481]  <=   0;dirty_bit_2[481] <= 0;tag_address_2[481] <= 0;cache_block_2[481] <= 0;lru_counter_2[481] <= 0;
        valid_bit_1[482]  <=   0;dirty_bit_1[482] <= 0;tag_address_1[482] <= 0;cache_block_1[482] <= 0;lru_counter_1[482] <= 0;valid_bit_2[482]  <=   0;dirty_bit_2[482] <= 0;tag_address_2[482] <= 0;cache_block_2[482] <= 0;lru_counter_2[482] <= 0;
        valid_bit_1[483]  <=   0;dirty_bit_1[483] <= 0;tag_address_1[483] <= 0;cache_block_1[483] <= 0;lru_counter_1[483] <= 0;valid_bit_2[483]  <=   0;dirty_bit_2[483] <= 0;tag_address_2[483] <= 0;cache_block_2[483] <= 0;lru_counter_2[483] <= 0;
        valid_bit_1[484]  <=   0;dirty_bit_1[484] <= 0;tag_address_1[484] <= 0;cache_block_1[484] <= 0;lru_counter_1[484] <= 0;valid_bit_2[484]  <=   0;dirty_bit_2[484] <= 0;tag_address_2[484] <= 0;cache_block_2[484] <= 0;lru_counter_2[484] <= 0;
        valid_bit_1[485]  <=   0;dirty_bit_1[485] <= 0;tag_address_1[485] <= 0;cache_block_1[485] <= 0;lru_counter_1[485] <= 0;valid_bit_2[485]  <=   0;dirty_bit_2[485] <= 0;tag_address_2[485] <= 0;cache_block_2[485] <= 0;lru_counter_2[485] <= 0;
        valid_bit_1[486]  <=   0;dirty_bit_1[486] <= 0;tag_address_1[486] <= 0;cache_block_1[486] <= 0;lru_counter_1[486] <= 0;valid_bit_2[486]  <=   0;dirty_bit_2[486] <= 0;tag_address_2[486] <= 0;cache_block_2[486] <= 0;lru_counter_2[486] <= 0;
        valid_bit_1[487]  <=   0;dirty_bit_1[487] <= 0;tag_address_1[487] <= 0;cache_block_1[487] <= 0;lru_counter_1[487] <= 0;valid_bit_2[487]  <=   0;dirty_bit_2[487] <= 0;tag_address_2[487] <= 0;cache_block_2[487] <= 0;lru_counter_2[487] <= 0;
        valid_bit_1[488]  <=   0;dirty_bit_1[488] <= 0;tag_address_1[488] <= 0;cache_block_1[488] <= 0;lru_counter_1[488] <= 0;valid_bit_2[488]  <=   0;dirty_bit_2[488] <= 0;tag_address_2[488] <= 0;cache_block_2[488] <= 0;lru_counter_2[488] <= 0;
        valid_bit_1[489]  <=   0;dirty_bit_1[489] <= 0;tag_address_1[489] <= 0;cache_block_1[489] <= 0;lru_counter_1[489] <= 0;valid_bit_2[489]  <=   0;dirty_bit_2[489] <= 0;tag_address_2[489] <= 0;cache_block_2[489] <= 0;lru_counter_2[489] <= 0;
        valid_bit_1[490]  <=   0;dirty_bit_1[490] <= 0;tag_address_1[490] <= 0;cache_block_1[490] <= 0;lru_counter_1[490] <= 0;valid_bit_2[490]  <=   0;dirty_bit_2[490] <= 0;tag_address_2[490] <= 0;cache_block_2[490] <= 0;lru_counter_2[490] <= 0;
        valid_bit_1[491]  <=   0;dirty_bit_1[491] <= 0;tag_address_1[491] <= 0;cache_block_1[491] <= 0;lru_counter_1[491] <= 0;valid_bit_2[491]  <=   0;dirty_bit_2[491] <= 0;tag_address_2[491] <= 0;cache_block_2[491] <= 0;lru_counter_2[491] <= 0;
        valid_bit_1[492]  <=   0;dirty_bit_1[492] <= 0;tag_address_1[492] <= 0;cache_block_1[492] <= 0;lru_counter_1[492] <= 0;valid_bit_2[492]  <=   0;dirty_bit_2[492] <= 0;tag_address_2[492] <= 0;cache_block_2[492] <= 0;lru_counter_2[492] <= 0;
        valid_bit_1[493]  <=   0;dirty_bit_1[493] <= 0;tag_address_1[493] <= 0;cache_block_1[493] <= 0;lru_counter_1[493] <= 0;valid_bit_2[493]  <=   0;dirty_bit_2[493] <= 0;tag_address_2[493] <= 0;cache_block_2[493] <= 0;lru_counter_2[493] <= 0;
        valid_bit_1[494]  <=   0;dirty_bit_1[494] <= 0;tag_address_1[494] <= 0;cache_block_1[494] <= 0;lru_counter_1[494] <= 0;valid_bit_2[494]  <=   0;dirty_bit_2[494] <= 0;tag_address_2[494] <= 0;cache_block_2[494] <= 0;lru_counter_2[494] <= 0;
        valid_bit_1[495]  <=   0;dirty_bit_1[495] <= 0;tag_address_1[495] <= 0;cache_block_1[495] <= 0;lru_counter_1[495] <= 0;valid_bit_2[495]  <=   0;dirty_bit_2[495] <= 0;tag_address_2[495] <= 0;cache_block_2[495] <= 0;lru_counter_2[495] <= 0;
        valid_bit_1[496]  <=   0;dirty_bit_1[496] <= 0;tag_address_1[496] <= 0;cache_block_1[496] <= 0;lru_counter_1[496] <= 0;valid_bit_2[496]  <=   0;dirty_bit_2[496] <= 0;tag_address_2[496] <= 0;cache_block_2[496] <= 0;lru_counter_2[496] <= 0;
        valid_bit_1[497]  <=   0;dirty_bit_1[497] <= 0;tag_address_1[497] <= 0;cache_block_1[497] <= 0;lru_counter_1[497] <= 0;valid_bit_2[497]  <=   0;dirty_bit_2[497] <= 0;tag_address_2[497] <= 0;cache_block_2[497] <= 0;lru_counter_2[497] <= 0;
        valid_bit_1[498]  <=   0;dirty_bit_1[498] <= 0;tag_address_1[498] <= 0;cache_block_1[498] <= 0;lru_counter_1[498] <= 0;valid_bit_2[498]  <=   0;dirty_bit_2[498] <= 0;tag_address_2[498] <= 0;cache_block_2[498] <= 0;lru_counter_2[498] <= 0;
        valid_bit_1[499]  <=   0;dirty_bit_1[499] <= 0;tag_address_1[499] <= 0;cache_block_1[499] <= 0;lru_counter_1[499] <= 0;valid_bit_2[499]  <=   0;dirty_bit_2[499] <= 0;tag_address_2[499] <= 0;cache_block_2[499] <= 0;lru_counter_2[499] <= 0;
        valid_bit_1[500]  <=   0;dirty_bit_1[500] <= 0;tag_address_1[500] <= 0;cache_block_1[500] <= 0;lru_counter_1[500] <= 0;valid_bit_2[500]  <=   0;dirty_bit_2[500] <= 0;tag_address_2[500] <= 0;cache_block_2[500] <= 0;lru_counter_2[500] <= 0;
        valid_bit_1[501]  <=   0;dirty_bit_1[501] <= 0;tag_address_1[501] <= 0;cache_block_1[501] <= 0;lru_counter_1[501] <= 0;valid_bit_2[501]  <=   0;dirty_bit_2[501] <= 0;tag_address_2[501] <= 0;cache_block_2[501] <= 0;lru_counter_2[501] <= 0;
        valid_bit_1[502]  <=   0;dirty_bit_1[502] <= 0;tag_address_1[502] <= 0;cache_block_1[502] <= 0;lru_counter_1[502] <= 0;valid_bit_2[502]  <=   0;dirty_bit_2[502] <= 0;tag_address_2[502] <= 0;cache_block_2[502] <= 0;lru_counter_2[502] <= 0;
        valid_bit_1[503]  <=   0;dirty_bit_1[503] <= 0;tag_address_1[503] <= 0;cache_block_1[503] <= 0;lru_counter_1[503] <= 0;valid_bit_2[503]  <=   0;dirty_bit_2[503] <= 0;tag_address_2[503] <= 0;cache_block_2[503] <= 0;lru_counter_2[503] <= 0;
        valid_bit_1[504]  <=   0;dirty_bit_1[504] <= 0;tag_address_1[504] <= 0;cache_block_1[504] <= 0;lru_counter_1[504] <= 0;valid_bit_2[504]  <=   0;dirty_bit_2[504] <= 0;tag_address_2[504] <= 0;cache_block_2[504] <= 0;lru_counter_2[504] <= 0;
        valid_bit_1[505]  <=   0;dirty_bit_1[505] <= 0;tag_address_1[505] <= 0;cache_block_1[505] <= 0;lru_counter_1[505] <= 0;valid_bit_2[505]  <=   0;dirty_bit_2[505] <= 0;tag_address_2[505] <= 0;cache_block_2[505] <= 0;lru_counter_2[505] <= 0;
        valid_bit_1[506]  <=   0;dirty_bit_1[506] <= 0;tag_address_1[506] <= 0;cache_block_1[506] <= 0;lru_counter_1[506] <= 0;valid_bit_2[506]  <=   0;dirty_bit_2[506] <= 0;tag_address_2[506] <= 0;cache_block_2[506] <= 0;lru_counter_2[506] <= 0;
        valid_bit_1[507]  <=   0;dirty_bit_1[507] <= 0;tag_address_1[507] <= 0;cache_block_1[507] <= 0;lru_counter_1[507] <= 0;valid_bit_2[507]  <=   0;dirty_bit_2[507] <= 0;tag_address_2[507] <= 0;cache_block_2[507] <= 0;lru_counter_2[507] <= 0;
        valid_bit_1[508]  <=   0;dirty_bit_1[508] <= 0;tag_address_1[508] <= 0;cache_block_1[508] <= 0;lru_counter_1[508] <= 0;valid_bit_2[508]  <=   0;dirty_bit_2[508] <= 0;tag_address_2[508] <= 0;cache_block_2[508] <= 0;lru_counter_2[508] <= 0;
        valid_bit_1[509]  <=   0;dirty_bit_1[509] <= 0;tag_address_1[509] <= 0;cache_block_1[509] <= 0;lru_counter_1[509] <= 0;valid_bit_2[509]  <=   0;dirty_bit_2[509] <= 0;tag_address_2[509] <= 0;cache_block_2[509] <= 0;lru_counter_2[509] <= 0;
        valid_bit_1[510]  <=   0;dirty_bit_1[510] <= 0;tag_address_1[510] <= 0;cache_block_1[510] <= 0;lru_counter_1[510] <= 0;valid_bit_2[510]  <=   0;dirty_bit_2[510] <= 0;tag_address_2[510] <= 0;cache_block_2[510] <= 0;lru_counter_2[510] <= 0;
        valid_bit_1[511]  <=   0;dirty_bit_1[511] <= 0;tag_address_1[511] <= 0;cache_block_1[511] <= 0;lru_counter_1[511] <= 0;valid_bit_2[511]  <=   0;dirty_bit_2[511] <= 0;tag_address_2[511] <= 0;cache_block_2[511] <= 0;lru_counter_2[511] <= 0; 
    end
end


endmodule
