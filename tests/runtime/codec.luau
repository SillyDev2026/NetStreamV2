local NetStream = loadNetStream()
local function equal(a, b)
    assert(typeof(a) == typeof(b), "Type mismatch")
    if type(a) == "table" then
        for k, v in a do equal(v, b[k]) end
        for k, v in b do equal(a[k], v) end
    elseif typeof(a) == "buffer" then assert(buffer.tostring(a) == buffer.tostring(b))
    else assert(a == b, "Value mismatch") end
end
for i = 1, 1000 do
    local args = table.pack(i, -i, i / 8, false, nil, "repeated:" .. (i % 7), {x = i, flag = false}, buffer.fromstring("\0\255"), nil)
    local data = NetStream.Codec.Encode(table.unpack(args, 1, args.n))
    local result = table.pack(NetStream.Codec.Decode(data))
    equal(args, result)
end
local sample = NetStream.Codec.Encode(123, "payload", false, nil)
for length = 0, buffer.len(sample) - 1 do
    local truncated = buffer.create(length)
    buffer.copy(truncated, 0, sample, 0, length)
    assert(not pcall(NetStream.Codec.Decode, truncated), "Truncation accepted")
end
local trailing = buffer.create(buffer.len(sample) + 1)
buffer.copy(trailing, 0, sample)
assert(not pcall(NetStream.Codec.Decode, trailing), "Trailing byte accepted")
for i = 1, 500 do
    local value = {count = i, enabled = false, entries = {"repeated string", "repeated string", i, -i, i / 4}}
    local packet = Compression.CompressTablePacket(value)
    equal(value, Compression.DecompressTable(packet))
    buffer.writeu8(packet, buffer.len(packet) - 1, bit32.bxor(buffer.readu8(packet, buffer.len(packet) - 1), 1))
    assert(not pcall(Compression.DecompressTable, packet), "Corruption accepted")
end
print("PASS codec: 1000 tuple round-trips, truncation/trailing bytes, 500 compression corruption cases")
local repeated = table.create(200, string.rep("repeated payload", 5))
local payload = Compression.CompressTablePacket(table.pack(repeated, nil, false))
local compressed = buffer.create(buffer.len(payload) + 1)
buffer.writeu8(compressed, 0, 1)
buffer.copy(compressed, 1, payload)
equal(table.pack(repeated, nil, false), table.pack(NetStream.Codec.Decode(compressed)))
local edges = table.pack(0, -0, 9007199254740991, -9007199254740991, 4294967295, 2147483648, 0.125, "", nil)
equal(edges, table.pack(NetStream.Codec.Decode(NetStream.Codec.Encode(table.unpack(edges, 1, edges.n)))))
assert(not pcall(NetStream.Codec.Encode, math.huge))
assert(not pcall(NetStream.Codec.Encode, 0/0))
print("PASS codec: compressed envelope, safe-integer boundaries, nonfinite rejection")
