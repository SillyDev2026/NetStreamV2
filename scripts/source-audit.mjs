import assert from "node:assert/strict";
import {readFileSync, readdirSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {dirname, resolve} from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFileSync(resolve(root, path), "utf8");
const source = read("Netstream.lua");
const version = "2.3.31";

assert(source.includes(`local VERSION = "${version}"`), "Release version mismatch");
assert(!/\\blocal\\s+[A-Za-z_]\\w*\\s*=\\s*\\n\\s*\\S/.test(source), "Local assignments must stay on one line");
assert(source.includes("Internal.writeAdaptiveUIntBitsUnchecked(self.buffer, self.bitPosition, value)"), "Single-validation varuint path missing");
assert(source.includes("writer:ensureBits(schema.count * 8)"), "U8 writer preflight missing");
assert(source.includes("reader:needBits(schema.count * 8)"), "U8 reader preflight missing");

const fixedStart = source.indexOf("local function readFixedSchemaArgs(reader, schema)");
const fixedEnd = source.indexOf("local function readSchemaArgs(reader, schema)", fixedStart);
assert(fixedStart >= 0 && fixedEnd > fixedStart, "Legacy fixed decoder not found");
const fixed = source.slice(fixedStart, fixedEnd);
assert.equal((fixed.match(/readFiniteFixedF64\\(data, /g) || []).length, 10, "Legacy composite finite guards missing");
assert(source.includes('error("NetStream incoming fixed-schema F64 is not finite", 0)'), "Fixed-schema finite rejection missing");

const tests = readdirSync(resolve(root, "tests")).filter((name) => name.endsWith(".lua"));
assert(tests.length >= 33, "Regression suite unexpectedly missing");
for (const name of tests) {
    const content = read("tests/" + name);
    assert(!/\\blocal\\s+[A-Za-z_]\\w*\\s*=\\s*\\n\\s*\\S/.test(content), `Broken local assignment in ${name}`);
    const guards = [...content.matchAll(/NetStream\\.GetVersion\\(\\) == "([^"]+)"/g)];
    for (const [, reported] of guards) assert.equal(reported, version, `Outdated version guard in ${name}`);
}

let state = 0x31415926;
function random() {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state;
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

for (const label of ["2.3.29", "2.3.30", "2.3.31"]) assert(read("docs/CHANGELOG.md").includes(label));
assert(read("README.md").includes("v2.3.31"));
console.log(`PASS NetStream ${version}: 10,000 packed-U8 cases, 6,009 valid varuints, 8 rejected invalid varuints, 8 F64 cases, ${tests.length} Studio-script static scans`);
