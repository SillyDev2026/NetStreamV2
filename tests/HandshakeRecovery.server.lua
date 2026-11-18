--!strict
-- Standalone ServerScriptService Script; pair with HandshakeRecovery.client.lua.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.2.3")
NetStream.Configure({HandshakeEnabled = true, HandshakeRequireReady = false})
NetStream.Start()
print("NetStream v4.2.3 duplicate HELLO handshake recovery server ready")
