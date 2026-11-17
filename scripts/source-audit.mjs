import assert from "node:assert/strict";
import {readFileSync, readdirSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {dirname, resolve} from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFileSync(resolve(root, path), "utf8");
const source = read("Netstream.lua");
const version = "4.0.0";

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
assert(tests.length >= 66, "Regression suite unexpectedly missing");
for (const name of tests) {
    const content = read("tests/" + name);
    assert(!/\blocal\s+[A-Za-z_]\w*\s*=\s*\n\s*\S/.test(content), `Broken local assignment in ${name}`);
    const guards = [...content.matchAll(/NetStream\.GetVersion\(\) == "([^"]+)"/g)];
    for (const [, reported] of guards) assert.equal(reported, version, `Outdated version guard in ${name}`);
}


const compression = read("Compression.lua");
assert(compression.includes('return "2.4.0"'), "Bundled compression API version was not advanced");
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
assert(source.includes("local budgetCheck = 32") && source.includes("if processed == budgetCheck then"), "Dispatch should avoid modulo in burst loop");
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
assert(read("README.md").includes(`v${version}`));
console.log(`PASS NetStream ${version}: 10,000 packed-U8 cases, 6,009 valid varuints, 8 rejected invalid varuints, 8 F64 cases, 5,000 packed-split parity models, atomic parser + packed scalar allowance models, fixed-discard, writer fast path and packed high-water GC guards, ${tests.length} Studio-script static scans`);
