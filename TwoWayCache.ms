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

// TODO: Complete the implementation of TwoWayCache
// NOTE: Implementing this module requires about 20 new lines of code from DirectMappedCache
module TwoWayCache(MainMemory mainMem);
    // SRAM arrays, one element per way (e.g., dataArrays[0] is the data array of way 0).
    Vector#(2, SRAM#(logCacheSets, Line)) dataArrays;
    Vector#(2, SRAM#(logCacheSets, CacheTag)) tagArrays;
    Vector#(2, SRAM#(logCacheSets, CacheStatus)) statusArrays;

    // LRU bits, one per set. We implement it as registers instead of an SRAM
    // array, because with small caches this is just a few bits (e.g., 64), and
    // SRAMs make sense only for larger memories. This also makes the code
    // simpler, and will make the cache easier to pipeline in the future.
    Vector#(cacheSets, RegU#(Bit#(1))) lru;

    // Registers for holding the current state of the cache and how far along
    // it is in processing a request.
    RegU#(MemReq) curReq;
    Reg#(ReqStatus) state(Ready);
 
    // Hit/miss counters
    Reg#(Word) hits(0);
    Reg#(Word) misses(0);
    
    input Maybe#(MemReq) req default = Invalid;
    
    //TODO return True if the cache can accept a new request
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
            for (Integer i = 0; i < 2; i = i + 1) begin
              dataArrays[i].req = Valid(DataReq{addr:index, write:False, data: ?});
              tagArrays[i].req = Valid(TagReq{addr:index, write: False, data: ?});
              statusArrays[i].req = Valid(StatusReq{addr:index, write: False, data: ?});
            end
        end else if (state == Lookup) begin
            // Initial Values
            let actualTag = getTag(curReq.addr);
            let tagData0 = fromMaybe(?, tagArrays[0].data);
            let tagData1 = fromMaybe(?, tagArrays[1].data);
            let statusData0 = fromMaybe(?, statusArrays[0].data);
            let statusData1 = fromMaybe(?, statusArrays[1].data);
            let index = getIndex(curReq.addr);
            let newData = curReq.data;
            let lineAddres = getLineAddr(curReq.addr);
            



            // Hit Case
            if ((tagData0 == actualTag && statusData0 != NotValid) || (tagData1 == actualTag && statusData1 != NotValid)) begin
               hits <= hits + 1;
               state <= Ready;
               let i = (tagData1 == actualTag && statusData1 != NotValid)? 1 : 0;
               lru[index] <= (i == 0)? 1 : 0; // lru for the index is the opposite set
               if (curReq.op == St) begin
                  let offset = getWordOffset(curReq.addr);
                  let dataFound = fromMaybe(?, dataArrays[i].data);
                  dataFound[offset] = curReq.data;
                  statusArrays[i].req = Valid(StatusReq{addr: index, write: True, data: Dirty});
                  dataArrays[i].req = Valid(DataReq{addr: index, write: True, data: dataFound});
               end
            end

            // Miss Case
            else begin
               misses <= misses +1;
               let i = lru[index];
               let statusData = (i==0)? statusData0 : statusData1;
               let tagData = (i==0)? tagData0 : tagData1;
               let dataFound = fromMaybe(?, dataArrays[i].data);
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
            let i = lru[index];
            lru[index] <= (i == 0)? 1 : 0; // lru for the index is the opposite set
            let newTag = getTag(curReq.addr);
            let newData = fromMaybe(?, mainMem.data);
            let stat = Clean;
            if (curReq.op == Ld) begin
               dataArrays[i].req = Valid(DataReq{addr: index, write: True, data: newData});
            end
            else begin
               let offset = getWordOffset(curReq.addr);
               newData[offset] = curReq.data;
               dataArrays[i].req = Valid(DataReq{addr: index, write: True, data: newData});
               stat = Dirty;
            end
            tagArrays[i].req = Valid({TagReq{addr: index, write: True, data: newTag}});
            statusArrays[i].req = Valid(StatusReq{addr: index, write: True, data: stat});
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

        // This function should take about 5-20 lines of code to implement.
        //TODO Your code here
        let tag = getTag(curReq.addr);
        let index = getIndex(curReq.addr);
        let offset = getWordOffset(curReq.addr);
        Maybe#(Word) ans = Invalid;
        if (state == Lookup && curReq.op == Ld && (fromMaybe(?, tagArrays[0].data) == tag || fromMaybe(?, tagArrays[1].data) == tag)) begin
           let i = (fromMaybe(?, tagArrays[0].data) == tag)? 0: 1;
           ans = Valid(fromMaybe(?, dataArrays[i].data)[offset]);
        end else if (state == Fill && curReq.op == Ld && isValid(mainMem.data)) begin
           ans =  Valid(fromMaybe(?, mainMem.data)[offset]);
        end
        return ans;

    endmethod

    method Bit#(32) getHits = hits;
    method Bit#(32) getMisses = misses;
endmodule
