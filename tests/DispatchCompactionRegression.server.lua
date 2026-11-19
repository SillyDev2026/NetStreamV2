--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "4.3.1")
NetStream.Configure({HandshakeEnabled = false, CompressionEnabled = false, BandwidthGovernorEnabled = false, TransportFastFlushEnabled = false, MaxBatchMessages = 128})
local T = NetStream.Types
local Data = NetStream.Event("__NSDispatchCompactionData", {Id = 40101, Schema = {T.U16}, Compression = false})
local Start = NetStream.Event("__NSDispatchCompactionStart", {Id = 40102, Schema = {T.Bool}, Compression = false})
local active = {}
Start:Connect(function(player, flag)
	if flag ~= true or active[player] then return end
	active[player] = true
	task.spawn(function()
		for frame = 1, 240 do
			if player.Parent ~= game:GetService("Players") then break end
			for j = 1, 16 do assert(Data:FireClient(player, (frame - 1) * 16 + j), "Compaction send failed") end
			NetStream.FlushTarget(player)
			RunService.Heartbeat:Wait()
		end
		active[player] = nil
	end)
end)
print("NetStream v4.3.1 dispatch compaction server ready")
