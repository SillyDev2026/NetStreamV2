--!strict
-- Pair with InterestGroupRegression.server.lua in a separate Roblox Studio Play session.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.1")
NetStream.Configure({HandshakeEnabled = false})
local T = NetStream.Types
local Event = NetStream.Event("__InterestEvent423", {Id = 36510, Schema = {T.U8}, Compression = false})
local State = NetStream.State("__InterestState423", {Id = 36511, Schema = {T.U16}, Compression = false})
local Ready = NetStream.Event("__InterestReady423", {Id = 36512, Schema = {T.Bool}, Compression = false})
local Ack = NetStream.Event("__InterestAck423", {Id = 36513, Schema = {T.U8}, Compression = false})
local received = 0
local stateSeen = false
local done = false
local function finish()
    if done or received ~= 2 or not stateSeen then return end
    done = true
    assert(Ack:FireServer(received), "Interest ACK failed")
    print("NetStream v4.3.1 interest CLIENT PASS")
end
Event:Connect(function(value)
    received += 1
    assert(received <= 2, "Unexpected event leaked to excluded player")
    assert(value == (if received == 1 then 11 else 33), "Interest routing delivered wrong event")
    finish()
end)
State:Connect(function(value)
    assert(value == 300 and not stateSeen, "Interest state wrong or duplicated")
    stateSeen = true
    finish()
end)
assert(Ready:FireServer(true), "Interest ready send failed")
task.delay(25, function() assert(done, "Interest regression timed out") end)
