--!strict
-- Run by itself in StarterPlayerScripts, paired with HandshakeRegression.server.lua.
local NetStream = require(game:GetService("ReplicatedStorage"):WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "2.3.13", "Handshake regression requires NetStream 2.3.13")
NetStream.Configure({HandshakeEnabled = true, HandshakePingIntervalSeconds = 2, TransportLatencyAwareBatching = true})
local challenge = NetStream.Event("__NSHandshakeRegression", {Id = 34101, Compression = false})
local response = NetStream.Event("__NSHandshakeResponse", {Id = 34102, Compression = false})
local responded = false
challenge:Connect(function(token)
	assert(type(token) == "string" and not responded, "Invalid or duplicated welcome")
	assert(NetStream.IsPeerReady(), "Received application traffic before handshake")
	responded = true
	assert(response:FireServer(token), "Handshake acknowledgment enqueue failed")
	print("NetStream handshake acknowledged:", NetStream.GetHandshakeStatus().Status)
end)
task.delay(10, function()
	assert(responded, "NetStream initial handshake/server welcome did not complete")
	local status = NetStream.GetHandshakeStatus()
	local stats = NetStream.GetPingStats()
	assert(status.Status == "ready", "Client handshake not ready")
	assert(stats.Available and stats.Samples >= 2, "Periodic RTT sample missing")
	assert(type(stats.SmoothedRTTMs) == "number" and stats.SmoothedRTTMs >= 0, "Invalid RTT")
	print(string.format("NetStream v2.3.13 application RTT %.1f ms, smoothed RTT %.1f ms, jitter %.1f ms, samples %d", stats.RTTMs, stats.SmoothedRTTMs, stats.JitterMs, stats.Samples))
end)
