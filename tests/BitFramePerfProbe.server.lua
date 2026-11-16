--!strict
-- Studio setup: ReplicatedStorage.Netstream (with Compression child); this Script in ServerScriptService.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "2.3.34")
local event = NetStream.Event("__NetStreamPerfProbe", {Compression = false})
local ack = NetStream.Event("__NetStreamPerfAck", {Compression = false})
local total = 300
local states = {}

local function expectedPayload(index: number): string
	local remainder = index % 4
	local length = if remainder == 0 then 260 elseif remainder == 1 then 17 elseif remainder == 2 then 80 else 31
	return string.rep(string.char(65 + index % 26), length)
end

event:Connect(function(player, sequence, payload)
	assert(typeof(sequence) == "number" and sequence >= 1 and sequence <= total and sequence % 1 == 0, "Perf probe sequence invalid")
	assert(typeof(payload) == "string" and payload == expectedPayload(sequence), "Perf probe payload corrupted")
	local state = states[player]
	if not state then
		state = {count = 0, seen = {}}
		states[player] = state
	end
	assert(not state.seen[sequence], "Perf probe sequence duplicated")
	state.seen[sequence] = true
	state.count += 1
	if state.count == total then
		local stats = NetStream.GetStats()
		ack:FireClient(player, state.count, stats.ReceivedBatches, stats.DecodeErrors)
		states[player] = nil
	end
end)

game:GetService("Players").PlayerRemoving:Connect(function(player)
	states[player] = nil
end)
print("NetStream 2.3.7 performance probe server listening")
