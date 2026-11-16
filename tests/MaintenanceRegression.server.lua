--!strict
-- Roblox Studio regression: place this Script beside Netstream (with Compression child).
local NetStream = require(script.Parent:WaitForChild("Netstream"))
local Compression = require(script.Parent:WaitForChild("Netstream"):WaitForChild("Compression"))

assert(NetStream.GetVersion() == "2.3.34", "Expected patched NetStream v2.3.34")
assert(Compression.Version() == "2.3.5", "Expected patched Compression v2.3.5")

local previousLimit = NetStream.GetConfig().MaxIncomingPacketBytes
local acceptedFraction = pcall(NetStream.Configure, {MaxIncomingPacketBytes = 1024.5})
assert(not acceptedFraction, "Fractional packet byte limit was accepted")
assert(NetStream.GetConfig().MaxIncomingPacketBytes == previousLimit, "Rejected configuration was partially applied")

NetStream.Configure({MaxIncomingPacketBytes = 1024})
local oversized = buffer.create(1025)
local acceptedOversized, decodeError = pcall(NetStream.Codec.Decode, oversized)
assert(not acceptedOversized, "Oversized public Codec input was accepted")
assert(string.find(tostring(decodeError), "MaxIncomingPacketBytes", 1, true) ~= nil, "Incorrect oversized input error")

local encoded = NetStream.Codec.Encode(42, "hello", true)
local numberValue, stringValue, booleanValue = NetStream.Codec.Decode(encoded)
assert(numberValue == 42 and stringValue == "hello" and booleanValue == true, "Native Codec roundtrip regressed")

local entries = table.create(64)
local textA = "Repeated-Compression-Test-String-AAAA-123456789"
local textB = "Repeated-Compression-Test-String-BBBB-123456789"
for i = 1, 64 do entries[i] = if i % 2 == 0 then textA else textB end
local dictionaryPacket = Compression.CompressTablePacket(entries, {StringDictionary = true})
assert(buffer.readu8(dictionaryPacket, 6) == 1, "Regression fixture did not generate a dictionary")
assert(buffer.readu8(dictionaryPacket, 11) >= 2, "Regression fixture requires two dictionary entries")
local roundtrip = Compression.DecompressTable(dictionaryPacket)
assert(roundtrip[1] == textB and roundtrip[64] == textA, "Dictionary packet roundtrip regressed")

local acceptsTooManyEntries, dictionaryError = pcall(Compression.DecompressTable, dictionaryPacket, {DictionaryMaxEntries = 1})
assert(not acceptsTooManyEntries, "DictionaryMaxEntries bypassed by decoder")
assert(string.find(tostring(dictionaryError), "MAX_DICTIONARY_ENTRIES_EXCEEDED", 1, true) ~= nil, "Incorrect dictionary-limit error")

local withoutDictionary = Compression.CompressTablePacket({1, 2, 3}, {StringDictionary = false})
assert(buffer.readu8(withoutDictionary, 6) == 0, "Expected dictionary-free fixture")
buffer.writeu8(withoutDictionary, 6, 1)
local acceptedEmptyDictionary = pcall(Compression.DecompressTable, withoutDictionary)
assert(not acceptedEmptyDictionary, "Empty dictionary with dictionary flag accepted")

print("NetStream v2.3.2 -> v2.3.34 maintenance regression PASS")
