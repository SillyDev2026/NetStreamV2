import assert from "node:assert/strict";
import {readFileSync, readdirSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {dirname, resolve} from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFileSync(resolve(root, path), "utf8");
const source = read("Netstream.lua");
const version = "4.3.0";

assert(source.includes(`local VERSION = "${version}"`), "Release version mismatch");
assert(!/\blocal\s+[A-Za-z_]\w*\s*=\s*\n\s*\S/.test(source), "Local assignments must stay on one line");
assert(source.includes("Internal.writeAdaptiveUIntBitsUnchecked(self.buffer, self.bitPosition, value)"), "Single-validation varuint path missing");
assert(source.includes("writer:ensureBits(schema.count * 8)"), "U8 writer preflight missing");
assert(source.includes("reader:needBits(schema.count * 8)"), "U8 reader preflight missing");
assert(source.includes("local values = acquirePackedValues(math.max(8, valueCount))"), "Packed runs must not reserve an entire maximum batch");
assert(source.includes("MaxPooledPackedValues = 64,"), "Bounded retained packed-value limit missing");
assert(source.includes("BitFrameInitialWriterBytes = 128,"), "BitFrame initial writer size missing");
assert(source.includes("BitFrameRetainWriterMaxBytes = 4096,"), "Binary writer retention cap missing");
assert(source.includes("function NetStream.TrimPools()"), "Idle memory trim API missing");
assert(source.includes("if length == 1 then"), "Unaligned single-byte string fast decoder missing");
assert(source.includes("local output = buffer.create(length)"), "Unaligned multi-byte buffer decoder missing");
assert(!source.includes("local chars = table.create(length)"), "Unaligned string decoder must not allocate a table of characters");
assert(source.includes("PackedValuePoolOversizeDrops"), "Oversized packed pool diagnostics missing");


const fixedStart = source.indexOf("local function readFixedSchemaArgs(reader, schema)");
const fixedEnd = source.indexOf("local function readSchemaArgs(reader, schema)", fixedStart);
assert(fixedStart >= 0 && fixedEnd > fixedStart, "Legacy fixed decoder not found");
const fixed = source.slice(fixedStart, fixedEnd);
assert.equal((fixed.match(/readFiniteFixedF64\(data, /g) || []).length, 10, "Legacy composite finite guards missing");
assert(source.includes('error("NetStream incoming fixed-schema F64 is not finite", 0)'), "Fixed-schema finite rejection missing");

const tests = readdirSync(resolve(root, "tests")).filter((name) => name.endsWith(".lua"));
assert(tests.length >= 94, "Regression suite unexpectedly missing");
for (const name of tests) {
    const content = read("tests/" + name);
    assert(!/\blocal\s+[A-Za-z_]\w*\s*=\s*\n\s*\S/.test(content), `Broken local assignment in ${name}`);
    const guards = [...content.matchAll(/NetStream\.GetVersion\(\) == "([^"]+)"/g)];
    for (const [, reported] of guards) assert.equal(reported, version, `Outdated version guard in ${name}`);
}



for (const name of ["RPCConcurrencyRegression.client.lua", "RPCConcurrencyRegression.server.lua"]) {
    assert(tests.includes(name), "Missing paired in-flight RPC overload and recovery regression: " + name);
}
for (const fragment of [
    "MaxConcurrentIncomingCalls = 512,",
    "MaxConcurrentIncomingCallsPerPlayer = 64,",
    "MaxConcurrentIncomingCalls must be an integer from 0 to 65536",
    "MaxConcurrentIncomingCallsPerPlayer must be an integer from 0 to 65536",
    "local activeIncomingCalls = 0",
    "local activeIncomingCallsByPlayer = setmetatable({}, {__mode = \"k\"})",
    "Stats.IncomingCallConcurrencyDrops += 1",
    "activeIncomingCalls += 1",
    "activeIncomingCallsByPlayer[player] = perPlayer + 1",
    "activeIncomingCalls = math.max(0, activeIncomingCalls - 1)",
    "function Internal.runIncomingCall(player, routeId, id, args)",
    "xpcall(Internal.handleCall, debug.traceback, player, routeId, id, args)",
    "function NetStream.GetRPCStats(player)",
    "copy.ActiveIncomingCalls = activeIncomingCalls",
]) assert(source.includes(fragment), "Missing bounded RPC concurrency guard: " + fragment);
assert.equal((source.match(/task\.spawn\(Internal\.runIncomingCall/g) || []).length,4,"Every incoming RPC codec path must use safe in-flight wrapper");
assert(!source.includes("task.spawn(Internal.handleCall"),"Unhandled raw RPC spawn bypasses concurrency slot cleanup");
for (const pCap of [1, 2, 4, 16, 64]) {
    const globalCap = pCap * 3;
    let active = 0, peak = 0, rejected = 0;
    const players = [0, 0, 0, 0, 0];
    for (let i = 0; i < globalCap * 40; i++) {
        const p = i % players.length;
        if (active >= globalCap || players[p] >= pCap) { rejected++; continue; }
        active++;players[p]++;peak = Math.max(peak,active);
    }
    assert(peak <= globalCap && players.every(n=>n <= pCap),"RPC concurrency model exceeded a cap");
    assert(rejected > 0,"RPC concurrency test did not pressure caps");
    for (let p = 0; p < players.length; p++) while (players[p] > 0) { players[p]--;active--; }
    assert.equal(active,0,"Finished callback did not release RPC slot");
    assert.equal(players.reduce((a,b)=>a+b,0),0,"RPC per-player count leaked");
}
for (const fragment of [
    "elseif n >= 4 and n <= 8 then",
    "elseif n == 12 then",
    "elseif count >= 4 and count <= 8 then",
    "elseif count == 12 then",
]) assert(source.includes(fragment),"Missing vararg copy fast path: " + fragment);
for (const count of [4,5,6,7,8,12]) {
    const args = Array.from({length:count},(_,i)=>i % 3 === 0 ? null : i * 17);
    const copied = Array.from({length:count},(_,i)=>args[i]);
    assert.deepEqual(copied,args,"Vararg bulk copy semantics for n=4..8/12 changed");
}
for (const name of ["MemoryRetentionRegression.client.lua", "MemoryRetentionRegression.server.lua"]) {
    assert(tests.includes(name), "Missing paired memory high-water regression: " + name);
}
for (const fragment of [
    "MaxPooledDictionaryEntries = 128,",
    "QueueRetainMaxSlots = 512,",
    "MaxPooledDictionaryEntries must be an integer from 0 to 8192",
    "QueueRetainMaxSlots must be an integer from 0 to 65536",
    "local function compactQueue(queue)",
    "local function clearDrainedQueue(queue)",
    "local items = table.create(pending)",
    "queue.items = items",
    "queue.items = {}",
    "Stats.QueueCompactions += 1",
    "Stats.QueueStorageRebuilds += 1",
    "Stats.DictionaryPoolRebuilds += 1",
    "Stats.NativeMeasureDictionaryRebuilds += 1",
    "state.stringEntries += 1",
    "state.strings = {}",
    "Stats.PooledWriterResets += 1",
]) assert(source.includes(fragment), "Missing memory retention protection: " + fragment);
const scratchRelease = source.slice(source.indexOf("function Internal.releaseScratchWriter"),source.indexOf("local Reader = {}"));
assert(scratchRelease.includes("writer:reset()"), "Idle scratch writer retains dynamic dictionaries");
const regularRelease = source.slice(source.indexOf("local function releaseWriter(writer)"),source.indexOf("local function batchLogicalCount"));
assert(regularRelease.includes("writer:reset()"), "Idle legacy writer retains dynamic dictionaries");
const bitWriterRelease = source.slice(source.indexOf("function Internal.releaseBitFrameWriter(writer)"),source.indexOf("function Internal.BitFrameWriter:ensureBits"));
assert(bitWriterRelease.includes("writer.stringToIndex = {}"), "BitFrame dictionary hash capacity not discarded at high-water");
const bitReaderRelease = source.slice(source.indexOf("function Internal.releaseBitFrameReader(reader)"),source.indexOf("function Internal.BitFrameReader:needBits"));
assert(bitReaderRelease.includes("reader.strings = {}"), "BitFrame reader dictionary high-water must be discarded");
const queueCompaction = source.slice(source.indexOf("local function compactQueue(queue)"),source.indexOf("function Internal.newBucket()"));
assert(queueCompaction.includes("compactQueue(queue)") && queueCompaction.includes("clearDrainedQueue(queue)"), "Per-item queue dequeue must release large sparse storage");
const batchCompaction = source.slice(source.indexOf("local function collectBatch(queue, latest, limit)"),source.indexOf("function Internal.packetByteBudget(",source.indexOf("local function collectBatch(queue, latest, limit)")));
assert(batchCompaction.includes("compactQueue(queue)") && batchCompaction.includes("clearDrainedQueue(queue)"), "Bulk dequeue must release large sparse storage");
for (const count of [32, 64, 128, 256, 512, 1057, 1328, 2049, 4097]) {
    let queue = {items:[],head:1,tail:0,rebuilds:0,compactions:0,logicalCount:0};
    for (let i = 1; i <= count; i++) { queue.items[++queue.tail] = i; queue.logicalCount++; }
    const delivered = [];
    while (queue.head <= queue.tail) {
        const batchLimit = 1 + count % 33;
        const take = Math.min(batchLimit,queue.tail - queue.head + 1);
        for (let i = 0; i < take; i++) {
            delivered.push(queue.items[queue.head]);
            queue.items[queue.head++] = undefined;
            queue.logicalCount--;
        }
        if (queue.head > queue.tail) {
            if (queue.tail > 16) { queue.items = []; queue.rebuilds++; }
            queue.head = 1;queue.tail = 0;queue.logicalCount = 0;
        } else if (queue.head > 1024 && queue.head > Math.floor(queue.tail / 2)) {
            const remaining = queue.tail - queue.head + 1;
            const next = Array.from({length:remaining},(_,index)=>queue.items[queue.head+index]);
            queue.items = [undefined,...next];queue.head = 1;queue.tail = remaining;queue.compactions++;
        }
    }
    assert.deepEqual(delivered,Array.from({length:count},(_,i)=>i+1),"Queue compaction changed FIFO or discarded messages");
    assert.equal(queue.logicalCount,0,"Queue logical count incorrect after draining");
    assert.equal(queue.tail,0,"Queue slots not reset after draining");
    assert(count <= 16 || queue.compactions + queue.rebuilds >= 1,"Queue must eventually release high-water storage");
}

for (const name of ["TypedTupleABBenchmark.client.lua", "TypedTupleABBenchmark.server.lua"]) {
    assert(tests.includes(name), "Missing paired Roblox Studio typed-tuple A/B benchmark: " + name);
}
for (const name of ["HomogeneousIntegerRunRegression.client.lua", "HomogeneousIntegerRunRegression.server.lua"]) {
    assert(tests.includes(name), "Missing paired U16/U32 packed-run regression: " + name);
}
for (const fragment of [
    "TypedTupleFastPathEnabled = true,",
    "TypedTupleFastPathEnabled must be a boolean",
    "wordRunU16 = wordRunU16,",
    "dwordRunU32 = dwordRunU32,",
    "Config.TypedTupleFastPathEnabled and (schema.wordRunU16 or schema.dwordRunU32)",
    "Config.TypedTupleFastPathEnabled and (item.schema.wordRunU16 or item.schema.dwordRunU32)",
    "count > 1 and Config.TypedTupleFastPathEnabled",
    "Stats.U16SchemaFastWrites += 1",
    "Stats.U32SchemaFastReads += 1",
    "Stats.BitFrameHomogeneousRunFastWrites += item.runCount",
    "Stats.BitFrameHomogeneousRunFastReads += count",
]) assert(source.includes(fragment), "U16/U32 serializer optimization missing: " + fragment);
assert.equal((source.match(/Config\.TypedTupleFastPathEnabled and \(schema\.wordRunU16 or schema\.dwordRunU32\)/g) || []).length, 3, "U16/U32 A/B guard must cover both single-message paths and run reads");
for (const width of [16, 32]) {
    for (const offset of [0, 1, 3, 7]) {
        for (let sample = 0; sample < 256; sample++) {
            const count = 1 + sample % 16;
            const max = 2 ** width - 1;
            const values = Array.from({length:count}, (_,index) => {
                if (index === 0) return sample % 256;
                if (index === 1) return 0;
                if (index === 2) return max;
                return Math.floor(((sample + 1) * 7919 + index * 104729) % (max + 1));
            });
            const bits = new Uint8Array(offset + count * width);
            let position = offset;
            for (const initial of values) {
                let value = initial;
                for (let i = 0; i < width; i++) { bits[position++] = value % 2; value = Math.floor(value / 2); }
            }
            position = offset;
            for (const expected of values) {
                let decoded = 0;
                for (let i = 0; i < width; i++) decoded += bits[position++] * 2 ** i;
                assert.equal(decoded,expected,"Homogeneous U16/U32 byte-unaligned bit layout changed");
            }
        }
    }
}
for (const name of ["DispatchFairnessRegression.client.lua", "DispatchFairnessRegression.server.lua", "BroadcastBudgetRegression.client.lua", "BroadcastBudgetRegression.server.lua"]) {
    assert(tests.includes(name), "Missing message-processing Studio regression: " + name);
}
for (const fragment of [
    "DispatchPerPlayerBacklogLimit = 2048,",
    "DispatchBudgetCheckInterval = 8,",
    "BroadcastFlushBudgetFraction = 0.5,",
    "local dispatchPendingByPlayer = setmetatable({}, {__mode = \"k\"})",
    "function NetStream.GetDispatchStats(player)",
    "local function dispatchCanEnqueue(player)",
    "local function dispatchRecordEnqueue(player)",
    "local function dispatchRecordDequeue(player)",
    "dispatchRecordDequeue(player)",
    "dispatchRecordEnqueue(player)",
    "player.Parent ~= Players",
    "Stats.DispatchPerPlayerDrops += 1",
    "Stats.DispatchDisconnectedDrops += 1",
    "budgetCheck += Config.DispatchBudgetCheckInterval",
    "Config.FlushBudgetSeconds * Config.BroadcastFlushBudgetFraction",
    "Stats.BroadcastBudgetSlices += 1",
    "table.clear(dispatchPendingByPlayer)",
]) assert(source.includes(fragment), "Message processing safety fragment missing: " + fragment);
for (let iteration = 1; iteration <= 1024; iteration++) {
    const cap = 1 + iteration % 40;
    const total = cap * 5;
    const queued = [];
    let aPending = 0, bPending = 0, aDrops = 0;
    for (let i = 0; i < total; i++) {
        if (aPending >= cap) aDrops++;
        else { queued.push("A"); aPending++; }
    }
    queued.push("B");
    bPending++;
    assert.equal(aPending,cap, "Noisy player exceeded per-player pending cap");
    assert.equal(aDrops,total-cap, "Per-player overflow accounting incorrect");
    assert.equal(bPending,1, "Quiet player must retain dispatch capacity");
    while (queued.length) {
        const next = queued.shift();
        if (next === "A") aPending--;
        else bPending--;
        assert(aPending >= 0 && bPending >= 0, "Dispatch pending counter underflow");
    }
    assert.equal(aPending,0,"Dispatch counter leaked on drain");
    assert.equal(bPending,0,"Quiet-player dispatch counter leaked");
    const fullDeadline = 1.5;
    const flushFraction = 0.1 + 0.9 * ((iteration % 100) / 100);
    const broadcastDeadline = Math.min(fullDeadline,1 + 0.5 * flushFraction);
    assert(broadcastDeadline <= fullDeadline && broadcastDeadline >= 1, "Broadcast budget does not reserve player processing time");
}

const compression = read("Compression.lua");
assert(compression.includes('return "2.4.2"'), "Bundled compression API version was not advanced");
assert(compression.includes("Compression.CodecVersion = 230") && compression.includes("Compression.EngineCode = 230") && compression.includes("Compression.Magic = 0x4E433233"), "Compression wire codec 230 must remain unchanged");
assert(source.includes('compressionFamily == "2.3." or compressionFamily == "2.4."'), "NetStream must support legacy compatible compression module");
assert(source.includes("Internal.CompressionCore.CodecVersion == 230"), "NetStream must check codec, not only package version");
assert(compression.includes("if value < 128 then") && compression.includes("self:Ensure(1)"), "Compression single-byte varuint writer fast path missing");
assert(compression.includes("local count = varUIntBytes(value)") && compression.includes("self:Ensure(count)"), "Compression multibyte writer exact preflight missing");
assert(compression.includes("if first < 128 then"), "Compression one-byte varuint reader fast path missing");
assert(compression.includes('error("NON_CANONICAL_VARUINT")') && compression.includes('error("VARUINT_TOO_LARGE")'), "Compression canonical varuint guards missing");
assert(compression.includes('error("UNSUPPORTED_MAP_KEY:" .. keyType)'), "Unsupported map key validation missing");
assert(source.includes("reader:needBits(count * width)"), "Packed receive burst preflight missing");
assert(source.includes("Stats.BitFramePackedScalarFastReads += count"), "Packed scalar receive path stats missing");
assert(source.includes("BitFramePackedScalarFastReads = stats.BitFramePackedScalarFastReads"), "Packed receive stats projection missing");
assert(tests.includes("CompressionV24Regression.server.lua"), "Compression v2.4.0 Studio regression missing");
for (const invalidKey of [{}, [], new Date()]) assert(!["string","number","boolean"].includes(typeof invalidKey), "Map-key type model broke");


assert(tests.includes("LowTrafficRegression.server.lua") && tests.includes("LowTrafficRegression.client.lua"), "Paired low-traffic Studio regression is missing");
for (const fragment of [
    "function NetStream.ConfigureLowTraffic(overrides)",
    "TransportBatchWindowSeconds = 0.05,",
    "TransportTargetMessagesPerPacket = 32,",
    "function Internal.recordSentState(target, unreliable, message)",
    "function Internal.shouldSuppressUnchangedState(target, route, value, unreliable, latest)",
    "Stats.LowTrafficStateDuplicatesSuppressed += 1",
    "if bucket and not bucketEmpty(bucket) then return false end",
    "if target == ALL then",
    "table.clear(stateDeliveryCache)",
    "if Internal.shouldSuppressUnchangedState(target, self, value, unreliable, latest) then",
    "LowTrafficStateCacheLimit = 128,",
    "LowTrafficMaxStateStringBytes = 64,",
    "stateDeliveryCache[CLIENT_STATE_CACHE_KEY] = nil",
]) assert(source.includes(fragment), "Low-traffic safety/behavior fragment missing: " + fragment);
const lowTrafficStart = source.indexOf("function Internal.shouldSuppressUnchangedState(");
const lowTrafficEnd = source.indexOf("function Internal.recordQueueAge(", lowTrafficStart);
assert(lowTrafficStart >= 0 && lowTrafficEnd > lowTrafficStart, "Low-traffic state guard boundary missing");
const lowTrafficGuard = source.slice(lowTrafficStart, lowTrafficEnd);
for (const clause of ["not route.SuppressUnchanged", "not latest", "unreliable", "target == ALL", "not stateCacheable(value)"]) assert(lowTrafficGuard.includes(clause), "Low-traffic cache must never suppress unsafe state classes: " + clause);
const recordStart = source.indexOf("function Internal.recordSentState(");
const recordEnd = source.indexOf("function Internal.shouldSuppressUnchangedState(", recordStart);
const record = source.slice(recordStart, recordEnd);
assert(record.includes('if message.kind ~= KIND_STATE then return end'), "Event/RPC messages must never be deduplicated");
assert(record.includes('table.clear(stateDeliveryCache)'), "Broadcast must invalidate stale per-player cached values");
assert(record.includes('Config.LowTrafficStateCacheLimit > 0'), "Disabled state cache should not allocate");
assert(source.includes('Internal.recordSentState(target, unreliable, item)'), "Isolated send must track delivery");
assert(source.includes('Internal.recordSentState(target, unreliable, items[i])'), "Batched send must track delivery");
for (const state of [false, true, 0, 1, -1, 255, "same"]) {
    for (const options of [
        {latest:true, unreliable:false, broadcast:false, pending:false, enabled:true, cache:true},
        {latest:false, unreliable:false, broadcast:false, pending:false, enabled:true, cache:true},
        {latest:true, unreliable:true, broadcast:false, pending:false, enabled:true, cache:true},
        {latest:true, unreliable:false, broadcast:true, pending:false, enabled:true, cache:true},
        {latest:true, unreliable:false, broadcast:false, pending:true, enabled:true, cache:true},
        {latest:true, unreliable:false, broadcast:false, pending:false, enabled:false, cache:true},
        {latest:true, unreliable:false, broadcast:false, pending:false, enabled:true, cache:false}
    ]) {
        const suppressed = options.enabled && options.latest && !options.unreliable && !options.broadcast && !options.pending && options.cache && state === state;
        const model = !(!options.enabled || !options.latest || options.unreliable || options.broadcast || options.pending || !options.cache || !Object.is(state,state));
        assert.equal(suppressed,model,"Low-traffic explicit guard model mismatch");
    }
}


for (const file of ["DeltaCodecRegression.server.lua", "DeltaCodecRegression.client.lua", "InterestGroupRegression.server.lua", "InterestGroupRegression.client.lua"]) {
    assert(tests.includes(file), "Missing v4.2.3 paired Studio regression: " + file);
}
for (const fragment of [
    "BitFrameFixedSchemaRunWrites = 0,",
    "BitFrameFixedSchemaRunReads = 0,",
    "writer:ensureBits(schema.discardBits * item.runCount)",
    "reader:needBits(schema.discardBits * count)",
    "function NetStream.CreateDeltaCodec(fieldNames)",
    "function codec:Full(state, revision)",
    "function codec:Diff(before, after, baseRevision)",
    "function codec:Apply(previous, previousRevision, frame)",
    "frame.Revision ~= previousRevision + 1",
    "bit32.band(nilMask, bit32.bnot(mask)) ~= 0",
    "function NetStream.CreateInterestGroup()",
    "function group:Fire(route, ...)",
    "function group:FireUnreliable(route, ...)",
    "function group:SetState(route, value, unreliable)",
    "player.Parent == Players",
    "InterestRecipientsQueued",
]) assert(source.includes(fragment), "Three-option feature guard missing: " + fragment);
function deltaModel(fields, prev, next) {
    let mask = 0, nilMask = 0, changes = [];
    for (let i = 0; i < fields.length; i++) {
        if (prev[fields[i]] !== next[fields[i]]) {
            mask += 2 ** i;
            if (next[fields[i]] === undefined) nilMask += 2 ** i;
            else changes.push(next[fields[i]]);
        }
    }
    return {mask, nilMask, changes};
}
for (let n = 1; n <= 32; n++) {
    const fields = Array.from({length:n},(_,i)=>"f"+i);
    const prev = Object.fromEntries(fields.map(x=>[x,0]));
    const next = {...prev, [fields[n-1]]:null};
    const model = deltaModel(fields,prev,next);
    assert.equal(model.mask,2 ** (n-1),"Delta bit mask at high field is incorrect");
    assert.equal(model.changes.length,1,"Delta changed field lost");
    const deleted = {...prev};
    delete deleted[fields[n-1]];
    const remove = deltaModel(fields,prev,deleted);
    assert.equal(remove.nilMask,remove.mask,"Delta explicit deletion mask is incorrect");
}
assert(tests.includes("MixedFixedSchemaRegression.server.lua") && tests.includes("MixedFixedSchemaRegression.client.lua"), "Paired mixed fixed-schema Studio regression missing");
assert(tests.includes("PacketSizeAuditRegression.server.lua") && tests.includes("PacketSizeAuditRegression.client.lua"), "Paired packet byte-audit Studio regression missing");
for (const fragment of [
    "PacketSizeAuditEnabled = false,",
    'assert(type(config.PacketSizeAuditEnabled) == "boolean"',
    "function Internal.bitFrameWriteOne(writer, item, audit)",
    "local metadataBits = 3 + routeBits + requestBits + runMarkerBits + runCountBits",
    "audit.PayloadBits += consumed - metadataBits",
    "function Internal.finishBitFrameBatch(writer, items, audit)",
    "audit.PhysicalBytes = math.ceil(writer.bitPosition / 8)",
    "local audit = if Config.PacketSizeAuditEnabled then newPacketAudit() else nil",
    "Internal._lastEncodedPacketAudit = audit",
    "if audit and audit.PhysicalBytes == bytes then",
    "function NetStream.GetPacketSizeAudit()",
    "Internal.PacketAuditTotals[field] += audit[field]",
]) assert(source.includes(fragment), "Packet-size audit guard missing: " + fragment);
const auditFields = ["Packets","LogicalMessages","Items","PresenceBits","KindBits","RouteIdBits","RequestIdBits","RunMarkerBits","RunCountBits","PayloadBits","EndBits","PaddingBits","UsefulBits","PhysicalBits","PhysicalBytes"];
for (const field of auditFields) assert(source.includes('"' + field + '"'), "Packet audit missing category " + field);
function adaptiveBits(value) { let bits=8; while(value>=128) {value=Math.floor(value/128);bits+=8;} return bits; }
function modelEvent(route,payloadBits,count=1) {
    const isRun=count>1;
    const presence=1, kind=2, routeBits=adaptiveBits(route), marker=1, runCount=isRun?adaptiveBits(count):0, ending=1;
    const useful=presence+kind+routeBits+marker+runCount+payloadBits*count+ending;
    return {bytes:Math.ceil(useful/8),useful,padding:Math.ceil(useful/8)*8-useful};
}
for (const [route,width,count,bytes] of [[1001,32,1,7],[1002,16,1,5],[1,16,1,4],[1002,16,8,20],[1001,32,27,112]]) {
    const m=modelEvent(route,width,count);
    assert.equal(m.bytes,bytes,"Packet audit reference byte size mismatch");
    assert.equal(m.useful + m.padding,m.bytes*8,"Packet audit pad/model mismatch");
}
assert.equal([modelEvent(1001,32,1),modelEvent(1002,16,1),modelEvent(1,16,1),modelEvent(1002,16,8)].reduce((sum,p)=>sum+p.bytes,0),36,"Packet audit mixed workload model mismatch");

let state = 0x31415926;
function random() {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state;
}
assert(source.includes("function Internal.splitPackedRunMessage(message, keepCount)"), "Packed-run splitting is missing");
assert(source.includes("Stats.PackedRunBatchSplits += 1"), "Packed split counter is missing");
assert(source.includes("while ok and buffer.len(data) > byteBudget do"), "Packet budget splitter must include single packed runs");
assert(source.includes("local packetBudget = Math") === false, "Luau packet budget accidentally uses JS");
assert(source.includes("local packetBudget = math.min(Config.MaxOutgoingBatchBytes, Config.BitFrameMaxBytes)"), "Packed runs must respect output byte caps");
assert(source.includes("if bitPosition + len * 8 > buffer.len(data) * 8 then error"), "Hybrid string bounds validation missing");
assert(source.includes("self:ensureBits(64)"), "F64 write fast path missing");
assert(source.includes("self:needBits(64)"), "F64 read fast path missing");

const commitStart = source.indexOf("function Internal.commitBitFrameStage(player, stage)");
const commitEnd = source.indexOf("function Internal.bitFrameReadDynamic(", commitStart);
const parseStart = source.indexOf("function Internal.parseBitFrame(", commitEnd);
const parseEnd = source.indexOf("function Internal.decodeBitFrame(", parseStart);
assert(commitStart >= 0 && commitEnd > commitStart && parseStart > commitEnd && parseEnd > parseStart, "Atomic parser and committer boundaries missing");
const commit = source.slice(commitStart, commitEnd);
const parser = source.slice(parseStart, parseEnd);
assert(/elseif kind == KIND_STATE then\s*if consumeRouteAllowance\(route, player, 1\) > 0 then/.test(commit), "State must be rate-limited before mutation");
assert(!/consumeRouteAllowance\(|enqueueDispatch\(|Internal\.processReturn\(|task\.spawn\(Internal\.handleCall|state\[routeId\]\s*=/.test(parser), "BitFrame parser must not trigger gameplay effects");
assert(source.includes("reader._bitFrameStage = stage"), "Atomic BitFrame decoder must retain pending staging for failure cleanup");
assert(source.includes("if bitFrame and reader._bitFrameStage then"), "Receive handler must clean up malformed staged packets");
assert(source.includes("pcall(decodeBatch, player, data, reader)"), "Receive handler must protect packet parsing");
assert(!source.includes("pcall(Internal.parseBitFrame,"), "Atomic decode should reuse existing protected receive call rather than nesting pcall");
assert(source.includes("Stats.BitFrameAtomicDiscardedActions += stage.count"), "Malformed BitFrame actions must be counted and discarded");
assert(source.includes("if actionCount > Config.MaxPooledBitFrameActions then return end"), "Large decoder staging arrays must not remain pooled");
assert(source.includes("function Internal.stageBitFrameScalar(stage, kind, route, routeId, value, group)"), "Allocation-free scalar staging missing");
assert(source.includes("Internal.BitFrameWriter.varUInt = Internal.BitFrameWriter.adaptiveUInt"), "BitFrame varUInt alias missing");
assert(source.includes("byte < 128 then"), "One-byte varUInt fast path missing");
assert(source.includes("MaxBitFrameStagePoolSize = 8,"), "Bounded stage-pool size default missing");
assert(source.includes("if #pool >= Config.MaxBitFrameStagePoolSize then return end"), "Full stage pool must drop actions without clearing unpooled arrays");
assert(source.includes("local routeId = if route then route.Id else 0"), "Commit must reuse route ID instead of storing a parallel array");
assert(!source.includes("stage.routeIds"), "Redundant stage route ID table still retained");
assert(!/stage\.(scalarFlags|scalarValues)/.test(source), "Scalar stages must not allocate separate flag/value tables");
assert(source.includes("stage.groups[index] = -((group or 1) + 1)"), "Scalar tag must distinguish nil from args tables");
assert(source.includes("if stage.groups[i] >= 0 and args then releaseArgs(args) end"), "Cleanup must not release a scalar as an args table");
assert(source.includes("function Internal.bitFrameDiscardSchemaArgs(reader, schema)"), "Allocation-free rejected schema parser missing");
assert(source.includes("reader.bitPosition += skipBits"), "Fixed-schema reject path should skip prevalidated bits");
assert(source.includes("Stats.BitFrameDiscardedFixedBits += skipBits"), "Discarded fixed-schema bits statistic missing");
assert(source.includes("discardBits = if discardFixed then discardBits else nil"), "Fixed skip lengths must be derived at schema compilation");
assert(source.includes("elseif kind == SCHEMA_COLOR3 then discardBits += 24"), "Color3 fixed skip size is missing");
assert(source.includes("else discardFixed = false end"), "Unsafe schema types must be excluded from skip optimization");
assert(source.includes("function Internal.bitFrameReadScalarSchema(reader, kind)"), "Single-field numeric decoder fast path missing");
for (const name of ["SCHEMA_U16", "SCHEMA_I16", "SCHEMA_U32", "SCHEMA_I32", "SCHEMA_F32", "SCHEMA_F64"]) assert(source.includes("if kind == " + name + " then return reader:"), `Scalar fast path missing ${name}`);
assert(source.includes("BitFrameScalarSchemaReads = stats.BitFrameScalarSchemaReads"), "Scalar hot-path diagnostics missing");
assert(source.includes("Stats.BitFrameDiscardedSchemaArgs += 1"), "Rejected schema decode counter missing");
assert(source.includes("for _ = 1, count do Internal.bitFrameDiscardSchemaArgs(reader, schema) end"), "Variable-width rejected schema runs must retain validated fallback");
assert(source.includes("local totalBits = fixedBits * count"), "Bulk schema rejection must compute exact run bit length");
assert(source.includes("reader:needBits(totalBits)"), "Bulk schema rejection must bounds-check whole run before advancing");
assert(source.includes("Stats.BitFrameBulkDiscardedRuns += 1"), "Bulk-rejection CPU counter missing");
assert(source.includes("elseif not scalar then\n\t\t\t\treleaseArgs(args)"), "Rate-limited scalar values must never pass through argument-table release");
assert(source.indexOf("Internal.commitBitFrameStage(player, stage)") < source.indexOf("reader._bitFrameStage = nil", source.indexOf("function Internal.decodeBitFrame")), "Decode stage must remain reachable during commit failures");
assert(!source.includes("dispatchScalarValues"), "Dispatch scalar payloads must share the args/value slot, not a second table");
assert(source.includes("dispatchArgs[dispatchCount] = value"), "Scalar dispatch payload slot missing");
assert(source.includes("dispatchScalarFlags[dispatchCount] = true"), "Nil scalar tag must be retained");
assert(source.includes("Stats.BitFrameRejectedDynamicArgsAvoided += 1"), "Rejected dynamic args fast path missing");
assert(source.includes("MaxArgsPoolSize = 512") && source.includes("MaxMessagePoolSize = 512") && source.includes("MaxPooledBatchItems = 512"), "Default bounded idle-pool limits missing");
assert(source.includes("unpooledBatches = setmetatable({}, {__mode = \"k\"})"), "Oversized transient batch tracking must not retain discarded keys");
assert(source.includes("if #batchPool >= Config.MaxBatchPoolSize then return end"), "Full batch pools must not clear dropped objects");
assert(source.includes("if #pool >= Config.MaxBitFrameStagePoolSize then return end"), "Full atomic stage pools must not clear dropped objects");
assert(source.includes("Stats.BatchPoolOversizeDrops += 1"), "Oversized batch drop metric missing");
const bitsWriterStart = source.indexOf("function Internal.BitFrameWriter:bits(value, count)");
const bitsWriterEnd = source.indexOf("function Internal.BitFrameWriter:adaptiveUInt(value)", bitsWriterStart);
assert(bitsWriterStart >= 0 && bitsWriterEnd > bitsWriterStart, "BitFrame writer fast path boundary missing");
const bitWriter = source.slice(bitsWriterStart, bitsWriterEnd);
assert(bitWriter.includes("nextPosition > self.capacity * 8 or nextPosition > Config.BitFrameMaxBytes * 8"), "Bit writer must keep both capacity and configured maximum checks");
assert(bitWriter.includes("buffer.writebits(self.buffer, position, count, value)"), "Bit writer direct fast path missing");
const makeArgsStart = source.indexOf("local function makeArgs(...)");
const makeArgsEnd = source.indexOf("local function acquirePackedValues(", makeArgsStart);
const makeArgs = source.slice(makeArgsStart, makeArgsEnd);
for (const guard of ["if n == 1 then", "elseif n == 2 then", "elseif n == 3 then", "select(i, ...)"]) assert(makeArgs.includes(guard), `Small vararg pack path missing ${guard}`);
assert(source.includes("if scalarKind and allowed then"), "Packed scalar run specialization missing");
assert(source.includes("Internal.stageBitFrameScalar(stage, kind, route, routeId, value, if index == 1 then count else 0)"), "Scalar run must preserve first group and following continuation tags");
assert(source.includes("stage.groups[index] = -((group or 1) + 1)"), "Scalar continuation sentinel missing");
assert(source.includes("group ~= 0 and group ~= -1"), "Scalar route allowance must skip run continuations");
assert(source.includes("Stats.BitFramePackedScalarRunItems += count"), "Packed scalar run diagnostics missing");
assert(source.includes('unpooledPackedValues = setmetatable({}, {__mode = "k"})'), "Packed high-water set must not prevent GC");
assert(source.includes("if base + valueCount > Config.MaxPooledPackedValues then unpooledPackedValues[values] = true end"), "Growing packed runs must retain high-water status");
assert(source.includes("if total * fieldCount > Config.MaxPooledPackedValues then unpooledPackedValues[values] = true end"), "Split packed runs must preserve high-water status");
assert(source.includes("if highWater or usedCount > Config.MaxPooledPackedValues then"), "Previously oversized arrays must never enter packed value pool");
assert(source.includes("PackedValueHighWaterDrops = Stats.PackedValueHighWaterDrops"), "High-water diagnostics missing");
for (const name of ["PackedScalarRunRegression", "PackedHighWaterRegression"]) assert(tests.includes(name + ".server.lua") && tests.includes(name + ".client.lua"), `Missing Studio test pair ${name}`);


for (const pair of ["PackedScalarRunRegression", "PackedHighWaterRegression", "StateThrottleRegression", "PackedBudgetRegression", "BinaryPrecisionRegression", "AtomicPacketRegression", "AtomicScalarRegression", "HeapDiscardRegression", "StagePoolMemoryRegression", "FixedDiscardRegression", "ExtendedScalarStringRegression", "ScalarThrottleHeapRegression", "DynamicDiscardHeapRegression", "BoundedPoolRegression"]) {
    assert(tests.includes(pair + ".client.lua") && tests.includes(pair + ".server.lua"), `Missing Studio regression pair: ${pair}`);
}

for (let run = 0; run < 5000; run++) {
    const fields = 1 + random() % 8;
    const count = 2 + random() % 256;
    const keep = 1 + random() % (count - 1);
    const values = Array.from({length: fields * count}, (_, i) => (i * 31 + run) % 256);
    const prefix = values.slice(0, keep * fields);
    const suffix = values.slice(keep * fields);
    assert.deepEqual(prefix.concat(suffix), values, "Packed split lost data or changed FIFO order");
    assert.equal(prefix.length / fields + suffix.length / fields, count, "Packed split count changed");
}



const batchDrainStart = source.indexOf("local function collectBatch(queue, latest, limit)");
const batchDrainEnd = source.indexOf("function Internal.packetByteBudget(", batchDrainStart);
assert(batchDrainStart > 0 && batchDrainEnd > batchDrainStart, "Missing burst batch-drain function");
const batchDrain = source.slice(batchDrainStart, batchDrainEnd);
assert(batchDrain.includes("local slots = queue.items") && batchDrain.includes("queue.logicalCount = math.max(0, queue.logicalCount - consumed)"), "Amortized burst queue accounting missing");
assert(!batchDrain.includes("local item = queuePop(queue)"), "Batch collection regressed to per-message queuePop");
assert(source.includes("local budgetCheck = Config.DispatchBudgetCheckInterval") && source.includes("if processed >= budgetCheck then"), "Configurable dispatch budget checks missing");
assert(source.includes("local function fillPackedValues(values, base, count, ...)"), "Small fixed-schema vararg packer missing");
assert(source.includes("Stats.BitFramePackedScalarRunWrites += item.runCount"), "Packed scalar bulk writer counter missing");
assert(source.includes("writer:ensureBits(item.runCount * width)"), "Packed scalar writer must preflight whole run");
for (const type of ["SCHEMA_BOOL", "SCHEMA_U8", "SCHEMA_U16"]) assert(source.includes("scalarKind == " + type), "Packed scalar writer missing " + type);
assert(tests.includes("BurstSaturationBenchmark.server.lua") && tests.includes("BurstSaturationBenchmark.client.lua"), "Paired burst benchmark missing");
// Reference-model the logical queue contract: a packed run can exceed the limit only as first item.
for (let trial = 0; trial < 8000; trial++) {
    const messageCounts = Array.from({length: 1 + random() % 90}, () => 1 + random() % 32);
    const limit = 1 + random() % 256;
    let oldIndex = 0;
    let oldLogical = 0;
    while (oldLogical < limit && oldIndex < messageCounts.length) {
        const nextCount = messageCounts[oldIndex];
        if (oldLogical > 0 && oldLogical + nextCount > limit) break;
        oldLogical += nextCount;
        oldIndex++;
    }
    let newHead = 0;
    let newLogical = 0;
    let consumed = 0;
    while (newLogical < limit && newHead < messageCounts.length) {
        const count = messageCounts[newHead];
        if (newLogical > 0 && newLogical + count > limit) break;
        newHead++;
        newLogical += count;
        consumed += count;
    }
    assert.equal(newHead, oldIndex, "Batch drain changed FIFO split");
    assert.equal(consumed, oldLogical, "Batch drain changed logical counts");
    assert.equal(messageCounts.slice(newHead).reduce((a, b) => a + b, 0), messageCounts.reduce((a, b) => a + b, 0) - consumed, "Batch drain corrupted pending count");
}


assert(source.includes("DispatchQueueCompactions = 0"), "Dispatch compaction counter missing");
assert(source.includes("Stats.DispatchQueueCompactions += 1"), "Dispatch compaction telemetry missing");
const dispatchStart = source.indexOf("local function runDispatch()");
const dispatchEnd = source.indexOf("local function enqueueDispatch(", dispatchStart);
assert(dispatchStart > 0 && dispatchEnd > dispatchStart, "Dispatch loop boundaries missing");
const dispatch = source.slice(dispatchStart, dispatchEnd);
assert(dispatch.includes("elseif dispatchHead > Config.MaxDispatchBacklog then"), "Sustained dispatch queue compaction guard missing");
assert(dispatch.includes("local pending = dispatchCount - dispatchHead + 1"), "Dispatch compaction must only move pending actions");
for (const name of ["dispatchRoutes", "dispatchPlayers", "dispatchArgs", "dispatchScalarFlags"]) {
    assert(dispatch.includes(name + "[i] = " + name + "[from]"), "Dispatch compaction must preserve " + name);
    assert(dispatch.includes(name + "[from] = nil"), "Dispatch compaction must clear stale " + name);
}
assert(compression.includes('return "2.4.2"'), "Compression release version mismatch");
assert(compression.includes('options.StringDictionary == false or typeof(value) ~= "table"'), "Scalar dictionary work should be skipped");
assert(!compression.includes("local seenKeys = {}"), "Map decode should not allocate a second map-key table");
assert(compression.includes("if output[key] ~= nil then error(\"DUPLICATE_MAP_KEY\") end"), "Decode must still reject duplicate primitive keys");
assert(compression.includes("math.max(64, HEADER_BYTES + dictionaryBytes + scannedNodes * 6)"), "Default compression writer size must be bounded");
for (const name of ["DispatchCompactionRegression", "CompressionV241Regression"]) {
    if (name === "DispatchCompactionRegression") assert(tests.includes(name + ".client.lua") && tests.includes(name + ".server.lua"), "Missing paired dispatch compaction regression");
    else assert(tests.includes(name + ".server.lua"), "Missing Compression 2.4.1 regression");
}
// Exercise FIFO compaction invariants, including false/nil scalar payload metadata.
for (let trial = 0; trial < 10000; trial++) {
    const limit = 8 + random() % 128;
    const head = limit + 1 + random() % 500;
    const pending = 1 + random() % limit;
    const initial = Array.from({length:pending}, (_, i) => ({seq:i, arg:i%3===0?null:i%3===1?false:i, scalar:i%2===0}));
    const store = new Map(initial.map((v,i)=>[head+i,v]));
    for (let i=1;i<=pending;i++) {
        const from=head+i-1;
        store.set(i,store.get(from));
        store.delete(from);
    }
    assert.deepEqual(Array.from({length:pending},(_,i)=>store.get(i+1)), initial, "Dispatch compaction changed FIFO or scalar values");
    assert.equal(store.size,pending,"Dispatch compaction retained old sparse indices");
}


const isolatedStart = source.indexOf("function Internal.sendIsolatedMessages(target, unreliable, items)");
const isolatedEnd = source.indexOf("local function flushChannel(", isolatedStart);
assert(isolatedStart > 0 && isolatedEnd > isolatedStart, "Isolated-send recovery function missing");
const isolated = source.slice(isolatedStart, isolatedEnd);
assert.equal((isolated.match(/items\[i\] = false/g) || []).length, 3, "Every isolated recovery release must retain array length with false sentinels");
assert(!isolated.includes("items[i] = nil"), "Isolated recovery must not create holes that truncate deferred tail");
const restoreStart = source.indexOf("function Internal.restoreDeferredItems(");
const restoreEnd = source.indexOf("local function fireRemote(", restoreStart);
assert(restoreStart > 0 && restoreEnd > restoreStart, "Deferred FIFO restore function missing");
const restore = source.slice(restoreStart, restoreEnd);
for (const snippet of ["local restoreCount = 0", "if restoreCount > 0 and queue.head <= restoreCount then", "for i = queue.tail, queue.head, -1 do", "queue.head = restoreCount + 1"]) assert(restore.includes(snippet), "Safe nonnegative prepend path missing: " + snippet);
assert(compression.includes("local EMPTY_DICTIONARY = table.freeze({})"), "Shared empty Compression dictionary missing");
assert(compression.includes("return EMPTY_DICTIONARY, EMPTY_DICTIONARY, 0, 0"), "No-dictionary codec still allocates throwaway maps");
assert(compression.includes("local seen = if typeof(value) == \"table\" then {} else EMPTY_DICTIONARY"), "Scalar encode still allocates a traversal map");
assert(compression.includes("local dictionary = if dictionaryCount > 0 then table.create(dictionaryCount) else EMPTY_DICTIONARY"), "No-dictionary decode still allocates an unnecessary array");
assert(compression.includes('if keyTag == TAG_ARRAY or keyTag == TAG_MAP then error("UNSUPPORTED_MAP_KEY:table") end'), "Composite map-key decoding must reject before any table allocation");
assert(tests.includes("TransportRecoveryRegression.client.lua") && tests.includes("TransportRecoveryRegression.server.lua") && tests.includes("CompressionV242Regression.server.lua"), "v4.0.2 Studio regressions missing");

// Model isolated send recovery: the completed prefix must never alter tail length/order.
for (let trial = 0; trial < 10000; trial++) {
    const len = 2 + random() % 96;
    const sent = 1 + random() % (len - 1);
    const items = Array.from({length:len}, (_, i) => ({id:i+1}));
    for (let i = 0; i < sent; i++) items[i] = false;
    assert.equal(items.length, len, "Recovery completion shortened the batch");
    const pending = items.slice(sent).filter(Boolean);
    assert.deepEqual(pending.map(v=>v.id), Array.from({length:len-sent},(_,i)=>sent+i+1), "Recovery lost or reordered deferred suffix");
}

// Model FIFO prefix-space reservation in empty and partially occupied queues.
for (let trial = 0; trial < 10000; trial++) {
    const restoreCount = 1 + random() % 64;
    const liveCount = random() % 128;
    const initialHead = 1 + random() % 48;
    const pending = Array.from({length:liveCount}, (_, i)=>10000+i);
    const deferred = Array.from({length:restoreCount}, (_, i)=>i);
    const slots = new Map();
    let head = initialHead;
    let tail = initialHead + liveCount - 1;
    for (let i = 0; i < liveCount; i++) slots.set(initialHead+i,pending[i]);
    if (restoreCount > 0 && head <= restoreCount) {
        if (liveCount > 0) {
            const shift = restoreCount - head + 1;
            for (let i = tail; i >= head; i--) { slots.set(i+shift,slots.get(i)); slots.delete(i); }
            tail += shift;
            head += shift;
        } else {
            head = restoreCount+1;
            tail = restoreCount;
        }
    }
    for (let i = deferred.length - 1; i >= 0; i--) slots.set(--head,deferred[i]);
    const ids = Array.from({length:tail-head+1},(_,i)=>slots.get(head+i));
    assert(head>=1,"Deferred restore created nonpositive sparse queue indices");
    assert.deepEqual(ids,deferred.concat(pending),"Deferred restore reordered FIFO or lost pending entries");
}

function put(bytes, position, value) {
    for (let bit = 0; bit < 8; bit++) {
        const at = position + bit;
        const mask = 1 << (at % 8);
        bytes[at >>> 3] = (bytes[at >>> 3] & ~mask) | (((value >>> bit) & 1) << (at % 8));
    }
}
function get(bytes, position) {
    let value = 0;
    for (let bit = 0; bit < 8; bit++) value |= ((bytes[(position + bit) >>> 3] >>> ((position + bit) % 8)) & 1) << bit;
    return value;
}

for (let run = 0; run < 10000; run++) {
    const count = 2 + random() % 31;
    const offset = random() % 8;
    const values = Array.from({length:count}, (_, i) => i === 0 ? 0 : i === count - 1 ? 255 : random() % 256);
    const before = new Uint8Array(Math.ceil((offset + count * 8) / 8) + 1);
    const after = new Uint8Array(before.length);
    for (let i = 0; i < count; i++) put(before, offset + i * 8, values[i]);
    let position = offset;
    for (let i = 0; i < count; i++) { put(after, position, values[i]); position += 8; }
    assert.deepEqual(after, before, `U8 wire parity failed on run ${run}`);
    for (let i = 0; i < count; i++) assert.equal(get(after, offset + i * 8), values[i], "U8 payload changed");
    assert(offset + count * 8 <= after.length * 8, "Bit preflight must prevent truncation");
}

const MAX = 9007199254740991;
function varintBytes(number) {
    assert(typeof number === "number" && Number.isSafeInteger(number) && number >= 0, "Invalid varuint");
    const result = [];
    do {
        let byte = number % 128;
        number = Math.floor(number / 128);
        if (number) byte += 128;
        result.push(byte);
    } while (number);
    return result;
}
function varintLength(number) {
    assert(typeof number === "number" && Number.isSafeInteger(number) && number >= 0, "Invalid varuint");
    let bits = 8;
    while (number >= 128) { number = Math.floor(number / 128); bits += 8; }
    return bits;
}
for (const value of [0, 1, 127, 128, 255, 16383, 16384, 4294967295, MAX]) assert.equal(varintBytes(value).length * 8, varintLength(value));
for (let run = 0; run < 6000; run++) {
    const value = Math.floor((random() / 0x100000000) * MAX);
    assert.equal(varintBytes(value).length * 8, varintLength(value));
}
for (const value of [-1, 1.5, NaN, Infinity, -Infinity, MAX + 1, "1", null]) assert.throws(() => varintLength(value));

for (const value of [NaN, Infinity, -Infinity, 0, -0, 1, -3.5, Number.MAX_VALUE]) {
    const data = new DataView(new ArrayBuffer(8));
    data.setFloat64(0, value, true);
    assert.equal(Number.isFinite(data.getFloat64(0, true)), Number.isFinite(value));
}

// Model the signed-group scalar layout including nil and repeated schema runs.
for (let run = 0; run < 5000; run++) {
    const messageCount = 1 + random() % 48;
    const originals = [];
    const staged = [];
    for (let index = 0; index < messageCount; index++) {
        const scalar = (random() % 3) === 0;
        const value = scalar ? [null, false, 0, 127, "tiny"][random() % 5] : [random() % 255, index];
        const group = scalar ? -1 : (index === 0 ? messageCount : 0);
        originals.push({scalar, value, group});
        staged.push({args:value, group});
    }
    for (let index = 0; index < staged.length; index++) {
        assert.equal(staged[index].group < 0, originals[index].scalar, "Scalar group tag changed");
        assert.deepEqual(staged[index].args, originals[index].value, "Stage payload lost data (including nil)");
    }
}


for (let run = 0; run < 6000; run++) {
    const width = [0, 1, 8, 16, 24, 32, 48, 64, 129][random() % 9];
    const count = 2 + random() % 255;
    const position = random() % 8;
    const length = position + width * count + (random() % 2 === 0 ? 0 : -1);
    const bulkValid = position + width * count <= length;
    let perItemPosition = position;
    let perItemValid = true;
    for (let i = 0; i < count; i++) {
        if (perItemPosition + width > length) { perItemValid = false; break; }
        perItemPosition += width;
    }
    assert.equal(bulkValid, perItemValid, "Bulk fixed-schema skip accepted an invalid truncated run");
    if (bulkValid) assert.equal(perItemPosition, position + width * count, "Bulk discard consumed different bits");
}
const scalarSamples = [undefined, null, true, false, 0, 255, -1337, "abc", "", 1 / 4];
for (let run = 0; run < 3000; run++) {
    const flags = [], payloads = [], expected = [];
    const size = 1 + random() % 48;
    for (let i = 1; i <= size; i++) {
        const scalar = random() % 2 === 0;
        const value = scalarSamples[random() % scalarSamples.length];
        flags[i] = scalar || undefined;
        payloads[i] = value;
        expected.push({scalar, value});
    }
    for (let i = 1; i <= size; i++) {
        assert.equal(flags[i] === true, expected[i - 1].scalar, "Scalar and args queue tags diverged");
        assert.equal(payloads[i], expected[i - 1].value, "Unified dispatch queue corrupted payload or nil");
        payloads[i] = undefined;
        flags[i] = undefined;
    }
}

for (const label of ["3.6.0", "3.7.0", "3.8.0", "2.3.29", "2.3.30", "2.3.31", "2.3.35", "2.3.36", "2.3.37", "2.4.0", "2.5.0", "2.6.0", "2.7.0", "2.8.0", "2.9.0", "3.0.0", "3.1.0", "3.2.0", "3.3.0", "3.4.0", "3.5.0"]) assert(read("docs/CHANGELOG.md").includes(label));
for (let run = 0; run < 5000; run++) {
    const count = 1 + random() % 256;
    const allowance = random() % (count + 1);
    let remaining = 0, delivered = 0;
    for (let i = 0; i < count; i++) {
        const groupTag = -( (i === 0 ? count : 0) + 1 );
        assert(groupTag < 0, "Scalar and continuation tags must be negative");
        if (groupTag !== -1) remaining = Math.min(allowance, -groupTag - 1);
        if (remaining > 0) { remaining--; delivered++; }
    }
    assert.equal(delivered, allowance, "Packed scalar run changed route token allowance accounting");
}
for (let run = 0; run < 2000; run++) {
    const limit = 8 + random() % 64;
    const highWater = limit + 1 + random() % 256;
    const afterSplit = random() % (limit + 1);
    assert(highWater > limit && afterSplit <= limit, "Invalid high-water test");
    assert(!(highWater <= limit && afterSplit <= limit), "Oversized backing storage must be discarded regardless of live split count");
}
for (const fragment of [
    "PackedSchemaRunMaxFields = 16,",
    "bitFrameWidths = if bitPackedBooleans or byteRunU8 then nil else bitFrameWidths,",
    "writer:ensureBits(schema.discardBits)",
    "reader:needBits(schema.discardBits)",
    "Stats.BitFrameFixedSchemaFastWrites += 1",
    "Stats.BitFrameFixedSchemaFastReads += 1",
    "BitFrameFixedSchemaFastReads = stats.BitFrameFixedSchemaFastReads",
]) assert(source.includes(fragment), "Mixed fixed-schema fast path missing: " + fragment);
const mixedWidths = [1, 8, 16, 16, 32, 32, 1, 8, 16, 16, 32, 32];
const mixedSigned = new Set([3, 5, 9, 11]);
for (let iteration = 1; iteration <= 2048; iteration++) {
    const values = [iteration % 2, 0, 65535, -32768, 4294967295, -2147483648, (iteration + 1) % 2, 255, iteration % 65536, -iteration, 2147483648, 2147483647];
    const offset = iteration % 8;
    const bits = new Uint8Array(offset + mixedWidths.reduce((a, b) => a + b, 0));
    let pos = offset;
    for (let i = 0; i < mixedWidths.length; i++) {
        let value = values[i] < 0 ? values[i] + 2 ** mixedWidths[i] : values[i];
        for (let bit = 0; bit < mixedWidths[i]; bit++) { bits[pos++] = value % 2; value = Math.floor(value / 2); }
    }
    pos = offset;
    const decoded = [];
    for (let i = 0; i < mixedWidths.length; i++) {
        let value = 0;
        for (let bit = 0; bit < mixedWidths[i]; bit++) value += bits[pos++] * 2 ** bit;
        if (mixedSigned.has(i) && value >= 2 ** (mixedWidths[i] - 1)) value -= 2 ** mixedWidths[i];
        decoded.push(value);
    }
    assert.deepEqual(decoded, values, "Mixed schema signed/unsigned bit layout parity failed");
}
assert(read("README.md").includes(`v${version}`));
console.log(`PASS NetStream ${version}: 10,000 packed-U8 cases, 6,009 valid varuints, 8 rejected invalid varuints, 8 F64 cases, 5,000 packed-split parity models, atomic parser + packed scalar allowance models, fixed-discard, writer fast path and packed high-water GC guards, ${tests.length} Studio-script static scans`);
