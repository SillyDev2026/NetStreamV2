--!strict
-- Run by itself in StarterPlayerScripts, paired with CompressionBackoffRegression.server.lua.
local NetStream = require(game:GetService("ReplicatedStorage"):WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "2.3.13")
NetStream.Configure({CompressionAdaptiveBackoff = true, CompressionNoGainThreshold = 2, CompressionBackoffMessages = 3, CompressionMinSavingsBytes = 65536, HybridCompressionThresholdBits = 0, BandwidthGovernorEnabled = false})
local event = NetStream.Event("__NSCompressionBackoff", {Id = 34103})
for index = 1, 20 do
	assert(event:FireServer({index = index, payload = string.rep(string.char(65 + index % 20), 64)}), "Compression test enqueue failed")
end
task.delay(7, function()
	local stats = NetStream.GetStats()
	assert(stats.CompressionBackoffActivations > 0, "Expected adaptive no-gain cooldown")
	assert(stats.CompressionBackoffSkips > 0, "Expected skipped compression attempts")
	assert(stats.HandshakeReady > 0, "Expected completed handshake")
	print("NetStream compression cooldown PASS", stats.CompressionBackoffActivations, stats.CompressionBackoffSkips)
end)
