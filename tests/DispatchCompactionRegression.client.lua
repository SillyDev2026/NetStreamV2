--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.1.1")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, BandwidthGovernorEnabled = false, MaxDispatchPerCycle = 2, MaxDispatchBacklog = 64, TransportFastFlushEnabled = false, MaxBatchMessages = 128})
local T = NetStream.Types
local Data = NetStream.Event("__NSDispatchCompactionData", {Id = 40101, Schema = {T.U16}, Compression = false})
local Start = NetStream.Event("__NSDispatchCompactionStart", {Id = 40102, Schema = {T.Bool}, Compression = false})
local last = 0
local accepted = 0
Data:Connect(function(value)
	assert(value > last and value <= 3840, "Dispatch compaction reordered or duplicated a callback")
	last = value
	accepted += 1
end)
assert(Start:FireServer(true), "Unable to start server stress producer")
task.delay(30, function()
	local stats = NetStream.GetStats()
	assert(stats.DecodeErrors == 0, "Packet decode failed under sustained backlog")
	assert(accepted >= 65, "Stress run did not process enough dispatch items")
	assert(stats.DispatchQueueCompactions > 0, "Sustained pending dispatch queue did not compact; inspect packet delivery")
	print("NetStream v4.1.1 dispatch compaction PASS", "processed", accepted, "compactions", stats.DispatchQueueCompactions, "dropped", stats.DroppedDispatch)
end)
