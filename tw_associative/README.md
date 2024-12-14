# Two-Way Associative 64KB Cache
* This cache size is 64KB
* Block size is 64 bytes. There are 1024 blocks and 512 sets.
* Each block has additional bits for 'tag_bits', 'valid bit' and a 'dirty bit'.
* It is a 'Write-Allocate' and 'Write-Back' Cache with 'LRU Replacement policy'
* The design file is 'tw_associative.v', testbench is 'tw_associative_test.v'
* The design is tested with 10000 transactions.
* The address and data for those transactions are generated and kept in file "block"
* All the features are verified and reports are featured too.
* The design is lint error free. 
