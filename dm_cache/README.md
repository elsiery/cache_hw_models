# Direct Mapped 64KB Cache
* This cache size is 64KB
* Block size is 64 bytes. There are 1024 blocks.
* Each block has additional bits for 'tag_bits', 'valid bit' and a 'dirty bit'.
* It is a 'Write-Allocate' and 'Write-Back' Cache.
* The design file is 'dm_cache.v', testbench is 'dm_cache_test.v'
* The design is tested with 102400 transactions.
* The address and data for those transactions are generated and kept in file "block"
* All the features are verified and reports are featured too.
* The design is lint error free and synthesizable. 
