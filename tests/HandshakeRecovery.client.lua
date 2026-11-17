--!strict
-- Standalone StarterPlayerScripts LocalScript; pair with HandshakeRecovery.server.lua.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.0.0")
NetStream.Configure({HandshakeEnabled = true, HandshakeRequireReady = false})
NetStream.Start()
local folder = ReplicatedStorage:WaitForChild("__NetStream_NetStream")
local remote = folder:WaitForChild("H")
assert(remote:IsA("RemoteEvent"), "Handshake control remote missing")
local clientNonce = 811023
local serverNonce = nil
local stage = 0
local done = false
local function send(op)
    local data = buffer.create(if op == 1 then 9 else 13)
    buffer.writeu8(data, 0, op)
    buffer.writeu8(data, 1, 1)
    buffer.writeu16(data, 2, 230)
    buffer.writeu8(data, 4, 1)
    buffer.writeu32(data, 5, clientNonce)
    if op == 3 then buffer.writeu32(data, 9, serverNonce) end
    remote:FireServer(data)
end
remote.OnClientEvent:Connect(function(data)
    if typeof(data) ~= "buffer" or buffer.len(data) ~= 13 or buffer.readu32(data, 5) ~= clientNonce then return end
    local op = buffer.readu8(data, 0)
    if stage == 1 and op == 2 then
        serverNonce = buffer.readu32(data, 9)
        assert(serverNonce ~= 0, "WELCOME nonce invalid")
        stage = 2
        send(3)
    elseif stage == 2 and op == 4 then
        assert(buffer.readu32(data, 9) == serverNonce, "READY server nonce mismatch")
        stage = 3
        task.delay(0.15, function() send(1) end)
    elseif stage == 3 and op == 2 then
        assert(buffer.readu32(data, 9) == serverNonce, "Recovered WELCOME nonce mismatch")
        stage = 4
        send(3)
    elseif stage == 4 and op == 4 then
        assert(buffer.readu32(data, 9) == serverNonce, "Recovery READY nonce mismatch")
        done = true
        print("NetStream v4.0.0 duplicate HELLO recovery PASS (WELCOME -> READY)")
    end
end)
task.delay(0.5, function() stage = 1; send(1) end)
task.delay(15, function() assert(done, "Handshake recovery probe timed out") end)
