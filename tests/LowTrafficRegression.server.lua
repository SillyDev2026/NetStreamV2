--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
local T = NetStream.Types

NetStream.ConfigureLowTraffic({HandshakeEnabled = false, PerformanceTelemetryEnabled = true})
assert(NetStream.GetVersion() == "4.3.0")
local settings = NetStream.GetConfig()
assert(settings.FlushRate == 30 and settings.TransportBatchWindowSeconds == 0.05 and settings.TransportTargetMessagesPerPacket == 32)

local Value = NetStream.State("__LowTrafficValue", {Id = 38661, Schema = {T.U16}, Coalesce = true, SuppressUnchanged = true, Compression = false})
local StepAck = NetStream.Event("__LowTrafficAck", {Id = 38662, Schema = {T.U8}, Compression = false})
local started: {[Player]: boolean} = {}

local function run(player: Player)
	if started[player] then return end
	started[player] = true
	task.spawn(function()
		task.wait(2)
		if player.Parent ~= Players then return end
		local before = NetStream.GetStats().LowTrafficStateDuplicatesSuppressed
		assert(Value:SetClient(player, 17))
		task.wait(0.5)
		for _ = 1, 64 do assert(Value:SetClient(player, 17)) end
		local stats = NetStream.GetStats()
		assert(stats.LowTrafficStateDuplicatesSuppressed - before == 64, "Identical reliable latest state was retransmitted")
		assert(Value:SetClient(player, 18))
		task.wait(0.5)
		assert(Value:SetClient(player, 18))
		assert(NetStream.GetStats().LowTrafficStateDuplicatesSuppressed - before == 65, "Second state was not cached")
		assert(Value:SetClientNow(player, 18), "Force-send failed")
		print("NetStream 4.3.0 LowTraffic SERVER PASS", "duplicates", stats.LowTrafficStateDuplicatesSuppressed)
	end)
end

StepAck:Connect(function(player, value)
	assert(value == 3, "Client failed to receive initial, changed and forced state")
	print("NetStream 4.3.0 LowTraffic CLIENT ACK PASS", player.UserId)
end)
for _, player in ipairs(Players:GetPlayers()) do run(player) end
Players.PlayerAdded:Connect(run)
Players.PlayerRemoving:Connect(function(player) started[player] = nil end)
