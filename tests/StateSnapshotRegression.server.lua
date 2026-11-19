--!strict
-- Run as ServerScript in a separate paired Studio Play session.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
local T = NetStream.Types
assert(NetStream.GetVersion() == "4.3.1")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false})
local Flag = NetStream.State("__NSStateBoolFix", {Id = 36901, Schema = {T.Bool}, Compression = false})
local Ack = NetStream.Event("__NSStateBoolFixAck", {Id = 36902, Schema = {T.Bool}, Compression = false})
local seen = 0
Flag:Connect(function(player, value)
    seen += 1
    assert(value == false, "Expected a false State packet")
    assert(Flag:Get(player) == false, "StateRoute:Get collapsed false into nil")
    local cache = NetStream.GetState(player)
    cache[36903] = {Nested = {Amount = 11}, Payload = buffer.fromstring("ok")}
    local snapshot = NetStream.GetStateSnapshot(player)
    snapshot[36903].Nested.Amount = 99
    buffer.writeu8(snapshot[36903].Payload, 0, 120)
    assert(cache[36903].Nested.Amount == 11, "Snapshot table mutation leaked into server cache")
    assert(buffer.readu8(cache[36903].Payload, 0) == 111, "Snapshot buffer mutation leaked into server cache")
    Ack:FireClient(player, true)
end)
task.delay(15, function() assert(seen == 1, "Expected one incoming false State packet") end)
