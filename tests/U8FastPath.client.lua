--!strict
-- Standalone StarterPlayerScripts LocalScript; pair with U8FastPath.server.lua.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "3.5.0")
local T = NetStream.Types
local schema32 = table.create(32)
local schema4 = table.create(4)
for i = 1, 32 do schema32[i] = T.U8 end
for i = 1, 4 do schema4[i] = T.U8 end
local Wide = NetStream.Event("__NSU8Wide", {Id = 35301, Compression = false, Schema = schema32})
local Short = NetStream.Event("__NSU8Short", {Id = 35302, Compression = false, Schema = schema4})
local Ack = NetStream.Event("__NSU8Ack", {Id = 35303, Compression = false})
local done = false
Ack:Connect(function(wide, short, reads)
    assert(wide == 16 and short == 96 and reads >= 112, "U8 server samples missing")
    local stats = NetStream.GetStats()
    assert(stats.U8SchemaFastWrites >= 112, "U8 fast encoder did not run")
    assert(stats.DecodeErrors == 0, "ACK decode failed")
    done = true
    print("NetStream v3.5.0 U8 schema fast path PASS", stats.U8SchemaFastWrites, reads)
end)
local values = table.create(32)
for i = 2, 31 do values[i] = (i * 7) % 256 end
values[32] = 255
for i = 1, 16 do
    values[1] = i
    assert(Wide:FireServer(table.unpack(values, 1, 32)), "U8 wide enqueue failed")
end
for i = 1, 96 do assert(Short:FireServer(i, 0, 128, 255), "U8 short enqueue failed") end
task.delay(40, function() assert(done, "U8 regression timed out") end)
