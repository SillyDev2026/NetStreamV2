--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.0")
local Compression = NetStream.Compression
assert(Compression.Version() == "2.4.2")
assert(Compression.CodecVersion == 230)
local function malformed(payload: {number}): buffer
	local result = buffer.create(11 + #payload)
	buffer.writeu32(result, 0, Compression.Magic)
	buffer.writeu16(result, 4, Compression.CodecVersion)
	buffer.writeu8(result, 6, 0)
	local a = 1
	local b = 0
	for i, byte in ipairs(payload) do
		buffer.writeu8(result, 10 + i, byte)
		a = (a + byte) % 65521
		b = (b + a) % 65521
	end
	buffer.writeu32(result, 7, b * 65536 + a)
	return result
end
for i = 1, 600 do
	local value = if i % 5 == 0 then false elseif i % 5 == 1 then i elseif i % 5 == 2 then "hello" elseif i % 5 == 3 then true else -i
	local bytes, report = Compression.CompressTablePacket(value, {StringDictionary = false})
	local roundtrip = Compression.DecompressTable(bytes, {StringDictionary = false})
	assert(roundtrip == value and report.EncodedBytes == buffer.len(bytes), "No-dictionary scalar roundtrip failed")
end
local tableInput = {Name = "audit", Stats = {Coins = 7, Lives = 2}, Tags = {"abcabc", "abcabc", "abcabc"}, Active = true}
local bytes = Compression.CompressTablePacket(tableInput)
local restored = Compression.DecompressTable(bytes)
assert(restored.Name == tableInput.Name and restored.Tags[3] == "abcabc" and restored.Stats.Coins == 7, "Dictionary and nested payload roundtrip failed")
local okKey, errKey = pcall(Compression.DecompressTable, malformed({0, 8, 1, 7}))
assert(not okKey and string.find(tostring(errKey), "UNSUPPORTED_MAP_KEY:table", 1, true) ~= nil, "Composite map key was not rejected before child allocation")
local okTag, errTag = pcall(Compression.DecompressTable, malformed({0, 8, 1, 240}))
assert(not okTag and string.find(tostring(errTag), "UNSUPPORTED_MAP_KEY_TAG:240", 1, true) ~= nil, "Invalid map-key tag was accepted")
print("Compression 2.4.2 hardened key/scalar regression PASS", "scalar_roundtrips", 600)
