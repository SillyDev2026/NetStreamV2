--!strict
-- Standalone handshake replay regression for ServerScriptService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.2.0", "Expected NetStream 4.2.0")
NetStream.Configure({HandshakeEnabled = true, HandshakeRequireReady = false})
NetStream.Start()
local tested = {}
Players.PlayerAdded:Connect(function(player)
	task.delay(12, function()
		if player.Parent ~= Players then return end
		local status = NetStream.GetHandshakeStatus(player)
		local stats = NetStream.GetStats()
		assert(status.Ready, "Handshake did not recover after replay test")
		assert(stats.HandshakeReplayRejected > 0, "Stale nonce replay was not rejected")
		tested[player] = true
		print("NetStream replay regression PASS: old nonce rejected, recovered READY state")
	end)
end)
print("NetStream handshake replay server ready; start a fresh Play Test client")
