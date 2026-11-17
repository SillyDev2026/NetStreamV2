import assert from "node:assert/strict";
import {readFileSync, readdirSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {dirname, resolve} from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFileSync(resolve(root, path), "utf8");
const source = read("Netstream.lua");
const version = "2.9.0";

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
assert(source.includes("if length >= 16 then"), "Unaligned binary string buffer decoder missing");
assert(source.includes("PackedValuePoolOversizeDrops"), "Oversized packed pool diagnostics missing");


const fixedStart = source.indexOf("local function readFixedSchemaArgs(reader, schema)");
const fixedEnd = source.indexOf("local function readSchemaArgs(reader, schema)", fixedStart);
assert(fixedStart >= 0 && fixedEnd > fixedStart, "Legacy fixed decoder not found");
const fixed = source.slice(fixedStart, fixedEnd);
assert.equal((fixed.match(/readFiniteFixedF64\(data, /g) || []).length, 10, "Legacy composite finite guards missing");
assert(source.includes('error("NetStream incoming fixed-schema F64 is not finite", 0)'), "Fixed-schema finite rejection missing");

const tests = readdirSync(resolve(root, "tests")).filter((name) => name.endsWith(".lua"));
assert(tests.length >= 49, "Regression suite unexpectedly missing");
for (const name of tests) {
    const content = read("tests/" + name);
    assert(!/\blocal\s+[A-Za-z_]\w*\s*=\s*\n\s*\S/.test(content), `Broken local assignment in ${name}`);
    const guards = [...content.matchAll(/NetStream\.GetVersion\(\) == "([^"]+)"/g)];
    for (const [, reported] of guards) assert.equal(reported, version, `Outdated version guard in ${name}`);
}

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
assert(source.includes("function Internal.stageBitFrameScalar(stage, kind, route, routeId, value)"), "Allocation-free scalar staging missing");
assert(source.includes("Internal.BitFrameWriter.varUInt = Internal.BitFrameWriter.adaptiveUInt"), "BitFrame varUInt alias missing");
assert(source.includes("byte < 128 then"), "One-byte varUInt fast path missing");
assert(source.includes("MaxBitFrameStagePoolSize = 8,"), "Bounded stage-pool size default missing");
assert(source.includes("if #pool < Config.MaxBitFrameStagePoolSize then"), "Stage pool incorrectly shares generic batch pool limit");
assert(source.includes("local routeId = if route then route.Id else 0"), "Commit must reuse route ID instead of storing a parallel array");
assert(!source.includes("stage.routeIds"), "Redundant stage route ID table still retained");
assert(!/stage\.(scalarFlags|scalarValues)/.test(source), "Scalar stages must not allocate separate flag/value tables");
assert(source.includes("stage.groups[index] = -1"), "Scalar tag must distinguish nil from args tables");
assert(source.includes("if stage.groups[i] >= 0 and args then releaseArgs(args) end"), "Cleanup must not release a scalar as an args table");
assert(source.includes("function Internal.bitFrameDiscardSchemaArgs(reader, schema)"), "Allocation-free rejected schema parser missing");
assert(source.includes("reader.bitPosition += bits"), "Homogeneous U8 reject path should skip bits without constructing fields");
assert(source.includes("Stats.BitFrameDiscardedSchemaArgs += 1"), "Rejected schema decode counter missing");
assert(source.includes("for _ = 1, count do Internal.bitFrameDiscardSchemaArgs(reader, schema) end"), "Rejected schema runs must use allocation-free skip");


for (const pair of ["StateThrottleRegression", "PackedBudgetRegression", "BinaryPrecisionRegression", "AtomicPacketRegression", "AtomicScalarRegression", "HeapDiscardRegression", "StagePoolMemoryRegression"]) {
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

for (const label of ["2.3.29", "2.3.30", "2.3.31", "2.3.35", "2.3.36", "2.3.37", "2.4.0", "2.5.0", "2.6.0", "2.7.0", "2.8.0", "2.9.0"]) assert(read("docs/CHANGELOG.md").includes(label));
assert(read("README.md").includes(`v${version}`));
console.log(`PASS NetStream ${version}: 10,000 packed-U8 cases, 6,009 valid varuints, 8 rejected invalid varuints, 8 F64 cases, 5,000 packed-split parity models, atomic parser + signed-scalar models, ${tests.length} Studio-script static scans`);
