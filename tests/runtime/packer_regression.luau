--!optimize 2
-- The public Codec API must reuse bounded readers/writers without aliasing outputs.
local net = loadNetStream()
local hooks = net.__test
local seed = buffer.fromstring("payload")
local first = net.Codec.Encode(13, false, "alpha")
local firstBytes = buffer.tostring(first)
local large = net.Codec.Encode(99999, -37, {Count = 4, Active = false, Tags = {"repeat", "repeat"}}, seed)
local largeBytes = buffer.tostring(large)
for i = 1, 2500 do
    local packet = net.Codec.Encode(13, false, "alpha")
    local a, b, c = net.Codec.Decode(packet)
    assert(a == 13 and b == false and c == "alpha", "Codec pool leaked data from previous packet")
    assert(buffer.tostring(first) == firstBytes, "Pool reuse mutated previously returned byte buffer")
    if i % 10 == 0 then
        local x = net.Codec.Encode(99999, -37, {Count = 4, Active = false, Tags = {"repeat", "repeat"}}, seed)
        local id, amount, payload, extra = net.Codec.Decode(x)
        assert(id == 99999 and amount == -37 and payload.Count == 4 and payload.Active == false and buffer.tostring(extra) == "payload")
        assert(buffer.tostring(large) == largeBytes, "Pooled writer corrupted earlier complex packet")
    end
end
local function hex(data)
    local chars = table.create(buffer.len(data))
    for index = 0, buffer.len(data) - 1 do chars[index + 1] = string.format("%02x", buffer.readu8(data, index)) end
    return table.concat(chars)
end
assert(hex(net.Codec.Encode(7, false, "abc")) == "0003271063616263", "Codec changed the baseline wire bytes")
local stats = net.GetStats()
assert(stats.CodecTinyFastEncodes >= 2500 and stats.CodecTinyFastDecodes >= 2500, "Tiny primitives did not use the direct native codec")
assert(stats.WriterPoolHits >= 200, "Complex Codec encode still allocates a writer per packet")
assert(stats.ArgsPoolHits >= 2700, "Codec encode still allocates argument tables per packet")
assert(stats.ReaderPoolHits >= 200, "Complex Codec decode still allocates a reader per packet")
assert(stats.WriterPoolSize >= 1 and stats.ReaderPoolSize >= 1, "Pooled resources were not retained")
print("PASS PACKER: 2500 tiny direct tuples and 250 pooled complex tuples preserved independent buffers")

local bad = buffer.create(buffer.len(first) - 1)
buffer.copy(bad, 0, first, 0, buffer.len(bad))
local readerHits = net.GetStats().ReaderPoolHits
for _ = 1, 500 do
    local success, values, err = net.Codec.TryDecode(bad)
    assert(not success and values == nil and type(err) == "string", "Truncated packet was accepted")
end
assert(net.GetStats().ReaderPoolHits >= readerHits + 500, "Failed decodes leaked the reader pool")
local a, b, c = net.Codec.Decode(first)
assert(a == 13 and b == false and c == "alpha", "A failed decode corrupted the next valid packet")
assert(not net.Codec.TryEncode(math.huge), "Codec accepted infinity")
assert(net.Codec.TryEncode(1), "Codec did not recover after invalid input")
print("PASS PACKER: malformed decode recycles reader and never poisons later messages")

local writer = hooks.makeRawWriter(1024, 1024)
writer.position = 1023
writer:varUInt(1)
assert(writer.position == 1024 and buffer.readu8(writer.buffer, 1023) == 1, "One-byte varuint failed at capacity boundary")
writer = hooks.makeRawWriter(1024, 1024)
writer.position = 1022
writer:varUInt(128)
assert(writer.position == 1024 and buffer.readu8(writer.buffer, 1022) == 128 and buffer.readu8(writer.buffer, 1023) == 1, "Two-byte varuint failed at limit")
writer = hooks.makeRawWriter(1024, 1024)
writer.position = 1023
assert(not pcall(function() writer:varUInt(128) end), "Oversized varuint crossed strict max-byte bound")
print("PASS PACKER: exact varuint reservation preserves bytes and enforces output limits")

local fixture = {
    table.pack(),
    table.pack(nil),
    table.pack(true, false, nil, 0),
    table.pack(-7, -1, 14, ""),
    table.pack("xy", "xy", false),
    table.pack(0, 1, -7, "four"),
    table.pack(15, false, "fallback"),
    table.pack("012345678901234", false),
}
for _, args in fixture do
    local encoded = net.Codec.Encode(table.unpack(args, 1, args.n))
    local decoded = table.pack(net.Codec.Decode(encoded))
    assert(decoded.n == args.n, "Tiny/fallback argument count changed")
    for i = 1, args.n do assert(decoded[i] == args[i], "Tiny/fallback primitive value changed at field " .. i) end
    local ok, errorMessage = net.Codec.TryDecode(encoded)
    assert(ok and errorMessage.n == args.n, "Tiny/fallback TryDecode failed")
end
assert(net.GetStats().CodecTinyFastEncodes > 2500, "No canonical tiny outputs produced")
print("PASS PACKER: empty args, nil, signs, bools, duplicate strings and threshold fallbacks")
