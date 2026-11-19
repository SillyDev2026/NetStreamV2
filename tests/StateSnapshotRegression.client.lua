--!strict
-- Run as LocalScript with the paired server test in a separate Studio Play session.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
local T = NetStream.Types
assert(NetStream.GetVersion() == "4.3.1")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false})
local Flag = NetStream.State("__NSStateBoolFix", {Id = 36901, Schema = {T.Bool}, Compression = false})
local Ack = NetStream.Event("__NSStateBoolFixAck", {Id = 36902, Schema = {T.Bool}, Compression = false})
local confirmed = false
Ack:Connect(function(ok)
    assert(ok == true)
    confirmed = true
    print("PASS STUDIO State: false getter and detached nested snapshots")
end)
assert(Flag:SetServer(false))
task.delay(15, function() assert(confirmed, "State regression acknowledgement timed out") end)
