--!strict
-- Roblox Studio: Script beside Netstream ModuleScript, which must contain
-- child Compression ModuleScript from this repository. No live remotes used.
local NetStream = require(script.Parent:WaitForChild("Netstream"))
local bits = NetStream.TransportCompression

local function checkNumber(value: number)
    local target = buffer.create(16)
    local nextBit = bits.WriteAdaptiveUIntBits(target, 0, value)
    local decoded, finalBit = bits.ReadAdaptiveUIntBits(target, 0)
    assert(decoded == value and finalBit == nextBit, "Adaptive varuint roundtrip failed")
end

checkNumber(0)
checkNumber(1)
checkNumber(127)
checkNumber(128)
checkNumber(16384)
checkNumber(9007199254740991)

local empty = buffer.create(0)
assert(not pcall(bits.ReadAdaptiveUIntBits, empty, 0), "Empty varuint accepted")

local truncated = buffer.create(1)
buffer.writeu8(truncated, 0, 128)
assert(not pcall(bits.ReadAdaptiveUIntBits, truncated, 0), "Truncated varuint accepted")

local overlong = buffer.create(2)
buffer.writeu8(overlong, 0, 0x80)
buffer.writeu8(overlong, 1, 0)
assert(not pcall(bits.ReadAdaptiveUIntBits, overlong, 0), "Overlong zero accepted")

local packet = NetStream.Codec.Encode(0, 127, 128, 16384)
local first, second, third, fourth = NetStream.Codec.Decode(packet)
assert(first == 0 and second == 127 and third == 128 and fourth == 16384,
    "Codec integer roundtrip changed")
print("NetStream v2.3.1 varuint regression PASS")
