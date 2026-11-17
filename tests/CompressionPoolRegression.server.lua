--!strict
-- ServerScriptService: verify the codec writer pool never aliases finished payload buffers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "3.2.0", "Wrong NetStream version")
local Compression = NetStream.Compression
assert(Compression.Version() == "2.3.5", "Wrong Compression version")
assert(Compression.CodecVersion == 230, "Codec wire version changed")
local outputs = table.create(120)
for i = 1, 120 do
	local payload = {Index = i, Label = string.rep("payload-" .. tostring(i), 24), Tags = {"A", "A", "B", "B"}, Enabled = i % 2 == 0}
	local encoded = Compression.CompressTablePacket(payload)
	assert(typeof(encoded) == "buffer", "Expected binary packet")
	outputs[i] = encoded
end
for i = 1, 120 do
	local decoded = Compression.DecompressTable(outputs[i])
	assert(decoded.Index == i, "Writer-pool aliasing corrupted an earlier packet")
	assert(decoded.Label == string.rep("payload-" .. tostring(i), 24), "Compressed string changed")
	assert(decoded.Tags[1] == "A" and decoded.Tags[4] == "B", "Dictionary roundtrip failed")
	assert(decoded.Enabled == (i % 2 == 0), "Boolean roundtrip failed")
end
print("NetStream Compression v2.3.5 pooled-writer 120-packet retention PASS")
