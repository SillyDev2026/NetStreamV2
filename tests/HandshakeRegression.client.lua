--!strict
-- Run this LocalScript alone in StarterPlayerScripts with the paired server regression.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "2.9.0", "Wrong NetStream version")
NetStream.Configure({HandshakeEnabled = true, HandshakeRequireReady = true, TransportFastFlushEnabled = true})
local probe = NetStream.Event("__NSHandshakeProbe", {Id = 34111, Priority = "Realtime", Compression = false})
local ack = NetStream.Event("__NSHandshakeReply", {Id = 34112, Priority = "Critical", Compression = false})
local finished = false
ack:Connect(function(sequence, status)
	assert(sequence == 42 and status == "ready", "Handshake acknowledgment invalid")
	assert(NetStream.IsHandshakeReady(), "Client handshake was not ready")
	local sample = NetStream.GetHandshakeStatus()
	assert(type(sample.RoundTripMs) == "number" and sample.RoundTripMs >= 0, "Missing handshake round-trip sample")
	assert(NetStream.GetStats().HandshakeReadyCount >= 1, "Missing handshake ready transition")
	finished = true
	print(string.format("NetStream handshake PASS: %.2f ms initial HELLO/WELCOME round trip, %d HELLO attempts, %d CONFIRM attempts", sample.RoundTripMs, sample.HelloAttempts, sample.ConfirmAttempts))
end)
-- Strict mode queues this event until the four-message handshake is complete.
assert(probe:FireServer(42, "handshake-ready"), "Unable to queue handshake test event")
task.delay(20, function() assert(finished, "Handshake regression timed out") end)
