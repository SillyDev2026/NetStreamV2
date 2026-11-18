--!strict
-- Studio setup: ReplicatedStorage.Netstream (with Compression child); this LocalScript in StarterPlayerScripts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.0")
local event = NetStream.Event("__NetStreamPerfProbe", {Compression = false})
local ack = NetStream.Event("__NetStreamPerfAck", {Compression = false})
local total = 300
local started = os.clock()
local finished = false

local function makePayload(index: number): string
	local remainder = index % 4
	local length = if remainder == 0 then 260 elseif remainder == 1 then 17 elseif remainder == 2 then 80 else 31
	return string.rep(string.char(65 + index % 26), length)
end

ack:Connect(function(received, serverBatches, serverDecodeErrors)
	if finished then return end
	finished = true
	assert(received == total, "Perf probe lost messages")
	assert(serverDecodeErrors == 0, "Server recorded malformed NetStream packets")
	local stats = NetStream.GetStats()
	assert(stats.DecodeErrors == 0 and stats.BitFramePacketsSent > 0, "Client BitFrame decode/send failed")
	print(string.format("NetStream %s: %d messages in %.3fs, %d client packets, %d server batches, %d bytes, %d writer-pool hits, %d predicted caps, %d split retries", NetStream.GetVersion(), received, os.clock() - started, stats.SentBatches, serverBatches, stats.SentBytes, stats.BitFrameWriterPoolHits, stats.TransportPredictedBatchCaps, stats.BandwidthBatchSplits))
end)

task.wait(1)
NetStream.ResetStats()
started = os.clock()
for i = 1, total do
	assert(event:FireServer(i, makePayload(i)), "Perf probe outgoing queue rejected event")
end
task.delay(30, function()
	if not finished then warn("NetStream perf probe did not receive the full acknowledgment within 30 seconds") end
end)
