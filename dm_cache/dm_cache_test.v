`include "dm_cache.v"


module dm_cache_test;
parameter ADDRESS_WIDTH =64;
parameter WRITE_DATA=64;
parameter BLOCK_SIZE_BYTE=64;
parameter BLOCK_SIZE_BITS=6;
parameter BLOCK_NUMBER_BITS=10;
parameter CACHE_SIZE=64*1024;

localparam TAG_WIDTH = ADDRESS_WIDTH-BLOCK_NUMBER_BITS-BLOCK_SIZE_BITS;
localparam BLOCK_ADDRESS_HIGH = ADDRESS_WIDTH-TAG_WIDTH-1;
localparam BLOCK_ADDRESS_LOW = BLOCK_SIZE_BITS; 
localparam TAG_HIGH = ADDRESS_WIDTH-1;
localparam TAG_LOW = BLOCK_ADDRESS_HIGH -1; 

reg i_cpu_valid;
reg i_cpu_rd_wr;
reg [ADDRESS_WIDTH-1:0] i_cpu_address;
reg clk,rst_n;
reg [575:0] test_vector [0:102399];
wire o_cpu_busy;
reg [WRITE_DATA*8-1:0] i_cpu_wr_data;
wire [WRITE_DATA*8-1:0] o_cpu_rd_data;
wire o_mem_rd_en,o_mem_wr_en;
wire [ADDRESS_WIDTH-1:0] o_mem_rd_address,o_mem_wr_address;
wire [WRITE_DATA*8-1:0] o_mem_wr_data;
reg [WRITE_DATA*8-1:0] i_mem_rd_data;
reg i_mem_rd_valid;
integer k,finalresult,detailedresult,i;
integer w_pass,w_fail,r_pass,r_fail,busy_for_out_rd,busy_for_out_wr;
dm_cache uut (
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


always
#5 clk = ~clk;
initial begin
    $dumpfile("dm_cache.vcd");
    $dumpvars();
end

initial  
begin 
    $readmemh("/home/elsiery/github_codes/cache_models_hw/dm_cache/vmod/block", test_vector);
    finalresult = $fopen("/home/elsiery/github_codes/cache_models_hw/dm_cache/vmod/final_result.txt");
    detailedresult = $fopen("/home/elsiery/github_codes/cache_models_hw/dm_cache/vmod/detailed_result.txt");
end




task initialize;
begin
    clk = 0;
    rst_n= 1;
    w_fail=0;
    w_pass=0;
    r_fail=0;
    r_pass=0;
    busy_for_out_rd=0;
    busy_for_out_wr=0;
    i_cpu_valid=0;
    i_cpu_rd_wr=0;
    i_cpu_address=0;
    i_cpu_wr_data=0;

    i_mem_rd_data=0;
    i_mem_rd_valid=0;

end
endtask



task apply_reset;
begin
    @(posedge clk);
    rst_n = 1'b0;
    @(posedge clk);
    rst_n = 1'b1;
end
endtask


initial begin
    initialize;
    apply_reset;
    #30;
//    cache_write;
    #100;
//    cache_read;
    #100;
    
    for(i=0;i<51200;i++) begin
        @(posedge clk);
        i_cpu_rd_wr=0;
        i_cpu_address=test_vector[i][575:512];
        i_cpu_valid=1'b1;
        @(posedge clk);
        if(o_cpu_busy == 1) begin
            $fdisplay(detailedresult,"Cache busy contacting out_memory for missed data of address %h\n",i);
            busy_for_out_rd=busy_for_out_rd+1;
            @(posedge clk);
            if(o_mem_rd_en==1) begin
                i_mem_rd_valid = 1'b1;
                i_mem_rd_data = test_vector[i][511:0];
            end
        end
        #30;
        if(test_vector[i][511:0]==o_cpu_rd_data) begin
            $fdisplay(detailedresult,"READ hit is successful for block_%h\n",i);
            r_pass=r_pass+1;
        end
        else begin
            r_fail=r_fail+1;
            $fdisplay(detailedresult,"READ miss for cache_%h=%h\noutput=%h\nans=%h\n",i,uut.cache_block[i],o_cpu_rd_data,test_vector[i][511:0]);
        end
    end


    for(i=51200;i<102400;i++) begin
        @(posedge clk);
        i_cpu_rd_wr=1;
        i_cpu_address=test_vector[i][575:512];
        i_cpu_wr_data=test_vector[i][511:0];
        i_cpu_valid=1'b1;
        @(posedge clk);
        if(o_cpu_busy == 1) begin
            $fdisplay(detailedresult,"Cache busy contacting out_memory for missed data of address %h\n",i);
            busy_for_out_wr=busy_for_out_wr+1;
            @(posedge clk);
            if(o_mem_rd_en==1) begin
                i_mem_rd_valid = 1'b1;
                i_mem_rd_data = $random;
            end
        end
        #30;
        if(test_vector[i][511:0]==uut.cache_block[i%1024]) begin
            $fdisplay(detailedresult,"write alloc and writ hit are successful for block %h\n",i);
            w_pass=w_pass+1;
        end
        else begin
            $fdisplay(detailedresult,"write alloc not successful for cache_%h=%h\nans=%h\n",i,uut.cache_block[i%1024],test_vector[i][511:0]);
            w_fail=w_fail+1;
        end
    end

    /*
    for(i=51200;i<102400;i++) begin
        @(posedge clk);
        i_cpu_rd_wr=1;
        i_cpu_address=test_vector[i][575:512];
        i_cpu_wr_data=test_vector[i][511:0];
        i_cpu_valid=1'b1;
        @(posedge clk);
        if((o_mem_wr_en==1)&&(o_mem_wr_address==test_vector[i-51200+50176][575:512])&&(o_mem_wr_data==test_vector[i-51200+50176][511:0])) begin
            $fdisplay(detailedresult,"Write miss has happened now write alloc is being done for address %h\n",i);
            busy_for_out_wr=busy_for_out_wr+1;
        end
        else begin
            $fdisplay(detailedresult,"enable=%d\naddress=%h\ndata=%h\n",o_mem_wr_en,o_mem_wr_address,o_mem_wr_data);
            $fdisplay(detailedresult,"real_address=%h\nreal_data=%h\n",test_vector[i-51200+50176][575:512],test_vector[i-51200+50176][511:0]);
        end
        #10;
        if(test_vector[i][511:0]==uut.cache_block[i%1024]) begin
            $fdisplay(detailedresult,"write alloc and writ hit are successful for block %h\n",i);
            w_pass=w_pass+1;
        end
        else begin
            $fdisplay(detailedresult,"write alloc not successful for cache_%h=%h\nans=%h\n",i,uut.cache_block[i%1024],test_vector[i][511:0]);
            w_fail=w_fail+1;
        end
    end
    */
    $fdisplay(finalresult,"write_hits=%d,write_fails=%d,read_hits=%d,read_miss=%d,busy_for_out_rd=%d,busy_for_out_wr=%d\n",w_pass,w_fail,r_pass,r_fail,busy_for_out_rd,busy_for_out_wr);


    $fclose(detailedresult);
    $fclose(finalresult);

    $finish;
end


endmodule








/*

    for(i=0;i<80000;i++) begin
        @(posedge clk);
        i_cpu_rd_wr=1;
        i_cpu_address=test_vector[i][575:512];
        i_cpu_wr_data=test_vector[i][511:0];
        i_cpu_valid=1'b1;
        #1;
        //$display("miss=%d\n",o_cpu_busy);
        #20;
    end
    for(k=0;k<8;k++) begin
        if(test_vector[79992+k][511:0]==uut.cache_block[k]) begin
            $fdisplay(result,"write alloc and writ hit are successful for cache_%h\n",k);
            //w_pass=w_pass+1;
        end
        else begin
            $fdisplay(result,"write alloc not successful for cache_%h=%h\nans=%h\n",k,uut.cache_block[k],test_vector[k+79992][511:0]);
            //w_fail=w_fail+1;
        end

    end
    for(i=0;i<8;i++) begin
        @(posedge clk);
        i_cpu_rd_wr=0;
        i_cpu_address=test_vector[79992+i][575:512];
        //i_cpu_wr_data=2024;
        i_cpu_valid=1'b1;
        //#1;
        //$display("miss=%d\n",o_cpu_busy);
        #20;
        #0;
        if(test_vector[79992+i][511:0]==o_cpu_rd_data) begin
            $fdisplay(result,"READ hit is successful for cache_%h\n",i);
        end
        else begin
            $fdisplay(result,"READ miss for cache_%h=%h\nans=%h\n",i,o_cpu_rd_data,test_vector[i+79992][511:0]);
        end

        //$display("rd_dt=%d\n",o_cpu_rd_data);
    end

*/



















/*
@(posedge clk);
i_cpu_rd_wr=1;
i_cpu_address=64;
i_cpu_wr_data=2025;
i_cpu_valid=1'b1;
#1;
$display("miss=%d\n",o_cpu_busy);
#20;
@(posedge clk);
i_cpu_rd_wr=1;
i_cpu_address=128;
i_cpu_wr_data=2026;
i_cpu_valid=1'b1;
#1;
$display("miss=%d\n",o_cpu_busy);
#20;
@(posedge clk);
i_cpu_rd_wr=1;
i_cpu_address=192;
i_cpu_wr_data=2027;
i_cpu_valid=1'b1;
#1;
$display("miss=%d\n",o_cpu_busy);
#20;
@(posedge clk);
i_cpu_rd_wr=1;
i_cpu_address=256;
i_cpu_wr_data=2028;
i_cpu_valid=1'b1;
#1;
$display("miss=%d\n",o_cpu_busy);
#20;
@(posedge clk);
i_cpu_rd_wr=1;
i_cpu_address=320;
i_cpu_wr_data=2029;
i_cpu_valid=1'b1;
#1;
$display("miss=%d\n",o_cpu_busy);
#20;
@(posedge clk);
i_cpu_rd_wr=1;
i_cpu_address=384;
i_cpu_wr_data=2030;
i_cpu_valid=1'b1;
#1;
$display("miss=%d\n",o_cpu_busy);
#20;
@(posedge clk);
i_cpu_rd_wr=1;
i_cpu_address=448;
i_cpu_wr_data=2031;
i_cpu_valid=1'b1;
#1;
$display("miss=%d\n",o_cpu_busy);

#100;
*/
/*
@(posedge clk);
i_cpu_rd_wr=0;
i_cpu_address=64;
i_cpu_wr_data=2025;
i_cpu_valid=1'b1;
#1;
$display("miss=%d\n",o_cpu_busy);
#20;
#1;
$display("rd_dt=%d\n",o_cpu_rd_data);

@(posedge clk);
i_cpu_rd_wr=0;
i_cpu_address=128;
i_cpu_wr_data=2026;
i_cpu_valid=1'b1;
#1;
$display("miss=%d\n",o_cpu_busy);
#20;
#1;
$display("rd_dt=%d\n",o_cpu_rd_data);

@(posedge clk);
i_cpu_rd_wr=0;
i_cpu_address=192;
i_cpu_wr_data=2027;
i_cpu_valid=1'b1;
#1;
$display("miss=%d\n",o_cpu_busy);
#20;
#1;
$display("rd_dt=%d\n",o_cpu_rd_data);

@(posedge clk);
i_cpu_rd_wr=0;
i_cpu_address=256;
i_cpu_wr_data=2028;
i_cpu_valid=1'b1;
#1;
$display("miss=%d\n",o_cpu_busy);
#20;
#1;
$display("rd_dt=%d\n",o_cpu_rd_data);

@(posedge clk);
i_cpu_rd_wr=0;
i_cpu_address=320;
i_cpu_wr_data=2029;
i_cpu_valid=1'b1;
#1;
$display("miss=%d\n",o_cpu_busy);
#20;
#1;
$display("rd_dt=%d\n",o_cpu_rd_data);

@(posedge clk);
i_cpu_rd_wr=0;
i_cpu_address=384;
i_cpu_wr_data=2030;
i_cpu_valid=1'b1;
#1;
$display("miss=%d\n",o_cpu_busy);
#20;
#1;
$display("rd_dt=%d\n",o_cpu_rd_data);

@(posedge clk);
i_cpu_rd_wr=0;
i_cpu_address=448;
i_cpu_wr_data=2031;
i_cpu_valid=1'b1;
#1;
$display("miss=%d\n",o_cpu_busy);
#1;
$display("rd_dt=%d\n",o_cpu_rd_data);
*/
