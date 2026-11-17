--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.1.0")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, PackedSchemaRunEnabled = false, TransportFastFlushEnabled = false, TransportBatchWindowSeconds = 0, BandwidthGovernorEnabled = true, BandwidthLimitBytesPerSecond = 64000, BandwidthMaxPacketsPerSecond = 1, MaxBatchMessages = 64})
local T = NetStream.Types
local Event = NetStream.Event("__NSIsolatedRecovery", {Id = 37041, Schema = {T.U16}, Compression = false, Trusted = true})
local Ack = NetStream.Event("__NSIsolatedRecoveryAck", {Id = 37042, Schema = {T.U16}, Compression = false})
local finished = false
Ack:Connect(function(value)
	assert(value == 3 and not finished, "Recovery ACK incorrect/duplicate")
	local stats = NetStream.GetStats()
	assert(stats.RejectedMessages >= 1, "Expected malformed trusted payload to be rejected during isolated recovery")
	assert(stats.TransportDeferredRestoredMessages >= 1, "Expected deferred reliable messages to be restored")
	assert(stats.DecodeErrors == 0, "Recovery produced malformed inbound packets")
	finished = true
	print("NetStream 4.1.0 isolated defer recovery CLIENT PASS", "deferred", stats.TransportDeferredRestoredMessages, "rejected", stats.RejectedMessages)
end)
task.wait(2)
assert(Event:FireServer(1), "First valid recovery payload rejected")
assert(Event:FireServer(2), "Second valid recovery payload rejected")
assert(Event:FireServer("INVALID_TRUSTED_PAYLOAD" :: any), "Trusted malformed payload unexpectedly rejected before encoder recovery")
assert(Event:FireServer(3), "Third valid recovery payload rejected")
for _ = 1, 240 do
	if finished then break end
	NetStream.Flush()
	task.wait(0.125)
end
assert(finished, "Isolated recovery timed out; deferred reliable messages may have been lost")
