--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.1")
local Compression = NetStream.Compression
assert(Compression.Version() == "2.4.2" and Compression.CodecVersion == 230)

local scalars = {false, true, 0, 1, -1, 127, 128, 16384, 32767, 4503599627370495, "small", string.rep("A", 4096)}
for _, value in ipairs(scalars) do
	local withDefault = Compression.CompressTablePacket(value)
	local withoutDictionary = Compression.CompressTablePacket(value, {StringDictionary = false})
	assert(buffer.tostring(withDefault) == buffer.tostring(withoutDictionary), "Scalar dictionary skip changed codec bytes")
	assert(Compression.DecompressTable(withDefault) == value, "Scalar codec roundtrip failed")
end
local mixed = {[false] = "disabled", [true] = false, [0] = "zero", Enabled = true}
local packet = Compression.CompressTablePacket(mixed)
local decoded = Compression.DecompressTable(packet)
assert(decoded[false] == "disabled" and decoded[true] == false and decoded[0] == "zero" and decoded.Enabled == true, "Mixed-key map decoded incorrectly")
local keyed = {Items = {{N = 1}, {N = 2}}, Cache = {A = "same", B = "same", C = "same"}}
for _ = 1, 1000 do
	local encoded = Compression.CompressTablePacket(keyed)
	local restored = Compression.DecompressTable(encoded)
	assert(restored.Items[2].N == 2 and restored.Cache.C == "same", "Nested map roundtrip failed")
end
local function wire(bytes: {number}): buffer
	local result = buffer.create(11 + #bytes)
	buffer.writeu32(result, 0, Compression.Magic)
	buffer.writeu16(result, 4, Compression.CodecVersion)
	buffer.writeu8(result, 6, 0)
	local a = 1
	local b = 0
	for i, v in ipairs(bytes) do
		buffer.writeu8(result, i + 10, v)
		a = (a + v) % 65521
		b = (b + a) % 65521
	end
	buffer.writeu32(result, 7, b * 65536 + a)
	return result
end
local okDuplicate, errDuplicate = pcall(Compression.DecompressTable, wire({0, 8, 2, 5, 1, 65, 1, 5, 1, 65, 2}))
assert(not okDuplicate and string.find(tostring(errDuplicate), "DUPLICATE_MAP_KEY", 1, true) ~= nil, "Duplicate map key with false prior value was accepted")
local okNil, errNil = pcall(Compression.DecompressTable, wire({0, 8, 1, 5, 1, 65, 0}))
assert(not okNil and string.find(tostring(errNil), "NIL_MAP_VALUE", 1, true) ~= nil, "Nil map value accepted")
print("NetStream v4.3.1 Compression v2.4.2 regression PASS", "scalar_cases", #scalars, "map_trials", 1000)
