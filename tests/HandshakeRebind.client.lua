--!strict
-- Isolated StarterPlayerScripts test; pair with HandshakeRebind.server.lua.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.1.1")
NetStream.Configure({HandshakeEnabled = true, HandshakeRequireReady = true, HandshakeRetrySeconds = 0.25})
NetStream.Start()
local folder = ReplicatedStorage:WaitForChild("__NetStream_NetStream")
local first = folder:WaitForChild("H")
local done = false
folder.ChildAdded:Connect(function(child)
    if child.Name ~= "H" or child == first or not child:IsA("RemoteEvent") then return end
    task.spawn(function()
        NetStream.RetryHandshake()
        local count = NetStream.GetStats().HandshakeRemoteRebinds
        assert(count >= 1, "Remote listener was not rebound")
        for _ = 1, 100 do if NetStream.IsHandshakeReady() then break end; task.wait(0.1) end
        assert(NetStream.IsHandshakeReady(), "Replacement remote handshake failed")
        NetStream.RetryHandshake()
        assert(NetStream.GetStats().HandshakeRemoteRebinds == count, "Duplicate handshake listener created")
        for _ = 1, 100 do if NetStream.IsHandshakeReady() then break end; task.wait(0.1) end
        assert(NetStream.IsHandshakeReady(), "Retry on current H failed")
        done = true
        print("NetStream v4.1.1 rebind and retry PASS")
    end)
end)
task.delay(18, function() assert(done, "Handshake control rebind timed out") end)
