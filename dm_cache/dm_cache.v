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

module dm_cache #(
    parameter ADDRESS_WIDTH =64,
    parameter WRITE_DATA=64,
    parameter BLOCK_SIZE_BYTE=64,
    parameter BLOCK_SIZE_BITS=6,
    parameter BLOCK_NUMBER_BITS=10,
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
localparam TAG_WIDTH = ADDRESS_WIDTH-BLOCK_NUMBER_BITS-BLOCK_SIZE_BITS;
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

reg [BLOCK_SIZE_BYTE*8-1:0] cache_block [0:1023];
reg valid_bit [0:1023];
reg dirty_bit [0:1023];
reg [TAG_WIDTH-1:0] tag_address[0:1023];
localparam CACHE_ACCESS=0,MISS=1;

reg cs,ns;
wire miss;
reg handled; 

assign miss = i_cpu_valid && ((i_cpu_address[TAG_HIGH:TAG_LOW]!=tag_address[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) || !valid_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]); 
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
            o_mem_wr_en <=0;

            if(i_cpu_valid & !i_cpu_rd_wr) begin
                if((i_cpu_address[TAG_HIGH:TAG_LOW]==tag_address[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) && valid_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                    //rd hit
                    //o_cpu_read_valid <= i_cpu_valid;
                    o_cpu_rd_data  <= cache_block[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]];
                    o_cpu_busy       <= 0;
                end
                else begin
                    o_cpu_busy       <= 1;
                end
            end
            else if(i_cpu_valid & i_cpu_rd_wr) begin
                if((i_cpu_address[TAG_HIGH:TAG_LOW]==tag_address[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) && valid_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                    //wr hit
                    cache_block[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]  <= i_cpu_wr_data;
                    dirty_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]    <= 1;
                    o_cpu_busy                                                          <= 0;
                    o_mem_wr_en                                                         <= 0;
                end
                else begin
                    o_cpu_busy          <=  1;
                end
            end
        end
        MISS: begin
            if(!valid_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                if(i_mem_rd_valid) begin                
                    cache_block[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_mem_rd_data;
                    tag_address[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_cpu_address[TAG_HIGH:TAG_LOW];
                    dirty_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]         <=   0;
                    valid_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]         <=   1;
                    handled                                                                <=   1;
                end
            end
            else if(valid_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                if(i_mem_rd_valid) begin                
                    if(dirty_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                        o_mem_wr_data <= cache_block[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]];
                        o_mem_wr_address <= i_cpu_address;
                        o_mem_wr_en <= 1;
                    end
                    cache_block[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_mem_rd_data;
                    tag_address[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_cpu_address[TAG_HIGH:TAG_LOW];
                    dirty_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]         <=   0;
                    handled                                                                <=   1;
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
        valid_bit[0]  <=   0;dirty_bit[0] <= 0;tag_address[0] <= 0;cache_block[0] <= 0;
        valid_bit[1]  <=   0;dirty_bit[1] <= 0;tag_address[1] <= 0;cache_block[1] <= 0;
        valid_bit[2]  <=   0;dirty_bit[2] <= 0;tag_address[2] <= 0;cache_block[2] <= 0;
        valid_bit[3]  <=   0;dirty_bit[3] <= 0;tag_address[3] <= 0;cache_block[3] <= 0;
        valid_bit[4]  <=   0;dirty_bit[4] <= 0;tag_address[4] <= 0;cache_block[4] <= 0;
        valid_bit[5]  <=   0;dirty_bit[5] <= 0;tag_address[5] <= 0;cache_block[5] <= 0;
        valid_bit[6]  <=   0;dirty_bit[6] <= 0;tag_address[6] <= 0;cache_block[6] <= 0;
        valid_bit[7]  <=   0;dirty_bit[7] <= 0;tag_address[7] <= 0;cache_block[7] <= 0;
        valid_bit[8]  <=   0;dirty_bit[8] <= 0;tag_address[8] <= 0;cache_block[8] <= 0;
        valid_bit[9]  <=   0;dirty_bit[9] <= 0;tag_address[9] <= 0;cache_block[9] <= 0;
        valid_bit[10]  <=   0;dirty_bit[10] <= 0;tag_address[10] <= 0;cache_block[10] <= 0;
        valid_bit[11]  <=   0;dirty_bit[11] <= 0;tag_address[11] <= 0;cache_block[11] <= 0;
        valid_bit[12]  <=   0;dirty_bit[12] <= 0;tag_address[12] <= 0;cache_block[12] <= 0;
        valid_bit[13]  <=   0;dirty_bit[13] <= 0;tag_address[13] <= 0;cache_block[13] <= 0;
        valid_bit[14]  <=   0;dirty_bit[14] <= 0;tag_address[14] <= 0;cache_block[14] <= 0;
        valid_bit[15]  <=   0;dirty_bit[15] <= 0;tag_address[15] <= 0;cache_block[15] <= 0;
        valid_bit[16]  <=   0;dirty_bit[16] <= 0;tag_address[16] <= 0;cache_block[16] <= 0;
        valid_bit[17]  <=   0;dirty_bit[17] <= 0;tag_address[17] <= 0;cache_block[17] <= 0;
        valid_bit[18]  <=   0;dirty_bit[18] <= 0;tag_address[18] <= 0;cache_block[18] <= 0;
        valid_bit[19]  <=   0;dirty_bit[19] <= 0;tag_address[19] <= 0;cache_block[19] <= 0;
        valid_bit[20]  <=   0;dirty_bit[20] <= 0;tag_address[20] <= 0;cache_block[20] <= 0;
        valid_bit[21]  <=   0;dirty_bit[21] <= 0;tag_address[21] <= 0;cache_block[21] <= 0;
        valid_bit[22]  <=   0;dirty_bit[22] <= 0;tag_address[22] <= 0;cache_block[22] <= 0;
        valid_bit[23]  <=   0;dirty_bit[23] <= 0;tag_address[23] <= 0;cache_block[23] <= 0;
        valid_bit[24]  <=   0;dirty_bit[24] <= 0;tag_address[24] <= 0;cache_block[24] <= 0;
        valid_bit[25]  <=   0;dirty_bit[25] <= 0;tag_address[25] <= 0;cache_block[25] <= 0;
        valid_bit[26]  <=   0;dirty_bit[26] <= 0;tag_address[26] <= 0;cache_block[26] <= 0;
        valid_bit[27]  <=   0;dirty_bit[27] <= 0;tag_address[27] <= 0;cache_block[27] <= 0;
        valid_bit[28]  <=   0;dirty_bit[28] <= 0;tag_address[28] <= 0;cache_block[28] <= 0;
        valid_bit[29]  <=   0;dirty_bit[29] <= 0;tag_address[29] <= 0;cache_block[29] <= 0;
        valid_bit[30]  <=   0;dirty_bit[30] <= 0;tag_address[30] <= 0;cache_block[30] <= 0;
        valid_bit[31]  <=   0;dirty_bit[31] <= 0;tag_address[31] <= 0;cache_block[31] <= 0;
        valid_bit[32]  <=   0;dirty_bit[32] <= 0;tag_address[32] <= 0;cache_block[32] <= 0;
        valid_bit[33]  <=   0;dirty_bit[33] <= 0;tag_address[33] <= 0;cache_block[33] <= 0;
        valid_bit[34]  <=   0;dirty_bit[34] <= 0;tag_address[34] <= 0;cache_block[34] <= 0;
        valid_bit[35]  <=   0;dirty_bit[35] <= 0;tag_address[35] <= 0;cache_block[35] <= 0;
        valid_bit[36]  <=   0;dirty_bit[36] <= 0;tag_address[36] <= 0;cache_block[36] <= 0;
        valid_bit[37]  <=   0;dirty_bit[37] <= 0;tag_address[37] <= 0;cache_block[37] <= 0;
        valid_bit[38]  <=   0;dirty_bit[38] <= 0;tag_address[38] <= 0;cache_block[38] <= 0;
        valid_bit[39]  <=   0;dirty_bit[39] <= 0;tag_address[39] <= 0;cache_block[39] <= 0;
        valid_bit[40]  <=   0;dirty_bit[40] <= 0;tag_address[40] <= 0;cache_block[40] <= 0;
        valid_bit[41]  <=   0;dirty_bit[41] <= 0;tag_address[41] <= 0;cache_block[41] <= 0;
        valid_bit[42]  <=   0;dirty_bit[42] <= 0;tag_address[42] <= 0;cache_block[42] <= 0;
        valid_bit[43]  <=   0;dirty_bit[43] <= 0;tag_address[43] <= 0;cache_block[43] <= 0;
        valid_bit[44]  <=   0;dirty_bit[44] <= 0;tag_address[44] <= 0;cache_block[44] <= 0;
        valid_bit[45]  <=   0;dirty_bit[45] <= 0;tag_address[45] <= 0;cache_block[45] <= 0;
        valid_bit[46]  <=   0;dirty_bit[46] <= 0;tag_address[46] <= 0;cache_block[46] <= 0;
        valid_bit[47]  <=   0;dirty_bit[47] <= 0;tag_address[47] <= 0;cache_block[47] <= 0;
        valid_bit[48]  <=   0;dirty_bit[48] <= 0;tag_address[48] <= 0;cache_block[48] <= 0;
        valid_bit[49]  <=   0;dirty_bit[49] <= 0;tag_address[49] <= 0;cache_block[49] <= 0;
        valid_bit[50]  <=   0;dirty_bit[50] <= 0;tag_address[50] <= 0;cache_block[50] <= 0;
        valid_bit[51]  <=   0;dirty_bit[51] <= 0;tag_address[51] <= 0;cache_block[51] <= 0;
        valid_bit[52]  <=   0;dirty_bit[52] <= 0;tag_address[52] <= 0;cache_block[52] <= 0;
        valid_bit[53]  <=   0;dirty_bit[53] <= 0;tag_address[53] <= 0;cache_block[53] <= 0;
        valid_bit[54]  <=   0;dirty_bit[54] <= 0;tag_address[54] <= 0;cache_block[54] <= 0;
        valid_bit[55]  <=   0;dirty_bit[55] <= 0;tag_address[55] <= 0;cache_block[55] <= 0;
        valid_bit[56]  <=   0;dirty_bit[56] <= 0;tag_address[56] <= 0;cache_block[56] <= 0;
        valid_bit[57]  <=   0;dirty_bit[57] <= 0;tag_address[57] <= 0;cache_block[57] <= 0;
        valid_bit[58]  <=   0;dirty_bit[58] <= 0;tag_address[58] <= 0;cache_block[58] <= 0;
        valid_bit[59]  <=   0;dirty_bit[59] <= 0;tag_address[59] <= 0;cache_block[59] <= 0;
        valid_bit[60]  <=   0;dirty_bit[60] <= 0;tag_address[60] <= 0;cache_block[60] <= 0;
        valid_bit[61]  <=   0;dirty_bit[61] <= 0;tag_address[61] <= 0;cache_block[61] <= 0;
        valid_bit[62]  <=   0;dirty_bit[62] <= 0;tag_address[62] <= 0;cache_block[62] <= 0;
        valid_bit[63]  <=   0;dirty_bit[63] <= 0;tag_address[63] <= 0;cache_block[63] <= 0;
        valid_bit[64]  <=   0;dirty_bit[64] <= 0;tag_address[64] <= 0;cache_block[64] <= 0;
        valid_bit[65]  <=   0;dirty_bit[65] <= 0;tag_address[65] <= 0;cache_block[65] <= 0;
        valid_bit[66]  <=   0;dirty_bit[66] <= 0;tag_address[66] <= 0;cache_block[66] <= 0;
        valid_bit[67]  <=   0;dirty_bit[67] <= 0;tag_address[67] <= 0;cache_block[67] <= 0;
        valid_bit[68]  <=   0;dirty_bit[68] <= 0;tag_address[68] <= 0;cache_block[68] <= 0;
        valid_bit[69]  <=   0;dirty_bit[69] <= 0;tag_address[69] <= 0;cache_block[69] <= 0;
        valid_bit[70]  <=   0;dirty_bit[70] <= 0;tag_address[70] <= 0;cache_block[70] <= 0;
        valid_bit[71]  <=   0;dirty_bit[71] <= 0;tag_address[71] <= 0;cache_block[71] <= 0;
        valid_bit[72]  <=   0;dirty_bit[72] <= 0;tag_address[72] <= 0;cache_block[72] <= 0;
        valid_bit[73]  <=   0;dirty_bit[73] <= 0;tag_address[73] <= 0;cache_block[73] <= 0;
        valid_bit[74]  <=   0;dirty_bit[74] <= 0;tag_address[74] <= 0;cache_block[74] <= 0;
        valid_bit[75]  <=   0;dirty_bit[75] <= 0;tag_address[75] <= 0;cache_block[75] <= 0;
        valid_bit[76]  <=   0;dirty_bit[76] <= 0;tag_address[76] <= 0;cache_block[76] <= 0;
        valid_bit[77]  <=   0;dirty_bit[77] <= 0;tag_address[77] <= 0;cache_block[77] <= 0;
        valid_bit[78]  <=   0;dirty_bit[78] <= 0;tag_address[78] <= 0;cache_block[78] <= 0;
        valid_bit[79]  <=   0;dirty_bit[79] <= 0;tag_address[79] <= 0;cache_block[79] <= 0;
        valid_bit[80]  <=   0;dirty_bit[80] <= 0;tag_address[80] <= 0;cache_block[80] <= 0;
        valid_bit[81]  <=   0;dirty_bit[81] <= 0;tag_address[81] <= 0;cache_block[81] <= 0;
        valid_bit[82]  <=   0;dirty_bit[82] <= 0;tag_address[82] <= 0;cache_block[82] <= 0;
        valid_bit[83]  <=   0;dirty_bit[83] <= 0;tag_address[83] <= 0;cache_block[83] <= 0;
        valid_bit[84]  <=   0;dirty_bit[84] <= 0;tag_address[84] <= 0;cache_block[84] <= 0;
        valid_bit[85]  <=   0;dirty_bit[85] <= 0;tag_address[85] <= 0;cache_block[85] <= 0;
        valid_bit[86]  <=   0;dirty_bit[86] <= 0;tag_address[86] <= 0;cache_block[86] <= 0;
        valid_bit[87]  <=   0;dirty_bit[87] <= 0;tag_address[87] <= 0;cache_block[87] <= 0;
        valid_bit[88]  <=   0;dirty_bit[88] <= 0;tag_address[88] <= 0;cache_block[88] <= 0;
        valid_bit[89]  <=   0;dirty_bit[89] <= 0;tag_address[89] <= 0;cache_block[89] <= 0;
        valid_bit[90]  <=   0;dirty_bit[90] <= 0;tag_address[90] <= 0;cache_block[90] <= 0;
        valid_bit[91]  <=   0;dirty_bit[91] <= 0;tag_address[91] <= 0;cache_block[91] <= 0;
        valid_bit[92]  <=   0;dirty_bit[92] <= 0;tag_address[92] <= 0;cache_block[92] <= 0;
        valid_bit[93]  <=   0;dirty_bit[93] <= 0;tag_address[93] <= 0;cache_block[93] <= 0;
        valid_bit[94]  <=   0;dirty_bit[94] <= 0;tag_address[94] <= 0;cache_block[94] <= 0;
        valid_bit[95]  <=   0;dirty_bit[95] <= 0;tag_address[95] <= 0;cache_block[95] <= 0;
        valid_bit[96]  <=   0;dirty_bit[96] <= 0;tag_address[96] <= 0;cache_block[96] <= 0;
        valid_bit[97]  <=   0;dirty_bit[97] <= 0;tag_address[97] <= 0;cache_block[97] <= 0;
        valid_bit[98]  <=   0;dirty_bit[98] <= 0;tag_address[98] <= 0;cache_block[98] <= 0;
        valid_bit[99]  <=   0;dirty_bit[99] <= 0;tag_address[99] <= 0;cache_block[99] <= 0;
        valid_bit[100]  <=   0;dirty_bit[100] <= 0;tag_address[100] <= 0;cache_block[100] <= 0;
        valid_bit[101]  <=   0;dirty_bit[101] <= 0;tag_address[101] <= 0;cache_block[101] <= 0;
        valid_bit[102]  <=   0;dirty_bit[102] <= 0;tag_address[102] <= 0;cache_block[102] <= 0;
        valid_bit[103]  <=   0;dirty_bit[103] <= 0;tag_address[103] <= 0;cache_block[103] <= 0;
        valid_bit[104]  <=   0;dirty_bit[104] <= 0;tag_address[104] <= 0;cache_block[104] <= 0;
        valid_bit[105]  <=   0;dirty_bit[105] <= 0;tag_address[105] <= 0;cache_block[105] <= 0;
        valid_bit[106]  <=   0;dirty_bit[106] <= 0;tag_address[106] <= 0;cache_block[106] <= 0;
        valid_bit[107]  <=   0;dirty_bit[107] <= 0;tag_address[107] <= 0;cache_block[107] <= 0;
        valid_bit[108]  <=   0;dirty_bit[108] <= 0;tag_address[108] <= 0;cache_block[108] <= 0;
        valid_bit[109]  <=   0;dirty_bit[109] <= 0;tag_address[109] <= 0;cache_block[109] <= 0;
        valid_bit[110]  <=   0;dirty_bit[110] <= 0;tag_address[110] <= 0;cache_block[110] <= 0;
        valid_bit[111]  <=   0;dirty_bit[111] <= 0;tag_address[111] <= 0;cache_block[111] <= 0;
        valid_bit[112]  <=   0;dirty_bit[112] <= 0;tag_address[112] <= 0;cache_block[112] <= 0;
        valid_bit[113]  <=   0;dirty_bit[113] <= 0;tag_address[113] <= 0;cache_block[113] <= 0;
        valid_bit[114]  <=   0;dirty_bit[114] <= 0;tag_address[114] <= 0;cache_block[114] <= 0;
        valid_bit[115]  <=   0;dirty_bit[115] <= 0;tag_address[115] <= 0;cache_block[115] <= 0;
        valid_bit[116]  <=   0;dirty_bit[116] <= 0;tag_address[116] <= 0;cache_block[116] <= 0;
        valid_bit[117]  <=   0;dirty_bit[117] <= 0;tag_address[117] <= 0;cache_block[117] <= 0;
        valid_bit[118]  <=   0;dirty_bit[118] <= 0;tag_address[118] <= 0;cache_block[118] <= 0;
        valid_bit[119]  <=   0;dirty_bit[119] <= 0;tag_address[119] <= 0;cache_block[119] <= 0;
        valid_bit[120]  <=   0;dirty_bit[120] <= 0;tag_address[120] <= 0;cache_block[120] <= 0;
        valid_bit[121]  <=   0;dirty_bit[121] <= 0;tag_address[121] <= 0;cache_block[121] <= 0;
        valid_bit[122]  <=   0;dirty_bit[122] <= 0;tag_address[122] <= 0;cache_block[122] <= 0;
        valid_bit[123]  <=   0;dirty_bit[123] <= 0;tag_address[123] <= 0;cache_block[123] <= 0;
        valid_bit[124]  <=   0;dirty_bit[124] <= 0;tag_address[124] <= 0;cache_block[124] <= 0;
        valid_bit[125]  <=   0;dirty_bit[125] <= 0;tag_address[125] <= 0;cache_block[125] <= 0;
        valid_bit[126]  <=   0;dirty_bit[126] <= 0;tag_address[126] <= 0;cache_block[126] <= 0;
        valid_bit[127]  <=   0;dirty_bit[127] <= 0;tag_address[127] <= 0;cache_block[127] <= 0;
        valid_bit[128]  <=   0;dirty_bit[128] <= 0;tag_address[128] <= 0;cache_block[128] <= 0;
        valid_bit[129]  <=   0;dirty_bit[129] <= 0;tag_address[129] <= 0;cache_block[129] <= 0;
        valid_bit[130]  <=   0;dirty_bit[130] <= 0;tag_address[130] <= 0;cache_block[130] <= 0;
        valid_bit[131]  <=   0;dirty_bit[131] <= 0;tag_address[131] <= 0;cache_block[131] <= 0;
        valid_bit[132]  <=   0;dirty_bit[132] <= 0;tag_address[132] <= 0;cache_block[132] <= 0;
        valid_bit[133]  <=   0;dirty_bit[133] <= 0;tag_address[133] <= 0;cache_block[133] <= 0;
        valid_bit[134]  <=   0;dirty_bit[134] <= 0;tag_address[134] <= 0;cache_block[134] <= 0;
        valid_bit[135]  <=   0;dirty_bit[135] <= 0;tag_address[135] <= 0;cache_block[135] <= 0;
        valid_bit[136]  <=   0;dirty_bit[136] <= 0;tag_address[136] <= 0;cache_block[136] <= 0;
        valid_bit[137]  <=   0;dirty_bit[137] <= 0;tag_address[137] <= 0;cache_block[137] <= 0;
        valid_bit[138]  <=   0;dirty_bit[138] <= 0;tag_address[138] <= 0;cache_block[138] <= 0;
        valid_bit[139]  <=   0;dirty_bit[139] <= 0;tag_address[139] <= 0;cache_block[139] <= 0;
        valid_bit[140]  <=   0;dirty_bit[140] <= 0;tag_address[140] <= 0;cache_block[140] <= 0;
        valid_bit[141]  <=   0;dirty_bit[141] <= 0;tag_address[141] <= 0;cache_block[141] <= 0;
        valid_bit[142]  <=   0;dirty_bit[142] <= 0;tag_address[142] <= 0;cache_block[142] <= 0;
        valid_bit[143]  <=   0;dirty_bit[143] <= 0;tag_address[143] <= 0;cache_block[143] <= 0;
        valid_bit[144]  <=   0;dirty_bit[144] <= 0;tag_address[144] <= 0;cache_block[144] <= 0;
        valid_bit[145]  <=   0;dirty_bit[145] <= 0;tag_address[145] <= 0;cache_block[145] <= 0;
        valid_bit[146]  <=   0;dirty_bit[146] <= 0;tag_address[146] <= 0;cache_block[146] <= 0;
        valid_bit[147]  <=   0;dirty_bit[147] <= 0;tag_address[147] <= 0;cache_block[147] <= 0;
        valid_bit[148]  <=   0;dirty_bit[148] <= 0;tag_address[148] <= 0;cache_block[148] <= 0;
        valid_bit[149]  <=   0;dirty_bit[149] <= 0;tag_address[149] <= 0;cache_block[149] <= 0;
        valid_bit[150]  <=   0;dirty_bit[150] <= 0;tag_address[150] <= 0;cache_block[150] <= 0;
        valid_bit[151]  <=   0;dirty_bit[151] <= 0;tag_address[151] <= 0;cache_block[151] <= 0;
        valid_bit[152]  <=   0;dirty_bit[152] <= 0;tag_address[152] <= 0;cache_block[152] <= 0;
        valid_bit[153]  <=   0;dirty_bit[153] <= 0;tag_address[153] <= 0;cache_block[153] <= 0;
        valid_bit[154]  <=   0;dirty_bit[154] <= 0;tag_address[154] <= 0;cache_block[154] <= 0;
        valid_bit[155]  <=   0;dirty_bit[155] <= 0;tag_address[155] <= 0;cache_block[155] <= 0;
        valid_bit[156]  <=   0;dirty_bit[156] <= 0;tag_address[156] <= 0;cache_block[156] <= 0;
        valid_bit[157]  <=   0;dirty_bit[157] <= 0;tag_address[157] <= 0;cache_block[157] <= 0;
        valid_bit[158]  <=   0;dirty_bit[158] <= 0;tag_address[158] <= 0;cache_block[158] <= 0;
        valid_bit[159]  <=   0;dirty_bit[159] <= 0;tag_address[159] <= 0;cache_block[159] <= 0;
        valid_bit[160]  <=   0;dirty_bit[160] <= 0;tag_address[160] <= 0;cache_block[160] <= 0;
        valid_bit[161]  <=   0;dirty_bit[161] <= 0;tag_address[161] <= 0;cache_block[161] <= 0;
        valid_bit[162]  <=   0;dirty_bit[162] <= 0;tag_address[162] <= 0;cache_block[162] <= 0;
        valid_bit[163]  <=   0;dirty_bit[163] <= 0;tag_address[163] <= 0;cache_block[163] <= 0;
        valid_bit[164]  <=   0;dirty_bit[164] <= 0;tag_address[164] <= 0;cache_block[164] <= 0;
        valid_bit[165]  <=   0;dirty_bit[165] <= 0;tag_address[165] <= 0;cache_block[165] <= 0;
        valid_bit[166]  <=   0;dirty_bit[166] <= 0;tag_address[166] <= 0;cache_block[166] <= 0;
        valid_bit[167]  <=   0;dirty_bit[167] <= 0;tag_address[167] <= 0;cache_block[167] <= 0;
        valid_bit[168]  <=   0;dirty_bit[168] <= 0;tag_address[168] <= 0;cache_block[168] <= 0;
        valid_bit[169]  <=   0;dirty_bit[169] <= 0;tag_address[169] <= 0;cache_block[169] <= 0;
        valid_bit[170]  <=   0;dirty_bit[170] <= 0;tag_address[170] <= 0;cache_block[170] <= 0;
        valid_bit[171]  <=   0;dirty_bit[171] <= 0;tag_address[171] <= 0;cache_block[171] <= 0;
        valid_bit[172]  <=   0;dirty_bit[172] <= 0;tag_address[172] <= 0;cache_block[172] <= 0;
        valid_bit[173]  <=   0;dirty_bit[173] <= 0;tag_address[173] <= 0;cache_block[173] <= 0;
        valid_bit[174]  <=   0;dirty_bit[174] <= 0;tag_address[174] <= 0;cache_block[174] <= 0;
        valid_bit[175]  <=   0;dirty_bit[175] <= 0;tag_address[175] <= 0;cache_block[175] <= 0;
        valid_bit[176]  <=   0;dirty_bit[176] <= 0;tag_address[176] <= 0;cache_block[176] <= 0;
        valid_bit[177]  <=   0;dirty_bit[177] <= 0;tag_address[177] <= 0;cache_block[177] <= 0;
        valid_bit[178]  <=   0;dirty_bit[178] <= 0;tag_address[178] <= 0;cache_block[178] <= 0;
        valid_bit[179]  <=   0;dirty_bit[179] <= 0;tag_address[179] <= 0;cache_block[179] <= 0;
        valid_bit[180]  <=   0;dirty_bit[180] <= 0;tag_address[180] <= 0;cache_block[180] <= 0;
        valid_bit[181]  <=   0;dirty_bit[181] <= 0;tag_address[181] <= 0;cache_block[181] <= 0;
        valid_bit[182]  <=   0;dirty_bit[182] <= 0;tag_address[182] <= 0;cache_block[182] <= 0;
        valid_bit[183]  <=   0;dirty_bit[183] <= 0;tag_address[183] <= 0;cache_block[183] <= 0;
        valid_bit[184]  <=   0;dirty_bit[184] <= 0;tag_address[184] <= 0;cache_block[184] <= 0;
        valid_bit[185]  <=   0;dirty_bit[185] <= 0;tag_address[185] <= 0;cache_block[185] <= 0;
        valid_bit[186]  <=   0;dirty_bit[186] <= 0;tag_address[186] <= 0;cache_block[186] <= 0;
        valid_bit[187]  <=   0;dirty_bit[187] <= 0;tag_address[187] <= 0;cache_block[187] <= 0;
        valid_bit[188]  <=   0;dirty_bit[188] <= 0;tag_address[188] <= 0;cache_block[188] <= 0;
        valid_bit[189]  <=   0;dirty_bit[189] <= 0;tag_address[189] <= 0;cache_block[189] <= 0;
        valid_bit[190]  <=   0;dirty_bit[190] <= 0;tag_address[190] <= 0;cache_block[190] <= 0;
        valid_bit[191]  <=   0;dirty_bit[191] <= 0;tag_address[191] <= 0;cache_block[191] <= 0;
        valid_bit[192]  <=   0;dirty_bit[192] <= 0;tag_address[192] <= 0;cache_block[192] <= 0;
        valid_bit[193]  <=   0;dirty_bit[193] <= 0;tag_address[193] <= 0;cache_block[193] <= 0;
        valid_bit[194]  <=   0;dirty_bit[194] <= 0;tag_address[194] <= 0;cache_block[194] <= 0;
        valid_bit[195]  <=   0;dirty_bit[195] <= 0;tag_address[195] <= 0;cache_block[195] <= 0;
        valid_bit[196]  <=   0;dirty_bit[196] <= 0;tag_address[196] <= 0;cache_block[196] <= 0;
        valid_bit[197]  <=   0;dirty_bit[197] <= 0;tag_address[197] <= 0;cache_block[197] <= 0;
        valid_bit[198]  <=   0;dirty_bit[198] <= 0;tag_address[198] <= 0;cache_block[198] <= 0;
        valid_bit[199]  <=   0;dirty_bit[199] <= 0;tag_address[199] <= 0;cache_block[199] <= 0;
        valid_bit[200]  <=   0;dirty_bit[200] <= 0;tag_address[200] <= 0;cache_block[200] <= 0;
        valid_bit[201]  <=   0;dirty_bit[201] <= 0;tag_address[201] <= 0;cache_block[201] <= 0;
        valid_bit[202]  <=   0;dirty_bit[202] <= 0;tag_address[202] <= 0;cache_block[202] <= 0;
        valid_bit[203]  <=   0;dirty_bit[203] <= 0;tag_address[203] <= 0;cache_block[203] <= 0;
        valid_bit[204]  <=   0;dirty_bit[204] <= 0;tag_address[204] <= 0;cache_block[204] <= 0;
        valid_bit[205]  <=   0;dirty_bit[205] <= 0;tag_address[205] <= 0;cache_block[205] <= 0;
        valid_bit[206]  <=   0;dirty_bit[206] <= 0;tag_address[206] <= 0;cache_block[206] <= 0;
        valid_bit[207]  <=   0;dirty_bit[207] <= 0;tag_address[207] <= 0;cache_block[207] <= 0;
        valid_bit[208]  <=   0;dirty_bit[208] <= 0;tag_address[208] <= 0;cache_block[208] <= 0;
        valid_bit[209]  <=   0;dirty_bit[209] <= 0;tag_address[209] <= 0;cache_block[209] <= 0;
        valid_bit[210]  <=   0;dirty_bit[210] <= 0;tag_address[210] <= 0;cache_block[210] <= 0;
        valid_bit[211]  <=   0;dirty_bit[211] <= 0;tag_address[211] <= 0;cache_block[211] <= 0;
        valid_bit[212]  <=   0;dirty_bit[212] <= 0;tag_address[212] <= 0;cache_block[212] <= 0;
        valid_bit[213]  <=   0;dirty_bit[213] <= 0;tag_address[213] <= 0;cache_block[213] <= 0;
        valid_bit[214]  <=   0;dirty_bit[214] <= 0;tag_address[214] <= 0;cache_block[214] <= 0;
        valid_bit[215]  <=   0;dirty_bit[215] <= 0;tag_address[215] <= 0;cache_block[215] <= 0;
        valid_bit[216]  <=   0;dirty_bit[216] <= 0;tag_address[216] <= 0;cache_block[216] <= 0;
        valid_bit[217]  <=   0;dirty_bit[217] <= 0;tag_address[217] <= 0;cache_block[217] <= 0;
        valid_bit[218]  <=   0;dirty_bit[218] <= 0;tag_address[218] <= 0;cache_block[218] <= 0;
        valid_bit[219]  <=   0;dirty_bit[219] <= 0;tag_address[219] <= 0;cache_block[219] <= 0;
        valid_bit[220]  <=   0;dirty_bit[220] <= 0;tag_address[220] <= 0;cache_block[220] <= 0;
        valid_bit[221]  <=   0;dirty_bit[221] <= 0;tag_address[221] <= 0;cache_block[221] <= 0;
        valid_bit[222]  <=   0;dirty_bit[222] <= 0;tag_address[222] <= 0;cache_block[222] <= 0;
        valid_bit[223]  <=   0;dirty_bit[223] <= 0;tag_address[223] <= 0;cache_block[223] <= 0;
        valid_bit[224]  <=   0;dirty_bit[224] <= 0;tag_address[224] <= 0;cache_block[224] <= 0;
        valid_bit[225]  <=   0;dirty_bit[225] <= 0;tag_address[225] <= 0;cache_block[225] <= 0;
        valid_bit[226]  <=   0;dirty_bit[226] <= 0;tag_address[226] <= 0;cache_block[226] <= 0;
        valid_bit[227]  <=   0;dirty_bit[227] <= 0;tag_address[227] <= 0;cache_block[227] <= 0;
        valid_bit[228]  <=   0;dirty_bit[228] <= 0;tag_address[228] <= 0;cache_block[228] <= 0;
        valid_bit[229]  <=   0;dirty_bit[229] <= 0;tag_address[229] <= 0;cache_block[229] <= 0;
        valid_bit[230]  <=   0;dirty_bit[230] <= 0;tag_address[230] <= 0;cache_block[230] <= 0;
        valid_bit[231]  <=   0;dirty_bit[231] <= 0;tag_address[231] <= 0;cache_block[231] <= 0;
        valid_bit[232]  <=   0;dirty_bit[232] <= 0;tag_address[232] <= 0;cache_block[232] <= 0;
        valid_bit[233]  <=   0;dirty_bit[233] <= 0;tag_address[233] <= 0;cache_block[233] <= 0;
        valid_bit[234]  <=   0;dirty_bit[234] <= 0;tag_address[234] <= 0;cache_block[234] <= 0;
        valid_bit[235]  <=   0;dirty_bit[235] <= 0;tag_address[235] <= 0;cache_block[235] <= 0;
        valid_bit[236]  <=   0;dirty_bit[236] <= 0;tag_address[236] <= 0;cache_block[236] <= 0;
        valid_bit[237]  <=   0;dirty_bit[237] <= 0;tag_address[237] <= 0;cache_block[237] <= 0;
        valid_bit[238]  <=   0;dirty_bit[238] <= 0;tag_address[238] <= 0;cache_block[238] <= 0;
        valid_bit[239]  <=   0;dirty_bit[239] <= 0;tag_address[239] <= 0;cache_block[239] <= 0;
        valid_bit[240]  <=   0;dirty_bit[240] <= 0;tag_address[240] <= 0;cache_block[240] <= 0;
        valid_bit[241]  <=   0;dirty_bit[241] <= 0;tag_address[241] <= 0;cache_block[241] <= 0;
        valid_bit[242]  <=   0;dirty_bit[242] <= 0;tag_address[242] <= 0;cache_block[242] <= 0;
        valid_bit[243]  <=   0;dirty_bit[243] <= 0;tag_address[243] <= 0;cache_block[243] <= 0;
        valid_bit[244]  <=   0;dirty_bit[244] <= 0;tag_address[244] <= 0;cache_block[244] <= 0;
        valid_bit[245]  <=   0;dirty_bit[245] <= 0;tag_address[245] <= 0;cache_block[245] <= 0;
        valid_bit[246]  <=   0;dirty_bit[246] <= 0;tag_address[246] <= 0;cache_block[246] <= 0;
        valid_bit[247]  <=   0;dirty_bit[247] <= 0;tag_address[247] <= 0;cache_block[247] <= 0;
        valid_bit[248]  <=   0;dirty_bit[248] <= 0;tag_address[248] <= 0;cache_block[248] <= 0;
        valid_bit[249]  <=   0;dirty_bit[249] <= 0;tag_address[249] <= 0;cache_block[249] <= 0;
        valid_bit[250]  <=   0;dirty_bit[250] <= 0;tag_address[250] <= 0;cache_block[250] <= 0;
        valid_bit[251]  <=   0;dirty_bit[251] <= 0;tag_address[251] <= 0;cache_block[251] <= 0;
        valid_bit[252]  <=   0;dirty_bit[252] <= 0;tag_address[252] <= 0;cache_block[252] <= 0;
        valid_bit[253]  <=   0;dirty_bit[253] <= 0;tag_address[253] <= 0;cache_block[253] <= 0;
        valid_bit[254]  <=   0;dirty_bit[254] <= 0;tag_address[254] <= 0;cache_block[254] <= 0;
        valid_bit[255]  <=   0;dirty_bit[255] <= 0;tag_address[255] <= 0;cache_block[255] <= 0;
        valid_bit[256]  <=   0;dirty_bit[256] <= 0;tag_address[256] <= 0;cache_block[256] <= 0;
        valid_bit[257]  <=   0;dirty_bit[257] <= 0;tag_address[257] <= 0;cache_block[257] <= 0;
        valid_bit[258]  <=   0;dirty_bit[258] <= 0;tag_address[258] <= 0;cache_block[258] <= 0;
        valid_bit[259]  <=   0;dirty_bit[259] <= 0;tag_address[259] <= 0;cache_block[259] <= 0;
        valid_bit[260]  <=   0;dirty_bit[260] <= 0;tag_address[260] <= 0;cache_block[260] <= 0;
        valid_bit[261]  <=   0;dirty_bit[261] <= 0;tag_address[261] <= 0;cache_block[261] <= 0;
        valid_bit[262]  <=   0;dirty_bit[262] <= 0;tag_address[262] <= 0;cache_block[262] <= 0;
        valid_bit[263]  <=   0;dirty_bit[263] <= 0;tag_address[263] <= 0;cache_block[263] <= 0;
        valid_bit[264]  <=   0;dirty_bit[264] <= 0;tag_address[264] <= 0;cache_block[264] <= 0;
        valid_bit[265]  <=   0;dirty_bit[265] <= 0;tag_address[265] <= 0;cache_block[265] <= 0;
        valid_bit[266]  <=   0;dirty_bit[266] <= 0;tag_address[266] <= 0;cache_block[266] <= 0;
        valid_bit[267]  <=   0;dirty_bit[267] <= 0;tag_address[267] <= 0;cache_block[267] <= 0;
        valid_bit[268]  <=   0;dirty_bit[268] <= 0;tag_address[268] <= 0;cache_block[268] <= 0;
        valid_bit[269]  <=   0;dirty_bit[269] <= 0;tag_address[269] <= 0;cache_block[269] <= 0;
        valid_bit[270]  <=   0;dirty_bit[270] <= 0;tag_address[270] <= 0;cache_block[270] <= 0;
        valid_bit[271]  <=   0;dirty_bit[271] <= 0;tag_address[271] <= 0;cache_block[271] <= 0;
        valid_bit[272]  <=   0;dirty_bit[272] <= 0;tag_address[272] <= 0;cache_block[272] <= 0;
        valid_bit[273]  <=   0;dirty_bit[273] <= 0;tag_address[273] <= 0;cache_block[273] <= 0;
        valid_bit[274]  <=   0;dirty_bit[274] <= 0;tag_address[274] <= 0;cache_block[274] <= 0;
        valid_bit[275]  <=   0;dirty_bit[275] <= 0;tag_address[275] <= 0;cache_block[275] <= 0;
        valid_bit[276]  <=   0;dirty_bit[276] <= 0;tag_address[276] <= 0;cache_block[276] <= 0;
        valid_bit[277]  <=   0;dirty_bit[277] <= 0;tag_address[277] <= 0;cache_block[277] <= 0;
        valid_bit[278]  <=   0;dirty_bit[278] <= 0;tag_address[278] <= 0;cache_block[278] <= 0;
        valid_bit[279]  <=   0;dirty_bit[279] <= 0;tag_address[279] <= 0;cache_block[279] <= 0;
        valid_bit[280]  <=   0;dirty_bit[280] <= 0;tag_address[280] <= 0;cache_block[280] <= 0;
        valid_bit[281]  <=   0;dirty_bit[281] <= 0;tag_address[281] <= 0;cache_block[281] <= 0;
        valid_bit[282]  <=   0;dirty_bit[282] <= 0;tag_address[282] <= 0;cache_block[282] <= 0;
        valid_bit[283]  <=   0;dirty_bit[283] <= 0;tag_address[283] <= 0;cache_block[283] <= 0;
        valid_bit[284]  <=   0;dirty_bit[284] <= 0;tag_address[284] <= 0;cache_block[284] <= 0;
        valid_bit[285]  <=   0;dirty_bit[285] <= 0;tag_address[285] <= 0;cache_block[285] <= 0;
        valid_bit[286]  <=   0;dirty_bit[286] <= 0;tag_address[286] <= 0;cache_block[286] <= 0;
        valid_bit[287]  <=   0;dirty_bit[287] <= 0;tag_address[287] <= 0;cache_block[287] <= 0;
        valid_bit[288]  <=   0;dirty_bit[288] <= 0;tag_address[288] <= 0;cache_block[288] <= 0;
        valid_bit[289]  <=   0;dirty_bit[289] <= 0;tag_address[289] <= 0;cache_block[289] <= 0;
        valid_bit[290]  <=   0;dirty_bit[290] <= 0;tag_address[290] <= 0;cache_block[290] <= 0;
        valid_bit[291]  <=   0;dirty_bit[291] <= 0;tag_address[291] <= 0;cache_block[291] <= 0;
        valid_bit[292]  <=   0;dirty_bit[292] <= 0;tag_address[292] <= 0;cache_block[292] <= 0;
        valid_bit[293]  <=   0;dirty_bit[293] <= 0;tag_address[293] <= 0;cache_block[293] <= 0;
        valid_bit[294]  <=   0;dirty_bit[294] <= 0;tag_address[294] <= 0;cache_block[294] <= 0;
        valid_bit[295]  <=   0;dirty_bit[295] <= 0;tag_address[295] <= 0;cache_block[295] <= 0;
        valid_bit[296]  <=   0;dirty_bit[296] <= 0;tag_address[296] <= 0;cache_block[296] <= 0;
        valid_bit[297]  <=   0;dirty_bit[297] <= 0;tag_address[297] <= 0;cache_block[297] <= 0;
        valid_bit[298]  <=   0;dirty_bit[298] <= 0;tag_address[298] <= 0;cache_block[298] <= 0;
        valid_bit[299]  <=   0;dirty_bit[299] <= 0;tag_address[299] <= 0;cache_block[299] <= 0;
        valid_bit[300]  <=   0;dirty_bit[300] <= 0;tag_address[300] <= 0;cache_block[300] <= 0;
        valid_bit[301]  <=   0;dirty_bit[301] <= 0;tag_address[301] <= 0;cache_block[301] <= 0;
        valid_bit[302]  <=   0;dirty_bit[302] <= 0;tag_address[302] <= 0;cache_block[302] <= 0;
        valid_bit[303]  <=   0;dirty_bit[303] <= 0;tag_address[303] <= 0;cache_block[303] <= 0;
        valid_bit[304]  <=   0;dirty_bit[304] <= 0;tag_address[304] <= 0;cache_block[304] <= 0;
        valid_bit[305]  <=   0;dirty_bit[305] <= 0;tag_address[305] <= 0;cache_block[305] <= 0;
        valid_bit[306]  <=   0;dirty_bit[306] <= 0;tag_address[306] <= 0;cache_block[306] <= 0;
        valid_bit[307]  <=   0;dirty_bit[307] <= 0;tag_address[307] <= 0;cache_block[307] <= 0;
        valid_bit[308]  <=   0;dirty_bit[308] <= 0;tag_address[308] <= 0;cache_block[308] <= 0;
        valid_bit[309]  <=   0;dirty_bit[309] <= 0;tag_address[309] <= 0;cache_block[309] <= 0;
        valid_bit[310]  <=   0;dirty_bit[310] <= 0;tag_address[310] <= 0;cache_block[310] <= 0;
        valid_bit[311]  <=   0;dirty_bit[311] <= 0;tag_address[311] <= 0;cache_block[311] <= 0;
        valid_bit[312]  <=   0;dirty_bit[312] <= 0;tag_address[312] <= 0;cache_block[312] <= 0;
        valid_bit[313]  <=   0;dirty_bit[313] <= 0;tag_address[313] <= 0;cache_block[313] <= 0;
        valid_bit[314]  <=   0;dirty_bit[314] <= 0;tag_address[314] <= 0;cache_block[314] <= 0;
        valid_bit[315]  <=   0;dirty_bit[315] <= 0;tag_address[315] <= 0;cache_block[315] <= 0;
        valid_bit[316]  <=   0;dirty_bit[316] <= 0;tag_address[316] <= 0;cache_block[316] <= 0;
        valid_bit[317]  <=   0;dirty_bit[317] <= 0;tag_address[317] <= 0;cache_block[317] <= 0;
        valid_bit[318]  <=   0;dirty_bit[318] <= 0;tag_address[318] <= 0;cache_block[318] <= 0;
        valid_bit[319]  <=   0;dirty_bit[319] <= 0;tag_address[319] <= 0;cache_block[319] <= 0;
        valid_bit[320]  <=   0;dirty_bit[320] <= 0;tag_address[320] <= 0;cache_block[320] <= 0;
        valid_bit[321]  <=   0;dirty_bit[321] <= 0;tag_address[321] <= 0;cache_block[321] <= 0;
        valid_bit[322]  <=   0;dirty_bit[322] <= 0;tag_address[322] <= 0;cache_block[322] <= 0;
        valid_bit[323]  <=   0;dirty_bit[323] <= 0;tag_address[323] <= 0;cache_block[323] <= 0;
        valid_bit[324]  <=   0;dirty_bit[324] <= 0;tag_address[324] <= 0;cache_block[324] <= 0;
        valid_bit[325]  <=   0;dirty_bit[325] <= 0;tag_address[325] <= 0;cache_block[325] <= 0;
        valid_bit[326]  <=   0;dirty_bit[326] <= 0;tag_address[326] <= 0;cache_block[326] <= 0;
        valid_bit[327]  <=   0;dirty_bit[327] <= 0;tag_address[327] <= 0;cache_block[327] <= 0;
        valid_bit[328]  <=   0;dirty_bit[328] <= 0;tag_address[328] <= 0;cache_block[328] <= 0;
        valid_bit[329]  <=   0;dirty_bit[329] <= 0;tag_address[329] <= 0;cache_block[329] <= 0;
        valid_bit[330]  <=   0;dirty_bit[330] <= 0;tag_address[330] <= 0;cache_block[330] <= 0;
        valid_bit[331]  <=   0;dirty_bit[331] <= 0;tag_address[331] <= 0;cache_block[331] <= 0;
        valid_bit[332]  <=   0;dirty_bit[332] <= 0;tag_address[332] <= 0;cache_block[332] <= 0;
        valid_bit[333]  <=   0;dirty_bit[333] <= 0;tag_address[333] <= 0;cache_block[333] <= 0;
        valid_bit[334]  <=   0;dirty_bit[334] <= 0;tag_address[334] <= 0;cache_block[334] <= 0;
        valid_bit[335]  <=   0;dirty_bit[335] <= 0;tag_address[335] <= 0;cache_block[335] <= 0;
        valid_bit[336]  <=   0;dirty_bit[336] <= 0;tag_address[336] <= 0;cache_block[336] <= 0;
        valid_bit[337]  <=   0;dirty_bit[337] <= 0;tag_address[337] <= 0;cache_block[337] <= 0;
        valid_bit[338]  <=   0;dirty_bit[338] <= 0;tag_address[338] <= 0;cache_block[338] <= 0;
        valid_bit[339]  <=   0;dirty_bit[339] <= 0;tag_address[339] <= 0;cache_block[339] <= 0;
        valid_bit[340]  <=   0;dirty_bit[340] <= 0;tag_address[340] <= 0;cache_block[340] <= 0;
        valid_bit[341]  <=   0;dirty_bit[341] <= 0;tag_address[341] <= 0;cache_block[341] <= 0;
        valid_bit[342]  <=   0;dirty_bit[342] <= 0;tag_address[342] <= 0;cache_block[342] <= 0;
        valid_bit[343]  <=   0;dirty_bit[343] <= 0;tag_address[343] <= 0;cache_block[343] <= 0;
        valid_bit[344]  <=   0;dirty_bit[344] <= 0;tag_address[344] <= 0;cache_block[344] <= 0;
        valid_bit[345]  <=   0;dirty_bit[345] <= 0;tag_address[345] <= 0;cache_block[345] <= 0;
        valid_bit[346]  <=   0;dirty_bit[346] <= 0;tag_address[346] <= 0;cache_block[346] <= 0;
        valid_bit[347]  <=   0;dirty_bit[347] <= 0;tag_address[347] <= 0;cache_block[347] <= 0;
        valid_bit[348]  <=   0;dirty_bit[348] <= 0;tag_address[348] <= 0;cache_block[348] <= 0;
        valid_bit[349]  <=   0;dirty_bit[349] <= 0;tag_address[349] <= 0;cache_block[349] <= 0;
        valid_bit[350]  <=   0;dirty_bit[350] <= 0;tag_address[350] <= 0;cache_block[350] <= 0;
        valid_bit[351]  <=   0;dirty_bit[351] <= 0;tag_address[351] <= 0;cache_block[351] <= 0;
        valid_bit[352]  <=   0;dirty_bit[352] <= 0;tag_address[352] <= 0;cache_block[352] <= 0;
        valid_bit[353]  <=   0;dirty_bit[353] <= 0;tag_address[353] <= 0;cache_block[353] <= 0;
        valid_bit[354]  <=   0;dirty_bit[354] <= 0;tag_address[354] <= 0;cache_block[354] <= 0;
        valid_bit[355]  <=   0;dirty_bit[355] <= 0;tag_address[355] <= 0;cache_block[355] <= 0;
        valid_bit[356]  <=   0;dirty_bit[356] <= 0;tag_address[356] <= 0;cache_block[356] <= 0;
        valid_bit[357]  <=   0;dirty_bit[357] <= 0;tag_address[357] <= 0;cache_block[357] <= 0;
        valid_bit[358]  <=   0;dirty_bit[358] <= 0;tag_address[358] <= 0;cache_block[358] <= 0;
        valid_bit[359]  <=   0;dirty_bit[359] <= 0;tag_address[359] <= 0;cache_block[359] <= 0;
        valid_bit[360]  <=   0;dirty_bit[360] <= 0;tag_address[360] <= 0;cache_block[360] <= 0;
        valid_bit[361]  <=   0;dirty_bit[361] <= 0;tag_address[361] <= 0;cache_block[361] <= 0;
        valid_bit[362]  <=   0;dirty_bit[362] <= 0;tag_address[362] <= 0;cache_block[362] <= 0;
        valid_bit[363]  <=   0;dirty_bit[363] <= 0;tag_address[363] <= 0;cache_block[363] <= 0;
        valid_bit[364]  <=   0;dirty_bit[364] <= 0;tag_address[364] <= 0;cache_block[364] <= 0;
        valid_bit[365]  <=   0;dirty_bit[365] <= 0;tag_address[365] <= 0;cache_block[365] <= 0;
        valid_bit[366]  <=   0;dirty_bit[366] <= 0;tag_address[366] <= 0;cache_block[366] <= 0;
        valid_bit[367]  <=   0;dirty_bit[367] <= 0;tag_address[367] <= 0;cache_block[367] <= 0;
        valid_bit[368]  <=   0;dirty_bit[368] <= 0;tag_address[368] <= 0;cache_block[368] <= 0;
        valid_bit[369]  <=   0;dirty_bit[369] <= 0;tag_address[369] <= 0;cache_block[369] <= 0;
        valid_bit[370]  <=   0;dirty_bit[370] <= 0;tag_address[370] <= 0;cache_block[370] <= 0;
        valid_bit[371]  <=   0;dirty_bit[371] <= 0;tag_address[371] <= 0;cache_block[371] <= 0;
        valid_bit[372]  <=   0;dirty_bit[372] <= 0;tag_address[372] <= 0;cache_block[372] <= 0;
        valid_bit[373]  <=   0;dirty_bit[373] <= 0;tag_address[373] <= 0;cache_block[373] <= 0;
        valid_bit[374]  <=   0;dirty_bit[374] <= 0;tag_address[374] <= 0;cache_block[374] <= 0;
        valid_bit[375]  <=   0;dirty_bit[375] <= 0;tag_address[375] <= 0;cache_block[375] <= 0;
        valid_bit[376]  <=   0;dirty_bit[376] <= 0;tag_address[376] <= 0;cache_block[376] <= 0;
        valid_bit[377]  <=   0;dirty_bit[377] <= 0;tag_address[377] <= 0;cache_block[377] <= 0;
        valid_bit[378]  <=   0;dirty_bit[378] <= 0;tag_address[378] <= 0;cache_block[378] <= 0;
        valid_bit[379]  <=   0;dirty_bit[379] <= 0;tag_address[379] <= 0;cache_block[379] <= 0;
        valid_bit[380]  <=   0;dirty_bit[380] <= 0;tag_address[380] <= 0;cache_block[380] <= 0;
        valid_bit[381]  <=   0;dirty_bit[381] <= 0;tag_address[381] <= 0;cache_block[381] <= 0;
        valid_bit[382]  <=   0;dirty_bit[382] <= 0;tag_address[382] <= 0;cache_block[382] <= 0;
        valid_bit[383]  <=   0;dirty_bit[383] <= 0;tag_address[383] <= 0;cache_block[383] <= 0;
        valid_bit[384]  <=   0;dirty_bit[384] <= 0;tag_address[384] <= 0;cache_block[384] <= 0;
        valid_bit[385]  <=   0;dirty_bit[385] <= 0;tag_address[385] <= 0;cache_block[385] <= 0;
        valid_bit[386]  <=   0;dirty_bit[386] <= 0;tag_address[386] <= 0;cache_block[386] <= 0;
        valid_bit[387]  <=   0;dirty_bit[387] <= 0;tag_address[387] <= 0;cache_block[387] <= 0;
        valid_bit[388]  <=   0;dirty_bit[388] <= 0;tag_address[388] <= 0;cache_block[388] <= 0;
        valid_bit[389]  <=   0;dirty_bit[389] <= 0;tag_address[389] <= 0;cache_block[389] <= 0;
        valid_bit[390]  <=   0;dirty_bit[390] <= 0;tag_address[390] <= 0;cache_block[390] <= 0;
        valid_bit[391]  <=   0;dirty_bit[391] <= 0;tag_address[391] <= 0;cache_block[391] <= 0;
        valid_bit[392]  <=   0;dirty_bit[392] <= 0;tag_address[392] <= 0;cache_block[392] <= 0;
        valid_bit[393]  <=   0;dirty_bit[393] <= 0;tag_address[393] <= 0;cache_block[393] <= 0;
        valid_bit[394]  <=   0;dirty_bit[394] <= 0;tag_address[394] <= 0;cache_block[394] <= 0;
        valid_bit[395]  <=   0;dirty_bit[395] <= 0;tag_address[395] <= 0;cache_block[395] <= 0;
        valid_bit[396]  <=   0;dirty_bit[396] <= 0;tag_address[396] <= 0;cache_block[396] <= 0;
        valid_bit[397]  <=   0;dirty_bit[397] <= 0;tag_address[397] <= 0;cache_block[397] <= 0;
        valid_bit[398]  <=   0;dirty_bit[398] <= 0;tag_address[398] <= 0;cache_block[398] <= 0;
        valid_bit[399]  <=   0;dirty_bit[399] <= 0;tag_address[399] <= 0;cache_block[399] <= 0;
        valid_bit[400]  <=   0;dirty_bit[400] <= 0;tag_address[400] <= 0;cache_block[400] <= 0;
        valid_bit[401]  <=   0;dirty_bit[401] <= 0;tag_address[401] <= 0;cache_block[401] <= 0;
        valid_bit[402]  <=   0;dirty_bit[402] <= 0;tag_address[402] <= 0;cache_block[402] <= 0;
        valid_bit[403]  <=   0;dirty_bit[403] <= 0;tag_address[403] <= 0;cache_block[403] <= 0;
        valid_bit[404]  <=   0;dirty_bit[404] <= 0;tag_address[404] <= 0;cache_block[404] <= 0;
        valid_bit[405]  <=   0;dirty_bit[405] <= 0;tag_address[405] <= 0;cache_block[405] <= 0;
        valid_bit[406]  <=   0;dirty_bit[406] <= 0;tag_address[406] <= 0;cache_block[406] <= 0;
        valid_bit[407]  <=   0;dirty_bit[407] <= 0;tag_address[407] <= 0;cache_block[407] <= 0;
        valid_bit[408]  <=   0;dirty_bit[408] <= 0;tag_address[408] <= 0;cache_block[408] <= 0;
        valid_bit[409]  <=   0;dirty_bit[409] <= 0;tag_address[409] <= 0;cache_block[409] <= 0;
        valid_bit[410]  <=   0;dirty_bit[410] <= 0;tag_address[410] <= 0;cache_block[410] <= 0;
        valid_bit[411]  <=   0;dirty_bit[411] <= 0;tag_address[411] <= 0;cache_block[411] <= 0;
        valid_bit[412]  <=   0;dirty_bit[412] <= 0;tag_address[412] <= 0;cache_block[412] <= 0;
        valid_bit[413]  <=   0;dirty_bit[413] <= 0;tag_address[413] <= 0;cache_block[413] <= 0;
        valid_bit[414]  <=   0;dirty_bit[414] <= 0;tag_address[414] <= 0;cache_block[414] <= 0;
        valid_bit[415]  <=   0;dirty_bit[415] <= 0;tag_address[415] <= 0;cache_block[415] <= 0;
        valid_bit[416]  <=   0;dirty_bit[416] <= 0;tag_address[416] <= 0;cache_block[416] <= 0;
        valid_bit[417]  <=   0;dirty_bit[417] <= 0;tag_address[417] <= 0;cache_block[417] <= 0;
        valid_bit[418]  <=   0;dirty_bit[418] <= 0;tag_address[418] <= 0;cache_block[418] <= 0;
        valid_bit[419]  <=   0;dirty_bit[419] <= 0;tag_address[419] <= 0;cache_block[419] <= 0;
        valid_bit[420]  <=   0;dirty_bit[420] <= 0;tag_address[420] <= 0;cache_block[420] <= 0;
        valid_bit[421]  <=   0;dirty_bit[421] <= 0;tag_address[421] <= 0;cache_block[421] <= 0;
        valid_bit[422]  <=   0;dirty_bit[422] <= 0;tag_address[422] <= 0;cache_block[422] <= 0;
        valid_bit[423]  <=   0;dirty_bit[423] <= 0;tag_address[423] <= 0;cache_block[423] <= 0;
        valid_bit[424]  <=   0;dirty_bit[424] <= 0;tag_address[424] <= 0;cache_block[424] <= 0;
        valid_bit[425]  <=   0;dirty_bit[425] <= 0;tag_address[425] <= 0;cache_block[425] <= 0;
        valid_bit[426]  <=   0;dirty_bit[426] <= 0;tag_address[426] <= 0;cache_block[426] <= 0;
        valid_bit[427]  <=   0;dirty_bit[427] <= 0;tag_address[427] <= 0;cache_block[427] <= 0;
        valid_bit[428]  <=   0;dirty_bit[428] <= 0;tag_address[428] <= 0;cache_block[428] <= 0;
        valid_bit[429]  <=   0;dirty_bit[429] <= 0;tag_address[429] <= 0;cache_block[429] <= 0;
        valid_bit[430]  <=   0;dirty_bit[430] <= 0;tag_address[430] <= 0;cache_block[430] <= 0;
        valid_bit[431]  <=   0;dirty_bit[431] <= 0;tag_address[431] <= 0;cache_block[431] <= 0;
        valid_bit[432]  <=   0;dirty_bit[432] <= 0;tag_address[432] <= 0;cache_block[432] <= 0;
        valid_bit[433]  <=   0;dirty_bit[433] <= 0;tag_address[433] <= 0;cache_block[433] <= 0;
        valid_bit[434]  <=   0;dirty_bit[434] <= 0;tag_address[434] <= 0;cache_block[434] <= 0;
        valid_bit[435]  <=   0;dirty_bit[435] <= 0;tag_address[435] <= 0;cache_block[435] <= 0;
        valid_bit[436]  <=   0;dirty_bit[436] <= 0;tag_address[436] <= 0;cache_block[436] <= 0;
        valid_bit[437]  <=   0;dirty_bit[437] <= 0;tag_address[437] <= 0;cache_block[437] <= 0;
        valid_bit[438]  <=   0;dirty_bit[438] <= 0;tag_address[438] <= 0;cache_block[438] <= 0;
        valid_bit[439]  <=   0;dirty_bit[439] <= 0;tag_address[439] <= 0;cache_block[439] <= 0;
        valid_bit[440]  <=   0;dirty_bit[440] <= 0;tag_address[440] <= 0;cache_block[440] <= 0;
        valid_bit[441]  <=   0;dirty_bit[441] <= 0;tag_address[441] <= 0;cache_block[441] <= 0;
        valid_bit[442]  <=   0;dirty_bit[442] <= 0;tag_address[442] <= 0;cache_block[442] <= 0;
        valid_bit[443]  <=   0;dirty_bit[443] <= 0;tag_address[443] <= 0;cache_block[443] <= 0;
        valid_bit[444]  <=   0;dirty_bit[444] <= 0;tag_address[444] <= 0;cache_block[444] <= 0;
        valid_bit[445]  <=   0;dirty_bit[445] <= 0;tag_address[445] <= 0;cache_block[445] <= 0;
        valid_bit[446]  <=   0;dirty_bit[446] <= 0;tag_address[446] <= 0;cache_block[446] <= 0;
        valid_bit[447]  <=   0;dirty_bit[447] <= 0;tag_address[447] <= 0;cache_block[447] <= 0;
        valid_bit[448]  <=   0;dirty_bit[448] <= 0;tag_address[448] <= 0;cache_block[448] <= 0;
        valid_bit[449]  <=   0;dirty_bit[449] <= 0;tag_address[449] <= 0;cache_block[449] <= 0;
        valid_bit[450]  <=   0;dirty_bit[450] <= 0;tag_address[450] <= 0;cache_block[450] <= 0;
        valid_bit[451]  <=   0;dirty_bit[451] <= 0;tag_address[451] <= 0;cache_block[451] <= 0;
        valid_bit[452]  <=   0;dirty_bit[452] <= 0;tag_address[452] <= 0;cache_block[452] <= 0;
        valid_bit[453]  <=   0;dirty_bit[453] <= 0;tag_address[453] <= 0;cache_block[453] <= 0;
        valid_bit[454]  <=   0;dirty_bit[454] <= 0;tag_address[454] <= 0;cache_block[454] <= 0;
        valid_bit[455]  <=   0;dirty_bit[455] <= 0;tag_address[455] <= 0;cache_block[455] <= 0;
        valid_bit[456]  <=   0;dirty_bit[456] <= 0;tag_address[456] <= 0;cache_block[456] <= 0;
        valid_bit[457]  <=   0;dirty_bit[457] <= 0;tag_address[457] <= 0;cache_block[457] <= 0;
        valid_bit[458]  <=   0;dirty_bit[458] <= 0;tag_address[458] <= 0;cache_block[458] <= 0;
        valid_bit[459]  <=   0;dirty_bit[459] <= 0;tag_address[459] <= 0;cache_block[459] <= 0;
        valid_bit[460]  <=   0;dirty_bit[460] <= 0;tag_address[460] <= 0;cache_block[460] <= 0;
        valid_bit[461]  <=   0;dirty_bit[461] <= 0;tag_address[461] <= 0;cache_block[461] <= 0;
        valid_bit[462]  <=   0;dirty_bit[462] <= 0;tag_address[462] <= 0;cache_block[462] <= 0;
        valid_bit[463]  <=   0;dirty_bit[463] <= 0;tag_address[463] <= 0;cache_block[463] <= 0;
        valid_bit[464]  <=   0;dirty_bit[464] <= 0;tag_address[464] <= 0;cache_block[464] <= 0;
        valid_bit[465]  <=   0;dirty_bit[465] <= 0;tag_address[465] <= 0;cache_block[465] <= 0;
        valid_bit[466]  <=   0;dirty_bit[466] <= 0;tag_address[466] <= 0;cache_block[466] <= 0;
        valid_bit[467]  <=   0;dirty_bit[467] <= 0;tag_address[467] <= 0;cache_block[467] <= 0;
        valid_bit[468]  <=   0;dirty_bit[468] <= 0;tag_address[468] <= 0;cache_block[468] <= 0;
        valid_bit[469]  <=   0;dirty_bit[469] <= 0;tag_address[469] <= 0;cache_block[469] <= 0;
        valid_bit[470]  <=   0;dirty_bit[470] <= 0;tag_address[470] <= 0;cache_block[470] <= 0;
        valid_bit[471]  <=   0;dirty_bit[471] <= 0;tag_address[471] <= 0;cache_block[471] <= 0;
        valid_bit[472]  <=   0;dirty_bit[472] <= 0;tag_address[472] <= 0;cache_block[472] <= 0;
        valid_bit[473]  <=   0;dirty_bit[473] <= 0;tag_address[473] <= 0;cache_block[473] <= 0;
        valid_bit[474]  <=   0;dirty_bit[474] <= 0;tag_address[474] <= 0;cache_block[474] <= 0;
        valid_bit[475]  <=   0;dirty_bit[475] <= 0;tag_address[475] <= 0;cache_block[475] <= 0;
        valid_bit[476]  <=   0;dirty_bit[476] <= 0;tag_address[476] <= 0;cache_block[476] <= 0;
        valid_bit[477]  <=   0;dirty_bit[477] <= 0;tag_address[477] <= 0;cache_block[477] <= 0;
        valid_bit[478]  <=   0;dirty_bit[478] <= 0;tag_address[478] <= 0;cache_block[478] <= 0;
        valid_bit[479]  <=   0;dirty_bit[479] <= 0;tag_address[479] <= 0;cache_block[479] <= 0;
        valid_bit[480]  <=   0;dirty_bit[480] <= 0;tag_address[480] <= 0;cache_block[480] <= 0;
        valid_bit[481]  <=   0;dirty_bit[481] <= 0;tag_address[481] <= 0;cache_block[481] <= 0;
        valid_bit[482]  <=   0;dirty_bit[482] <= 0;tag_address[482] <= 0;cache_block[482] <= 0;
        valid_bit[483]  <=   0;dirty_bit[483] <= 0;tag_address[483] <= 0;cache_block[483] <= 0;
        valid_bit[484]  <=   0;dirty_bit[484] <= 0;tag_address[484] <= 0;cache_block[484] <= 0;
        valid_bit[485]  <=   0;dirty_bit[485] <= 0;tag_address[485] <= 0;cache_block[485] <= 0;
        valid_bit[486]  <=   0;dirty_bit[486] <= 0;tag_address[486] <= 0;cache_block[486] <= 0;
        valid_bit[487]  <=   0;dirty_bit[487] <= 0;tag_address[487] <= 0;cache_block[487] <= 0;
        valid_bit[488]  <=   0;dirty_bit[488] <= 0;tag_address[488] <= 0;cache_block[488] <= 0;
        valid_bit[489]  <=   0;dirty_bit[489] <= 0;tag_address[489] <= 0;cache_block[489] <= 0;
        valid_bit[490]  <=   0;dirty_bit[490] <= 0;tag_address[490] <= 0;cache_block[490] <= 0;
        valid_bit[491]  <=   0;dirty_bit[491] <= 0;tag_address[491] <= 0;cache_block[491] <= 0;
        valid_bit[492]  <=   0;dirty_bit[492] <= 0;tag_address[492] <= 0;cache_block[492] <= 0;
        valid_bit[493]  <=   0;dirty_bit[493] <= 0;tag_address[493] <= 0;cache_block[493] <= 0;
        valid_bit[494]  <=   0;dirty_bit[494] <= 0;tag_address[494] <= 0;cache_block[494] <= 0;
        valid_bit[495]  <=   0;dirty_bit[495] <= 0;tag_address[495] <= 0;cache_block[495] <= 0;
        valid_bit[496]  <=   0;dirty_bit[496] <= 0;tag_address[496] <= 0;cache_block[496] <= 0;
        valid_bit[497]  <=   0;dirty_bit[497] <= 0;tag_address[497] <= 0;cache_block[497] <= 0;
        valid_bit[498]  <=   0;dirty_bit[498] <= 0;tag_address[498] <= 0;cache_block[498] <= 0;
        valid_bit[499]  <=   0;dirty_bit[499] <= 0;tag_address[499] <= 0;cache_block[499] <= 0;
        valid_bit[500]  <=   0;dirty_bit[500] <= 0;tag_address[500] <= 0;cache_block[500] <= 0;
        valid_bit[501]  <=   0;dirty_bit[501] <= 0;tag_address[501] <= 0;cache_block[501] <= 0;
        valid_bit[502]  <=   0;dirty_bit[502] <= 0;tag_address[502] <= 0;cache_block[502] <= 0;
        valid_bit[503]  <=   0;dirty_bit[503] <= 0;tag_address[503] <= 0;cache_block[503] <= 0;
        valid_bit[504]  <=   0;dirty_bit[504] <= 0;tag_address[504] <= 0;cache_block[504] <= 0;
        valid_bit[505]  <=   0;dirty_bit[505] <= 0;tag_address[505] <= 0;cache_block[505] <= 0;
        valid_bit[506]  <=   0;dirty_bit[506] <= 0;tag_address[506] <= 0;cache_block[506] <= 0;
        valid_bit[507]  <=   0;dirty_bit[507] <= 0;tag_address[507] <= 0;cache_block[507] <= 0;
        valid_bit[508]  <=   0;dirty_bit[508] <= 0;tag_address[508] <= 0;cache_block[508] <= 0;
        valid_bit[509]  <=   0;dirty_bit[509] <= 0;tag_address[509] <= 0;cache_block[509] <= 0;
        valid_bit[510]  <=   0;dirty_bit[510] <= 0;tag_address[510] <= 0;cache_block[510] <= 0;
        valid_bit[511]  <=   0;dirty_bit[511] <= 0;tag_address[511] <= 0;cache_block[511] <= 0;
        valid_bit[512]  <=   0;dirty_bit[512] <= 0;tag_address[512] <= 0;cache_block[512] <= 0;
        valid_bit[513]  <=   0;dirty_bit[513] <= 0;tag_address[513] <= 0;cache_block[513] <= 0;
        valid_bit[514]  <=   0;dirty_bit[514] <= 0;tag_address[514] <= 0;cache_block[514] <= 0;
        valid_bit[515]  <=   0;dirty_bit[515] <= 0;tag_address[515] <= 0;cache_block[515] <= 0;
        valid_bit[516]  <=   0;dirty_bit[516] <= 0;tag_address[516] <= 0;cache_block[516] <= 0;
        valid_bit[517]  <=   0;dirty_bit[517] <= 0;tag_address[517] <= 0;cache_block[517] <= 0;
        valid_bit[518]  <=   0;dirty_bit[518] <= 0;tag_address[518] <= 0;cache_block[518] <= 0;
        valid_bit[519]  <=   0;dirty_bit[519] <= 0;tag_address[519] <= 0;cache_block[519] <= 0;
        valid_bit[520]  <=   0;dirty_bit[520] <= 0;tag_address[520] <= 0;cache_block[520] <= 0;
        valid_bit[521]  <=   0;dirty_bit[521] <= 0;tag_address[521] <= 0;cache_block[521] <= 0;
        valid_bit[522]  <=   0;dirty_bit[522] <= 0;tag_address[522] <= 0;cache_block[522] <= 0;
        valid_bit[523]  <=   0;dirty_bit[523] <= 0;tag_address[523] <= 0;cache_block[523] <= 0;
        valid_bit[524]  <=   0;dirty_bit[524] <= 0;tag_address[524] <= 0;cache_block[524] <= 0;
        valid_bit[525]  <=   0;dirty_bit[525] <= 0;tag_address[525] <= 0;cache_block[525] <= 0;
        valid_bit[526]  <=   0;dirty_bit[526] <= 0;tag_address[526] <= 0;cache_block[526] <= 0;
        valid_bit[527]  <=   0;dirty_bit[527] <= 0;tag_address[527] <= 0;cache_block[527] <= 0;
        valid_bit[528]  <=   0;dirty_bit[528] <= 0;tag_address[528] <= 0;cache_block[528] <= 0;
        valid_bit[529]  <=   0;dirty_bit[529] <= 0;tag_address[529] <= 0;cache_block[529] <= 0;
        valid_bit[530]  <=   0;dirty_bit[530] <= 0;tag_address[530] <= 0;cache_block[530] <= 0;
        valid_bit[531]  <=   0;dirty_bit[531] <= 0;tag_address[531] <= 0;cache_block[531] <= 0;
        valid_bit[532]  <=   0;dirty_bit[532] <= 0;tag_address[532] <= 0;cache_block[532] <= 0;
        valid_bit[533]  <=   0;dirty_bit[533] <= 0;tag_address[533] <= 0;cache_block[533] <= 0;
        valid_bit[534]  <=   0;dirty_bit[534] <= 0;tag_address[534] <= 0;cache_block[534] <= 0;
        valid_bit[535]  <=   0;dirty_bit[535] <= 0;tag_address[535] <= 0;cache_block[535] <= 0;
        valid_bit[536]  <=   0;dirty_bit[536] <= 0;tag_address[536] <= 0;cache_block[536] <= 0;
        valid_bit[537]  <=   0;dirty_bit[537] <= 0;tag_address[537] <= 0;cache_block[537] <= 0;
        valid_bit[538]  <=   0;dirty_bit[538] <= 0;tag_address[538] <= 0;cache_block[538] <= 0;
        valid_bit[539]  <=   0;dirty_bit[539] <= 0;tag_address[539] <= 0;cache_block[539] <= 0;
        valid_bit[540]  <=   0;dirty_bit[540] <= 0;tag_address[540] <= 0;cache_block[540] <= 0;
        valid_bit[541]  <=   0;dirty_bit[541] <= 0;tag_address[541] <= 0;cache_block[541] <= 0;
        valid_bit[542]  <=   0;dirty_bit[542] <= 0;tag_address[542] <= 0;cache_block[542] <= 0;
        valid_bit[543]  <=   0;dirty_bit[543] <= 0;tag_address[543] <= 0;cache_block[543] <= 0;
        valid_bit[544]  <=   0;dirty_bit[544] <= 0;tag_address[544] <= 0;cache_block[544] <= 0;
        valid_bit[545]  <=   0;dirty_bit[545] <= 0;tag_address[545] <= 0;cache_block[545] <= 0;
        valid_bit[546]  <=   0;dirty_bit[546] <= 0;tag_address[546] <= 0;cache_block[546] <= 0;
        valid_bit[547]  <=   0;dirty_bit[547] <= 0;tag_address[547] <= 0;cache_block[547] <= 0;
        valid_bit[548]  <=   0;dirty_bit[548] <= 0;tag_address[548] <= 0;cache_block[548] <= 0;
        valid_bit[549]  <=   0;dirty_bit[549] <= 0;tag_address[549] <= 0;cache_block[549] <= 0;
        valid_bit[550]  <=   0;dirty_bit[550] <= 0;tag_address[550] <= 0;cache_block[550] <= 0;
        valid_bit[551]  <=   0;dirty_bit[551] <= 0;tag_address[551] <= 0;cache_block[551] <= 0;
        valid_bit[552]  <=   0;dirty_bit[552] <= 0;tag_address[552] <= 0;cache_block[552] <= 0;
        valid_bit[553]  <=   0;dirty_bit[553] <= 0;tag_address[553] <= 0;cache_block[553] <= 0;
        valid_bit[554]  <=   0;dirty_bit[554] <= 0;tag_address[554] <= 0;cache_block[554] <= 0;
        valid_bit[555]  <=   0;dirty_bit[555] <= 0;tag_address[555] <= 0;cache_block[555] <= 0;
        valid_bit[556]  <=   0;dirty_bit[556] <= 0;tag_address[556] <= 0;cache_block[556] <= 0;
        valid_bit[557]  <=   0;dirty_bit[557] <= 0;tag_address[557] <= 0;cache_block[557] <= 0;
        valid_bit[558]  <=   0;dirty_bit[558] <= 0;tag_address[558] <= 0;cache_block[558] <= 0;
        valid_bit[559]  <=   0;dirty_bit[559] <= 0;tag_address[559] <= 0;cache_block[559] <= 0;
        valid_bit[560]  <=   0;dirty_bit[560] <= 0;tag_address[560] <= 0;cache_block[560] <= 0;
        valid_bit[561]  <=   0;dirty_bit[561] <= 0;tag_address[561] <= 0;cache_block[561] <= 0;
        valid_bit[562]  <=   0;dirty_bit[562] <= 0;tag_address[562] <= 0;cache_block[562] <= 0;
        valid_bit[563]  <=   0;dirty_bit[563] <= 0;tag_address[563] <= 0;cache_block[563] <= 0;
        valid_bit[564]  <=   0;dirty_bit[564] <= 0;tag_address[564] <= 0;cache_block[564] <= 0;
        valid_bit[565]  <=   0;dirty_bit[565] <= 0;tag_address[565] <= 0;cache_block[565] <= 0;
        valid_bit[566]  <=   0;dirty_bit[566] <= 0;tag_address[566] <= 0;cache_block[566] <= 0;
        valid_bit[567]  <=   0;dirty_bit[567] <= 0;tag_address[567] <= 0;cache_block[567] <= 0;
        valid_bit[568]  <=   0;dirty_bit[568] <= 0;tag_address[568] <= 0;cache_block[568] <= 0;
        valid_bit[569]  <=   0;dirty_bit[569] <= 0;tag_address[569] <= 0;cache_block[569] <= 0;
        valid_bit[570]  <=   0;dirty_bit[570] <= 0;tag_address[570] <= 0;cache_block[570] <= 0;
        valid_bit[571]  <=   0;dirty_bit[571] <= 0;tag_address[571] <= 0;cache_block[571] <= 0;
        valid_bit[572]  <=   0;dirty_bit[572] <= 0;tag_address[572] <= 0;cache_block[572] <= 0;
        valid_bit[573]  <=   0;dirty_bit[573] <= 0;tag_address[573] <= 0;cache_block[573] <= 0;
        valid_bit[574]  <=   0;dirty_bit[574] <= 0;tag_address[574] <= 0;cache_block[574] <= 0;
        valid_bit[575]  <=   0;dirty_bit[575] <= 0;tag_address[575] <= 0;cache_block[575] <= 0;
        valid_bit[576]  <=   0;dirty_bit[576] <= 0;tag_address[576] <= 0;cache_block[576] <= 0;
        valid_bit[577]  <=   0;dirty_bit[577] <= 0;tag_address[577] <= 0;cache_block[577] <= 0;
        valid_bit[578]  <=   0;dirty_bit[578] <= 0;tag_address[578] <= 0;cache_block[578] <= 0;
        valid_bit[579]  <=   0;dirty_bit[579] <= 0;tag_address[579] <= 0;cache_block[579] <= 0;
        valid_bit[580]  <=   0;dirty_bit[580] <= 0;tag_address[580] <= 0;cache_block[580] <= 0;
        valid_bit[581]  <=   0;dirty_bit[581] <= 0;tag_address[581] <= 0;cache_block[581] <= 0;
        valid_bit[582]  <=   0;dirty_bit[582] <= 0;tag_address[582] <= 0;cache_block[582] <= 0;
        valid_bit[583]  <=   0;dirty_bit[583] <= 0;tag_address[583] <= 0;cache_block[583] <= 0;
        valid_bit[584]  <=   0;dirty_bit[584] <= 0;tag_address[584] <= 0;cache_block[584] <= 0;
        valid_bit[585]  <=   0;dirty_bit[585] <= 0;tag_address[585] <= 0;cache_block[585] <= 0;
        valid_bit[586]  <=   0;dirty_bit[586] <= 0;tag_address[586] <= 0;cache_block[586] <= 0;
        valid_bit[587]  <=   0;dirty_bit[587] <= 0;tag_address[587] <= 0;cache_block[587] <= 0;
        valid_bit[588]  <=   0;dirty_bit[588] <= 0;tag_address[588] <= 0;cache_block[588] <= 0;
        valid_bit[589]  <=   0;dirty_bit[589] <= 0;tag_address[589] <= 0;cache_block[589] <= 0;
        valid_bit[590]  <=   0;dirty_bit[590] <= 0;tag_address[590] <= 0;cache_block[590] <= 0;
        valid_bit[591]  <=   0;dirty_bit[591] <= 0;tag_address[591] <= 0;cache_block[591] <= 0;
        valid_bit[592]  <=   0;dirty_bit[592] <= 0;tag_address[592] <= 0;cache_block[592] <= 0;
        valid_bit[593]  <=   0;dirty_bit[593] <= 0;tag_address[593] <= 0;cache_block[593] <= 0;
        valid_bit[594]  <=   0;dirty_bit[594] <= 0;tag_address[594] <= 0;cache_block[594] <= 0;
        valid_bit[595]  <=   0;dirty_bit[595] <= 0;tag_address[595] <= 0;cache_block[595] <= 0;
        valid_bit[596]  <=   0;dirty_bit[596] <= 0;tag_address[596] <= 0;cache_block[596] <= 0;
        valid_bit[597]  <=   0;dirty_bit[597] <= 0;tag_address[597] <= 0;cache_block[597] <= 0;
        valid_bit[598]  <=   0;dirty_bit[598] <= 0;tag_address[598] <= 0;cache_block[598] <= 0;
        valid_bit[599]  <=   0;dirty_bit[599] <= 0;tag_address[599] <= 0;cache_block[599] <= 0;
        valid_bit[600]  <=   0;dirty_bit[600] <= 0;tag_address[600] <= 0;cache_block[600] <= 0;
        valid_bit[601]  <=   0;dirty_bit[601] <= 0;tag_address[601] <= 0;cache_block[601] <= 0;
        valid_bit[602]  <=   0;dirty_bit[602] <= 0;tag_address[602] <= 0;cache_block[602] <= 0;
        valid_bit[603]  <=   0;dirty_bit[603] <= 0;tag_address[603] <= 0;cache_block[603] <= 0;
        valid_bit[604]  <=   0;dirty_bit[604] <= 0;tag_address[604] <= 0;cache_block[604] <= 0;
        valid_bit[605]  <=   0;dirty_bit[605] <= 0;tag_address[605] <= 0;cache_block[605] <= 0;
        valid_bit[606]  <=   0;dirty_bit[606] <= 0;tag_address[606] <= 0;cache_block[606] <= 0;
        valid_bit[607]  <=   0;dirty_bit[607] <= 0;tag_address[607] <= 0;cache_block[607] <= 0;
        valid_bit[608]  <=   0;dirty_bit[608] <= 0;tag_address[608] <= 0;cache_block[608] <= 0;
        valid_bit[609]  <=   0;dirty_bit[609] <= 0;tag_address[609] <= 0;cache_block[609] <= 0;
        valid_bit[610]  <=   0;dirty_bit[610] <= 0;tag_address[610] <= 0;cache_block[610] <= 0;
        valid_bit[611]  <=   0;dirty_bit[611] <= 0;tag_address[611] <= 0;cache_block[611] <= 0;
        valid_bit[612]  <=   0;dirty_bit[612] <= 0;tag_address[612] <= 0;cache_block[612] <= 0;
        valid_bit[613]  <=   0;dirty_bit[613] <= 0;tag_address[613] <= 0;cache_block[613] <= 0;
        valid_bit[614]  <=   0;dirty_bit[614] <= 0;tag_address[614] <= 0;cache_block[614] <= 0;
        valid_bit[615]  <=   0;dirty_bit[615] <= 0;tag_address[615] <= 0;cache_block[615] <= 0;
        valid_bit[616]  <=   0;dirty_bit[616] <= 0;tag_address[616] <= 0;cache_block[616] <= 0;
        valid_bit[617]  <=   0;dirty_bit[617] <= 0;tag_address[617] <= 0;cache_block[617] <= 0;
        valid_bit[618]  <=   0;dirty_bit[618] <= 0;tag_address[618] <= 0;cache_block[618] <= 0;
        valid_bit[619]  <=   0;dirty_bit[619] <= 0;tag_address[619] <= 0;cache_block[619] <= 0;
        valid_bit[620]  <=   0;dirty_bit[620] <= 0;tag_address[620] <= 0;cache_block[620] <= 0;
        valid_bit[621]  <=   0;dirty_bit[621] <= 0;tag_address[621] <= 0;cache_block[621] <= 0;
        valid_bit[622]  <=   0;dirty_bit[622] <= 0;tag_address[622] <= 0;cache_block[622] <= 0;
        valid_bit[623]  <=   0;dirty_bit[623] <= 0;tag_address[623] <= 0;cache_block[623] <= 0;
        valid_bit[624]  <=   0;dirty_bit[624] <= 0;tag_address[624] <= 0;cache_block[624] <= 0;
        valid_bit[625]  <=   0;dirty_bit[625] <= 0;tag_address[625] <= 0;cache_block[625] <= 0;
        valid_bit[626]  <=   0;dirty_bit[626] <= 0;tag_address[626] <= 0;cache_block[626] <= 0;
        valid_bit[627]  <=   0;dirty_bit[627] <= 0;tag_address[627] <= 0;cache_block[627] <= 0;
        valid_bit[628]  <=   0;dirty_bit[628] <= 0;tag_address[628] <= 0;cache_block[628] <= 0;
        valid_bit[629]  <=   0;dirty_bit[629] <= 0;tag_address[629] <= 0;cache_block[629] <= 0;
        valid_bit[630]  <=   0;dirty_bit[630] <= 0;tag_address[630] <= 0;cache_block[630] <= 0;
        valid_bit[631]  <=   0;dirty_bit[631] <= 0;tag_address[631] <= 0;cache_block[631] <= 0;
        valid_bit[632]  <=   0;dirty_bit[632] <= 0;tag_address[632] <= 0;cache_block[632] <= 0;
        valid_bit[633]  <=   0;dirty_bit[633] <= 0;tag_address[633] <= 0;cache_block[633] <= 0;
        valid_bit[634]  <=   0;dirty_bit[634] <= 0;tag_address[634] <= 0;cache_block[634] <= 0;
        valid_bit[635]  <=   0;dirty_bit[635] <= 0;tag_address[635] <= 0;cache_block[635] <= 0;
        valid_bit[636]  <=   0;dirty_bit[636] <= 0;tag_address[636] <= 0;cache_block[636] <= 0;
        valid_bit[637]  <=   0;dirty_bit[637] <= 0;tag_address[637] <= 0;cache_block[637] <= 0;
        valid_bit[638]  <=   0;dirty_bit[638] <= 0;tag_address[638] <= 0;cache_block[638] <= 0;
        valid_bit[639]  <=   0;dirty_bit[639] <= 0;tag_address[639] <= 0;cache_block[639] <= 0;
        valid_bit[640]  <=   0;dirty_bit[640] <= 0;tag_address[640] <= 0;cache_block[640] <= 0;
        valid_bit[641]  <=   0;dirty_bit[641] <= 0;tag_address[641] <= 0;cache_block[641] <= 0;
        valid_bit[642]  <=   0;dirty_bit[642] <= 0;tag_address[642] <= 0;cache_block[642] <= 0;
        valid_bit[643]  <=   0;dirty_bit[643] <= 0;tag_address[643] <= 0;cache_block[643] <= 0;
        valid_bit[644]  <=   0;dirty_bit[644] <= 0;tag_address[644] <= 0;cache_block[644] <= 0;
        valid_bit[645]  <=   0;dirty_bit[645] <= 0;tag_address[645] <= 0;cache_block[645] <= 0;
        valid_bit[646]  <=   0;dirty_bit[646] <= 0;tag_address[646] <= 0;cache_block[646] <= 0;
        valid_bit[647]  <=   0;dirty_bit[647] <= 0;tag_address[647] <= 0;cache_block[647] <= 0;
        valid_bit[648]  <=   0;dirty_bit[648] <= 0;tag_address[648] <= 0;cache_block[648] <= 0;
        valid_bit[649]  <=   0;dirty_bit[649] <= 0;tag_address[649] <= 0;cache_block[649] <= 0;
        valid_bit[650]  <=   0;dirty_bit[650] <= 0;tag_address[650] <= 0;cache_block[650] <= 0;
        valid_bit[651]  <=   0;dirty_bit[651] <= 0;tag_address[651] <= 0;cache_block[651] <= 0;
        valid_bit[652]  <=   0;dirty_bit[652] <= 0;tag_address[652] <= 0;cache_block[652] <= 0;
        valid_bit[653]  <=   0;dirty_bit[653] <= 0;tag_address[653] <= 0;cache_block[653] <= 0;
        valid_bit[654]  <=   0;dirty_bit[654] <= 0;tag_address[654] <= 0;cache_block[654] <= 0;
        valid_bit[655]  <=   0;dirty_bit[655] <= 0;tag_address[655] <= 0;cache_block[655] <= 0;
        valid_bit[656]  <=   0;dirty_bit[656] <= 0;tag_address[656] <= 0;cache_block[656] <= 0;
        valid_bit[657]  <=   0;dirty_bit[657] <= 0;tag_address[657] <= 0;cache_block[657] <= 0;
        valid_bit[658]  <=   0;dirty_bit[658] <= 0;tag_address[658] <= 0;cache_block[658] <= 0;
        valid_bit[659]  <=   0;dirty_bit[659] <= 0;tag_address[659] <= 0;cache_block[659] <= 0;
        valid_bit[660]  <=   0;dirty_bit[660] <= 0;tag_address[660] <= 0;cache_block[660] <= 0;
        valid_bit[661]  <=   0;dirty_bit[661] <= 0;tag_address[661] <= 0;cache_block[661] <= 0;
        valid_bit[662]  <=   0;dirty_bit[662] <= 0;tag_address[662] <= 0;cache_block[662] <= 0;
        valid_bit[663]  <=   0;dirty_bit[663] <= 0;tag_address[663] <= 0;cache_block[663] <= 0;
        valid_bit[664]  <=   0;dirty_bit[664] <= 0;tag_address[664] <= 0;cache_block[664] <= 0;
        valid_bit[665]  <=   0;dirty_bit[665] <= 0;tag_address[665] <= 0;cache_block[665] <= 0;
        valid_bit[666]  <=   0;dirty_bit[666] <= 0;tag_address[666] <= 0;cache_block[666] <= 0;
        valid_bit[667]  <=   0;dirty_bit[667] <= 0;tag_address[667] <= 0;cache_block[667] <= 0;
        valid_bit[668]  <=   0;dirty_bit[668] <= 0;tag_address[668] <= 0;cache_block[668] <= 0;
        valid_bit[669]  <=   0;dirty_bit[669] <= 0;tag_address[669] <= 0;cache_block[669] <= 0;
        valid_bit[670]  <=   0;dirty_bit[670] <= 0;tag_address[670] <= 0;cache_block[670] <= 0;
        valid_bit[671]  <=   0;dirty_bit[671] <= 0;tag_address[671] <= 0;cache_block[671] <= 0;
        valid_bit[672]  <=   0;dirty_bit[672] <= 0;tag_address[672] <= 0;cache_block[672] <= 0;
        valid_bit[673]  <=   0;dirty_bit[673] <= 0;tag_address[673] <= 0;cache_block[673] <= 0;
        valid_bit[674]  <=   0;dirty_bit[674] <= 0;tag_address[674] <= 0;cache_block[674] <= 0;
        valid_bit[675]  <=   0;dirty_bit[675] <= 0;tag_address[675] <= 0;cache_block[675] <= 0;
        valid_bit[676]  <=   0;dirty_bit[676] <= 0;tag_address[676] <= 0;cache_block[676] <= 0;
        valid_bit[677]  <=   0;dirty_bit[677] <= 0;tag_address[677] <= 0;cache_block[677] <= 0;
        valid_bit[678]  <=   0;dirty_bit[678] <= 0;tag_address[678] <= 0;cache_block[678] <= 0;
        valid_bit[679]  <=   0;dirty_bit[679] <= 0;tag_address[679] <= 0;cache_block[679] <= 0;
        valid_bit[680]  <=   0;dirty_bit[680] <= 0;tag_address[680] <= 0;cache_block[680] <= 0;
        valid_bit[681]  <=   0;dirty_bit[681] <= 0;tag_address[681] <= 0;cache_block[681] <= 0;
        valid_bit[682]  <=   0;dirty_bit[682] <= 0;tag_address[682] <= 0;cache_block[682] <= 0;
        valid_bit[683]  <=   0;dirty_bit[683] <= 0;tag_address[683] <= 0;cache_block[683] <= 0;
        valid_bit[684]  <=   0;dirty_bit[684] <= 0;tag_address[684] <= 0;cache_block[684] <= 0;
        valid_bit[685]  <=   0;dirty_bit[685] <= 0;tag_address[685] <= 0;cache_block[685] <= 0;
        valid_bit[686]  <=   0;dirty_bit[686] <= 0;tag_address[686] <= 0;cache_block[686] <= 0;
        valid_bit[687]  <=   0;dirty_bit[687] <= 0;tag_address[687] <= 0;cache_block[687] <= 0;
        valid_bit[688]  <=   0;dirty_bit[688] <= 0;tag_address[688] <= 0;cache_block[688] <= 0;
        valid_bit[689]  <=   0;dirty_bit[689] <= 0;tag_address[689] <= 0;cache_block[689] <= 0;
        valid_bit[690]  <=   0;dirty_bit[690] <= 0;tag_address[690] <= 0;cache_block[690] <= 0;
        valid_bit[691]  <=   0;dirty_bit[691] <= 0;tag_address[691] <= 0;cache_block[691] <= 0;
        valid_bit[692]  <=   0;dirty_bit[692] <= 0;tag_address[692] <= 0;cache_block[692] <= 0;
        valid_bit[693]  <=   0;dirty_bit[693] <= 0;tag_address[693] <= 0;cache_block[693] <= 0;
        valid_bit[694]  <=   0;dirty_bit[694] <= 0;tag_address[694] <= 0;cache_block[694] <= 0;
        valid_bit[695]  <=   0;dirty_bit[695] <= 0;tag_address[695] <= 0;cache_block[695] <= 0;
        valid_bit[696]  <=   0;dirty_bit[696] <= 0;tag_address[696] <= 0;cache_block[696] <= 0;
        valid_bit[697]  <=   0;dirty_bit[697] <= 0;tag_address[697] <= 0;cache_block[697] <= 0;
        valid_bit[698]  <=   0;dirty_bit[698] <= 0;tag_address[698] <= 0;cache_block[698] <= 0;
        valid_bit[699]  <=   0;dirty_bit[699] <= 0;tag_address[699] <= 0;cache_block[699] <= 0;
        valid_bit[700]  <=   0;dirty_bit[700] <= 0;tag_address[700] <= 0;cache_block[700] <= 0;
        valid_bit[701]  <=   0;dirty_bit[701] <= 0;tag_address[701] <= 0;cache_block[701] <= 0;
        valid_bit[702]  <=   0;dirty_bit[702] <= 0;tag_address[702] <= 0;cache_block[702] <= 0;
        valid_bit[703]  <=   0;dirty_bit[703] <= 0;tag_address[703] <= 0;cache_block[703] <= 0;
        valid_bit[704]  <=   0;dirty_bit[704] <= 0;tag_address[704] <= 0;cache_block[704] <= 0;
        valid_bit[705]  <=   0;dirty_bit[705] <= 0;tag_address[705] <= 0;cache_block[705] <= 0;
        valid_bit[706]  <=   0;dirty_bit[706] <= 0;tag_address[706] <= 0;cache_block[706] <= 0;
        valid_bit[707]  <=   0;dirty_bit[707] <= 0;tag_address[707] <= 0;cache_block[707] <= 0;
        valid_bit[708]  <=   0;dirty_bit[708] <= 0;tag_address[708] <= 0;cache_block[708] <= 0;
        valid_bit[709]  <=   0;dirty_bit[709] <= 0;tag_address[709] <= 0;cache_block[709] <= 0;
        valid_bit[710]  <=   0;dirty_bit[710] <= 0;tag_address[710] <= 0;cache_block[710] <= 0;
        valid_bit[711]  <=   0;dirty_bit[711] <= 0;tag_address[711] <= 0;cache_block[711] <= 0;
        valid_bit[712]  <=   0;dirty_bit[712] <= 0;tag_address[712] <= 0;cache_block[712] <= 0;
        valid_bit[713]  <=   0;dirty_bit[713] <= 0;tag_address[713] <= 0;cache_block[713] <= 0;
        valid_bit[714]  <=   0;dirty_bit[714] <= 0;tag_address[714] <= 0;cache_block[714] <= 0;
        valid_bit[715]  <=   0;dirty_bit[715] <= 0;tag_address[715] <= 0;cache_block[715] <= 0;
        valid_bit[716]  <=   0;dirty_bit[716] <= 0;tag_address[716] <= 0;cache_block[716] <= 0;
        valid_bit[717]  <=   0;dirty_bit[717] <= 0;tag_address[717] <= 0;cache_block[717] <= 0;
        valid_bit[718]  <=   0;dirty_bit[718] <= 0;tag_address[718] <= 0;cache_block[718] <= 0;
        valid_bit[719]  <=   0;dirty_bit[719] <= 0;tag_address[719] <= 0;cache_block[719] <= 0;
        valid_bit[720]  <=   0;dirty_bit[720] <= 0;tag_address[720] <= 0;cache_block[720] <= 0;
        valid_bit[721]  <=   0;dirty_bit[721] <= 0;tag_address[721] <= 0;cache_block[721] <= 0;
        valid_bit[722]  <=   0;dirty_bit[722] <= 0;tag_address[722] <= 0;cache_block[722] <= 0;
        valid_bit[723]  <=   0;dirty_bit[723] <= 0;tag_address[723] <= 0;cache_block[723] <= 0;
        valid_bit[724]  <=   0;dirty_bit[724] <= 0;tag_address[724] <= 0;cache_block[724] <= 0;
        valid_bit[725]  <=   0;dirty_bit[725] <= 0;tag_address[725] <= 0;cache_block[725] <= 0;
        valid_bit[726]  <=   0;dirty_bit[726] <= 0;tag_address[726] <= 0;cache_block[726] <= 0;
        valid_bit[727]  <=   0;dirty_bit[727] <= 0;tag_address[727] <= 0;cache_block[727] <= 0;
        valid_bit[728]  <=   0;dirty_bit[728] <= 0;tag_address[728] <= 0;cache_block[728] <= 0;
        valid_bit[729]  <=   0;dirty_bit[729] <= 0;tag_address[729] <= 0;cache_block[729] <= 0;
        valid_bit[730]  <=   0;dirty_bit[730] <= 0;tag_address[730] <= 0;cache_block[730] <= 0;
        valid_bit[731]  <=   0;dirty_bit[731] <= 0;tag_address[731] <= 0;cache_block[731] <= 0;
        valid_bit[732]  <=   0;dirty_bit[732] <= 0;tag_address[732] <= 0;cache_block[732] <= 0;
        valid_bit[733]  <=   0;dirty_bit[733] <= 0;tag_address[733] <= 0;cache_block[733] <= 0;
        valid_bit[734]  <=   0;dirty_bit[734] <= 0;tag_address[734] <= 0;cache_block[734] <= 0;
        valid_bit[735]  <=   0;dirty_bit[735] <= 0;tag_address[735] <= 0;cache_block[735] <= 0;
        valid_bit[736]  <=   0;dirty_bit[736] <= 0;tag_address[736] <= 0;cache_block[736] <= 0;
        valid_bit[737]  <=   0;dirty_bit[737] <= 0;tag_address[737] <= 0;cache_block[737] <= 0;
        valid_bit[738]  <=   0;dirty_bit[738] <= 0;tag_address[738] <= 0;cache_block[738] <= 0;
        valid_bit[739]  <=   0;dirty_bit[739] <= 0;tag_address[739] <= 0;cache_block[739] <= 0;
        valid_bit[740]  <=   0;dirty_bit[740] <= 0;tag_address[740] <= 0;cache_block[740] <= 0;
        valid_bit[741]  <=   0;dirty_bit[741] <= 0;tag_address[741] <= 0;cache_block[741] <= 0;
        valid_bit[742]  <=   0;dirty_bit[742] <= 0;tag_address[742] <= 0;cache_block[742] <= 0;
        valid_bit[743]  <=   0;dirty_bit[743] <= 0;tag_address[743] <= 0;cache_block[743] <= 0;
        valid_bit[744]  <=   0;dirty_bit[744] <= 0;tag_address[744] <= 0;cache_block[744] <= 0;
        valid_bit[745]  <=   0;dirty_bit[745] <= 0;tag_address[745] <= 0;cache_block[745] <= 0;
        valid_bit[746]  <=   0;dirty_bit[746] <= 0;tag_address[746] <= 0;cache_block[746] <= 0;
        valid_bit[747]  <=   0;dirty_bit[747] <= 0;tag_address[747] <= 0;cache_block[747] <= 0;
        valid_bit[748]  <=   0;dirty_bit[748] <= 0;tag_address[748] <= 0;cache_block[748] <= 0;
        valid_bit[749]  <=   0;dirty_bit[749] <= 0;tag_address[749] <= 0;cache_block[749] <= 0;
        valid_bit[750]  <=   0;dirty_bit[750] <= 0;tag_address[750] <= 0;cache_block[750] <= 0;
        valid_bit[751]  <=   0;dirty_bit[751] <= 0;tag_address[751] <= 0;cache_block[751] <= 0;
        valid_bit[752]  <=   0;dirty_bit[752] <= 0;tag_address[752] <= 0;cache_block[752] <= 0;
        valid_bit[753]  <=   0;dirty_bit[753] <= 0;tag_address[753] <= 0;cache_block[753] <= 0;
        valid_bit[754]  <=   0;dirty_bit[754] <= 0;tag_address[754] <= 0;cache_block[754] <= 0;
        valid_bit[755]  <=   0;dirty_bit[755] <= 0;tag_address[755] <= 0;cache_block[755] <= 0;
        valid_bit[756]  <=   0;dirty_bit[756] <= 0;tag_address[756] <= 0;cache_block[756] <= 0;
        valid_bit[757]  <=   0;dirty_bit[757] <= 0;tag_address[757] <= 0;cache_block[757] <= 0;
        valid_bit[758]  <=   0;dirty_bit[758] <= 0;tag_address[758] <= 0;cache_block[758] <= 0;
        valid_bit[759]  <=   0;dirty_bit[759] <= 0;tag_address[759] <= 0;cache_block[759] <= 0;
        valid_bit[760]  <=   0;dirty_bit[760] <= 0;tag_address[760] <= 0;cache_block[760] <= 0;
        valid_bit[761]  <=   0;dirty_bit[761] <= 0;tag_address[761] <= 0;cache_block[761] <= 0;
        valid_bit[762]  <=   0;dirty_bit[762] <= 0;tag_address[762] <= 0;cache_block[762] <= 0;
        valid_bit[763]  <=   0;dirty_bit[763] <= 0;tag_address[763] <= 0;cache_block[763] <= 0;
        valid_bit[764]  <=   0;dirty_bit[764] <= 0;tag_address[764] <= 0;cache_block[764] <= 0;
        valid_bit[765]  <=   0;dirty_bit[765] <= 0;tag_address[765] <= 0;cache_block[765] <= 0;
        valid_bit[766]  <=   0;dirty_bit[766] <= 0;tag_address[766] <= 0;cache_block[766] <= 0;
        valid_bit[767]  <=   0;dirty_bit[767] <= 0;tag_address[767] <= 0;cache_block[767] <= 0;
        valid_bit[768]  <=   0;dirty_bit[768] <= 0;tag_address[768] <= 0;cache_block[768] <= 0;
        valid_bit[769]  <=   0;dirty_bit[769] <= 0;tag_address[769] <= 0;cache_block[769] <= 0;
        valid_bit[770]  <=   0;dirty_bit[770] <= 0;tag_address[770] <= 0;cache_block[770] <= 0;
        valid_bit[771]  <=   0;dirty_bit[771] <= 0;tag_address[771] <= 0;cache_block[771] <= 0;
        valid_bit[772]  <=   0;dirty_bit[772] <= 0;tag_address[772] <= 0;cache_block[772] <= 0;
        valid_bit[773]  <=   0;dirty_bit[773] <= 0;tag_address[773] <= 0;cache_block[773] <= 0;
        valid_bit[774]  <=   0;dirty_bit[774] <= 0;tag_address[774] <= 0;cache_block[774] <= 0;
        valid_bit[775]  <=   0;dirty_bit[775] <= 0;tag_address[775] <= 0;cache_block[775] <= 0;
        valid_bit[776]  <=   0;dirty_bit[776] <= 0;tag_address[776] <= 0;cache_block[776] <= 0;
        valid_bit[777]  <=   0;dirty_bit[777] <= 0;tag_address[777] <= 0;cache_block[777] <= 0;
        valid_bit[778]  <=   0;dirty_bit[778] <= 0;tag_address[778] <= 0;cache_block[778] <= 0;
        valid_bit[779]  <=   0;dirty_bit[779] <= 0;tag_address[779] <= 0;cache_block[779] <= 0;
        valid_bit[780]  <=   0;dirty_bit[780] <= 0;tag_address[780] <= 0;cache_block[780] <= 0;
        valid_bit[781]  <=   0;dirty_bit[781] <= 0;tag_address[781] <= 0;cache_block[781] <= 0;
        valid_bit[782]  <=   0;dirty_bit[782] <= 0;tag_address[782] <= 0;cache_block[782] <= 0;
        valid_bit[783]  <=   0;dirty_bit[783] <= 0;tag_address[783] <= 0;cache_block[783] <= 0;
        valid_bit[784]  <=   0;dirty_bit[784] <= 0;tag_address[784] <= 0;cache_block[784] <= 0;
        valid_bit[785]  <=   0;dirty_bit[785] <= 0;tag_address[785] <= 0;cache_block[785] <= 0;
        valid_bit[786]  <=   0;dirty_bit[786] <= 0;tag_address[786] <= 0;cache_block[786] <= 0;
        valid_bit[787]  <=   0;dirty_bit[787] <= 0;tag_address[787] <= 0;cache_block[787] <= 0;
        valid_bit[788]  <=   0;dirty_bit[788] <= 0;tag_address[788] <= 0;cache_block[788] <= 0;
        valid_bit[789]  <=   0;dirty_bit[789] <= 0;tag_address[789] <= 0;cache_block[789] <= 0;
        valid_bit[790]  <=   0;dirty_bit[790] <= 0;tag_address[790] <= 0;cache_block[790] <= 0;
        valid_bit[791]  <=   0;dirty_bit[791] <= 0;tag_address[791] <= 0;cache_block[791] <= 0;
        valid_bit[792]  <=   0;dirty_bit[792] <= 0;tag_address[792] <= 0;cache_block[792] <= 0;
        valid_bit[793]  <=   0;dirty_bit[793] <= 0;tag_address[793] <= 0;cache_block[793] <= 0;
        valid_bit[794]  <=   0;dirty_bit[794] <= 0;tag_address[794] <= 0;cache_block[794] <= 0;
        valid_bit[795]  <=   0;dirty_bit[795] <= 0;tag_address[795] <= 0;cache_block[795] <= 0;
        valid_bit[796]  <=   0;dirty_bit[796] <= 0;tag_address[796] <= 0;cache_block[796] <= 0;
        valid_bit[797]  <=   0;dirty_bit[797] <= 0;tag_address[797] <= 0;cache_block[797] <= 0;
        valid_bit[798]  <=   0;dirty_bit[798] <= 0;tag_address[798] <= 0;cache_block[798] <= 0;
        valid_bit[799]  <=   0;dirty_bit[799] <= 0;tag_address[799] <= 0;cache_block[799] <= 0;
        valid_bit[800]  <=   0;dirty_bit[800] <= 0;tag_address[800] <= 0;cache_block[800] <= 0;
        valid_bit[801]  <=   0;dirty_bit[801] <= 0;tag_address[801] <= 0;cache_block[801] <= 0;
        valid_bit[802]  <=   0;dirty_bit[802] <= 0;tag_address[802] <= 0;cache_block[802] <= 0;
        valid_bit[803]  <=   0;dirty_bit[803] <= 0;tag_address[803] <= 0;cache_block[803] <= 0;
        valid_bit[804]  <=   0;dirty_bit[804] <= 0;tag_address[804] <= 0;cache_block[804] <= 0;
        valid_bit[805]  <=   0;dirty_bit[805] <= 0;tag_address[805] <= 0;cache_block[805] <= 0;
        valid_bit[806]  <=   0;dirty_bit[806] <= 0;tag_address[806] <= 0;cache_block[806] <= 0;
        valid_bit[807]  <=   0;dirty_bit[807] <= 0;tag_address[807] <= 0;cache_block[807] <= 0;
        valid_bit[808]  <=   0;dirty_bit[808] <= 0;tag_address[808] <= 0;cache_block[808] <= 0;
        valid_bit[809]  <=   0;dirty_bit[809] <= 0;tag_address[809] <= 0;cache_block[809] <= 0;
        valid_bit[810]  <=   0;dirty_bit[810] <= 0;tag_address[810] <= 0;cache_block[810] <= 0;
        valid_bit[811]  <=   0;dirty_bit[811] <= 0;tag_address[811] <= 0;cache_block[811] <= 0;
        valid_bit[812]  <=   0;dirty_bit[812] <= 0;tag_address[812] <= 0;cache_block[812] <= 0;
        valid_bit[813]  <=   0;dirty_bit[813] <= 0;tag_address[813] <= 0;cache_block[813] <= 0;
        valid_bit[814]  <=   0;dirty_bit[814] <= 0;tag_address[814] <= 0;cache_block[814] <= 0;
        valid_bit[815]  <=   0;dirty_bit[815] <= 0;tag_address[815] <= 0;cache_block[815] <= 0;
        valid_bit[816]  <=   0;dirty_bit[816] <= 0;tag_address[816] <= 0;cache_block[816] <= 0;
        valid_bit[817]  <=   0;dirty_bit[817] <= 0;tag_address[817] <= 0;cache_block[817] <= 0;
        valid_bit[818]  <=   0;dirty_bit[818] <= 0;tag_address[818] <= 0;cache_block[818] <= 0;
        valid_bit[819]  <=   0;dirty_bit[819] <= 0;tag_address[819] <= 0;cache_block[819] <= 0;
        valid_bit[820]  <=   0;dirty_bit[820] <= 0;tag_address[820] <= 0;cache_block[820] <= 0;
        valid_bit[821]  <=   0;dirty_bit[821] <= 0;tag_address[821] <= 0;cache_block[821] <= 0;
        valid_bit[822]  <=   0;dirty_bit[822] <= 0;tag_address[822] <= 0;cache_block[822] <= 0;
        valid_bit[823]  <=   0;dirty_bit[823] <= 0;tag_address[823] <= 0;cache_block[823] <= 0;
        valid_bit[824]  <=   0;dirty_bit[824] <= 0;tag_address[824] <= 0;cache_block[824] <= 0;
        valid_bit[825]  <=   0;dirty_bit[825] <= 0;tag_address[825] <= 0;cache_block[825] <= 0;
        valid_bit[826]  <=   0;dirty_bit[826] <= 0;tag_address[826] <= 0;cache_block[826] <= 0;
        valid_bit[827]  <=   0;dirty_bit[827] <= 0;tag_address[827] <= 0;cache_block[827] <= 0;
        valid_bit[828]  <=   0;dirty_bit[828] <= 0;tag_address[828] <= 0;cache_block[828] <= 0;
        valid_bit[829]  <=   0;dirty_bit[829] <= 0;tag_address[829] <= 0;cache_block[829] <= 0;
        valid_bit[830]  <=   0;dirty_bit[830] <= 0;tag_address[830] <= 0;cache_block[830] <= 0;
        valid_bit[831]  <=   0;dirty_bit[831] <= 0;tag_address[831] <= 0;cache_block[831] <= 0;
        valid_bit[832]  <=   0;dirty_bit[832] <= 0;tag_address[832] <= 0;cache_block[832] <= 0;
        valid_bit[833]  <=   0;dirty_bit[833] <= 0;tag_address[833] <= 0;cache_block[833] <= 0;
        valid_bit[834]  <=   0;dirty_bit[834] <= 0;tag_address[834] <= 0;cache_block[834] <= 0;
        valid_bit[835]  <=   0;dirty_bit[835] <= 0;tag_address[835] <= 0;cache_block[835] <= 0;
        valid_bit[836]  <=   0;dirty_bit[836] <= 0;tag_address[836] <= 0;cache_block[836] <= 0;
        valid_bit[837]  <=   0;dirty_bit[837] <= 0;tag_address[837] <= 0;cache_block[837] <= 0;
        valid_bit[838]  <=   0;dirty_bit[838] <= 0;tag_address[838] <= 0;cache_block[838] <= 0;
        valid_bit[839]  <=   0;dirty_bit[839] <= 0;tag_address[839] <= 0;cache_block[839] <= 0;
        valid_bit[840]  <=   0;dirty_bit[840] <= 0;tag_address[840] <= 0;cache_block[840] <= 0;
        valid_bit[841]  <=   0;dirty_bit[841] <= 0;tag_address[841] <= 0;cache_block[841] <= 0;
        valid_bit[842]  <=   0;dirty_bit[842] <= 0;tag_address[842] <= 0;cache_block[842] <= 0;
        valid_bit[843]  <=   0;dirty_bit[843] <= 0;tag_address[843] <= 0;cache_block[843] <= 0;
        valid_bit[844]  <=   0;dirty_bit[844] <= 0;tag_address[844] <= 0;cache_block[844] <= 0;
        valid_bit[845]  <=   0;dirty_bit[845] <= 0;tag_address[845] <= 0;cache_block[845] <= 0;
        valid_bit[846]  <=   0;dirty_bit[846] <= 0;tag_address[846] <= 0;cache_block[846] <= 0;
        valid_bit[847]  <=   0;dirty_bit[847] <= 0;tag_address[847] <= 0;cache_block[847] <= 0;
        valid_bit[848]  <=   0;dirty_bit[848] <= 0;tag_address[848] <= 0;cache_block[848] <= 0;
        valid_bit[849]  <=   0;dirty_bit[849] <= 0;tag_address[849] <= 0;cache_block[849] <= 0;
        valid_bit[850]  <=   0;dirty_bit[850] <= 0;tag_address[850] <= 0;cache_block[850] <= 0;
        valid_bit[851]  <=   0;dirty_bit[851] <= 0;tag_address[851] <= 0;cache_block[851] <= 0;
        valid_bit[852]  <=   0;dirty_bit[852] <= 0;tag_address[852] <= 0;cache_block[852] <= 0;
        valid_bit[853]  <=   0;dirty_bit[853] <= 0;tag_address[853] <= 0;cache_block[853] <= 0;
        valid_bit[854]  <=   0;dirty_bit[854] <= 0;tag_address[854] <= 0;cache_block[854] <= 0;
        valid_bit[855]  <=   0;dirty_bit[855] <= 0;tag_address[855] <= 0;cache_block[855] <= 0;
        valid_bit[856]  <=   0;dirty_bit[856] <= 0;tag_address[856] <= 0;cache_block[856] <= 0;
        valid_bit[857]  <=   0;dirty_bit[857] <= 0;tag_address[857] <= 0;cache_block[857] <= 0;
        valid_bit[858]  <=   0;dirty_bit[858] <= 0;tag_address[858] <= 0;cache_block[858] <= 0;
        valid_bit[859]  <=   0;dirty_bit[859] <= 0;tag_address[859] <= 0;cache_block[859] <= 0;
        valid_bit[860]  <=   0;dirty_bit[860] <= 0;tag_address[860] <= 0;cache_block[860] <= 0;
        valid_bit[861]  <=   0;dirty_bit[861] <= 0;tag_address[861] <= 0;cache_block[861] <= 0;
        valid_bit[862]  <=   0;dirty_bit[862] <= 0;tag_address[862] <= 0;cache_block[862] <= 0;
        valid_bit[863]  <=   0;dirty_bit[863] <= 0;tag_address[863] <= 0;cache_block[863] <= 0;
        valid_bit[864]  <=   0;dirty_bit[864] <= 0;tag_address[864] <= 0;cache_block[864] <= 0;
        valid_bit[865]  <=   0;dirty_bit[865] <= 0;tag_address[865] <= 0;cache_block[865] <= 0;
        valid_bit[866]  <=   0;dirty_bit[866] <= 0;tag_address[866] <= 0;cache_block[866] <= 0;
        valid_bit[867]  <=   0;dirty_bit[867] <= 0;tag_address[867] <= 0;cache_block[867] <= 0;
        valid_bit[868]  <=   0;dirty_bit[868] <= 0;tag_address[868] <= 0;cache_block[868] <= 0;
        valid_bit[869]  <=   0;dirty_bit[869] <= 0;tag_address[869] <= 0;cache_block[869] <= 0;
        valid_bit[870]  <=   0;dirty_bit[870] <= 0;tag_address[870] <= 0;cache_block[870] <= 0;
        valid_bit[871]  <=   0;dirty_bit[871] <= 0;tag_address[871] <= 0;cache_block[871] <= 0;
        valid_bit[872]  <=   0;dirty_bit[872] <= 0;tag_address[872] <= 0;cache_block[872] <= 0;
        valid_bit[873]  <=   0;dirty_bit[873] <= 0;tag_address[873] <= 0;cache_block[873] <= 0;
        valid_bit[874]  <=   0;dirty_bit[874] <= 0;tag_address[874] <= 0;cache_block[874] <= 0;
        valid_bit[875]  <=   0;dirty_bit[875] <= 0;tag_address[875] <= 0;cache_block[875] <= 0;
        valid_bit[876]  <=   0;dirty_bit[876] <= 0;tag_address[876] <= 0;cache_block[876] <= 0;
        valid_bit[877]  <=   0;dirty_bit[877] <= 0;tag_address[877] <= 0;cache_block[877] <= 0;
        valid_bit[878]  <=   0;dirty_bit[878] <= 0;tag_address[878] <= 0;cache_block[878] <= 0;
        valid_bit[879]  <=   0;dirty_bit[879] <= 0;tag_address[879] <= 0;cache_block[879] <= 0;
        valid_bit[880]  <=   0;dirty_bit[880] <= 0;tag_address[880] <= 0;cache_block[880] <= 0;
        valid_bit[881]  <=   0;dirty_bit[881] <= 0;tag_address[881] <= 0;cache_block[881] <= 0;
        valid_bit[882]  <=   0;dirty_bit[882] <= 0;tag_address[882] <= 0;cache_block[882] <= 0;
        valid_bit[883]  <=   0;dirty_bit[883] <= 0;tag_address[883] <= 0;cache_block[883] <= 0;
        valid_bit[884]  <=   0;dirty_bit[884] <= 0;tag_address[884] <= 0;cache_block[884] <= 0;
        valid_bit[885]  <=   0;dirty_bit[885] <= 0;tag_address[885] <= 0;cache_block[885] <= 0;
        valid_bit[886]  <=   0;dirty_bit[886] <= 0;tag_address[886] <= 0;cache_block[886] <= 0;
        valid_bit[887]  <=   0;dirty_bit[887] <= 0;tag_address[887] <= 0;cache_block[887] <= 0;
        valid_bit[888]  <=   0;dirty_bit[888] <= 0;tag_address[888] <= 0;cache_block[888] <= 0;
        valid_bit[889]  <=   0;dirty_bit[889] <= 0;tag_address[889] <= 0;cache_block[889] <= 0;
        valid_bit[890]  <=   0;dirty_bit[890] <= 0;tag_address[890] <= 0;cache_block[890] <= 0;
        valid_bit[891]  <=   0;dirty_bit[891] <= 0;tag_address[891] <= 0;cache_block[891] <= 0;
        valid_bit[892]  <=   0;dirty_bit[892] <= 0;tag_address[892] <= 0;cache_block[892] <= 0;
        valid_bit[893]  <=   0;dirty_bit[893] <= 0;tag_address[893] <= 0;cache_block[893] <= 0;
        valid_bit[894]  <=   0;dirty_bit[894] <= 0;tag_address[894] <= 0;cache_block[894] <= 0;
        valid_bit[895]  <=   0;dirty_bit[895] <= 0;tag_address[895] <= 0;cache_block[895] <= 0;
        valid_bit[896]  <=   0;dirty_bit[896] <= 0;tag_address[896] <= 0;cache_block[896] <= 0;
        valid_bit[897]  <=   0;dirty_bit[897] <= 0;tag_address[897] <= 0;cache_block[897] <= 0;
        valid_bit[898]  <=   0;dirty_bit[898] <= 0;tag_address[898] <= 0;cache_block[898] <= 0;
        valid_bit[899]  <=   0;dirty_bit[899] <= 0;tag_address[899] <= 0;cache_block[899] <= 0;
        valid_bit[900]  <=   0;dirty_bit[900] <= 0;tag_address[900] <= 0;cache_block[900] <= 0;
        valid_bit[901]  <=   0;dirty_bit[901] <= 0;tag_address[901] <= 0;cache_block[901] <= 0;
        valid_bit[902]  <=   0;dirty_bit[902] <= 0;tag_address[902] <= 0;cache_block[902] <= 0;
        valid_bit[903]  <=   0;dirty_bit[903] <= 0;tag_address[903] <= 0;cache_block[903] <= 0;
        valid_bit[904]  <=   0;dirty_bit[904] <= 0;tag_address[904] <= 0;cache_block[904] <= 0;
        valid_bit[905]  <=   0;dirty_bit[905] <= 0;tag_address[905] <= 0;cache_block[905] <= 0;
        valid_bit[906]  <=   0;dirty_bit[906] <= 0;tag_address[906] <= 0;cache_block[906] <= 0;
        valid_bit[907]  <=   0;dirty_bit[907] <= 0;tag_address[907] <= 0;cache_block[907] <= 0;
        valid_bit[908]  <=   0;dirty_bit[908] <= 0;tag_address[908] <= 0;cache_block[908] <= 0;
        valid_bit[909]  <=   0;dirty_bit[909] <= 0;tag_address[909] <= 0;cache_block[909] <= 0;
        valid_bit[910]  <=   0;dirty_bit[910] <= 0;tag_address[910] <= 0;cache_block[910] <= 0;
        valid_bit[911]  <=   0;dirty_bit[911] <= 0;tag_address[911] <= 0;cache_block[911] <= 0;
        valid_bit[912]  <=   0;dirty_bit[912] <= 0;tag_address[912] <= 0;cache_block[912] <= 0;
        valid_bit[913]  <=   0;dirty_bit[913] <= 0;tag_address[913] <= 0;cache_block[913] <= 0;
        valid_bit[914]  <=   0;dirty_bit[914] <= 0;tag_address[914] <= 0;cache_block[914] <= 0;
        valid_bit[915]  <=   0;dirty_bit[915] <= 0;tag_address[915] <= 0;cache_block[915] <= 0;
        valid_bit[916]  <=   0;dirty_bit[916] <= 0;tag_address[916] <= 0;cache_block[916] <= 0;
        valid_bit[917]  <=   0;dirty_bit[917] <= 0;tag_address[917] <= 0;cache_block[917] <= 0;
        valid_bit[918]  <=   0;dirty_bit[918] <= 0;tag_address[918] <= 0;cache_block[918] <= 0;
        valid_bit[919]  <=   0;dirty_bit[919] <= 0;tag_address[919] <= 0;cache_block[919] <= 0;
        valid_bit[920]  <=   0;dirty_bit[920] <= 0;tag_address[920] <= 0;cache_block[920] <= 0;
        valid_bit[921]  <=   0;dirty_bit[921] <= 0;tag_address[921] <= 0;cache_block[921] <= 0;
        valid_bit[922]  <=   0;dirty_bit[922] <= 0;tag_address[922] <= 0;cache_block[922] <= 0;
        valid_bit[923]  <=   0;dirty_bit[923] <= 0;tag_address[923] <= 0;cache_block[923] <= 0;
        valid_bit[924]  <=   0;dirty_bit[924] <= 0;tag_address[924] <= 0;cache_block[924] <= 0;
        valid_bit[925]  <=   0;dirty_bit[925] <= 0;tag_address[925] <= 0;cache_block[925] <= 0;
        valid_bit[926]  <=   0;dirty_bit[926] <= 0;tag_address[926] <= 0;cache_block[926] <= 0;
        valid_bit[927]  <=   0;dirty_bit[927] <= 0;tag_address[927] <= 0;cache_block[927] <= 0;
        valid_bit[928]  <=   0;dirty_bit[928] <= 0;tag_address[928] <= 0;cache_block[928] <= 0;
        valid_bit[929]  <=   0;dirty_bit[929] <= 0;tag_address[929] <= 0;cache_block[929] <= 0;
        valid_bit[930]  <=   0;dirty_bit[930] <= 0;tag_address[930] <= 0;cache_block[930] <= 0;
        valid_bit[931]  <=   0;dirty_bit[931] <= 0;tag_address[931] <= 0;cache_block[931] <= 0;
        valid_bit[932]  <=   0;dirty_bit[932] <= 0;tag_address[932] <= 0;cache_block[932] <= 0;
        valid_bit[933]  <=   0;dirty_bit[933] <= 0;tag_address[933] <= 0;cache_block[933] <= 0;
        valid_bit[934]  <=   0;dirty_bit[934] <= 0;tag_address[934] <= 0;cache_block[934] <= 0;
        valid_bit[935]  <=   0;dirty_bit[935] <= 0;tag_address[935] <= 0;cache_block[935] <= 0;
        valid_bit[936]  <=   0;dirty_bit[936] <= 0;tag_address[936] <= 0;cache_block[936] <= 0;
        valid_bit[937]  <=   0;dirty_bit[937] <= 0;tag_address[937] <= 0;cache_block[937] <= 0;
        valid_bit[938]  <=   0;dirty_bit[938] <= 0;tag_address[938] <= 0;cache_block[938] <= 0;
        valid_bit[939]  <=   0;dirty_bit[939] <= 0;tag_address[939] <= 0;cache_block[939] <= 0;
        valid_bit[940]  <=   0;dirty_bit[940] <= 0;tag_address[940] <= 0;cache_block[940] <= 0;
        valid_bit[941]  <=   0;dirty_bit[941] <= 0;tag_address[941] <= 0;cache_block[941] <= 0;
        valid_bit[942]  <=   0;dirty_bit[942] <= 0;tag_address[942] <= 0;cache_block[942] <= 0;
        valid_bit[943]  <=   0;dirty_bit[943] <= 0;tag_address[943] <= 0;cache_block[943] <= 0;
        valid_bit[944]  <=   0;dirty_bit[944] <= 0;tag_address[944] <= 0;cache_block[944] <= 0;
        valid_bit[945]  <=   0;dirty_bit[945] <= 0;tag_address[945] <= 0;cache_block[945] <= 0;
        valid_bit[946]  <=   0;dirty_bit[946] <= 0;tag_address[946] <= 0;cache_block[946] <= 0;
        valid_bit[947]  <=   0;dirty_bit[947] <= 0;tag_address[947] <= 0;cache_block[947] <= 0;
        valid_bit[948]  <=   0;dirty_bit[948] <= 0;tag_address[948] <= 0;cache_block[948] <= 0;
        valid_bit[949]  <=   0;dirty_bit[949] <= 0;tag_address[949] <= 0;cache_block[949] <= 0;
        valid_bit[950]  <=   0;dirty_bit[950] <= 0;tag_address[950] <= 0;cache_block[950] <= 0;
        valid_bit[951]  <=   0;dirty_bit[951] <= 0;tag_address[951] <= 0;cache_block[951] <= 0;
        valid_bit[952]  <=   0;dirty_bit[952] <= 0;tag_address[952] <= 0;cache_block[952] <= 0;
        valid_bit[953]  <=   0;dirty_bit[953] <= 0;tag_address[953] <= 0;cache_block[953] <= 0;
        valid_bit[954]  <=   0;dirty_bit[954] <= 0;tag_address[954] <= 0;cache_block[954] <= 0;
        valid_bit[955]  <=   0;dirty_bit[955] <= 0;tag_address[955] <= 0;cache_block[955] <= 0;
        valid_bit[956]  <=   0;dirty_bit[956] <= 0;tag_address[956] <= 0;cache_block[956] <= 0;
        valid_bit[957]  <=   0;dirty_bit[957] <= 0;tag_address[957] <= 0;cache_block[957] <= 0;
        valid_bit[958]  <=   0;dirty_bit[958] <= 0;tag_address[958] <= 0;cache_block[958] <= 0;
        valid_bit[959]  <=   0;dirty_bit[959] <= 0;tag_address[959] <= 0;cache_block[959] <= 0;
        valid_bit[960]  <=   0;dirty_bit[960] <= 0;tag_address[960] <= 0;cache_block[960] <= 0;
        valid_bit[961]  <=   0;dirty_bit[961] <= 0;tag_address[961] <= 0;cache_block[961] <= 0;
        valid_bit[962]  <=   0;dirty_bit[962] <= 0;tag_address[962] <= 0;cache_block[962] <= 0;
        valid_bit[963]  <=   0;dirty_bit[963] <= 0;tag_address[963] <= 0;cache_block[963] <= 0;
        valid_bit[964]  <=   0;dirty_bit[964] <= 0;tag_address[964] <= 0;cache_block[964] <= 0;
        valid_bit[965]  <=   0;dirty_bit[965] <= 0;tag_address[965] <= 0;cache_block[965] <= 0;
        valid_bit[966]  <=   0;dirty_bit[966] <= 0;tag_address[966] <= 0;cache_block[966] <= 0;
        valid_bit[967]  <=   0;dirty_bit[967] <= 0;tag_address[967] <= 0;cache_block[967] <= 0;
        valid_bit[968]  <=   0;dirty_bit[968] <= 0;tag_address[968] <= 0;cache_block[968] <= 0;
        valid_bit[969]  <=   0;dirty_bit[969] <= 0;tag_address[969] <= 0;cache_block[969] <= 0;
        valid_bit[970]  <=   0;dirty_bit[970] <= 0;tag_address[970] <= 0;cache_block[970] <= 0;
        valid_bit[971]  <=   0;dirty_bit[971] <= 0;tag_address[971] <= 0;cache_block[971] <= 0;
        valid_bit[972]  <=   0;dirty_bit[972] <= 0;tag_address[972] <= 0;cache_block[972] <= 0;
        valid_bit[973]  <=   0;dirty_bit[973] <= 0;tag_address[973] <= 0;cache_block[973] <= 0;
        valid_bit[974]  <=   0;dirty_bit[974] <= 0;tag_address[974] <= 0;cache_block[974] <= 0;
        valid_bit[975]  <=   0;dirty_bit[975] <= 0;tag_address[975] <= 0;cache_block[975] <= 0;
        valid_bit[976]  <=   0;dirty_bit[976] <= 0;tag_address[976] <= 0;cache_block[976] <= 0;
        valid_bit[977]  <=   0;dirty_bit[977] <= 0;tag_address[977] <= 0;cache_block[977] <= 0;
        valid_bit[978]  <=   0;dirty_bit[978] <= 0;tag_address[978] <= 0;cache_block[978] <= 0;
        valid_bit[979]  <=   0;dirty_bit[979] <= 0;tag_address[979] <= 0;cache_block[979] <= 0;
        valid_bit[980]  <=   0;dirty_bit[980] <= 0;tag_address[980] <= 0;cache_block[980] <= 0;
        valid_bit[981]  <=   0;dirty_bit[981] <= 0;tag_address[981] <= 0;cache_block[981] <= 0;
        valid_bit[982]  <=   0;dirty_bit[982] <= 0;tag_address[982] <= 0;cache_block[982] <= 0;
        valid_bit[983]  <=   0;dirty_bit[983] <= 0;tag_address[983] <= 0;cache_block[983] <= 0;
        valid_bit[984]  <=   0;dirty_bit[984] <= 0;tag_address[984] <= 0;cache_block[984] <= 0;
        valid_bit[985]  <=   0;dirty_bit[985] <= 0;tag_address[985] <= 0;cache_block[985] <= 0;
        valid_bit[986]  <=   0;dirty_bit[986] <= 0;tag_address[986] <= 0;cache_block[986] <= 0;
        valid_bit[987]  <=   0;dirty_bit[987] <= 0;tag_address[987] <= 0;cache_block[987] <= 0;
        valid_bit[988]  <=   0;dirty_bit[988] <= 0;tag_address[988] <= 0;cache_block[988] <= 0;
        valid_bit[989]  <=   0;dirty_bit[989] <= 0;tag_address[989] <= 0;cache_block[989] <= 0;
        valid_bit[990]  <=   0;dirty_bit[990] <= 0;tag_address[990] <= 0;cache_block[990] <= 0;
        valid_bit[991]  <=   0;dirty_bit[991] <= 0;tag_address[991] <= 0;cache_block[991] <= 0;
        valid_bit[992]  <=   0;dirty_bit[992] <= 0;tag_address[992] <= 0;cache_block[992] <= 0;
        valid_bit[993]  <=   0;dirty_bit[993] <= 0;tag_address[993] <= 0;cache_block[993] <= 0;
        valid_bit[994]  <=   0;dirty_bit[994] <= 0;tag_address[994] <= 0;cache_block[994] <= 0;
        valid_bit[995]  <=   0;dirty_bit[995] <= 0;tag_address[995] <= 0;cache_block[995] <= 0;
        valid_bit[996]  <=   0;dirty_bit[996] <= 0;tag_address[996] <= 0;cache_block[996] <= 0;
        valid_bit[997]  <=   0;dirty_bit[997] <= 0;tag_address[997] <= 0;cache_block[997] <= 0;
        valid_bit[998]  <=   0;dirty_bit[998] <= 0;tag_address[998] <= 0;cache_block[998] <= 0;
        valid_bit[999]  <=   0;dirty_bit[999] <= 0;tag_address[999] <= 0;cache_block[999] <= 0;
        valid_bit[1000]  <=   0;dirty_bit[1000] <= 0;tag_address[1000] <= 0;cache_block[1000] <= 0;
        valid_bit[1001]  <=   0;dirty_bit[1001] <= 0;tag_address[1001] <= 0;cache_block[1001] <= 0;
        valid_bit[1002]  <=   0;dirty_bit[1002] <= 0;tag_address[1002] <= 0;cache_block[1002] <= 0;
        valid_bit[1003]  <=   0;dirty_bit[1003] <= 0;tag_address[1003] <= 0;cache_block[1003] <= 0;
        valid_bit[1004]  <=   0;dirty_bit[1004] <= 0;tag_address[1004] <= 0;cache_block[1004] <= 0;
        valid_bit[1005]  <=   0;dirty_bit[1005] <= 0;tag_address[1005] <= 0;cache_block[1005] <= 0;
        valid_bit[1006]  <=   0;dirty_bit[1006] <= 0;tag_address[1006] <= 0;cache_block[1006] <= 0;
        valid_bit[1007]  <=   0;dirty_bit[1007] <= 0;tag_address[1007] <= 0;cache_block[1007] <= 0;
        valid_bit[1008]  <=   0;dirty_bit[1008] <= 0;tag_address[1008] <= 0;cache_block[1008] <= 0;
        valid_bit[1009]  <=   0;dirty_bit[1009] <= 0;tag_address[1009] <= 0;cache_block[1009] <= 0;
        valid_bit[1010]  <=   0;dirty_bit[1010] <= 0;tag_address[1010] <= 0;cache_block[1010] <= 0;
        valid_bit[1011]  <=   0;dirty_bit[1011] <= 0;tag_address[1011] <= 0;cache_block[1011] <= 0;
        valid_bit[1012]  <=   0;dirty_bit[1012] <= 0;tag_address[1012] <= 0;cache_block[1012] <= 0;
        valid_bit[1013]  <=   0;dirty_bit[1013] <= 0;tag_address[1013] <= 0;cache_block[1013] <= 0;
        valid_bit[1014]  <=   0;dirty_bit[1014] <= 0;tag_address[1014] <= 0;cache_block[1014] <= 0;
        valid_bit[1015]  <=   0;dirty_bit[1015] <= 0;tag_address[1015] <= 0;cache_block[1015] <= 0;
        valid_bit[1016]  <=   0;dirty_bit[1016] <= 0;tag_address[1016] <= 0;cache_block[1016] <= 0;
        valid_bit[1017]  <=   0;dirty_bit[1017] <= 0;tag_address[1017] <= 0;cache_block[1017] <= 0;
        valid_bit[1018]  <=   0;dirty_bit[1018] <= 0;tag_address[1018] <= 0;cache_block[1018] <= 0;
        valid_bit[1019]  <=   0;dirty_bit[1019] <= 0;tag_address[1019] <= 0;cache_block[1019] <= 0;
        valid_bit[1020]  <=   0;dirty_bit[1020] <= 0;tag_address[1020] <= 0;cache_block[1020] <= 0;
        valid_bit[1021]  <=   0;dirty_bit[1021] <= 0;tag_address[1021] <= 0;cache_block[1021] <= 0;
        valid_bit[1022]  <=   0;dirty_bit[1022] <= 0;tag_address[1022] <= 0;cache_block[1022] <= 0;
        valid_bit[1023]  <=   0;dirty_bit[1023] <= 0;tag_address[1023] <= 0;cache_block[1023] <= 0;














    end
end
            

endmodule




/*
else begin
    //wr miss
    //wr allocate
    if(!valid_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
        cache_block[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_cpu_wr_data;
        tag_address[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_cpu_address[TAG_HIGH:TAG_LOW];
        dirty_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]         <=   1;
        valid_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]         <=   1;
        o_cpu_busy                                                             <=   0;
        o_mem_wr_en                                                            <=   0;
    end
    else if(valid_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
        if(dirty_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
            o_mem_wr_data <= cache_block[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]];
            o_mem_wr_address <= {tag_address[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]],i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW],6'd0};
            o_mem_wr_en <= 1;
        end
        cache_block[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_cpu_wr_data;
        tag_address[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]       <=   i_cpu_address[TAG_HIGH:TAG_LOW];
        dirty_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]         <=   1;
        o_cpu_busy                                                             <=   0;
    end
end


*/

/*










module dm_cache #(
    parameter ADDRESS_WIDTH =64,
    parameter WRITE_DATA=64,
    parameter BLOCK_SIZE_BYTE=64,
    parameter BLOCK_SIZE_BITS=6,
    parameter BLOCK_NUMBER_BITS=3,
    parameter CACHE_SIZE=64*3
)(
clk,
rst_n,
i_cpu_valid,
i_cpu_rd_wr,
i_cpu_address,
o_cpu_ready,
i_cpu_write_data,
o_cpu_read_data,
o_cpu_read_valid,
i_cpu_read_ready,


o_mem_valid,
o_mem_rd_wr,
o_mem_address,
i_mem_ready,
o_mem_write_data,
i_mem_read_data,
i_mem_read_valid,
o_mem_read_ready
);

input clk;
input rst_n;
localparam TAG_WIDTH = ADDRESS_WIDTH-BLOCK_NUMBER_BITS-BLOCK_SIZE_BITS;
localparam BLOCK_ADDRESS_HIGH = ADDRESS_WIDTH-TAG_WIDTH-1;
localparam BLOCK_ADDRESS_LOW = BLOCK_SIZE_BITS; 
localparam TAG_HIGH = ADDRESS_WIDTH-1;
localparam TAG_LOW = BLOCK_ADDRESS_HIGH +1; 
input i_cpu_valid;
input i_cpu_rd_wr;
input [ADDRESS_WIDTH-1:0] i_cpu_address;


output reg o_cpu_ready;
input [WRITE_DATA*8-1:0] i_cpu_write_data;
output reg [WRITE_DATA*8-1:0] o_cpu_read_data;
output reg o_cpu_read_valid;
input i_cpu_read_ready;

output reg o_mem_valid;
output reg o_mem_rd_wr;
output reg [ADDRESS_WIDTH-1:0] o_mem_address;
input i_mem_ready;
output reg [WRITE_DATA*8-1:0] o_mem_write_data;
input [WRITE_DATA*8-1:0] i_mem_read_data;
input i_mem_read_valid;
output reg o_mem_read_ready;

reg [BLOCK_SIZE_BYTE*8-1:0] cache_block [0:7];
reg valid_bit [0:7];
reg dirty_bit [0:7];
reg [TAG_WIDTH-1:0] tag_address[0:7];
localparam IDLE=0,READ=1,WRITE=2,READ_MISS=3,WRITE_MISS=4;

reg [2:0] cs,ns;
wire miss;
reg handled;

always @(*) begin
    ns = 0;
    case(cs)
    IDLE: begin
        if(i_cpu_valid&!i_cpu_rd_wr)
            ns = READ;
        else if(i_cpu_valid&i_cpu_rd_wr)
            ns = WRITE;
        else
            ns = IDLE;
    end
    READ: begin
        if(miss)
            ns = READ_MISS;
        else if(i_cpu_valid&i_cpu_rd_wr)
            ns = WRITE;
        else if(i_cpu_valid&!i_cpu_rd_wr)
            ns = READ;
    end
    READ_MISS: begin
        if(!handled)
            ns = READ_MISS;
        else if(handled&i_cpu_valid&!i_cpu_rd_wr)
            ns = READ;
        else if(handled&i_cpu_valid&i_cpu_rd_wr)
            ns = WRITE;
        else if(handled&!i_cpu_valid)
            ns = IDLE;
    end
    WRITE: begin
        if(wr_miss)
            ns = WRITE_MISS;
        else if(i_cpu_valid&i_cpu_rd_wr)
            ns = WRITE;
        else if(i_cpu_valid&!i_cpu_rd_wr)
            ns = READ;
    end
    WRITE_MISS: begin
        if(!handled)
            ns = WRITE_MISS;
        else if(handled&i_cpu_valid&!i_cpu_rd_wr)
            ns = READ;
        else if(handled&i_cpu_valid&i_cpu_rd_wr)
            ns = WRITE;
        else if(handled&!i_cpu_valid)
            ns = IDLE;
    end
    endcase
end


always@(posedge clk or negedge rst_n) begin
    if(!rst_n)
        cs <= IDLE;
    else    
        cs <= ns;
end
assign wr_miss = dirty_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]] & i_cpu_rd_wr & miss;
assign miss = i_cpu_valid&((i_cpu_address[TAG_HIGH:TAG_LOW]!=tag_address[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) | !valid_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]); 
assign hit  = i_cpu_valid&((i_cpu_address[TAG_HIGH:TAG_LOW]==tag_address[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]])&valid_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]); 
always@(posedge clk or negedge rst_n) begin
    if(rst_n) begin
        case(cs)
        READ: begin
            handled                 <= 0;
            if(miss) begin
                o_mem_valid         <= 1'b1;
                o_mem_address       <= i_cpu_address;
                o_mem_rd_wr         <= 0;
                o_cpu_ready         <= 0;
                o_mem_read_ready    <= 1;
                o_cpu_read_valid    <= 0;
            end
            else if(hit) begin
                o_cpu_read_valid    <= i_cpu_valid;
                o_cpu_read_data     <= cache_block[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]];
                o_cpu_ready         <= 1'b1;
                o_mem_valid         <= 0;
            end
        end
        READ_MISS: begin
            handled <= i_mem_read_valid;
            if(i_mem_read_valid) begin
                o_cpu_read_data                                                  <= i_mem_read_data;
                o_cpu_read_valid                                                 <= 1'b1;
                o_cpu_ready                                                      <= 1'b1;
                o_mem_valid                                                      <= 0;
                cache_block[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]] <= i_mem_read_data;
                valid_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]   <= 1'b1;
                tag_address[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]] <= i_cpu_address[TAG_HIGH:TAG_LOW];
                o_mem_read_ready                                                 <= 0;
            end
        end
        WRITE: begin
            handled <= 0;
            if(miss) begin
                if(dirty_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                    o_mem_valid <= 1;
                    o_mem_rd_wr <= 1;
                    o_mem_write_data <= cache_block[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]];
                    o_mem_address <= i_cpu_address;
                    cache_block[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]] <= i_cpu_write_data;
                    tag_address[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]] <= i_cpu_address[TAG_HIGH:TAG_LOW];
                end
                else if(!dirty_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                    cache_block[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]] <= i_cpu_write_data;
                    tag_address[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]] <= i_cpu_address[TAG_HIGH:TAG_LOW];
                    valid_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]   <= 1;
                    dirty_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]   <= 1;
                end               
            end
            else if(hit) begin
                    cache_block[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]] <= i_cpu_write_data;
                    tag_address[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]] <= i_cpu_address[TAG_HIGH:TAG_LOW];
                    dirty_bit[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]   <= 1;
            end
        end
        WRITE_MISS: begin
            handled <= o_mem_valid & i_mem_ready;
        end
        endcase
    end
    else if(!rst_n) begin
        valid_bit[0]  <=   0;dirty_bit[0] <= 0;tag_address[0] <= 0;cache_block[0] <= 0;
        valid_bit[1]  <=   0;dirty_bit[1] <= 0;tag_address[1] <= 0;cache_block[1] <= 0;
        valid_bit[2]  <=   0;dirty_bit[2] <= 0;tag_address[2] <= 0;cache_block[2] <= 0;
        valid_bit[3]  <=   0;dirty_bit[3] <= 0;tag_address[3] <= 0;cache_block[3] <= 0;
        valid_bit[4]  <=   0;dirty_bit[4] <= 0;tag_address[4] <= 0;cache_block[4] <= 0;
        valid_bit[5]  <=   0;dirty_bit[5] <= 0;tag_address[5] <= 0;cache_block[5] <= 0;
        valid_bit[6]  <=   0;dirty_bit[6] <= 0;tag_address[6] <= 0;cache_block[6] <= 0;
        valid_bit[7]  <=   0;dirty_bit[7] <= 0;tag_address[7] <= 0;cache_block[7] <= 0;
        o_cpu_read_data<=0;
        o_cpu_read_valid<=0;
        o_cpu_ready<=0;
        o_mem_address<=0;
        o_mem_read_ready<=0;
        o_mem_rd_wr<=0;
        o_mem_valid<=0;
        o_mem_write_data<=0;
    end
end





endmodule
*/
