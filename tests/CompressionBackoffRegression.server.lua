--!strict
-- Run by itself in ServerScriptService, paired with CompressionBackoffRegression.client.lua.
local NetStream = require(game:GetService("ReplicatedStorage"):WaitForChild("Netstream"))
assert(NetStream.GetVersion() == "2.3.13")
local event = NetStream.Event("__NSCompressionBackoff", {Id = 34103})
local counts = {}
event:Connect(function(player, payload)
	assert(type(payload) == "table" and type(payload.index) == "number", "Compression payload invalid")
	assert(payload.payload == string.rep(string.char(65 + payload.index % 20), 64), "Compression payload mutated")
	counts[player] = (counts[player] or 0) + 1
	if counts[player] == 20 then print("NetStream compression 20 decoded events PASS for", player.Name) end
end)
