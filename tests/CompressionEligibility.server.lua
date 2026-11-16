--!strict
-- Standalone Script in ServerScriptService; pair with CompressionEligibility.client.lua.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "2.3.34")
NetStream.Configure({CompressionEnabled = true, CompressionMinStringBytes = 6})
local Payload = NetStream.Event("__NSEligibility", {Id = 35311})
local Ack = NetStream.Event("__NSEligibilityAck", {Id = 35312, Compression = false})
local counts = {}
Payload:Connect(function(player, seq, a, b)
    local n = (counts[player] or 0) + 1
    counts[player] = n
    assert(seq == n, "Compression eligibility regression lost FIFO")
    if n <= 64 then
        assert(a == "unique" .. n and b == n, "Unique string payload corrupted")
    else
        assert(a == string.rep("match", 8) and b == a, "Repeated string payload corrupted")
    end
    if n == 96 then assert(Ack:FireClient(player, n), "Failed to acknowledge compression test") end
end)
Players.PlayerRemoving:Connect(function(player) counts[player] = nil end)
print("NetStream v2.3.34 compression eligibility server ready")
