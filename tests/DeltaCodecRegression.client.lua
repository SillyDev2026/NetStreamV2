--!strict
-- Pair with DeltaCodecRegression.server.lua in a separate Roblox Studio Play session.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.1")
NetStream.Configure({HandshakeEnabled = false})
local T = NetStream.Types
local Codec = NetStream.CreateDeltaCodec({"Coins", "Wins", "Title", "Ready"})
local Frame = NetStream.Event("__DeltaFrame423", {Id = 36500, Compression = false})
local Start = NetStream.Event("__DeltaStart423", {Id = 36501, Schema = {T.Bool}, Compression = false})
local Ack = NetStream.Event("__DeltaAck423", {Id = 36502, Schema = {T.U8}, Compression = false})
local current = nil
local revision = nil
local received = 0
Frame:Connect(function(packet)
    received += 1
    local applied, nextRevision, reason = Codec:Apply(current, revision, packet)
    assert(applied, "Delta frame failed to apply: " .. tostring(reason))
    current = applied
    revision = nextRevision
    if received == 1 then
        assert(revision == 1 and current.Coins == 10 and current.Title == "Rookie" and current.Ready == false, "Full snapshot corrupted")
    elseif received == 2 then
        assert(revision == 2 and current.Coins == 12 and current.Wins == 1 and current.Title == nil and current.Ready == true, "Delta changes corrupted")
        assert(Ack:FireServer(received), "Could not acknowledge delta state")
        print("NetStream v4.3.1 delta codec CLIENT PASS")
    else
        error("Unexpected extra delta frame")
    end
end)
assert(Start:FireServer(true), "Could not start delta regression")
task.delay(25, function() assert(received == 2, "Delta regression timed out") end)
