--!strict
-- Standalone ServerScriptService Script; pair with HandshakeRecovery.client.lua.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "2.9.0")
NetStream.Configure({HandshakeEnabled = true, HandshakeRequireReady = false})
NetStream.Start()
print("NetStream v2.9.0 duplicate HELLO handshake recovery server ready")
