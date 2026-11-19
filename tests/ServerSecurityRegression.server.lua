--!strict
-- Pair with ServerSecurityRegression.client.lua in a separate Roblox Studio Play session.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.1")
NetStream.Configure({HandshakeEnabled = false})
local T = NetStream.Types
local Request = NetStream.Event("__SecurityRequest431", {Id = 36611, Schema = {T.U16}, Compression = false, MaxPerSecond = 20, Burst = 20})
local Result = NetStream.Event("__SecurityResult431", {Id = 36612, Schema = {T.U16}, Compression = false})
local Verify = NetStream.Function("__SecurityRPC431", {Id = 36613, Schema = {T.U16}, Compression = false})
NetStream.SetServerPolicy(Request, {
    Validate = function(_, value) return type(value) == "number" and value >= 1 and value <= 10 end,
    Authorize = function(_, value) return value == 7 end,
})
NetStream.SetServerPolicy(Verify, {Authorize = function(_, value) return value == 9 end})
local accepted = 0
Request:Connect(function(player, value)
    accepted += 1
    assert(value == 7, "Unauthorized event reached server")
    Result:FireClient(player, value)
end)
Verify:SetCallback(function(_, value)
    assert(value == 9, "Unauthorized RPC reached server")
    return 90
end)
task.delay(20, function()
    assert(accepted == 1, "Security event admission count unexpected")
    local s = NetStream.GetStats()
    assert(s.SecurityPolicyRejects >= 2, "Security guard rejection counters missing")
    print("NetStream security SERVER PASS", s.SecurityPolicyChecks, s.SecurityPolicyRejects)
end)
