--!strict
-- Pair with DeltaCodecRegression.client.lua in a separate Roblox Studio Play session.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.2.3")
NetStream.Configure({HandshakeEnabled = false})
local T = NetStream.Types
local Codec = NetStream.CreateDeltaCodec({"Coins", "Wins", "Title", "Ready"})
local Frame = NetStream.Event("__DeltaFrame423", {Id = 36500, Compression = false})
local Start = NetStream.Event("__DeltaStart423", {Id = 36501, Schema = {T.Bool}, Compression = false})
local Ack = NetStream.Event("__DeltaAck423", {Id = 36502, Schema = {T.U8}, Compression = false})
local started = {}
local initial = {Coins = 10, Wins = 1, Title = "Rookie", Ready = false}
local changed = {Coins = 12, Wins = 1, Ready = true}
local full = Codec:Full(initial, 1)
local diff = Codec:Diff(initial, changed, 1)
assert(diff and diff.Mask == 13 and diff.NilMask == 4, "Delta changed-field mask incorrect")
assert(Codec:Diff(initial, initial, 1) == nil, "Unchanged state produced a delta")
local restored, revision = Codec:Apply(nil, nil, full)
assert(restored and restored.Title == "Rookie" and revision == 1, "Full snapshot round-trip failed")
local nextState, nextRevision = Codec:Apply(restored, revision, diff)
assert(nextState and nextState.Coins == 12 and nextState.Title == nil and nextState.Ready == true and nextRevision == 2, "Delta application lost a field")
local stale, _, reason = Codec:Apply(restored, 5, diff)
assert(stale == nil and type(reason) == "string", "Wrong base revision accepted")
assert(restored.Coins == 10 and restored.Title == "Rookie", "Rejected delta mutated its original state")
local malformed = table.clone(diff)
malformed.Mask = 4294967295
assert(Codec:Apply(restored, 1, malformed) == nil, "Extra delta bits were accepted")
Start:Connect(function(player, ready)
    assert(ready == true, "Delta client not ready")
    assert(not started[player], "Delta start duplicated")
    started[player] = true
    assert(Frame:FireClient(player, full), "Full snapshot send failed")
    assert(Frame:FireClient(player, diff), "Delta send failed")
end)
Ack:Connect(function(player, received)
    assert(started[player] and received == 2, "Delta result ACK invalid")
    print("NetStream v4.2.3 delta codec SERVER PASS", player.UserId)
end)
print("NetStream v4.2.3 delta codec server ready")
