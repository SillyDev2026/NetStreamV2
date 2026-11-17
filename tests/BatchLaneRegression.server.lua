--!strict
-- ServerScriptService; place Netstream (and its Compression child) in ReplicatedStorage.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetStream = require(ReplicatedStorage:WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "2.3.37", "Expected NetStream v2.3.37")
local reliable = NetStream.Event("__NSBatchReliable", {Id = 34001, Compression = false})
local unreliable = NetStream.Unreliable("__NSBatchUnreliable", {Id = 34002, Compression = false})
local ack = NetStream.Event("__NSBatchAck", {Id = 34003, Compression = false})
local totals = {}
reliable:Connect(function(player, sequence, payload)
	assert(type(sequence) == "number" and sequence >= 1 and sequence <= 120 and sequence % 1 == 0, "Invalid reliable sequence")
	assert(payload == string.rep("R", 72), "Reliable payload corrupted")
	local state = totals[player]
	if not state then state = {Seen = {}, Count = 0, Unreliable = 0}; totals[player] = state end
	assert(not state.Seen[sequence], "Duplicate reliable sequence")
	state.Seen[sequence] = true
	state.Count += 1
	if state.Count == 120 then
		ack:FireClient(player, state.Count, state.Unreliable)
	end
end)
unreliable:Connect(function(player, sequence, payload)
	assert(type(sequence) == "number" and sequence >= 1 and sequence <= 120 and sequence % 1 == 0, "Invalid unreliable sequence")
	assert(payload == string.rep("U", 52), "Unreliable payload corrupted")
	local state = totals[player]
	if not state then state = {Seen = {}, Count = 0, Unreliable = 0}; totals[player] = state end
	state.Unreliable += 1
end)
game:GetService("Players").PlayerRemoving:Connect(function(player) totals[player] = nil end)
print("NetStream v2.3.37 batching regression server ready")
