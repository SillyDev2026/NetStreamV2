--!strict
-- Pair with ServerSecurityRegression.server.lua in a separate Roblox Studio Play session.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.1")
NetStream.Configure({HandshakeEnabled = false})
local T = NetStream.Types
local Request = NetStream.Event("__SecurityRequest431", {Id = 36611, Schema = {T.U16}, Compression = false})
local Result = NetStream.Event("__SecurityResult431", {Id = 36612, Schema = {T.U16}, Compression = false})
local Verify = NetStream.Function("__SecurityRPC431", {Id = 36613, Schema = {T.U16}, Compression = false})
local accepted = 0
Result:Connect(function(value)
    accepted += 1
    assert(value == 7, "Unauthorized event response")
end)
task.spawn(function()
    assert(Request:FireServer(8), "Could not send denied event")
    assert(Request:FireServer(7), "Could not send allowed event")
    local ok = pcall(function() Verify:InvokeServer(8) end)
    assert(not ok, "Denied RPC was accepted")
    assert(Verify:InvokeServer(9) == 90, "Allowed RPC failed")
    task.wait(2)
    assert(accepted == 1, "Unexpected authorized event count")
    print("NetStream security CLIENT PASS")
end)
