--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.4.0", "Wrong NetStream version")
local Compression = NetStream.Compression
assert(Compression.Version() == "2.4.2", "Wrong bundled Compression version")
assert(Compression.CodecVersion == 230 and Compression.Magic == 0x4E433233, "Compression 230 wire format changed")

local samples = {0, 1, 63, 64, 127, 128, 16383, 16384, 65535, 4294967295, 4503599627370495, -1, -64, -127, -4503599627370495}
for _, value in ipairs(samples) do
	local wire = Compression.CompressTablePacket(value, {StringDictionary = false})
	assert(buffer.readu16(wire, 4) == 230, "Wrong codec header")
	assert(Compression.DecompressTable(wire) == value, "Integer varint roundtrip failed: " .. tostring(value))
end

local packets = table.create(300)
for i = 1, 300 do
	local value = {Seq = i, Text = string.rep("repeatable-" .. tostring(i % 6), 20), Values = {i, i + 1, i + 2}, Meta = {Enabled = i % 2 == 0}}
	packets[i] = Compression.CompressTablePacket(value)
end
for i = 1, #packets do
	local decoded = Compression.DecompressTable(packets[i])
	assert(decoded.Seq == i and decoded.Values[3] == i + 2 and decoded.Meta.Enabled == (i % 2 == 0), "Codec writer pooling corrupted retained wire payload")
end

local key = {}
local okKey, errKey = pcall(Compression.CompressTablePacket, {[key] = "invalid"}, {StringDictionary = false})
assert(not okKey and string.find(tostring(errKey), "UNSUPPORTED_MAP_KEY", 1, true) ~= nil, "Table keys should fail instead of silently changing identity")

local function malformedPacket(bytes: {number}): buffer
	local wire = buffer.create(11 + #bytes)
	buffer.writeu32(wire, 0, Compression.Magic)
	buffer.writeu16(wire, 4, Compression.CodecVersion)
	buffer.writeu8(wire, 6, 0)
	local a = 1
	local b = 0
	for i, value in ipairs(bytes) do
		buffer.writeu8(wire, 10 + i, value)
		a = (a + value) % 65521
		b = (b + a) % 65521
	end
	buffer.writeu32(wire, 7, b * 65536 + a)
	return wire
end

local okMap, errMap = pcall(Compression.DecompressTable, malformedPacket({0, 8, 1, 7, 0, 2}))
assert(not okMap and string.find(tostring(errMap), "UNSUPPORTED_MAP_KEY:table", 1, true) ~= nil, "Malformed table-key wire should fail")
local okCanonical, errCanonical = pcall(Compression.DecompressTable, malformedPacket({128, 0, 2}))
assert(not okCanonical and string.find(tostring(errCanonical), "NON_CANONICAL_VARUINT", 1, true) ~= nil, "Noncanonical dictionary-count varuint accepted")
local okTrunc, errTrunc = pcall(Compression.DecompressTable, malformedPacket({128}))
assert(not okTrunc and string.find(tostring(errTrunc), "COMPRESSION_TRUNCATED", 1, true) ~= nil, "Truncated dictionary-count varuint accepted")
local okHuge, errHuge = pcall(Compression.DecompressTable, malformedPacket({128, 128, 128, 128, 128, 128, 128, 128, 0}))
assert(not okHuge and string.find(tostring(errHuge), "VARUINT_TOO_LARGE", 1, true) ~= nil, "Oversized varuint accepted")

print("NetStream 4.4.0 / Compression 2.4.2 regression PASS", "integer_cases", #samples, "pooled_packets", #packets)
