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
