--!strict
-- Standalone StarterPlayerScripts LocalScript with BooleanQueueRegression.server.lua.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "2.3.37", "Expected NetStream v2.3.37")
NetStream.Configure({BandwidthGovernorEnabled = true, BandwidthLimitBytesPerSecond = 131072, BandwidthMaxPacketBytes = 500, BandwidthMaxPacketsPerSecond = 120, TransportBatchWindowSeconds = 0.2, TransportFastFlushEnabled = false, MaxBatchMessages = 128})
local T = NetStream.Types
local flag = NetStream.Event("__NSBooleanQueue", {Id = 35200, Compression = false, Schema = {T.Bool, T.Bool, T.Bool, T.Bool, T.Bool, T.Bool, T.Bool, T.Bool}})
local text = NetStream.Event("__NSTextQueue", {Id = 35201, Compression = false})
local schema32 = table.create(32)
for i = 1, 32 do schema32[i] = T.Bool end
local flag32 = NetStream.Event("__NSBoolean32", {Id = 35203, Compression = false, Schema = schema32})
local ack = NetStream.Event("__NSQueueAck", {Id = 35202, Compression = false})
local done = false
ack:Connect(function(serverReads)
	local stats = NetStream.GetStats()
	assert(stats.BooleanBitPackWrites >= 97 and serverReads >= 97, "Boolean fast path not used")
	assert(stats.TransportDeferredRestoreCalls > 0 and stats.TransportDeferredRestoredMessages > 0, "Deferred queue did not restore split batches")
	assert(stats.DecodeErrors == 0, "Client packet decode errors")
	done = true
	print(string.format("NetStream 2.3.37 regression PASS: %d boolean writes, %d reads, %d deferred restore calls, %d restored messages", stats.BooleanBitPackWrites, serverReads, stats.TransportDeferredRestoreCalls, stats.TransportDeferredRestoredMessages))
end)
for i = 1, 96 do
	local a = i % 2 == 1
	local b = math.floor(i / 2) % 2 == 1
	local c = math.floor(i / 4) % 2 == 1
	local d = math.floor(i / 8) % 2 == 1
	local e = math.floor(i / 16) % 2 == 1
	local f = math.floor(i / 32) % 2 == 1
	local g = math.floor(i / 64) % 2 == 1
	local h = math.floor(i / 128) % 2 == 1
	assert(flag:FireServer(a, b, c, d, e, f, g, h), "Could not enqueue flag")
end
for i = 1, 80 do assert(text:FireServer(i, string.rep("P", 90)), "Could not enqueue text") end
local bits32 = table.create(32, false)
bits32[1] = true
bits32[32] = true
assert(flag32:FireServer(table.unpack(bits32, 1, 32)), "Could not enqueue 32-bit Boolean boundary")
task.delay(45, function() assert(done, "Boolean/queue regression timed out") end)
