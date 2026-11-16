--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "2.3.31")
NetStream.Configure({BitFrameMaxBytes = 1024, BandwidthGovernorEnabled = false, CompressionEnabled = false, TransportFastFlushEnabled = false, HandshakeEnabled = false})
local oversized = NetStream.Event("__NSOversizedFrame", {Id = 35220, Compression = false})
local valid = NetStream.Event("__NSFrameRecovery", {Id = 35221, Compression = false})
local ack = NetStream.Event("__NSFrameAck", {Id = 35222, Compression = false})
local folder = ReplicatedStorage:WaitForChild("__NetStream_NetStream")
local remote = folder:WaitForChild("R")
assert(remote:IsA("RemoteEvent"), "Missing reliable remote")
local done = false
ack:Connect(function(tailRejected)
	local stats = NetStream.GetStats()
	assert(tailRejected >= 1, "Malformed BitFrame was not rejected")
	assert(stats.BitFrameEncodeFailures >= 1, "Oversized BitFrame did not fail")
	assert(stats.BitFrameWriterPoolHits > 0, "Writer failed to return to pool after encode error")
	done = true
	print("NetStream 2.3.31 BitFrame padding and writer recovery PASS")
end)
remote:FireServer(buffer.create(2)) -- Invalid: 15 zero bits follow the end-of-frame marker.
assert(oversized:FireServer(string.rep("X", 1500)), "Could not enqueue oversized test payload")
assert(valid:FireServer(123), "Could not enqueue subsequent valid payload")
task.delay(15, function() assert(done, "BitFrame hardening regression timed out") end)
