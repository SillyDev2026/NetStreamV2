--!strict
-- Place this Script beside a Netstream ModuleScript containing a Compression child.
local Compression = require(script.Parent:WaitForChild("Netstream"):WaitForChild("Compression"))
assert(Compression.Version() == "2.3.3")
assert(Compression.CodecVersion == 230)

local source = {Coins = 10, Inventory = {"Sword", "Bow"}, Settings = {Music = true}}
local encoded, report = Compression.CompressTablePacket(source, {StringDictionary = true})
assert(typeof(encoded) == "buffer")
assert(report.EncodedBytes == buffer.len(encoded))

local restored = Compression.DecompressTable(encoded)
assert(restored.Coins == 10 and restored.Inventory[2] == "Bow")
assert(restored.Settings.Music == true)
local valid = pcall(Compression.DecompressTable, buffer.create(0))
assert(not valid, "Empty compressed payload accepted")
print("NetStream bundled Compression v2.3.3 regression PASS")
