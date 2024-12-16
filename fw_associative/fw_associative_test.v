`include "fw_associative.v"


module fw_associative_test;
parameter ADDRESS_WIDTH =64;
parameter WRITE_DATA=64;

parameter BLOCK_SIZE_BYTE=64;
parameter BLOCK_SIZE_BITS=6;
parameter BLOCK_NUMBER_BITS=10;
parameter SET_BITS = 2;
parameter BLOCK_NUMBER = 264;
parameter CACHE_SIZE=64*1024;
localparam TAG_WIDTH = ADDRESS_WIDTH-(BLOCK_NUMBER_BITS - SET_BITS)-BLOCK_SIZE_BITS;
localparam BLOCK_ADDRESS_HIGH = ADDRESS_WIDTH-TAG_WIDTH-1;
localparam BLOCK_ADDRESS_LOW = BLOCK_SIZE_BITS; 
localparam TAG_HIGH = ADDRESS_WIDTH-1;
localparam TAG_LOW = BLOCK_ADDRESS_HIGH +1; 


reg i_cpu_valid;
reg i_cpu_rd_wr;
reg [ADDRESS_WIDTH-1:0] i_cpu_address;
reg clk,rst_n;
reg [575:0] test_vector [0:9999];
wire o_cpu_busy;
reg [WRITE_DATA*8-1:0] i_cpu_wr_data;
wire [WRITE_DATA*8-1:0] o_cpu_rd_data;
wire o_mem_rd_en,o_mem_wr_en;
wire [ADDRESS_WIDTH-1:0] o_mem_rd_address,o_mem_wr_address;
wire [WRITE_DATA*8-1:0] o_mem_wr_data;
reg [WRITE_DATA*8-1:0] i_mem_rd_data;
reg i_mem_rd_valid;
integer k,finalresult,detailedresult,i,counter_fail,counter_pass;
integer w_pass,w_fail,r_pass,r_fail,busy_for_out_rd,busy_for_out_wr,cache_1_hit,cache_1_miss,cache_2_hit,cache_2_miss,cache_3_hit,cache_3_miss,cache_4_hit,cache_4_miss;
fw_associative uut (
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
    $dumpfile("fw_associative.vcd");
    $dumpvars();
end

initial  
begin 
    $readmemh("/home/elsiery/github_codes/cache_models_hw/fw_associative/vmod/block", test_vector);
    finalresult = $fopen("/home/elsiery/github_codes/cache_models_hw/fw_associative/vmod/final_result.txt");
    detailedresult = $fopen("/home/elsiery/github_codes/cache_models_hw/fw_associative/vmod/detailed_result.txt");
end




task initialize;
begin
    clk = 0;
    rst_n= 1;
    w_fail=0;
    w_pass=0;
    r_fail=0;
    r_pass=0;
    cache_1_hit=0;
    cache_1_miss=0;
    cache_2_hit=0;
    cache_2_miss=0;
    cache_3_hit=0;
    cache_3_miss=0;
    cache_4_hit=0;
    cache_4_miss=0;
    counter_pass=0;
    counter_fail=0;
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
    
    for(i=0;i<1024;i++) begin

        @(posedge clk);
        $fdisplay(detailedresult,$time,"    Step1 Rd req start for transaction %d",i);
        i_cpu_rd_wr=0;
        i_cpu_address=test_vector[i][575:512];
        i_cpu_valid=1'b1;
        @(posedge clk);
        $fdisplay(detailedresult,$time,"    Step2 miss detect for transaction %d ",i);
        if(o_cpu_busy == 1) begin
            $fdisplay(detailedresult,"Cache busy contacting out_memory for missed data of address %h\n",i);
            busy_for_out_rd=busy_for_out_rd+1;
            @(posedge clk);
            $fdisplay(detailedresult,$time,"    Step3 waiting for mem data for transaction %d",i);
            if(o_mem_rd_en==1) begin
                i_mem_rd_valid = 1'b1;
                i_mem_rd_data = test_vector[i][511:0];
                //#1 $fdisplay(detailedresult,"start------lru_1=%b,lru_2=%b",uut.lru_counter_1[i%512],uut.lru_counter_2[i%512]);
                /*
                $fdisplay(detailedresult,"Ans=%h\ncache_block_1=%h\n",test_vector[i][511:0],uut.cache_block_1[i%256]);
                $fdisplay(detailedresult,"cache_block_2=%h\n",uut.cache_block_2[i%256]);
                $fdisplay(detailedresult,"cache_block_3=%h\n",uut.cache_block_3[i%512]);
                $fdisplay(detailedresult,"cache_block_4=%h\n",uut.cache_block_4[i%512]);
                */
                //#1 $fdisplay(detailedresult,"start------lru_1=%b,lru_2=%b",uut.lru_counter_1[i%512],uut.lru_counter_2[i%512]);
                /*
                $fdisplay(detailedresult,"Ans=%h\ncache_block_1=%h\n",test_vector[i][511:0],uut.cache_block_1[i%512]);
                $fdisplay(detailedresult,"cache_block_2=%h\n",uut.cache_block_2[i%512]);
                */
            end
            @(posedge clk);
            i_mem_rd_valid=0;

            //Checking which cache is accessed in a set.
            $fdisplay(detailedresult,$time,"    Step4 mem writes into cache for transaction %d",i);

            
            if(i<256) begin
                if(test_vector[i][511:0]==uut.cache_block_1[i%256]) begin
                    $fdisplay(detailedresult,"Cache 1 is being hit for address %d\n",test_vector[i][575:512]);
                    $fdisplay(detailedresult,"lru_1=%b,lru_2=%b,lru_3=%b,lru_4=%b\n",uut.lru_counter_1[i%256],uut.lru_counter_2[i%256],uut.lru_counter_3[i%256],uut.lru_counter_4[i%256]);
                    cache_1_hit+=1;
                end
                else begin
                    $fdisplay(detailedresult,"Cache 1 is NOT being hit for address %d\n",test_vector[i][575:512]);
                    cache_1_miss+=1;
                end
            end
            else if(i>=256 && i<512) begin
                if(test_vector[i][511:0]==uut.cache_block_2[i%256]) begin
                    $fdisplay(detailedresult,"Cache 2 is being hit for address %d\n",test_vector[i][575:512]);
                    $fdisplay(detailedresult,"lru_1=%b,lru_2=%b,lru_3=%b,lru_4=%b\n",uut.lru_counter_1[i%256],uut.lru_counter_2[i%256],uut.lru_counter_3[i%256],uut.lru_counter_4[i%256]);
                    cache_2_hit+=1;
                end
                else begin
                    $fdisplay(detailedresult,"Cache 2 is NOT being hit for address %d\n",test_vector[i][575:512]);
                    cache_2_miss+=1;
                end
            end
            else if(i>=512 && i<768) begin
                if(test_vector[i][511:0]==uut.cache_block_3[i%256]) begin
                    $fdisplay(detailedresult,"Cache 3 is being hit for address %d\n",test_vector[i][575:512]);
                    $fdisplay(detailedresult,"lru_1=%b,lru_2=%b,lru_3=%b,lru_4=%b\n",uut.lru_counter_1[i%256],uut.lru_counter_2[i%256],uut.lru_counter_3[i%256],uut.lru_counter_4[i%256]);
                    cache_3_hit+=1;
                end
                else begin
                    $fdisplay(detailedresult,"Cache 3 is NOT being hit for address %d\n",test_vector[i][575:512]);
                    cache_3_miss+=1;
                end
            end
            else if(i>=768) begin
                if(test_vector[i][511:0]==uut.cache_block_4[i%256]) begin
                    $fdisplay(detailedresult,"Cache 4 is being hit for address %d\n",test_vector[i][575:512]);
                    $fdisplay(detailedresult,"lru_1=%b,lru_2=%b,lru_3=%b,lru_4=%b\n",uut.lru_counter_1[i%256],uut.lru_counter_2[i%256],uut.lru_counter_3[i%256],uut.lru_counter_4[i%256]);
                    cache_4_hit+=1;
                end
                else begin
                    $fdisplay(detailedresult,"Cache 4 is NOT being hit for address %d\n",test_vector[i][575:512]);
                    $fdisplay(detailedresult,"lru_1=%b,lru_2=%b,lru_3=%b,lru_4=%b\n",uut.lru_counter_1[i%256],uut.lru_counter_2[i%256],uut.lru_counter_3[i%256],uut.lru_counter_4[i%256]);
                    $fdisplay(detailedresult,"cache 4 is a miss cache_1=%h\ncache_2=%h\ncache_3=%h\ncache_4=%h\nans=%h\n",uut.cache_block_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]
                                                                                    ,uut.cache_block_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]
                                                                                    ,uut.cache_block_3[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]
                                                                                    ,uut.cache_block_4[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]
                                                                                    ,test_vector[i][511:0]);

                    cache_4_miss+=1;
                end
            end
        end
        #10;
        #1;
        $fdisplay(detailedresult,$time,"    Step5 Rd data out for transaction %d",i);
        if(test_vector[i][511:0]==o_cpu_rd_data) begin
            $fdisplay(detailedresult,"READ hit is successful for block_%h\n",i);
            r_pass=r_pass+1;
        end
        else begin
            r_fail=r_fail+1;
            $fdisplay(detailedresult,"READ miss for transaction %h cache_1=%h,cache_2=%h,cache_3=%h,cache_4=%h\noutput=%h\nans=%h\n",i,uut.cache_block_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]
                                                                                    ,uut.cache_block_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]
                                                                                    ,uut.cache_block_3[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]
                                                                                    ,uut.cache_block_4[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]
                                                                                    ,o_cpu_rd_data,test_vector[i][511:0]);
        end
    end
    
    //Now reading all the 1024 address spaces.
    for(i=0;i<1024;i++) begin

        @(posedge clk);

        $fdisplay(detailedresult,$time,"    Step1 Rd req start for %d",i);
        i_cpu_rd_wr=0;
        i_cpu_address=test_vector[i][575:512];
        i_cpu_valid=1'b1;
        @(posedge clk);
        if(o_cpu_busy==0) begin
            //HIT
            if(i<256) begin
                if(test_vector[i][511:0]==uut.cache_block_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                    $fdisplay(detailedresult,"Cache 1 is being hit for address %d\n",test_vector[i][575:512]);
                    cache_1_hit+=1;
                end
                else begin
                    $fdisplay(detailedresult,"Cache 1 is NOT being hit for address %d\n",test_vector[i][575:512]);
                    cache_1_miss+=1;
                end
            end
            else if(i>=256 && i<512) begin
                if(test_vector[i][511:0]==uut.cache_block_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                    $fdisplay(detailedresult,"Cache 2 is being hit for address %d\n",test_vector[i][575:512]);
                    cache_2_hit+=1;
                end
                else begin
                    $fdisplay(detailedresult,"Cache 2 is NOT being hit for address %d\n",test_vector[i][575:512]);
                    cache_2_miss+=1;
                end
            end
            else if(i>=512 && i<768) begin
                if(test_vector[i][511:0]==uut.cache_block_3[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                    $fdisplay(detailedresult,"Cache 3 is being hit for address %d\n",test_vector[i][575:512]);
                    cache_3_hit+=1;
                end
                else begin
                    $fdisplay(detailedresult,"Cache 3 is NOT being hit for address %d\n",test_vector[i][575:512]);
                    cache_3_miss+=1;
                end
            end
            else if(i>=768 && i<1024) begin
                if(test_vector[i][511:0]==uut.cache_block_4[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                    $fdisplay(detailedresult,"Cache 4 is being hit for address %d\n",test_vector[i][575:512]);
                    cache_4_hit+=1;
                end
                else begin
                    $fdisplay(detailedresult,"Cache 4 is NOT being hit for address %d\n",test_vector[i][575:512]);
                    cache_4_miss+=1;
                end
            end
        end
        //#20;
        $fdisplay(detailedresult,$time,"    step 2 rd data is out for transaction %d\n",i);
            
        if(test_vector[i][511:0]==o_cpu_rd_data) begin
            $fdisplay(detailedresult,"READ hit is successful for block_%h\n",i);
            r_pass=r_pass+1;
        end
        else begin
            r_fail=r_fail+1;
            $fdisplay(detailedresult,"READ miss for cache_%h=%h\noutput=%h\nans=%h\n",i,uut.cache_block_1[i],o_cpu_rd_data,test_vector[i][511:0]);
        end
    end
    
    
    //Now reading 256 transactions the least recent would be block 1.
    for(i=1024;i<1280;i++) begin
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
                /*
                $fdisplay(detailedresult,"Ans=%h\ncache_block_1=%h\n",test_vector[i][511:0],uut.cache_block_1[i-1024]);
                $fdisplay(detailedresult,"cache_block_2=%h\n",uut.cache_block_2[i-1024]);
                #1 $fdisplay(detailedresult,"start------lru_1=%b,lru_2=%b",uut.lru_counter_1[i-1024],uut.lru_counter_2[i-1024]);
                $fdisplay(detailedresult,"Ans=%h\ncache_block_1=%h\n",test_vector[i][511:0],uut.cache_block_1[i-1024]);
                $fdisplay(detailedresult,"cache_block_2=%h\n",uut.cache_block_2[i-1024]);
                */
            end
            @(posedge clk);
            //Checking which cache is accessed in a set.
            i_mem_rd_valid=0;
            if(i<1280) begin
                if(test_vector[i][511:0]==uut.cache_block_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                    $fdisplay(detailedresult,"Cache 1 is being hit for address %d\n",test_vector[i][575:512]);
                    cache_1_hit+=1;
                end
                else begin
                    $fdisplay(detailedresult,"Cache 1 is NOT being hit for address %d\n",test_vector[i][575:512]);
                    $fdisplay(detailedresult,"Ans=%h\ncache_block_1=%h\n",test_vector[i][511:0],uut.cache_block_1[i-1024]);
                    $fdisplay(detailedresult,"Ans=%h\ncache_block_2=%h\n",test_vector[i][511:0],uut.cache_block_2[i-1024]);
                    $fdisplay(detailedresult,"end------lru_1=%b,lru_2=%b",uut.lru_counter_1[i-1024],uut.lru_counter_2[i-1024]);

                    cache_1_miss+=1;
                end
            end
        end
        #11;
        if(test_vector[i][511:0]==o_cpu_rd_data) begin
            $fdisplay(detailedresult,"READ hit is successful for block_%h\n",i);
            r_pass=r_pass+1;
        end
        else begin
            r_fail=r_fail+1;
            $fdisplay(detailedresult,"READ miss for cache_%h=%h\noutput=%h\nans=%h\n",i,uut.cache_block_1[i],o_cpu_rd_data,test_vector[i][511:0]);
        end
    end
    //Now checking lru counter bits they all should be "3   0   1   2"
    for(i=0;i<256;i++) begin
        if((uut.lru_counter_1[i]==3)&&(uut.lru_counter_2[i]==0)&&(uut.lru_counter_3[i]==1)&&(uut.lru_counter_4[i]==2)) begin
            counter_pass +=1;
            $fdisplay(detailedresult,"set %d counters are set right\n",i);
        end
        else begin           
            $fdisplay(detailedresult,"set %d counters are NOT set right\n",i);
            counter_fail += 1;
        end
    end

    //Now reading 256 transactions the least recent would be block 2.
    for(i=1280;i<1536;i++) begin
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
            @(posedge clk);
            //Checking which cache is accessed in a set.
            i_mem_rd_valid=0;
            if(i<1536) begin
                if(test_vector[i][511:0]==uut.cache_block_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                    $fdisplay(detailedresult,"Cache 2 is being hit for address %d\n",test_vector[i][575:512]);
                    cache_2_hit+=1;
                end
                else begin
                    $fdisplay(detailedresult,"Cache 2 is NOT being hit for address %d\n",test_vector[i][575:512]);
                    cache_2_miss+=1;
                end
            end
        end
        #11;
        if(test_vector[i][511:0]==o_cpu_rd_data) begin
            $fdisplay(detailedresult,"READ hit is successful for block_%h\n",i);
            r_pass=r_pass+1;
        end
        else begin
            r_fail=r_fail+1;
            $fdisplay(detailedresult,"READ miss for cache_%h=%h\noutput=%h\nans=%h\n",i,uut.cache_block_1[i],o_cpu_rd_data,test_vector[i][511:0]);
        end
    end
    //Now checking lru counter bits they all should be "2   3   0   1"
    for(i=0;i<256;i++) begin
        if((uut.lru_counter_1[i]==2)&&(uut.lru_counter_2[i]==3)&&(uut.lru_counter_3[i]==0)&&(uut.lru_counter_4[i]==1)) begin
            counter_pass +=1;
            $fdisplay(detailedresult,"set %d counters are set right\n",i);
        end
        else begin           
            $fdisplay(detailedresult,"set %d counters are NOT set right\n",i);
            counter_fail += 1;
        end
    end


    //Now reading 256 transactions the least recent would be block 3.
    for(i=1280+256;i<1536+256;i++) begin
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
            @(posedge clk);
            //Checking which cache is accessed in a set.
            i_mem_rd_valid=0;
            if(i<1536+256) begin
                if(test_vector[i][511:0]==uut.cache_block_3[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                    $fdisplay(detailedresult,"Cache 3 is being hit for address %d\n",test_vector[i][575:512]);
                    cache_3_hit+=1;
                end
                else begin
                    $fdisplay(detailedresult,"Cache 3 is NOT being hit for address %d\n",test_vector[i][575:512]);
                    cache_3_miss+=1;
                end
            end
        end
        #11;
        if(test_vector[i][511:0]==o_cpu_rd_data) begin
            $fdisplay(detailedresult,"READ hit is successful for block_%h\n",i);
            r_pass=r_pass+1;
        end
        else begin
            r_fail=r_fail+1;
            $fdisplay(detailedresult,"READ miss for cache_%h=%h\noutput=%h\nans=%h\n",i,uut.cache_block_1[i],o_cpu_rd_data,test_vector[i][511:0]);
        end
    end
    //Now checking lru counter bits they all should be "1   2   3   0"
    for(i=0;i<256;i++) begin
        if((uut.lru_counter_1[i]==1)&&(uut.lru_counter_2[i]==2)&&(uut.lru_counter_3[i]==3)&&(uut.lru_counter_4[i]==0)) begin
            counter_pass +=1;
            $fdisplay(detailedresult,"set %d counters are set right\n",i);
        end
        else begin           
            $fdisplay(detailedresult,"set %d counters are NOT set right\n",i);
            counter_fail += 1;
        end
    end



    //Now reading 256 transactions the least recent would be block 3.
    for(i=1280+512;i<1536+512;i++) begin
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
            @(posedge clk);
            //Checking which cache is accessed in a set.
            i_mem_rd_valid=0;
            if(i<1536+512) begin
                if(test_vector[i][511:0]==uut.cache_block_4[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                    $fdisplay(detailedresult,"Cache 4 is being hit for address %d\n",test_vector[i][575:512]);
                    cache_4_hit+=1;
                end
                else begin
                    $fdisplay(detailedresult,"Cache 4 is NOT being hit for address %d\n",test_vector[i][575:512]);
                    cache_4_miss+=1;
                end
            end
        end
        #11;
        if(test_vector[i][511:0]==o_cpu_rd_data) begin
            $fdisplay(detailedresult,"READ hit is successful for block_%h\n",i);
            r_pass=r_pass+1;
        end
        else begin
            r_fail=r_fail+1;
            $fdisplay(detailedresult,"READ miss for cache_%h=%h\noutput=%h\nans=%h\n",i,uut.cache_block_1[i],o_cpu_rd_data,test_vector[i][511:0]);
        end
    end
    //Now checking lru counter bits they all should be "0   1   2   3"
    for(i=0;i<256;i++) begin
        if((uut.lru_counter_1[i]==0)&&(uut.lru_counter_2[i]==1)&&(uut.lru_counter_3[i]==2)&&(uut.lru_counter_4[i]==3)) begin
            counter_pass +=1;
            $fdisplay(detailedresult,"set %d counters are set right\n",i);
        end
        else begin           
            $fdisplay(detailedresult,"set %d counters are NOT set right\n",i);
            counter_fail += 1;
        end
    end


        
    //checking dirty bit functioning
    for(i=2048;i<3072;i++) begin
        @(posedge clk);
        i_cpu_rd_wr=1;
        i_cpu_address=test_vector[i][575:512];
        i_cpu_wr_data=test_vector[i][511:0];
        i_cpu_valid=1'b1;
        @(posedge clk);
        if((o_mem_wr_en==1)&&(o_mem_wr_address==test_vector[i-1024][575:512])&&(o_mem_wr_data==test_vector[i-1024][511:0])) begin
            $fdisplay(detailedresult,"Write miss has happened now write alloc is being done for address %h\n",i);
            busy_for_out_wr=busy_for_out_wr+1;
        end
        else begin
            $fdisplay(detailedresult,"enable=%d\naddress=%d\ndata=%h\n",o_mem_wr_en,o_mem_wr_address,o_mem_wr_data);
            $fdisplay(detailedresult,"real_address=%d\nreal_data=%h\n",test_vector[i-1024][575:512],test_vector[i-1024][511:0]);
        end
        #1;
        if(i<2048+256) begin
            if(test_vector[i][511:0]==uut.cache_block_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                $fdisplay(detailedresult,"write alloc and writ hit are successful for block %h\n",i);
                w_pass=w_pass+1;
                cache_1_hit+=1;
            end
            else begin
                $fdisplay(detailedresult,"write alloc not successful for cache_%h=%h\nans=%h\n",i,uut.cache_block_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]],test_vector[i][511:0]);
                w_fail=w_fail+1;
                cache_1_miss+=1;
            end
        end
        else if(i>=2048+256 && i<2048+512) begin
            if(test_vector[i][511:0]==uut.cache_block_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                $fdisplay(detailedresult,"write alloc and writ hit are successful for block %h\n",i);
                w_pass=w_pass+1;
                cache_2_hit+=1;
            end
            else begin
                $fdisplay(detailedresult,"write alloc not successful for cache_%h=%h\nans=%h\n",i,uut.cache_block_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]],test_vector[i][511:0]);
                w_fail=w_fail+1;
                cache_2_miss+=1;
            end
        end
        else if(i>=2048+512 && i<2048+768) begin
            if(test_vector[i][511:0]==uut.cache_block_3[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                $fdisplay(detailedresult,"write alloc and writ hit are successful for block %h\n",i);
                w_pass=w_pass+1;
                cache_3_hit+=1;
            end
            else begin
                $fdisplay(detailedresult,"write alloc not successful for cache_%h=%h\nans=%h\n",i,uut.cache_block_3[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]],test_vector[i][511:0]);
                w_fail=w_fail+1;
                cache_3_miss+=1;
            end
        end
        else begin
            if(test_vector[i][511:0]==uut.cache_block_4[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                $fdisplay(detailedresult,"write alloc and writ hit are successful for block %h\n",i);
                w_pass=w_pass+1;
                cache_4_hit+=1;
            end
            else begin
                $fdisplay(detailedresult,"write alloc not successful for cache_%h=%h\nans=%h\n",i,uut.cache_block_4[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]],test_vector[i][511:0]);
                w_fail=w_fail+1;
                cache_4_miss+=1;
            end
        end
    end
    //checking dirty bit functioning
    for(i=2048+1024;i<3072+1024;i++) begin
        @(posedge clk);
        i_cpu_rd_wr=1;
        i_cpu_address=test_vector[i][575:512];
        i_cpu_wr_data=test_vector[i][511:0];
        i_cpu_valid=1'b1;
        @(posedge clk);
        if((o_mem_wr_en==1)&&(o_mem_wr_address==test_vector[i-1024][575:512])&&(o_mem_wr_data==test_vector[i-1024][511:0])) begin
            $fdisplay(detailedresult,"Write miss has happened now write alloc is being done for address %h\n",i);
            busy_for_out_wr=busy_for_out_wr+1;
        end
        else begin
            $fdisplay(detailedresult,"enable=%d\naddress=%d\ndata=%h\n",o_mem_wr_en,o_mem_wr_address,o_mem_wr_data);
            $fdisplay(detailedresult,"real_address=%d\nreal_data=%h\n",test_vector[i-1024][575:512],test_vector[i-1024][511:0]);
        end
        #1;
        if(i<2048+256+1024) begin
            if(test_vector[i][511:0]==uut.cache_block_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                $fdisplay(detailedresult,"write alloc and writ hit are successful for block %h\n",i);
                w_pass=w_pass+1;
                cache_1_hit+=1;
            end
            else begin
                $fdisplay(detailedresult,"write alloc not successful for cache_%h=%h\nans=%h\n",i,uut.cache_block_1[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]],test_vector[i][511:0]);
                w_fail=w_fail+1;
                cache_1_miss+=1;
            end
        end
        else if(i>=2048+256+1024 && i<2048+512+1024) begin
            if(test_vector[i][511:0]==uut.cache_block_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                $fdisplay(detailedresult,"write alloc and writ hit are successful for block %h\n",i);
                w_pass=w_pass+1;
                cache_2_hit+=1;
            end
            else begin
                $fdisplay(detailedresult,"write alloc not successful for cache_%h=%h\nans=%h\n",i,uut.cache_block_2[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]],test_vector[i][511:0]);
                w_fail=w_fail+1;
                cache_2_miss+=1;
            end
        end
        else if(i>=2048+512+1024 && i<2048+768+1024) begin
            if(test_vector[i][511:0]==uut.cache_block_3[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                $fdisplay(detailedresult,"write alloc and writ hit are successful for block %h\n",i);
                w_pass=w_pass+1;
                cache_3_hit+=1;
            end
            else begin
                $fdisplay(detailedresult,"write alloc not successful for cache_%h=%h\nans=%h\n",i,uut.cache_block_3[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]],test_vector[i][511:0]);
                w_fail=w_fail+1;
                cache_3_miss+=1;
            end
        end
        else begin
            if(test_vector[i][511:0]==uut.cache_block_4[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]]) begin
                $fdisplay(detailedresult,"write alloc and writ hit are successful for block %h\n",i);
                w_pass=w_pass+1;
                cache_4_hit+=1;
            end
            else begin
                $fdisplay(detailedresult,"write alloc not successful for cache_%h=%h\nans=%h\n",i,uut.cache_block_4[i_cpu_address[BLOCK_ADDRESS_HIGH:BLOCK_ADDRESS_LOW]],test_vector[i][511:0]);
                w_fail=w_fail+1;
                cache_4_miss+=1;
            end
        end
    end




    $fdisplay(finalresult,"write_hits=%d,write_fails=%d,read_hits=%d,read_miss=%d,busy_for_out_rd=%d\nbusy_for_out_wr=%d\ncache_1_hit=%d,cache_1_miss=%d,cache_2_hit=%d,cache_2_miss=%d\ncache_3_hit=%d,cache_3_miss=%d,cache_4_hit=%d,cache_4_miss=%d,counter_pass=%d,counter_fail=%d\n",w_pass,w_fail,r_pass,r_fail,busy_for_out_rd,busy_for_out_wr,cache_1_hit,cache_1_miss,cache_2_hit,cache_2_miss,cache_3_hit,cache_3_miss,cache_4_hit,cache_4_miss,counter_pass,counter_fail);
    $display("write_hits=%d,write_fails=%d,read_hits=%d,read_miss=%d,busy_for_out_rd=%d\nbusy_for_out_wr=%d\ncache_1_hit=%d,cache_1_miss=%d,cache_2_hit=%d,cache_2_miss=%d\ncache_3_hit=%d,cache_3_miss=%d,cache_4_hit=%d,cache_4_miss=%d,counter_pass=%d,counter_fail=%d\n",w_pass,w_fail,r_pass,r_fail,busy_for_out_rd,busy_for_out_wr,cache_1_hit,cache_1_miss,cache_2_hit,cache_2_miss,cache_3_hit,cache_3_miss,cache_4_hit,cache_4_miss,counter_pass,counter_fail);


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
