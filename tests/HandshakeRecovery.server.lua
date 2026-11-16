--!strict
-- Standalone ServerScriptService Script; pair with HandshakeRecovery.client.lua.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "2.3.34")
NetStream.Configure({HandshakeEnabled = true, HandshakeRequireReady = false})
NetStream.Start()
print("NetStream v2.3.34 duplicate HELLO handshake recovery server ready")
