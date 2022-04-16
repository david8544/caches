# caches

This project implements two different cache types in RISC-V.

### What this project shows?
This project includes low level programming, deep understanding of cycle operations, and optimization in creating circuits 
for computations.

### direct-mapped cache
This cache type has three memory arrays for cache store and retrieval. Each addressed location in 
main memory maps to a single location in cache memory. First, the data array stores data in blocks
of multiple consecutive words, called cache lines. Second, the tag array stores the tag of each cache line, i.e.,
the bits of its address needed to uniquely identify its memory location. Third, the status array holds valid
and dirty bits for each cache line. In a direct-mapped cache, each line can reside in a single location in the
cache, i.e., a single row of the memory arrays.
To perform a lookup in a direct-mapped cache, we divide the address into three elds: the word oset
bits identify the particular word accessed within the cache line; the index bits determine the location (row)
in the cache where the line can reside; and the tag bits are all the remaining bits. A lookup rst reads the
status, tag, and data arrays at the location given by the index bits. If the location has a valid line and the
stored tag matches the tag bits, we have a cache hit, and the data is served from the data array (using the
oset bits to select the right word). Otherwise, the lookup results in a cache miss and data is fetched from
main memory.

### two-way set-associative cache
Set-associative caches (Figure 1b) reduce misses by allowing each address to reside in one of multiple
locations. An N-way set-associative cache can be seen as N replicas of a direct-mapped cache. We call each
such replica a way. Each line can reside in a single location (row) of each way, so it maps to one of N possible
locations across the cache. We call this group of locations (a row across all ways) a set.
A lookup in a set-associative cache checks all the ways in parallel. A cache hit happens when one of the
ways has a valid line with a matching tag. If there are no matches, the cache fetches the line from memory
and selects which of the cached lines to replace. The cache implements a replacement policy for this purpose.
In our case, the two-way set-associative cache will use the LRU replacement policy, which maintains an LRU
array that tracks which of the two lines in each set was accessed least recently.

October 2021.

