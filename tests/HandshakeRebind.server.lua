--!strict
-- Isolated ServerScriptService test; pair with HandshakeRebind.client.lua.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "3.9.0")
NetStream.Configure({HandshakeEnabled = true, HandshakeRequireReady = true, HandshakeRetrySeconds = 0.25})
NetStream.Start()
local folder = ReplicatedStorage:WaitForChild("__NetStream_NetStream")
task.delay(3, function()
    local old = folder:FindFirstChild("H")
    assert(old and old:IsA("RemoteEvent"), "Control remote missing")
    old.Name = "HObsolete"
    local replacement = Instance.new("RemoteEvent")
    replacement.Name = "H"
    replacement.Parent = folder
    replacement.OnServerEvent:Connect(function(player, data)
        if typeof(data) ~= "buffer" or (buffer.len(data) ~= 9 and buffer.len(data) ~= 13) then return end
        local op = buffer.readu8(data, 0)
        local nonce = buffer.readu32(data, 5)
        if nonce == 0 or buffer.readu8(data, 1) ~= 1 or buffer.readu16(data, 2) ~= 230 or buffer.readu8(data, 4) ~= 1 then return end
        if op == 3 and (buffer.len(data) ~= 13 or buffer.readu32(data, 9) ~= 19127) then return end
        if op ~= 1 and op ~= 3 then return end
        local response = buffer.create(13)
        buffer.writeu8(response, 0, if op == 1 then 2 else 4)
        buffer.writeu8(response, 1, 1)
        buffer.writeu16(response, 2, 230)
        buffer.writeu8(response, 4, 1)
        buffer.writeu32(response, 5, nonce)
        buffer.writeu32(response, 9, 19127)
        replacement:FireClient(player, response)
    end)
    print("NetStream v3.9.0 replacement handshake control ready")
end)
