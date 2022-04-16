import CacheTypes;
import CacheHelpers;
import MainMemory;

// ReqStatus (defined in CacheTypes.ms) is used to keep track of the state of the current request
//typedef enum {
//    Ready,         // The cache is ready for a new request
//    Lookup,        // Issued a lookup to tag/data arrays
//    Writeback,     // In main memory access for dirty writeback
//    Fill           // In main memory access for requested data
//} ReqStatus;
//
// Possible flows:
//   HIT: Ready -> Lookup -> Ready
//   MISS, line is clean: Ready -> Lookup -> Fill
//   MISS, line is dirty: Ready -> Lookup -> Writeback -> Fill

// Cache SRAM Synonyms (defined in CacheTypes.ms)
// You may find the following type synonyms helpful to access the tag/data/status arrays
// typedef SRAMReq#(logCacheSets, CacheTag) TagReq;
// typedef SRAMReq#(logCacheSets, Line) DataReq;
// typedef SRAMReq#(logCacheSets, CacheStatus) StatusReq;

// TODO: Complete the implementation of DirectMappedCache
// NOTE: Implementing this module requires about 50 lines of additional code
// (~40 lines in the rule, ~5-10 lines in the data method, and 1 line in the reqEnabled method)
module DirectMappedCache(MainMemory mainMem);
    // SRAM arrays. Note that, for a direct-mapped cache,
    // number of cache sets == number of cache lines
    SRAM#(logCacheSets, Line) dataArray;
    SRAM#(logCacheSets, CacheTag) tagArray;
    SRAM#(logCacheSets, CacheStatus) statusArray;
    
    // Registers for holding the current state of the cache and how far along
    // it is in processing a request.
    RegU#(MemReq) curReq;
    Reg#(ReqStatus) state(Ready);
    
    // Hit/miss counters
    Reg#(Word) hits(0);
    Reg#(Word) misses(0);

    input Maybe#(MemReq) req default = Invalid;
    
    // TODO return True if the cache can accept a new request
    method Bool reqEnabled;
      if (state == Ready) begin
         return True;
      end else begin
         return False;
      end
    endmethod

    rule tick;
        if (state == Ready && isValid(req)) begin
            state <= Lookup;
            let new_req = fromMaybe(?, req);
            let index = getIndex(new_req.addr);
            curReq <= new_req;
            dataArray.req = Valid(DataReq{addr:index, write:False, data: ?});
            tagArray.req = Valid(TagReq{addr:index, write: False, data: ?});
            statusArray.req = Valid(StatusReq{addr:index, write: False, data: ?});            
            // Requested from all
        end else if (state == Lookup) begin
            // Initial Values
            let actualTag = getTag(curReq.addr);
            let tagData = fromMaybe(?, tagArray.data);
            let statusData = fromMaybe(?, statusArray.data);
            let dataFound = fromMaybe(?, dataArray.data);
            let index = getIndex(curReq.addr);
            let newData = curReq.data;
            let lineAddres = getLineAddr(curReq.addr);

            // Hit Case
            if (tagData == actualTag && statusData != NotValid) begin
               hits <= hits + 1;
               state <= Ready;
               if (curReq.op == St) begin
                  let offset = getWordOffset(curReq.addr);
                  dataFound[offset] = newData;
                  statusArray.req = Valid(StatusReq{addr: index, write: True, data: Dirty});
                  dataArray.req = Valid(DataReq{addr: index, write: True, data: dataFound}); 
               end
            end 
            
            // Miss Case
            else begin
               misses <= misses +1;
               // Clean Miss
               if (statusData == Clean || statusData == NotValid) begin
                  state <= Fill;
                  mainMem.req = Valid(LineReq{op: Ld, lineAddr:lineAddres, data: ?});
               end
               else if (statusData == Dirty) begin
                  state <= Writeback;
                  let writeAddres = {tagData, index};
                  // write the dirty value from cache to memory
                  mainMem.req = Valid(LineReq{op: St, lineAddr:writeAddres, data: dataFound});
               end
            end
            
        end else if (state == Writeback && mainMem.reqEnabled) begin
             // We ahve stored the dirty value, now retrieve new Value
             state <= Fill;
             let lineAddres = getLineAddr(curReq.addr);
             // get the value from the memory
             mainMem.req = Valid(LineReq{op:Ld, lineAddr: lineAddres, data: ?});


        end else if (state == Fill && isValid(mainMem.data)) begin
            state <= Ready;
            let index = getIndex(curReq.addr);
            let newTag = getTag(curReq.addr);
            let newData = fromMaybe(?, mainMem.data);
            let stat = Clean;
            if (curReq.op == Ld) begin
               dataArray.req = Valid(DataReq{addr: index, write: True, data: newData});
            end 
            else begin
               let offset = getWordOffset(curReq.addr);
               newData[offset] = curReq.data;
               dataArray.req = Valid(DataReq{addr: index, write: True, data: newData});
               stat = Dirty;
            end
            tagArray.req = Valid({TagReq{addr: index, write: True, data: newTag}});
            statusArray.req = Valid(StatusReq{addr: index, write: True, data: stat});
        end
    endrule

    method Maybe#(Word) data;
        // This method should return a Valid output in only two cases:
        // 1. On a load hit (we're in the Lookup state, there's a hit, and
        //    curReq.op == Ld).
        // 2. On a fill for a load request (we're in the Fill state,
        //    mainMem.data is valid, and curReq.op == Ld).
        // In all other cases, the output should be Invalid
        //
        // NOTE: You should be checking the above conditions explicitly in
        //    THIS method so you can return data as soon as possible.
        //    DO NOT place your output into a register in the rule and then
        //    simply return that register here.

        // This function should take about 4-8 lines of code to implement.
        // TODO Your code here.
        let tag = getTag(curReq.addr);
        let index = getIndex(curReq.addr);
        let offset = getWordOffset(curReq.addr);
        Maybe#(Word) ans = Invalid;
        if (state == Lookup && curReq.op == Ld && fromMaybe(?, tagArray.data) == tag) begin
           ans = Valid(fromMaybe(?, dataArray.data)[offset]);
        end else if (state == Fill && curReq.op == Ld && isValid(mainMem.data)) begin
           ans =  Valid(fromMaybe(?, mainMem.data)[offset]);
        end
        return ans;
        
    endmethod

    method Bit#(32) getHits = hits;
    method Bit#(32) getMisses = misses;
endmodule
